#!/usr/bin/env python3
# =============================================================================
# verificar_conexion.py
#
# Prueba de humo de la conexion a Sypex_SQL: entra, cambia al esquema de la app
# y responde las preguntas basicas (quien soy, en que esquema, cuantos objetos,
# cuantos invalidos, si la app 100 esta importada).
#
# Por que existe: los demas runners (importar_export.py, compilar_objeto.py)
# fallan con un error generico de oracledb y hay que traducirlo a mano. Este
# script traduce el codigo y dice que tocar.
#
# Uso (desde la raiz del repo):
#   python deploy/conexion/verificar_conexion.py
#   python deploy/conexion/verificar_conexion.py --esquema WKSP_SYPEXWS
#
# Sale con codigo 1 si no conecta o si hay objetos invalidos.
# Requiere DB_USER y DB_PASSWORD en el entorno o en el .env de la raiz.
# =============================================================================

import argparse
import os
import sys
import time

import oracledb

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

CONNECT_STRING = (
    "(DESCRIPTION=(RETRY_COUNT=2)(RETRY_DELAY=2)"
    "(ADDRESS=(PROTOCOL=TCPS)(PORT=1521)(HOST=adb.mx-monterrey-1.oraclecloud.com))"
    "(CONNECT_DATA=(SERVICE_NAME=GFD7E2575D251AE_SYPEXSQL_high.adb.oraclecloud.com))"
    "(SECURITY=(SSL_SERVER_DN_MATCH=YES)))"
)

# Traduccion de los codigos que se han visto en este entorno (ver README.md).
DIAGNOSTICO = {
    12506: ("ACL de la instancia: la IP publica de este equipo no esta autorizada.",
            "OCI -> Autonomous Database -> Network -> Access control list: "
            "agregar la IP actual. NO se arregla en la cadena ni en el .env."),
    1017: ("Credenciales rechazadas: usuario o clave del .env.",
           "Revisar DB_USER/DB_PASSWORD en el .env de la raiz."),
    12514: ("El SERVICE_NAME no existe en esta instancia.",
            "Sypex_SQL usa GFD7E2575D251AE_SYPEXSQL_high (o _low)."),
    28000: ("Cuenta bloqueada.", "Desbloquear el usuario en la base."),
    28001: ("Clave expirada.", "Renovar la clave del usuario de conexion."),
}


def credenciales():
    datos = {}
    ruta = os.path.join(REPO, ".env")
    if os.path.exists(ruta):
        with open(ruta, encoding="utf-8") as f:
            for linea in f:
                linea = linea.strip()
                if linea and not linea.startswith("#") and "=" in linea:
                    clave, valor = linea.split("=", 1)
                    datos[clave.strip()] = valor.strip()
    datos["DB_USER"] = os.environ.get("DB_USER", datos.get("DB_USER"))
    datos["DB_PASSWORD"] = os.environ.get("DB_PASSWORD", datos.get("DB_PASSWORD"))
    if not datos.get("DB_USER") or not datos.get("DB_PASSWORD"):
        sys.exit("Faltan DB_USER y/o DB_PASSWORD (entorno o .env de la raiz).")
    return datos


def ip_publica():
    """La IP publica importa: si el proveedor la mueve, la ACL deja de valer."""
    import urllib.request

    try:
        with urllib.request.urlopen("https://api.ipify.org", timeout=15) as r:
            return r.read().decode("ascii", "replace").strip()
    except Exception:
        return "desconocida"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--esquema", default="WKSP_SYPEXWS",
                    help="esquema de la app (por defecto WKSP_SYPEXWS)")
    args = ap.parse_args()

    datos = credenciales()
    print(f"usuario: {datos['DB_USER']}   IP publica: {ip_publica()}")

    inicio = time.time()
    try:
        con = oracledb.connect(user=datos["DB_USER"], password=datos["DB_PASSWORD"],
                               dsn=CONNECT_STRING)
    except oracledb.Error as ex:
        error, = ex.args if ex.args else (ex,)
        texto = getattr(error, "message", None) or str(error)
        codigo = getattr(error, "code", None)
        if not codigo:
            # python-oracledb envuelve el ORA real en DPY-6005/DPY-6000 y deja
            # code = 0: "Listener refused connection. (Similar to ORA-12506)".
            # "Listener refused connection. (Similar to ORA-12506)".
            import re
            m = re.search(r"ORA-(\d{5})", texto)
            if m:
                codigo = -int(m.group(1))
        print(f"FALLO al conectar ({time.time() - inicio:.1f}s)")
        print(f"  {error}")
        clave = abs(codigo) if codigo is not None else None
        if clave in DIAGNOSTICO:
            causa, accion = DIAGNOSTICO[clave]
            print(f"  causa:  {causa}")
            print(f"  accion: {accion}")
        sys.exit(1)

    with con:
        cur = con.cursor()
        cur.execute("select user, sys_context('userenv','service_name'), "
                    "sys_context('userenv','db_name'), systimestamp from dual")
        usuario, servicio, base, ahora = cur.fetchone()
        print(f"CONECTADO en {time.time() - inicio:.1f}s")
        print(f"  usuario  : {usuario}")
        print(f"  servicio : {servicio}")
        print(f"  base     : {base}")
        print(f"  hora db  : {ahora}")

        cur.execute(f"alter session set current_schema = {args.esquema}")
        cur.execute("select sys_context('userenv','current_schema') from dual")
        esquema = cur.fetchone()[0]
        print(f"  esquema  : {esquema}")

        cur.execute("""
            select object_type, count(*)
              from all_objects
             where owner = :o
               and object_type in ('TABLE','VIEW','PACKAGE','PACKAGE BODY',
                                   'PROCEDURE','FUNCTION','TRIGGER','SEQUENCE','INDEX')
             group by object_type
             order by object_type
        """, o=args.esquema)
        filas = cur.fetchall()
        if not filas:
            print(f"  AVISO: no hay objetos de la app en {args.esquema}")
        else:
            print("  objetos  : " + ", ".join(f"{t} {n}" for t, n in filas))

        cur.execute("select count(*) from all_objects where owner = :o and status = 'INVALID'",
                    o=args.esquema)
        invalidos = cur.fetchone()[0]
        print(f"  invalidos: {invalidos}")

        try:
            cur.execute("select count(*) from apex_application_pages where application_id = 100")
            print(f"  paginas app 100: {cur.fetchone()[0]}")
        except oracledb.Error as ex:
            print(f"  paginas app 100: no se pudo leer ({ex.args[0].message})")

    if invalidos:
        print(f"FALLAS=1 (objetos invalidos en {args.esquema})")
        sys.exit(1)
    print("FALLAS=0")


if __name__ == "__main__":
    main()
