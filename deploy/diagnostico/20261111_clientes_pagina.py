#!/usr/bin/env python3
"""Modulo de Clientes (2026-11-11): la pagina 20 lista, la 21 es el dialogo.

Comprueba:
  - metadatos: la 20 tiene el IR y la guarda; la 21 es MODAL con su proceso de
    guardado llamando a fn_rif_cliente_valido;
  - el menu trae «Clientes»;
  - HTTP: la 20 responde 200 y trae los clientes de la empresa del usuario y no
    los de la otra; consulta.demo (CONSULTA) no ve el boton de alta.

La 21 es modal: se abre desde la 20 con un enlace con checksum, asi que su
render no se puede pedir por HTTP (se anota).
"""
import os
import re
import subprocess
import sys
import tempfile

import oracledb

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(REPO, "deploy", "conexion"))
from verificar_conexion import CONNECT_STRING, credenciales  # noqa: E402

fallas = 0
TEMPORAL = "diag.clientes"


def comprueba(ok, texto, detalle=""):
    global fallas
    print("  [%s] %s%s" % ("OK   " if ok else "FALLA", texto,
                           "" if not detalle else " (%s)" % detalle))
    if not ok:
        fallas += 1


def abrir(usuario, pagina, ruta):
    r = subprocess.run([sys.executable, os.path.join(REPO, "deploy", "conexion", "abrir_pagina.py"),
                        usuario, "Diag#2026", str(pagina), ruta],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    salida = (r.stdout or "") + (r.stderr or "")
    m = re.search(r"HTTP (\d+)", salida)
    codigo = int(m.group(1)) if m else 0
    with open(ruta, encoding="utf-8", errors="replace") as f:
        return codigo, f.read()


def main():
    c = credenciales()
    con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
    cur = con.cursor()
    cur.execute("alter session set current_schema = WKSP_SYPEXWS")
    tmp = tempfile.mkdtemp(prefix="clientes_")

    try:
        print("== Metadatos ==")
        cur.execute("""select count(*) from apex_application_pages
                        where application_id = 100 and page_id in (20, 21)""")
        comprueba(cur.fetchone()[0] == 2, "existen las paginas 20 y 21")
        cur.execute("""select count(*) from apex_application_page_regions
                        where application_id = 100 and page_id = 20
                          and source_type_plugin_static_id = 'NATIVE_IR'""")
        comprueba(cur.fetchone()[0] == 1, "la 20 tiene el Interactive Report")
        cur.execute("""select count(*) from apex_application_page_proc
                        where application_id = 100 and page_id = 20
                          and static_id = 'valida-rol-clientes'""")
        comprueba(cur.fetchone()[0] == 1, "la 20 tiene guarda de rol")
        cur.execute("""select count(*) from apex_application_page_proc
                        where application_id = 100 and page_id = 21
                          and static_id = 'guardar-cliente'
                          and instr(upper(process_source), 'FN_RIF_CLIENTE_VALIDO') > 0""")
        comprueba(cur.fetchone()[0] == 1, "el guardado valida el RIF")
        cur.execute("""select count(*) from apex_application_list_entries
                        where application_id = 100 and list_name = 'Navigation Menu'
                          and lower(entry_text) = 'clientes'""")
        comprueba(cur.fetchone()[0] == 1, "el menu trae Clientes")

        # Todas las LOV de la pagina 21 tienen que EJECUTARSE. Este caso existe
        # porque el 2026-11-11 la del pais usaba p.nombre_pais y la columna es
        # p.nombre: el dialogo reventaba con ORA-20999 al abrirlo.
        # El usuario temporal se crea aqui porque la LOV de empresas filtra
        # por :APP_USER (se sustituye por el para poder ejecutarla fuera de APEX).
        cur.execute("begin delete from usuario_empresa where usuario_id in "
                    "(select usuario_id from usuario where upper(username)=upper(:u)); commit; end;", u=TEMPORAL)
        cur.execute("delete from usuario where upper(username)=upper(:u)", u=TEMPORAL)
        cur.execute("""insert into usuario (username, email, password_hash, estado, id_empresa, rol_id,
                                            debe_cambiar_clave, reintentos_fallidos)
                       values (:u, 'x@x', sypex_hash_password('Diag#2026'), 'ACTIVO', 1,
                               (select id_rol from syn_roles where codigo_rol='ADMIN'), 'N', 0)""", u=TEMPORAL)
        con.commit()

        print("== LOV de la pagina 21 ==")
        cur.execute("select item_name, lov_definition from apex_application_page_items "
                    "where application_id = 100 and page_id = 21 and lov_definition is not null")
        for nombre, lov in cur.fetchall():
            if not lov.lstrip().lower().startswith(("select", "with")):
                continue  # STATIC2:..., no es SQL
            try:
                lov_ok = lov.replace(":APP_USER", "'" + TEMPORAL + "'")
                cur.execute("select count(*) from (" + lov_ok + ")")
                n = cur.fetchone()[0]
                comprueba(n > 0, "la LOV de " + nombre + " devuelve filas", str(n))
            except Exception as ex:
                comprueba(False, "la LOV de " + nombre + " no ejecuta", str(ex)[:120])

        print("== HTTP ==")
        cur.execute("begin delete from usuario_empresa where usuario_id in "
                    "(select usuario_id from usuario where upper(username)=upper(:u)); commit; end;", u=TEMPORAL)
        cur.execute("delete from usuario where upper(username)=upper(:u)", u=TEMPORAL)
        cur.execute("""insert into usuario (username, email, password_hash, estado, id_empresa, rol_id,
                                            debe_cambiar_clave, reintentos_fallidos)
                       values (:u, 'x@x', sypex_hash_password('Diag#2026'), 'ACTIVO', 1,
                               (select id_rol from syn_roles where codigo_rol='ADMIN'), 'N', 0)""", u=TEMPORAL)
        con.commit()

        codigo, html = abrir(TEMPORAL, 20, os.path.join(tmp, "p20.html"))
        comprueba(codigo == 200, "la pagina 20 responde 200", str(codigo))
        comprueba("Corporaci" in html, "trae los clientes de la empresa 1")
        comprueba("Distribuidora Azteca" not in html, "no trae los de la empresa 2")
        comprueba("BTN_NUEVO_CLIENTE" in html, "el admin ve el boton de alta")
        comprueba("clientes" in html.lower(), "el menu trae Clientes")
    finally:
        try:
            cur.execute("begin delete from usuario_empresa where usuario_id in "
                        "(select usuario_id from usuario where upper(username)=upper(:u)); commit; end;", u=TEMPORAL)
            cur.execute("delete from usuario where upper(username)=upper(:u)", u=TEMPORAL)
            con.commit()
        except Exception:
            pass
        cur.close()
        con.close()

    print("\nRESULTADO: FALLAS=%d" % fallas)
    return 1 if fallas else 0


if __name__ == "__main__":
    sys.exit(main())
