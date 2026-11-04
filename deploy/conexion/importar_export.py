#!/usr/bin/env python3
# =============================================================================
# importar_export.py
#
# Ejecuta un export de APEX (por ejemplo pagina_apex/f100.sql) contra la base,
# sentencia por sentencia, sin SQLcl y sin SQL*Plus.
#
# Por que existe: en este entorno SQLcl invocado desde el agente muere con
#   java.io.IOException: Funcion incorrecta
# y devuelve rc=0 sin ejecutar nada (falso OK). El rodeo con conhost.exe funciona
# a veces y deja de hacerlo sin avisar. python-oracledb en modo thin conecta
# siempre y devuelve los errores de verdad.
#
# Uso (desde la raiz del repo):
#   python deploy/conexion/importar_export.py pagina_apex/f100.sql
#
# Requiere DB_USER y DB_PASSWORD en el entorno o en el .env de la raiz.
# El export hace delete_application + create_application: la app se borra y se
# recrea, y se pierde cualquier cambio hecho en App Builder despues del export.
# =============================================================================

import os
import sys
import time

import oracledb

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

CONNECT_STRING = (
    "(DESCRIPTION=(RETRY_COUNT=5)(RETRY_DELAY=2)"
    "(ADDRESS=(PROTOCOL=TCPS)(PORT=1521)(HOST=adb.mx-monterrey-1.oraclecloud.com))"
    "(CONNECT_DATA=(SERVICE_NAME=GFD7E2575D251AE_SYPEXSQL_high.adb.oraclecloud.com))"
    "(SECURITY=(SSL_SERVER_DN_MATCH=YES)))"
)

# Comandos de SQL*Plus que no se pueden mandar por el driver
SKIP = ("PROMPT ", "SET ", "WHENEVER ", "SPOOL ", "EXIT", "COLUMN ", "SHOW ", "DEFINE ")


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


def sentencias(ruta):
    """Parte el script en bloques ejecutables usando las lineas que son solo '/'."""
    with open(ruta, encoding="utf-8") as f:
        lineas = f.read().replace("\r\n", "\n").split("\n")

    buffer, salida = [], []
    for linea in lineas:
        limpia = linea.strip()
        if limpia == "/":
            if buffer:
                salida.append("\n".join(buffer))
                buffer = []
            continue
        if any(limpia.upper().startswith(p) for p in SKIP):
            continue
        if limpia.startswith("--"):
            continue
        buffer.append(linea)
    if buffer and "\n".join(buffer).strip():
        salida.append("\n".join(buffer))
    return salida


def main():
    if len(sys.argv) < 2:
        sys.exit("Uso: python deploy/conexion/importar_export.py <archivo.sql>")

    ruta = sys.argv[1]
    if not os.path.isabs(ruta):
        ruta = os.path.join(REPO, ruta)

    datos = credenciales()
    lista = sentencias(ruta)
    print(f"{os.path.basename(ruta)}: {len(lista)} sentencias")

    inicio = time.time()
    with oracledb.connect(user=datos["DB_USER"], password=datos["DB_PASSWORD"], dsn=CONNECT_STRING) as con:
        cur = con.cursor()
        ejecutadas = 0
        for numero, bloque in enumerate(lista, 1):
            if not bloque.strip(" ;\n"):
                continue
            cuerpo = bloque.rstrip()
            es_plsql = cuerpo.lstrip().lower().startswith(("begin", "declare", "create or replace"))
            if cuerpo.endswith(";") and not es_plsql:
                cuerpo = cuerpo[:-1]
            try:
                cur.execute(cuerpo)
                ejecutadas += 1
            except oracledb.DatabaseError as ex:
                error, = ex.args
                print(f"FALLO en la sentencia {numero} (codigo {error.code}): {error.message}")
                print("--- inicio de la sentencia ---")
                print("\n".join(bloque.splitlines()[:10]))
                sys.exit(1)
        con.commit()

    print(f"ejecutadas OK: {ejecutadas} en {time.time() - inicio:.1f}s")


if __name__ == "__main__":
    main()
