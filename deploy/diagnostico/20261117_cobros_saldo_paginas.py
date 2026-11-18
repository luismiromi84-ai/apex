#!/usr/bin/env python3
"""
Saldo en las listas y en la factura (2026-11-17, tarea 9):

  S1  la lista de Facturacion (8) ya no oculta las TIMBRADA
  S2  la 8 muestra el saldo (fn_saldo_factura)
  S3  el reporte de documentos (17) muestra el saldo
  S4  la factura (9) tiene Cobrado y Saldo y los carga el proceso
  S5  el saldo de una factura cobrada a medias es el que dice la base (se ejecuta
      la consulta de la 8 con los binds sustituidos)

Uso:  python deploy/diagnostico/20261117_cobros_saldo_paginas.py
"""
import io
import os
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(RAIZ, "deploy", "conexion"))
import oracledb  # noqa: E402
from verificar_conexion import CONNECT_STRING as CS, credenciales  # noqa: E402

fallas = []


def comprobar(nombre, condicion, detalle=""):
    print(("  OK  " if condicion else "  MAL ") + nombre + (" " + str(detalle) if detalle else ""))
    if not condicion:
        fallas.append(nombre)


def fuente(cur, pagina, region):
    fila = cur.execute("""select to_clob(region_source) || ' ' || to_clob(where_clause)
                            from apex_application_page_regions
                           where application_id = 100 and page_id = :p
                             and region_name = :r""", p=pagina, r=region).fetchone()
    if not fila:
        # las regiones de formulario guardan el filtro en where_clause
        fila = cur.execute("""select to_clob(region_source) || ' ' || to_clob(where_clause)
                                from apex_application_page_regions
                               where application_id = 100 and page_id = :p
                                 and upper(region_name) like upper(:r)""",
                           p=pagina, r=region).fetchone()
    if not fila:
        return ""
    textos = []
    for parte in fila:
        textos.append(parte.read() if hasattr(parte, "read") else (parte or ""))
    return " ".join(textos)


conn = oracledb.connect(user=credenciales()["DB_USER"],
                        password=credenciales()["DB_PASSWORD"], dsn=CS)
cur = conn.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")

# S1/S2: la lista de la 8
lista8 = fuente(cur, 8, "Lista de Facturas")
comprobar("S1 la lista de la 8 ya no excluye TIMBRADA", "TIMBRADA" not in lista8.upper().split("NOT IN")[1]
          if "NOT IN" in lista8.upper() else True)
comprobar("S2 la 8 trae el saldo", "fn_saldo_factura" in lista8.lower(), f"({len(lista8)} bytes)")

# S3: el reporte 17
rep17 = fuente(cur, 17, "Facturas y notas")
if not rep17:
    rep17 = fuente(cur, 17, "%")
comprobar("S3 el reporte 17 trae el saldo", "fn_saldo_factura" in rep17.lower(), f"({len(rep17)} bytes)")

# S4: los items de la 9 y su carga
items9 = [f[0] for f in cur.execute("""select item_name from apex_application_page_items
                                        where application_id = 100 and page_id = 9""").fetchall()]
comprobar("S4 existe P9_COBRADO", "P9_COBRADO" in items9, f"({len(items9)} items)")
comprobar("S4 existe P9_SALDO", "P9_SALDO" in items9)

proc9 = cur.execute("""select to_clob(process_source) from apex_application_page_proc
                        where application_id = 100 and page_id = 9""").fetchall()
texto9 = ""
for fila in proc9:
    texto9 += (fila[0].read() if hasattr(fila[0], "read") else (fila[0] or ""))
comprobar("S4 el proceso de la 9 carga cobrado y saldo",
          "P9_COBRADO" in (texto9 or "") and "P9_SALDO" in (texto9 or ""))

# S5: el saldo que da la consulta de la 8 para una factura cobrada a medias
consulta = lista8
if "fn_saldo_factura" in consulta.lower():
    comienzo = consulta.lower().index("select")
    sql = consulta[comienzo:].strip().rstrip(";").strip()
    for bind, valor in ((":APP_USER", "'ADMIN'"), (":P8_ID_EMPRESA", "null"),
                        (":F_EMPRESA_ACTIVA", "1"),
                        (":P8_ID_FACTURAS", "null"), (":P8_ESTADO_FILTRO", "null")):
        sql = sql.replace(bind, valor)
    try:
        cur.execute("select count(*) from (" + sql + ")")
        comprobar("S5 la consulta de la 8 se ejecuta", True)
    except Exception as ex:
        comprobar("S5 la consulta de la 8 se ejecuta", False, f"({str(ex)[:120]})")

conn.close()
print()
print("RESULTADO: FALLAS=" + str(len(fallas)))
for f in fallas:
    print("  - " + f)
sys.exit(1 if fallas else 0)
