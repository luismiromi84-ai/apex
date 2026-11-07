# -*- coding: utf-8 -*-
"""
Genera una version PUBLICA y autocontenida de la portada (pagina 15).

Uso:
    python libreria/portada/construir_publicacion.py

Entrada : libreria/portada/portada_synpex.html   (fuente canonica, la que se importa a APEX)
Salida  : libreria/portada/publicar/index.html   (un solo archivo, sin dependencias externas)

Que cambia respecto de la fuente canonica:
  - Se envuelve en un documento HTML completo (<!DOCTYPE>, meta charset, viewport, title).
  - El logo (#APP_IMAGES#logo_synpex.png, que en APEX sirve desde /i/...) se incrusta como
    data URI con libreria/variantes/logo_3d_sin_fondo_700.png, que es el mismo archivo.
  - `margin:-16px -16px 0 -16px` pasa a `margin:0`: ese negativo compensa el padding de la
    region de APEX y en una pagina suelta provocaria desbordamiento horizontal.
  - Los enlaces `f?p=&APP_ID.:15:&APP_SESSION.` (marca) pasan a anclas locales.
  - `f?p=&APP_ID.:1:&APP_SESSION.` («Ingresar») pasa a la URL viva del login; solo funciona
    para IPs autorizadas en la ACL del Autonomous Database (ver README de publicar/).

La salida es HTML+CSS puro: cero JavaScript, cero fuentes ni CDN externos.
"""

import base64
import pathlib
import re
import sys

AQUI = pathlib.Path(__file__).resolve().parent
FUENTE = AQUI / "portada_synpex.html"
LOGO = AQUI.parent / "variantes" / "logo_3d_sin_fondo_700.png"
SALIDA = AQUI / "publicar" / "index.html"

APP_URL = "https://gfd7e2575d251ae-sypexsql.adb.mx-monterrey-1.oraclecloudapps.com/ords/f?p=100"
INGRESAR_URL = APP_URL + ":1"

TITULO = "Synpex - Sistema de gestion empresarial"
DESCRIPCION = (
    "Synpex: presupuestos, facturacion y control de clientes para empresas en "
    "Mexico y Venezuela. Solicite una demostracion."
)

PLANTILLA = """<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{titulo}</title>
<meta name="description" content="{descripcion}">
<meta name="theme-color" content="#0b2a5b">
<style>
  html, body {{ margin:0; padding:0; background:#fff; }}
  body {{ -webkit-font-smoothing:antialiased; }}
</style>
</head>
<body>
{cuerpo}
</body>
</html>
"""


def fallar(mensaje: str) -> None:
    print("FALLO: " + mensaje)
    sys.exit(1)


def main() -> int:
    if not FUENTE.exists():
        fallar("no existe " + str(FUENTE))
    if not LOGO.exists():
        fallar("no existe el logo " + str(LOGO))

    html = FUENTE.read_text(encoding="utf-8")
    logo_b64 = base64.b64encode(LOGO.read_bytes()).decode("ascii")
    data_uri = "data:image/png;base64," + logo_b64

    # 1. logo incrustado
    if '#APP_IMAGES#logo_synpex.png' not in html:
        fallar("la fuente no referencia #APP_IMAGES#logo_synpex.png; revisa la portada canonica")
    html = html.replace('src="#APP_IMAGES#logo_synpex.png"', 'src="' + data_uri + '"')

    # 2. margen negativo de la region de APEX
    if "margin:-16px -16px 0 -16px;" not in html:
        fallar("no encontre el margen negativo de la region; revisa el CSS de la portada")
    html = html.replace("margin:-16px -16px 0 -16px;", "margin:0;")

    # 3. enlaces de APEX
    html = html.replace('href="f?p=&APP_ID.:15:&APP_SESSION."', 'href="#spx-inicio"')
    html = html.replace('href="f?p=&APP_ID.:1:&APP_SESSION."', 'href="' + INGRESAR_URL + '"')

    resto = re.findall(r"#APP_[A-Z_]+#|&APP_ID\.|&APP_SESSION\.", html)
    if resto:
        fallar("quedaron marcas de APEX sin sustituir: " + ", ".join(sorted(set(resto))))

    documento = PLANTILLA.format(titulo=TITULO, descripcion=DESCRIPCION, cuerpo=html.strip())

    SALIDA.parent.mkdir(parents=True, exist_ok=True)
    SALIDA.write_text(documento, encoding="utf-8", newline="\n")

    # --- verificacion ---
    fallas = 0

    def revisar(ok: bool, descripcion_: str) -> None:
        nonlocal fallas
        if not ok:
            fallas += 1
            print("  [FALLA] " + descripcion_)

    print("salida: " + str(SALIDA))
    print("bytes : " + str(len(documento.encode("utf-8"))))

    for ancla in ("spx-inicio", "spx-servicios", "spx-nosotros", "spx-contacto"):
        revisar('id="' + ancla + '"' in documento and 'href="#' + ancla + '"' in documento,
                "ancla " + ancla)
    revisar("wa.me/528111198920" in documento, "WhatsApp")
    revisar("mailto:luismiromi84@hotmail.com" in documento, "correo")
    revisar("<script" not in documento.lower(), "cero JavaScript")
    revisar("http://" not in documento, "cero recursos por http")
    externos = re.findall(r"https?://", documento)
    permitidos = re.findall(r"https?://wa\.me|" + re.escape(INGRESAR_URL), documento)
    revisar(len(externos) == len(permitidos), "solo enlaces externos: wa.me e Ingresar")
    revisar(documento.count("data:image/png;base64,") == 1, "un solo logo incrustado")
    revisar("\ufffd" not in documento, "sin caracteres de reemplazo")
    revisar(documento.startswith("<!DOCTYPE html>"), "documento completo")
    revisar(documento.rstrip().endswith("</html>"), "cierre de documento")

    print("FALLAS=" + str(fallas))
    return 1 if fallas else 0


if __name__ == "__main__":
    sys.exit(main())
