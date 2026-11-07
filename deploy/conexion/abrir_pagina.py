#!/usr/bin/env python3
# =============================================================================
# abrir_pagina.py
#
# Abre una pagina de la app con un usuario real (login programatico) y guarda el
# HTML en un archivo, para poder revisarlo sin navegador.
#
# Por que existe: las paginas NO modales se pueden leer tal cual, y eso permite
# comprobar el HTML que genera APEX (iconos, clases, orden de los campos) sin
# depender de una captura. Las paginas modales (6, 7, 9, 10) no sirven por esta
# via: piden `p_dialog_cs` y la proteccion de pagina responde 400 o
# «Violacion de la proteccion del estado de la sesion».
#
# Uso (desde la raiz del repo):
#   python deploy/conexion/abrir_pagina.py admin.demo 'Prueba#2026' 5 pagina5.html
#   python deploy/conexion/abrir_pagina.py admin.demo 'Prueba#2026' 11 pagina11.html P11_ID_FACTURA=1040
#
# El ultimo argumento, opcional, son items de pagina separados por ';'
# (nombre=valor). Ojo: las paginas 5-12 tienen «Arguments Must Have Checksum»,
# asi que pasar items por la URL da violacion de proteccion; solo funciona en
# las que no llevan checksum (las de impresion, por ejemplo).
#
# Devuelve el codigo HTTP y el tamano. Sale con codigo 1 si no puede entrar.
# =============================================================================

import html as ht
import http.cookiejar
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from json import dumps

BASE = ("https://gfd7e2575d251ae-sypexsql.adb.mx-monterrey-1.oraclecloudapps.com"
        "/ords")


def campos_ocultos(pagina):
    """Los inputs ocultos del formulario, por name o por id (varios solo tienen id)."""
    campos = {}
    for m in re.finditer(r'<input[^>]*type="hidden"[^>]*>', pagina):
        etiqueta = m.group(0)
        nombre = re.search(r'name="([^"]+)"', etiqueta) or re.search(r'id="([^"]+)"', etiqueta)
        valor = re.search(r'value="([^"]*)"', etiqueta)
        if nombre:
            campos[nombre.group(1)] = ht.unescape(valor.group(1)) if valor else ""
    return campos


def entrar(usuario, clave):
    """Login real contra la pagina 9999. Devuelve (opener, instancia_de_sesion)."""
    cj = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
    pagina = opener.open(f"{BASE}/f?p=100:9999", timeout=60).read().decode("utf-8", "replace")
    campos = campos_ocultos(pagina)
    instancia = campos.get("p_instance")
    if not instancia:
        raise SystemExit("la pagina de login no trae p_instance")

    # APEX exige el salt y el checksum de los items protegidos; sin ellos
    # responde «Violacion de la proteccion de la pagina».
    cuerpo = dumps({
        "pageItems": {
            "itemsToSubmit": [{"n": "P9999_USERNAME", "v": usuario},
                              {"n": "P9999_PASSWORD", "v": clave}],
            "protected": campos.get("pPageItemsProtected", ""),
            "rowVersion": campos.get("pPageItemsRowVersion", ""),
            "formRegionChecksums": [],
        },
        "salt": campos.get("pSalt", ""),
    })
    datos = {"p_flow_id": "100", "p_flow_step_id": "9999", "p_instance": instancia,
             "p_page_submission_id": campos.get("p_page_submission_id", ""),
             "p_request": "LOGIN", "p_reload_on_submit": "S", "p_json": cuerpo}
    peticion = urllib.request.Request(
        f"{BASE}/wwv_flow.accept?p_context=synpex/login/{instancia}",
        data=urllib.parse.urlencode(datos).encode("utf-8"),
        headers={"Content-Type": "application/x-www-form-urlencoded"})
    respuesta = opener.open(peticion, timeout=60).read().decode("utf-8", "replace")

    m = re.search(r'session=(\d+)', respuesta)
    if not m:
        raise SystemExit("login fallido: " + respuesta[:300])
    return opener, m.group(1)


def main():
    if len(sys.argv) < 5:
        sys.exit("Uso: python deploy/conexion/abrir_pagina.py <usuario> <clave> "
                 "<pagina> <archivo.html> [ITEM=valor;ITEM=valor]")
    usuario, clave, pagina, archivo = sys.argv[1:5]
    items = sys.argv[5] if len(sys.argv) > 5 else ""

    opener, sesion = entrar(usuario, clave)
    url = f"{BASE}/f?p=100:{pagina}:{sesion}"
    if items:
        partes = [p for p in items.split(";") if p]
        nombres = ",".join(p.split("=")[0] for p in partes)
        valores = ",".join(p.split("=", 1)[1] for p in partes)
        url += f":::{nombres}:{valores}"

    try:
        r = opener.open(url, timeout=60)
        codigo, cuerpo = r.status, r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        codigo, cuerpo = e.code, e.read().decode("utf-8", "replace")

    with open(archivo, "w", encoding="utf-8") as f:
        f.write(cuerpo)
    print(f"{usuario} pagina {pagina}: HTTP {codigo}, {len(cuerpo):,} bytes -> {archivo}")


# Se expone entrar() para otros diagnosticos (probar_subida_logo.py). Con la
# guarda, importar este archivo ya no dispara una peticion.
if __name__ == "__main__":
    main()
