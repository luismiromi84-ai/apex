# -*- coding: utf-8 -*-
"""
Convierte un .md sencillo a .docx (titulos, vinetas, numeradas, negrita y tablas no soportadas).

Se usa para los documentos de pendientes/pruebas, que el dueno lee en Word. Mantiene el .md como
fuente: si se edita el markdown, se vuelve a lanzar esto.

Uso:
    python "instalacion y migracion/md_a_docx.py" <archivo.md> [<archivo.docx>]

Soporta: `#`, `##`, `###`, parrafos, `- [ ]` / `- [x]` / `- `, `1. `, `**negrita**`, `code`,
lineas separadoras `---` y tablas | a | b | (como parrafos monoespaciados).
"""
import re
import sys

from docx import Document
from docx.shared import Pt, RGBColor


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


def main():
    if len(sys.argv) < 2:
        sys.exit("Uso: python md_a_docx.py <archivo.md> [<archivo.docx>]")
    origen = sys.argv[1]
    destino = sys.argv[2] if len(sys.argv) > 2 else re.sub(r"\.md$", ".docx", origen)

    doc = Document()
    estilo = doc.styles["Normal"]
    estilo.font.name = "Calibri"
    estilo.font.size = Pt(10.5)

    for linea in open(origen, encoding="utf-8"):
        linea = linea.rstrip("\n")
        limpia = linea.strip()

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
        if limpia.startswith("|"):
            parrafo = doc.add_paragraph()
            run = parrafo.add_run(limpia)
            run.font.name = "Consolas"
            run.font.size = Pt(8.5)
            continue
        trozos(doc.add_paragraph(), limpia)

    doc.save(destino)
    print("escrito:", destino, "|", len(doc.paragraphs), "parrafos")


if __name__ == "__main__":
    main()
