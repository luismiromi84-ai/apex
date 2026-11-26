"""
Pone la banda azul del estandar (cabecera de region con degradado, titulo blanco y 44 px) en las
paginas que nacieron sin ella: 37 «Pago», 42 «Inventario», 43 «Kardex», 44 «Ajuste de inventario»
y 45 «Costos de inventario» (lo detecto la auditoria del 2026-11-25).

Si la pagina ya tiene p_inline_css, el bloque se anade al final; si no, se crea el atributo antes de
p_page_template_options. Idempotente: no repite el bloque si ya esta.

    python deploy/conexion/banda_azul_paginas.py
"""
import io
import re

RUTA = r"C:\Users\luism\OneDrive\Documents\Apex_luis\pagina_apex\f100.sql"
PAGINAS = [28, 37, 42, 43, 44, 45]
MARCA = "Banda azul del estandar"

CSS = [
    "/* Banda azul del estandar (2026-11-25): la misma cabecera que el resto de la app. */",
    ".t-Region-header {",
    "    background: linear-gradient(135deg, #0076ce 0%, #005291 100%) !important;",
    "    border: none !important;",
    "    padding: 0 14px !important;",
    "    --ut-region-header-padding-y: 0.625rem !important;",
    "}",
    ".t-Region-header .t-Region-title, .t-Region-header .t-Region-title * {",
    "    color: #ffffff !important;",
    "    font-weight: 600 !important;",
    "    font-size: 0.95rem !important;",
    "}",
]

texto = io.open(RUTA, encoding="utf-8", newline="").read()
lineas = texto.split("\n")


def literal(s):
    return "'" + s.replace("'", "''") + "'"


hechas = []
for pag in PAGINAS:
    ini = None
    for i, l in enumerate(lineas):
        if l.rstrip("\r") == "wwv_flow_imp_page.create_page(" and \
                lineas[i + 1].rstrip("\r") == " p_id=>%d" % pag:
            ini = i
            break
    if ini is None:
        raise SystemExit("no encontre create_page de la %d" % pag)
    fin = next(k for k in range(ini, ini + 400) if lineas[k].rstrip("\r") == ");")
    cr = "\r" if lineas[ini].endswith("\r") else ""
    if any(MARCA in lineas[k] for k in range(ini, fin)):
        print("pagina %d: ya tenia la banda" % pag)
        continue

    css_k = next((k for k in range(ini, fin)
                  if lineas[k].startswith(",p_inline_css=>wwv_flow_string.join")), None)
    if css_k is not None:
        cierre = next(k for k in range(css_k, fin) if lineas[k].rstrip("\r").endswith("'))"))
        t = lineas[cierre].rstrip("\r")
        nuevas = [t[:-2] + "," + cr]
        for j, c in enumerate(CSS):
            nuevas.append(literal(c) + ("))" if j == len(CSS) - 1 else ",") + cr)
        lineas[cierre:cierre + 1] = nuevas
    else:
        k = next(k for k in range(ini, fin)
                 if lineas[k].startswith(",p_page_template_options"))
        nuevas = [",p_inline_css=>wwv_flow_string.join(wwv_flow_t_varchar2(" + cr]
        for j, c in enumerate(CSS):
            nuevas.append(literal(c) + ("))" if j == len(CSS) - 1 else ",") + cr)
        lineas[k:k] = nuevas
    hechas.append(pag)

io.open(RUTA, "w", encoding="utf-8", newline="").write("\n".join(lineas))
print("banda azul anadida en:", hechas)
