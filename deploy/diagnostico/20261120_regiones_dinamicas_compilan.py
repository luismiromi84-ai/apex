#!/usr/bin/env python3
# =============================================================================
# 20261120_regiones_dinamicas_compilan.py
#
# Compila la fuente PL/SQL de TODAS las regiones de contenido dinamico de la
# app 100 y dice si alguna tiene un error de sintaxis.
#
# Por que existe: la fuente de una region dinamica NO se compila al importar la
# app; APEX la compila al pintar la pagina y, si falla, el usuario recibe un
# HTTP 400 con un mensaje que no dice nada ("No se ha encontrado la opcion CASE"
# o el manejador generico de APEX). Paso el 2026-11-06 con la pagina 17 y el
# 2026-11-18 con el PL/SQL de una region que se sirvio como texto.
#
# Como funciona: lee REGION_SOURCE de APEX_APPLICATION_PAGE_REGIONS, sustituye
# los binds `:P9_XXX` por una variable local, crea una funcion temporal cuyo
# cuerpo es esa fuente (la region devuelve un valor, por eso funcion y no
# procedimiento) y mira ALL_ERRORS. OJO: los binds se sustituyen por `v_bind` y
# NO por `null`; con `null` las asignaciones `:P9_X := ...` dan PLS-00363.
#
# Uso (desde la raiz del repo):
#   python deploy/diagnostico/20261120_regiones_dinamicas_compilan.py
#
# Sale con codigo 1 si alguna region no compila.
# =============================================================================

import re
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "conexion"))
import oracledb
from verificar_conexion import CONNECT_STRING, credenciales

ESQUEMA = "WKSP_SYPEXWS"
TEMP = "SPX_PRUEBA_REGION"


def main():
    c = credenciales()
    con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
    cur = con.cursor()
    cur.execute(f"alter session set current_schema = {ESQUEMA}")

    cur.execute("""select page_id, region_id, region_name, region_source
                     from apex_application_page_regions
                    where application_id = 100
                      and function_body_language = 'PLSQL'
                      and region_source is not null
                    order by page_id, display_sequence""")
    filas = cur.fetchall()
    print(f"regiones dinamicas PL/SQL: {len(filas)}")

    malas = 0
    for page_id, region_id, nombre, src in filas:
        cuerpo = re.sub(r":[A-Z0-9_]+", "v_bind", src.read())
        cur.execute(f"begin execute immediate 'drop function {TEMP}'; "
                    "exception when others then null; end;")
        try:
            cur.execute(f"create or replace function {TEMP} return clob is "
                        f"v_bind varchar2(4000); begin {cuerpo} end;")
        except Exception as ex:
            malas += 1
            print(f"[MAL] p{page_id} {region_id} {nombre}: {str(ex)[:160]}")
            continue
        cur.execute("select line, position, substr(text, 1, 110) from all_errors "
                    f"where name = '{TEMP}' and type = 'FUNCTION' order by sequence")
        errs = cur.fetchall()
        if errs:
            malas += 1
            print(f"[MAL] p{page_id} {region_id} {nombre}")
            for e in errs[:5]:
                print("      ", e)

    cur.execute(f"begin execute immediate 'drop function {TEMP}'; "
                "exception when others then null; end;")
    con.close()

    print(f"RESULTADO: FALLAS={malas}")
    return 1 if malas else 0


if __name__ == "__main__":
    sys.exit(main())
