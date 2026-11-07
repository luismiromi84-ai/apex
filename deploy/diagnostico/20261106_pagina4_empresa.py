"""Pagina 4: cada administrador solo administra usuarios de su empresa (2026-11-07).

Comprueba, contra la app importada:
  1. Los cuatro procesos de escritura de la pagina 4 llevan la guarda de empresa.
  2. La lista de usuarios (pagina 3) filtra por la empresa del usuario.
  3. Comportamiento real: con mx.demo (empresa 2) no se puede tocar un usuario de la
     empresa 1 (-20003), y con la propia empresa si. Todo con rollback.
  4. Nada invalido y las 19 paginas siguen.

Uso:  python deploy/diagnostico/20261106_pagina4_empresa.py
Sale con codigo 1 si algo falla.
"""

import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(REPO, "deploy", "conexion"))

import oracledb
from importar_export import CONNECT_STRING, credenciales

fallas = 0


def comprueba(ok, texto, detalle=""):
    global fallas
    print(f"  [{'OK   ' if ok else 'FALLA'}] {texto}" + (f" ({detalle})" if detalle else ""))
    if not ok:
        fallas += 1


def main():
    datos = credenciales()
    con = oracledb.connect(user=datos["DB_USER"], password=datos["DB_PASSWORD"], dsn=CONNECT_STRING)
    cur = con.cursor()
    cur.execute("alter session set current_schema = WKSP_SYPEXWS")

    print("== Procesos de la pagina 4 ==")
    cur.execute("""select process_name, process_source from apex_application_page_proc
                    where application_id = 100 and page_id = 4
                      and process_point_code = 'AFTER_SUBMIT'
                      and static_id in ('crear-usuario', 'update-usuario', 'eliminar-usuario',
                                        'desbloquear-usuario')""")
    procesos = {n: s.read() for n, s in cur.fetchall()}
    for nombre in ("crear-usuario", "update-usuario", "eliminar-usuario", "desbloquear-usuario"):
        clave = [k for k in procesos if k.lower().replace(" ", "-") == nombre]
        cuerpo = procesos[clave[0]] if clave else ""
        comprueba("fn_clean_num(:P4_ID_EMPRESA)" in cuerpo or "fn_clean_num(:P4_USUARIO_ID)" in cuerpo,
                  f"{nombre}: valida la empresa")
        comprueba("raise_application_error(-20003" in cuerpo, f"{nombre}: rechaza con -20003")

    print("== Lista de usuarios (pagina 3) ==")
    cur.execute("""select region_source from apex_application_page_regions
                    where application_id = 100 and page_id = 3 and region_name like 'Gesti%'""")
    fuente = cur.fetchone()[0].read()
    comprueba("u.id_empresa is null" in fuente, "la lista trae los de su empresa y los pendientes sin empresa")
    comprueba("upper(x.username) = upper(:APP_USER)" in fuente.replace("\n", " ")
              or "upper(x.username)=upper(:APP_USER)" in fuente.replace("\n", "").replace(" ", ""),
              "el filtro es por el usuario de la sesion")

    print("== Filas que ve cada administrador en la lista ==")
    for usuario, esperado in (("admin.demo", 13), ("mx.demo", 1)):
        cur.execute(f"select count(*) from ({fuente})", {"APP_USER": usuario})
        n = cur.fetchone()[0]
        comprueba(n == esperado, f"{usuario} ve {esperado} usuario(s)", str(n))

    print("== Comportamiento: borrar usuarios ==")
    cur.execute("select usuario_id from usuario where upper(username) = 'ADMIN.DEMO'")
    id_admin = cur.fetchone()[0]
    cur.execute("select usuario_id from usuario where upper(username) = 'MX.DEMO'")
    id_mx = cur.fetchone()[0]
    cur.execute("select usuario_id from usuario where upper(username) = 'VENTAS1.DEMO'")
    id_emp1 = cur.fetchone()[0]

    cur.execute("select process_source from apex_application_page_proc where application_id = 100 "
                "and page_id = 4 and static_id = 'eliminar-usuario'")
    bloque = cur.fetchone()[0].read()

    def intenta(usuario_app, id_objetivo):
        """Ejecuta el proceso real de la app con esos valores. Devuelve el codigo de error."""
        try:
            cur.execute(bloque, {"APP_USER": usuario_app, "P4_USUARIO_ID": str(id_objetivo)})
            return 0
        except oracledb.DatabaseError as ex:
            error, = ex.args
            # python-oracledb devuelve el codigo en positivo (20003, no -20003).
            return abs(error.code)
        finally:
            con.rollback()

    comprueba(intenta("mx.demo", id_emp1) == 20003,
              "mx.demo (empresa 2) NO puede borrar un usuario de la empresa 1")
    comprueba(intenta("mx.demo", id_mx) == 0,
              "mx.demo SI puede borrar un usuario de su empresa")
    comprueba(intenta("admin.demo", id_emp1) == 0,
              "admin.demo SI puede borrar un usuario de su empresa")
    comprueba(intenta("admin.demo", id_mx) == 20003,
              "admin.demo (empresa 1) NO puede tocar la empresa 2")
    comprueba(intenta("usuario.inventado", id_emp1) == 20003,
              "un usuario que no existe en USUARIO no puede tocar nada")

    print("== Estado general ==")
    cur.execute("""select count(*) from all_objects where owner = 'WKSP_SYPEXWS'
                    and status <> 'VALID'
                    and object_type in ('FUNCTION','PROCEDURE','PACKAGE','PACKAGE BODY','TRIGGER','VIEW')""")
    n = cur.fetchone()[0]
    comprueba(n == 0, "cero objetos invalidos", str(n))
    cur.execute("select count(*) from apex_application_pages where application_id = 100")
    n = cur.fetchone()[0]
    comprueba(n == 19, "siguen las 19 paginas", str(n))

    print(f"\nRESULTADO: FALLAS={fallas}")
    con.close()
    sys.exit(1 if fallas else 0)


if __name__ == "__main__":
    main()
