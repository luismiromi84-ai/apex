#!/usr/bin/env python3
# =============================================================================
# probar_subida_logo.py
#
# Reproduce la subida de la pagina 17 SIN navegador: entra con un usuario real,
# arma el mismo POST multipart que haria el formulario y lee la respuesta.
#
# Para que existe: el fallo de la 17 no se puede diagnosticar mirando tablas
# (apex_application_temp_files filtra por sesion y desde SQLcl siempre sale
# vacia). Esto manda el archivo de verdad y dice que contesto APEX.
#
# Uso:
#   python deploy/diagnostico/probar_subida_logo.py admin.demo 'Prueba#2026' 1 archivo.png
# =============================================================================

import mimetypes
import os
import re
import sys
import urllib.error
import urllib.request
import uuid

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "conexion"))
from abrir_pagina import entrar, campos_ocultos  # noqa: E402  (login y campos, reutilizados)

BASE = ("https://gfd7e2575d251ae-sypexsql.adb.mx-monterrey-1.oraclecloudapps.com"
        "/ords")


def campos(pagina):
    """Los campos ocultos del formulario, por name o por id (varios solo tienen id)."""
    return campos_ocultos(pagina)


def multipart(campos_form, archivo, nombre_campo="P17_ARCHIVO"):
    frontera = "----" + uuid.uuid4().hex
    trozos = []
    for nombre, valor in campos_form.items():
        trozos.append(f"--{frontera}\r\nContent-Disposition: form-data; name=\"{nombre}\"\r\n\r\n{valor}\r\n")
    tipo = mimetypes.guess_type(archivo)[0] or "image/png"
    with open(archivo, "rb") as f:
        contenido = f.read()
    nombre_archivo = os.path.basename(archivo)
    trozos.append(
        f"--{frontera}\r\nContent-Disposition: form-data; name=\"{nombre_campo}\"; "
        f"filename=\"{nombre_archivo}\"\r\nContent-Type: {tipo}\r\n\r\n")
    cuerpo = b"".join(t.encode() for t in trozos) + contenido + f"\r\n--{frontera}--\r\n".encode()
    return cuerpo, f"multipart/form-data; boundary={frontera}"


def main():
    if len(sys.argv) < 5:
        sys.exit("uso: probar_subida_logo.py <usuario> <clave> <id_empresa> <archivo>")
    usuario, clave, empresa, archivo = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

    opener, instancia = entrar(usuario, clave)
    pagina = opener.open(f"{BASE}/f?p=100:17:{instancia}", timeout=60).read().decode("utf-8", "replace")
    accion = re.search(r'action="([^"]*wwv_flow\.accept[^"]*)"', pagina)
    if not accion:
        sys.exit("la pagina 17 no trae formulario wwv_flow.accept (HTTP distinto?)")
    print(f"formulario: {accion.group(1)}")

    # Con el item clasico (NATIVE_FILE_BROWSE) el navegador manda el archivo en
    # una parte multipart con el nombre del item.
    c = campos(pagina)
    c["p_flow_id"] = "100"
    c["p_flow_step_id"] = "17"
    c["p_instance"] = instancia
    c["p_request"] = "BTN_SUBIR_LOGO"
    c["P17_ID_EMPRESA"] = empresa
    c.pop("P17_ARCHIVO", None)

    cuerpo, tipo = multipart(c, archivo)
    peticion = urllib.request.Request(
        f"{BASE}/{accion.group(1)}", data=cuerpo,
        headers={"Content-Type": tipo, "Content-Length": str(len(cuerpo))})
    try:
        respuesta = opener.open(peticion, timeout=120).read().decode("utf-8", "replace")
        estado = 200
    except urllib.error.HTTPError as e:
        respuesta = e.read().decode("utf-8", "replace")
        estado = e.code

    print(f"HTTP {estado}, {len(respuesta)} bytes")
    encontrado = False
    for patron in ("Logo guardado", "no llego al servidor", "No se recibio ningun archivo",
                   "no es PNG ni JPEG", "demasiado grande", "ORA-"):
        for m in re.finditer(r'[^<>]{0,160}' + re.escape(patron) + r'[^<>]{0,200}', respuesta, re.I):
            print("  >", m.group(0).strip()[:320].replace("\n", " "))
            encontrado = True
    if not encontrado:
        texto = re.sub(r"<[^>]+>", " ", respuesta)
        texto = re.sub(r"\s+", " ", texto)
        print("  (sin mensaje reconocible) primeros 300:", texto[:300])


if __name__ == "__main__":
    main()
