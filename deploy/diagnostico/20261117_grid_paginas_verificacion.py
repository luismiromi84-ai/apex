#!/usr/bin/env python3
"""
Comprueba que ninguna region de items del export de la app 100 desborda la
rejilla de 12 columnas de APEX.

APEX calcula la columna de cada item al pintar, en orden de secuencia, sumando
`p_colspan` (1 si no se indica) y empezando fila nueva cuando el item lleva
`p_begin_on_new_line` distinto de 'N'. Si una fila pasa de 12, la pagina muere
con HTTP 400:

    WWV_FLOW_GRID_LAYOUT.MORE_THAN_SUPPORTED_COLUMNS
    Component Pxx_NOMBRE ... Column 13 ... Column Span 3 ...

El calculo de aqui cuenta **todos** los items visibles de la region, como el
peor caso: los campos exclusivos por condicion (p.ej. NRO_CONTROL de VE y
UUID_FISCAL de MX) se cuentan los dos. Es deliberado: si la suma del peor caso
cabe, cualquier combinacion real cabe.

Uso:  python deploy/diagnostico/20261117_grid_paginas_verificacion.py
Sale 1 si hay alguna fila con mas de 12 columnas.
"""
import os
import re
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
EXPORT = os.path.join(RAIZ, "pagina_apex", "f100.sql")
COLS = 12

# Parejas de items que NUNCA se pintan juntos: ocupan la misma casilla porque sus
# condiciones son excluyentes. Se cuenta uno solo (si no, el peor caso da un
# falso positivo). Se declaran a mano y con su motivo.
EXCLUSIVOS = {
    "P9_UUID_FISCAL": "P9_NRO_CONTROL",   # UUID es de Mexico, N de Control de Venezuela
}


def paginas(txt):
    """Devuelve [(n_pagina, texto_de_la_pagina)] a partir de los prompt del export."""
    marcas = [(m.start(), m.group(1)) for m in re.finditer(
        r"prompt --application/pages/page_(\d+)", txt)]
    for i, (pos, num) in enumerate(marcas):
        fin = marcas[i + 1][0] if i + 1 < len(marcas) else len(txt)
        yield num, txt[pos:fin]


def items(seccion):
    """[(region, seq, nombre, span, nueva_fila, hidden)] de los create_page_item de la seccion.

    La rejilla es **por region**: dos items de regiones distintas nunca comparten
    fila, asi que se agrupan por `p_item_plug_id` (el id de la region).
    """
    salida = []
    for bloque in seccion.split("wwv_flow_imp_page.create_page_item(")[1:]:
        nombre = re.search(r"p_name=>'([^']+)'", bloque)
        if not nombre:
            continue
        region = re.search(r"p_item_plug_id=>wwv_flow_imp\.id\((\d+)\)", bloque)
        seq = re.search(r"p_item_sequence=>(\d+)", bloque)
        span = re.search(r"p_colspan=>(\d+)", bloque)
        nueva = re.search(r"p_begin_on_new_line=>'(\w)'", bloque)
        dsp = re.search(r"p_display_as=>'([^']+)'", bloque)
        salida.append((
            region.group(1) if region else "?",
            int(seq.group(1)) if seq else 0,
            nombre.group(1),
            int(span.group(1)) if span else 1,
            (nueva.group(1) if nueva else "Y") == "Y",
            (dsp.group(1) if dsp else "") == "NATIVE_HIDDEN",
        ))
    salida.sort(key=lambda r: (r[0], r[1]))
    return salida


def filas_desbordadas(region_items):
    """Agrupa en filas (dentro de una region) y devuelve las que pasan de COLS."""
    malas = []
    fila, usado = [], 0
    for _, seq, nombre, span, nueva, hidden in region_items:
        if hidden:
            continue
        if nombre in EXCLUSIVOS and any(f[0] == EXCLUSIVOS[nombre] for f in fila):
            continue
        if nueva or not fila:
            if fila and usado > COLS:
                malas.append((fila, usado))
            fila, usado = [], 0
        fila.append((nombre, span, usado + 1, usado + span))
        usado += span
    if fila and usado > COLS:
        malas.append((fila, usado))
    return malas


def main():
    txt = open(EXPORT, encoding="utf-8", errors="replace").read()
    fallas = 0
    for num in sorted({n for n, _ in paginas(txt)}, key=int):
        for seccion in [s for n, s in paginas(txt) if n == num]:
            por_region = {}
            for it in items(seccion):
                por_region.setdefault(it[0], []).append(it)
            for region, lista in por_region.items():
                for fila, usado in filas_desbordadas(lista):
                    fallas += 1
                    print(f"FALLA pagina {num} (region {region}): fila de {usado} columnas")
                    for nombre, span, desde, hasta in fila:
                        marca = "  <-- se sale" if hasta > COLS else ""
                        print(f"    {nombre:<36} span {span}  cols {desde}..{hasta}{marca}")
    print(f"RESULTADO: FALLAS={fallas}")
    sys.exit(1 if fallas else 0)


if __name__ == "__main__":
    main()
