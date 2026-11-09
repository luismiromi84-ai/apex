#!/usr/bin/env python3
# =============================================================================
# 20261109_compilar_procesos_pagina.py
#
# Compila los procesos PL/SQL de pagina de la app 100 y dice si alguno tiene un
# error de sintaxis.
#
# Por que existe: los procesos de pagina NO se compilan cuando se importa la app
# (el import solo crea la fila en APEX_APPLICATION_PAGE_PROC). Un error como el
# PLS-00103 por una coma de menos en la llamada a un package pasa inadvertido
# hasta que el usuario pulsa Guardar. Paso el 2026-11-09 en la pagina 9.
#
# Como funciona: saca el cuerpo de APEX_APPLICATION_PAGE_PROC, sustituye los
# binds `:P9_XXX` por una variable local y crea un procedimiento temporal; luego
# mira ALL_ERRORS y lo borra.
#
# OJO: los binds se sustituyen por `v_bind`, NO por `null`. Con `null` se rompen
# las asignaciones del tipo `:P9_SUBTOTAL := ...` y salen falsos positivos
# (PLS-00363: expression 'NULL' cannot be used as an assignment target).
#
# Uso (desde la raiz del repo):
#   python deploy/diagnostico/20261109_compilar_procesos_pagina.py
#
# Sale con codigo 1 si algun proceso no compila.
# =============================================================================

import re
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "conexion"))
import oracledb
from verificar_conexion import CONNECT_STRING, credenciales

ESQUEMA = "WKSP_SYPEXWS"
TEMP = "SPX_PRUEBA_PROCESO"


def main():
    c = credenciales()
    con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
    cur = con.cursor()
    cur.execute(f"alter session set current_schema = {ESQUEMA}")

    cur.execute("""select page_id, process_name, execution_sequence, process_point, process_source
                     from apex_application_page_proc
                    where application_id = 100
                      and process_source is not null
                      and process_source_language = 'PLSQL'
                    order by page_id, execution_sequence""")
    filas = cur.fetchall()
    print(f"procesos PL/SQL de pagina: {len(filas)}")

    malos = 0
    for page_id, nombre, seq, punto, src in filas:
        cuerpo = re.sub(r":[A-Z0-9_]+", "v_bind", src.read())
        cur.execute(f"begin execute immediate 'drop procedure {TEMP}'; "
                    "exception when others then null; end;")
        try:
            cur.execute(f"create or replace procedure {TEMP} is v_bind varchar2(4000); "
                        f"begin {cuerpo} end;")
        except Exception as ex:
            malos += 1
            print(f"[MAL] p{page_id} #{seq} {nombre} ({punto}): {str(ex)[:140]}")
            continue
        cur.execute("select line, position, substr(text, 1, 100) from all_errors "
                    f"where name = '{TEMP}' and type = 'PROCEDURE' order by sequence")
        errs = cur.fetchall()
        if errs:
            malos += 1
            print(f"[MAL] p{page_id} #{seq} {nombre} ({punto})")
            for e in errs[:5]:
                print("      ", e)

    cur.execute(f"begin execute immediate 'drop procedure {TEMP}'; "
                "exception when others then null; end;")
    con.close()

    print(f"RESULTADO: FALLAS={malos}")
    return 1 if malos else 0


if __name__ == "__main__":
    sys.exit(main())
