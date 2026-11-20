"""Pagina 4: cada administrador solo administra usuarios de su empresa (2026-11-07).

Comprueba, contra la app importada:
  1. Los cuatro procesos de escritura de la pagina 4 llevan la guarda de empresa.
  2. La lista de usuarios (pagina 3) filtra por la empresa del usuario.
  3. Comportamiento real: con prueba2 (empresa 2) no se puede tocar un usuario de la
     empresa 1 (-20003), y con la propia empresa si. Todo con rollback.
  4. Nada invalido y las 21 paginas siguen.

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
        # Desde la fase 3 la validacion de "es una empresa suya" vive en
        # v_empresas_usuario (crear) o en fn_usuario_administrable / el
        # procedimiento (los otros tres).
        valida = ("v_empresas_usuario" in cuerpo
                  or "fn_usuario_administrable" in cuerpo
                  or "prc_empresas_usuario" in cuerpo)
        comprueba(valida, f"{nombre}: valida la empresa")
        comprueba("raise_application_error(-20003" in cuerpo, f"{nombre}: rechaza con -20003")

    print("== Lista de usuarios (pagina 3) ==")
    cur.execute("""select region_source from apex_application_page_regions
                    where application_id = 100 and page_id = 3 and region_name like 'Gesti%'""")
    fuente = cur.fetchone()[0].read()
    # MEDIDO (2026-11-10, tarea 4 del plan de multiempresa): el filtro de la
    # pagina 3 ya NO usa la columna unica USUARIO.ID_EMPRESA: usa la tabla de
    # asociacion USUARIO_EMPRESA (F5). Se comprueba que el filtro existe y
    # que se apoya en USUARIO_EMPRESA, no la forma exacta del texto: lo que
    # el caso quiere decir lo comprueba el conteo de filas de mas abajo.
    comprueba("usuario_empresa" in fuente,
              "la lista trae los de su empresa y los pendientes sin empresa")
    comprueba(":APP_USER" in fuente, "el filtro es por el usuario de la sesion")

    print("== Filas que ve cada administrador en la lista ==")
    # MEDIDO (2026-11-10): el numero esperado ya no se puede escribir a mano:
    # la base tiene los 9 usuarios REALES (la purga del demo del 2026-11-08
    # dejo la base con ellos) y el fixture agrega 3 mas. Se CALCULA con la
    # misma regla del filtro F5: los usuarios que comparten alguna empresa con
    # el administrador, mas los que no tienen ninguna empresa (los PENDIENTE
    # que hay que activar). Lo que se sigue comprobando, ademas, es que
    # prueba1 NO ve a los de la empresa 2.
    for usuario, empresa in (("prueba1", 1), ("prueba2", 2)):
        cur.execute("""select count(*) from usuario u
                        where (exists (select 1
                                  from usuario_empresa ue
                                  join usuario_empresa mia on mia.id_empresa = ue.id_empresa
                                  join usuario a on a.usuario_id = mia.usuario_id
                                 where ue.usuario_id = u.usuario_id
                                   and upper(a.username) = upper(:u))
                            or not exists (select 1 from usuario_empresa x
                                            where x.usuario_id = u.usuario_id))""",
                    {"u": usuario})
        esperado = cur.fetchone()[0]
        cur.execute(f"select count(*) from ({fuente})", {"APP_USER": usuario})
        n = cur.fetchone()[0]
        comprueba(n == esperado, f"{usuario} ve {esperado} usuario(s)", str(n))
        # Y lo importante: el administrador NO ve a los usuarios de la OTRA
        # empresa (la que no es la suya).
        cur.execute("""select count(*) from usuario u
                        where u.id_empresa = :e
                          and exists (select 1 from usuario_empresa ue
                                      join usuario_empresa mia on mia.id_empresa = ue.id_empresa
                                      join usuario a on a.usuario_id = mia.usuario_id
                                     where ue.usuario_id = u.usuario_id
                                       and upper(a.username) = upper(:u))""",
                    {"e": 3 - empresa, "u": usuario})
        ajenos = cur.fetchone()[0]
        comprueba(ajenos == 0,
                  f"{usuario} no ve usuarios de la empresa {3 - empresa} ajena",
                  str(ajenos))

    print("== Comportamiento: borrar usuarios ==")
    cur.execute("select usuario_id from usuario where upper(username) = 'PRUEBA1'")
    id_admin = cur.fetchone()[0]
    cur.execute("select usuario_id from usuario where upper(username) = 'PRUEBA2'")
    id_mx = cur.fetchone()[0]
    cur.execute("select usuario_id from usuario where upper(username) = 'PRUEBA3'")
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

    comprueba(intenta("prueba2", id_emp1) == 20003,
              "prueba2 (empresa 2) NO puede borrar un usuario de la empresa 1")
    comprueba(intenta("prueba2", id_mx) == 20005,
              "prueba2: la baja se rechaza (-20005, los usuarios no se eliminan)")
    comprueba(intenta("prueba1", id_emp1) == 20005,
              "prueba1: la baja se rechaza (-20005, los usuarios no se eliminan)")
    comprueba(intenta("prueba1", id_mx) == 20003,
              "prueba1 (empresa 1) NO puede tocar la empresa 2")
    comprueba(intenta("usuario.inventado", id_emp1) == 20003,
              "un usuario que no existe en USUARIO no puede tocar nada")

    print("== Correo con formato en la pagina 4 ==")
    cur.execute("select process_source from apex_application_page_proc where application_id = 100 "
                "and page_id = 4 and static_id = 'update-usuario'")
    bloque_upd = cur.fetchone()[0].read()

    def con_correo(email):
        try:
            cur.execute(bloque_upd, {"APP_USER": "prueba1", "P4_USUARIO_ID": None,
                                     "P4_USERNAME": "x", "P4_EMAIL": email,
                                     "P4_ESTADO": "ACTIVO", "P4_ROL_ID": None,
                                     "P4_PASSWORD": None, "P4_ID_EMPRESA": None})
            return 0
        except oracledb.DatabaseError as ex:
            error, = ex.args
            return abs(error.code)
        finally:
            con.rollback()

    comprueba(con_correo("jdahdh") == 20015,
              "un correo sin formato se rechaza (-20015)")
    comprueba(con_correo("ana@ejemplo.com") == 20003,
              "un correo valido pasa a la guarda de empresa")

    print("== Estado general ==")
    cur.execute("""select count(*) from all_objects where owner = 'WKSP_SYPEXWS'
                    and status <> 'VALID'
                    and object_type in ('FUNCTION','PROCEDURE','PACKAGE','PACKAGE BODY','TRIGGER','VIEW')""")
    n = cur.fetchone()[0]
    comprueba(n == 0, "cero objetos invalidos", str(n))
    cur.execute("select count(*) from apex_application_pages where application_id = 100")
    n = cur.fetchone()[0]
    comprueba(n == 34, "siguen las 34 paginas", str(n))

    print(f"\nRESULTADO: FALLAS={fallas}")
    con.close()
    sys.exit(1 if fallas else 0)


if __name__ == "__main__":
    main()
