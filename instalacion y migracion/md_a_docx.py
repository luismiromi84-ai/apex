# -*- coding: utf-8 -*-
"""
Convierte un .md sencillo a .docx (titulos, vinetas, numeradas, negrita y TABLAS REALES).

Se usa para los documentos de pendientes/pruebas, que el dueno lee en Word. Mantiene el .md como
fuente: si se edita el markdown, se vuelve a lanzar esto.

Uso:
    python "instalacion y migracion/md_a_docx.py" <archivo.md> [<archivo.docx>]

Soporta: `#`, `##`, `###`, parrafos, `- [ ]` / `- [x]` / `- `, `1. `, `**negrita**`, `code`,
lineas separadoras `---` y tablas `| a | b |` (se convierten en una tabla de Word con cabecera en
negrita; la fila separadora `|---|` se descarta).

Desde el 2026-11-08 las tablas son tablas de verdad: la matriz de roles se lee como matriz y no como
parrafos monoespaciados.
"""
import os
import re
import sys

from docx import Document
from docx.shared import Pt, RGBColor, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH


def trozos(parrafo, texto):
    """Anade `texto` al parrafo interpretando **negrita** y `codigo`."""
    for parte in re.split(r"(\*\*[^*]+\*\*|`[^`]+`)", texto):
        if not parte:
            continue
        if parte.startswith("**") and parte.endswith("**"):
            negrita = parrafo.add_run(parte[2:-2])
            negrita.bold = True
        elif parte.startswith("`") and parte.endswith("`"):
            codigo = parrafo.add_run(parte[1:-1])
            codigo.font.name = "Consolas"
            codigo.font.size = Pt(9)
        else:
            parrafo.add_run(parte)


def tabla_docx(doc, filas):
    """Convierte un bloque markdown `| a | b |` en una tabla real de Word.

    La fila separadora (`|---|---|` o `|:--|:--:|`) se descarta. La primera fila
    va en negrita como cabecera. Se usa el estilo "Table Grid", que existe en la
    plantilla por defecto de python-docx.
    """
    celdas = []
    for linea in filas:
        partes = [c.strip() for c in linea.strip().strip("|").split("|")]
        # Separador (|---|---|). OJO: una fila de celdas vacias NO es separador;
        # si se confunden, desaparecen las filas en blanco de las plantillas.
        no_vacias = [c for c in partes if c != ""]
        if no_vacias and all(re.match(r"^:?-{2,}:?$", c) for c in no_vacias):
            continue
        celdas.append(partes)
    if not celdas:
        return

    ancho = max(len(f) for f in celdas)
    celdas = [f + [""] * (ancho - len(f)) for f in celdas]

    tabla = doc.add_table(rows=len(celdas), cols=ancho)
    tabla.style = "Table Grid"
    for r, fila in enumerate(celdas):
        for c, valor in enumerate(fila):
            parrafo = tabla.cell(r, c).paragraphs[0]
            trozos(parrafo, valor)
            if r == 0:
                for run in parrafo.runs:
                    run.bold = True
    doc.add_paragraph()


def main():
    if len(sys.argv) < 2:
        sys.exit("Uso: python md_a_docx.py <archivo.md> [<archivo.docx>]")
    origen = sys.argv[1]
    destino = sys.argv[2] if len(sys.argv) > 2 else re.sub(r"\.md$", ".docx", origen)

    doc = Document()
    estilo = doc.styles["Normal"]
    estilo.font.name = "Calibri"
    estilo.font.size = Pt(10.5)

    lineas = [l.rstrip("\n") for l in open(origen, encoding="utf-8")]
    i = 0
    while i < len(lineas):
        limpia = lineas[i].strip()
        i += 1

        if not limpia:
            continue
        if limpia.startswith("---"):
            doc.add_paragraph("_" * 78).runs[0].font.color.rgb = RGBColor(0xAA, 0xAA, 0xAA)
            continue
        if limpia.startswith("#"):
            nivel = len(limpia) - len(limpia.lstrip("#"))
            trozos(doc.add_heading(level=min(nivel, 3)), limpia[nivel:].strip())
            continue
        if limpia.startswith("- [ ]"):
            trozos(doc.add_paragraph(style="List Bullet"), "[   ]  " + limpia[5:].strip())
            continue
        if limpia.startswith("- [x]") or limpia.startswith("- [X]"):
            trozos(doc.add_paragraph(style="List Bullet"), "[ X ]  " + limpia[5:].strip())
            continue
        if limpia.startswith("- "):
            trozos(doc.add_paragraph(style="List Bullet"), limpia[2:].strip())
            continue
        numerada = re.match(r"^(\d+)\.\s+(.*)$", limpia)
        if numerada:
            trozos(doc.add_paragraph(style="List Number"), numerada.group(2))
            continue
        imagen = re.match(r"^!\[([^\]]*)\]\(([^)]+)\)$", limpia)
        if imagen:
            alt, rel = imagen.group(1).strip(), imagen.group(2).strip()
            ruta_img = rel if os.path.isabs(rel) else os.path.join(
                os.path.dirname(os.path.abspath(origen)), rel.replace("/", os.sep))
            if os.path.exists(ruta_img):
                try:
                    doc.add_picture(ruta_img, width=Inches(6.0))
                    doc.paragraphs[-1].alignment = WD_ALIGN_PARAGRAPH.CENTER
                except Exception as e:
                    doc.add_paragraph("[imagen no legible: %s (%s)]" % (rel, e))
            else:
                doc.add_paragraph("[imagen no encontrada: %s]" % rel)
            if alt:
                pie = doc.add_paragraph()
                pie.alignment = WD_ALIGN_PARAGRAPH.CENTER
                run = pie.add_run(alt)
                run.italic = True
                run.font.size = Pt(8)
                run.font.color.rgb = RGBColor(0x55, 0x55, 0x55)
            continue
        if limpia.startswith("|"):
            filas = [limpia]
            while i < len(lineas) and lineas[i].strip().startswith("|"):
                filas.append(lineas[i].strip())
                i += 1
            tabla_docx(doc, filas)
            continue
        trozos(doc.add_paragraph(), limpia)

    doc.save(destino)
    print("escrito:", destino, "|", len(doc.paragraphs), "parrafos |", len(doc.tables), "tablas")


if __name__ == "__main__":
    main()
