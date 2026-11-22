"""
Anade el bloque de cabecera compacta al final del CSS de las paginas que pintan la banda azul.

El bloque va AL FINAL del p_inline_css de cada pagina. Lleva `!important` y, donde la pagina usa
selectores mas especificos (`.t-Region.card-3d ...` en las 5 y 8), se repite el mismo selector
para empatar y ganar por orden. No se toca ninguna regla existente.

La pagina 28 («Compra») no tenia la banda azul: se le pone el bloque completo (fondo, titulo
blanco y alto), para que las tres pantallas de compras se lean igual.

Uso:  python deploy/conexion/cabecera_global.py
"""
import io
import re
import sys

RUTA = r"C:\Users\luism\OneDrive\Documents\Apex_luis\pagina_apex\f100.sql"

# Paginas que ya pintan la banda: solo hay que compactarla.
OBJETIVO = ["00003", "00004", "00005", "00006", "00007", "00008", "00009", "00010",
            "00013", "00016", "00017", "00018", "00020", "00022", "00023", "00024",
            "00025", "00027", "00029", "00032", "00033", "00034"]

# Pagina sin banda azul: la 28 lleva el titulo al tema por decision del dueno (2026-11-20).
COMPLETO = []

MARCA = "Cabecera compacta e igual en toda la app"

SEL_COMP = ".t-Region-header, .t-DialogRegion-header, .t-Region.card-3d .t-Region-header"
SEL_TIT = ".t-Region-title, .t-DialogRegion-title, .t-Region.card-3d .t-Region-title"

COMENTARIO = [
    "/* Cabecera compacta e igual en toda la app (2026-11-21): banda de 44 px, como la 19.",
    "   El tema pone 12 px arriba y abajo a .t-Region-headerItems--title con la variable",
    "   --ut-region-header-padding-y; sin moverla el alto no baja, aunque se achique el titulo.",
    "   Se repite .t-Region.card-3d porque las paginas 5 y 8 usan ese selector, mas especifico. */",
]

BLOQUE = COMENTARIO + [
    SEL_COMP + " { padding: 0 14px !important; --ut-region-header-padding-y: 0.625rem !important; }",
    SEL_TIT + " { font-size: 0.95rem !important; }",
    "@media screen { .ui-dialog-titlebar { padding: 8px 14px !important; } }",
    ".ui-dialog-title { font-size: 1.05rem !important; }",
]

BLOQUE_COMPLETO = COMENTARIO + [
    SEL_COMP + " {",
    "    background: linear-gradient(135deg, #0076ce 0%, #005291 100%) !important;",
    "    border: none !important;",
    "    padding: 0 14px !important;",
    "    --ut-region-header-padding-y: 0.625rem !important;",
    "}",
    SEL_TIT + " {",
    "    color: #ffffff !important;",
    "    font-weight: 600 !important;",
    "    font-size: 0.95rem !important;",
    "}",
    "@media screen { .ui-dialog-titlebar { padding: 8px 14px !important; } }",
    ".ui-dialog-title { font-size: 1.05rem !important; }",
]

texto = io.open(RUTA, encoding="utf-8", newline="").read()
lineas = texto.split("\n")


def prompts():
    out = []
    for i, l in enumerate(lineas):
        m = re.match(r"\s*prompt --application/pages/page_(\d+)\s*$", l.rstrip("\r"))
        if m:
            out.append((i, m.group(1)))
    return out


hechas, fallos = [], []
lista = prompts()

# de atras hacia adelante: asi los indices de las paginas anteriores no se desplazan
for n in range(len(lista) - 1, -1, -1):
    i, pag = lista[n]
    if pag not in OBJETIVO and pag not in COMPLETO:
        continue
    fin = lista[n + 1][0] if n + 1 < len(lista) else len(lineas)
    bloque = BLOQUE if pag in OBJETIVO else BLOQUE_COMPLETO

    ini = None
    for k in range(i, fin):
        if "p_inline_css=>wwv_flow_string.join(wwv_flow_t_varchar2(" in lineas[k]:
            ini = k
            break
    if ini is None:
        fallos.append((pag, "no tiene p_inline_css"))
        continue

    ult = None
    cierre = None
    cierre_suelto = False
    for k in range(ini, fin):
        t = lineas[k].rstrip("\r")
        if t.endswith("')))"):
            ult, cierre = k, "')))"
            break
        if t.endswith("'))"):
            ult, cierre = k, "'))"
            break
        if t.strip() == "))":
            ult, cierre = k - 1, "'"
            cierre_suelto = True
            break
    if ult is None:
        fallos.append((pag, "no encontre el cierre del join"))
        continue

    if any(MARCA in lineas[k] for k in range(ini, ult + 1)):
        fallos.append((pag, "ya tenia el bloque"))
        continue

    t = lineas[ult]
    cr = "\r" if t.endswith("\r") else ""
    t0 = t.rstrip("\r")
    if cierre_suelto:
        cuerpo = t0
    elif t0.endswith("')))"):
        cuerpo = t0[:-3]
    elif t0.endswith("'))"):
        cuerpo = t0[:-2]
    else:
        fallos.append((pag, "cierre inesperado: " + t0[-30:]))
        continue
    if not cuerpo.rstrip().endswith("'"):
        fallos.append((pag, "el ultimo elemento no acaba en comilla: " + cuerpo[-40:]))
        continue

    nuevas = [cuerpo.rstrip() + ","]
    for j, css in enumerate(bloque):
        ultimo = (j == len(bloque) - 1)
        nuevas.append("'" + css + (cierre if ultimo else "',"))
    nuevas[-1] += cr

    lineas[ult:ult + 1] = nuevas
    hechas.append(pag)

io.open(RUTA, "w", encoding="utf-8", newline="").write("\n".join(lineas))
print("paginas con el bloque:", len(hechas))
print("  " + ", ".join(reversed(hechas)))
if fallos:
    print("SIN TOCAR:")
    for p, m in fallos:
        print("  pagina", p, "-", m)
    sys.exit(1)
