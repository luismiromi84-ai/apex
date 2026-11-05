#!/usr/bin/env python3
# =============================================================================
# compilar_objeto.py
#
# Compila UN objeto (funcion, procedimiento, package, trigger) desde un archivo
# canonico del repo, sin pasar por importar_export.py.
#
# Por que existe: importar_export.py descarta las lineas que empiezan por
# 'set ', 'prompt ', 'column ', 'define ', 'spool ', 'show ' o 'exit', porque
# las confunde con comandos de SQL*Plus. Dentro de un PACKAGE BODY eso rompe
# los UPDATE que llevan 'set' al inicio de linea: el objeto compila con
# ORA-00971 "missing SET keyword" y queda INVALID. Medido el 2026-11-05 con
# pkg_facturacion.
#
# Tambien antepone el 'alter session set current_schema', que los archivos
# canonicos no llevan: sin el, el objeto se crea en el esquema del usuario de
# conexion (ADMIN) y la app sigue usando el viejo.
#
# Uso:
#   python deploy/conexion/compilar_objeto.py package_bodies/pkg_facturacion.sql
#   python deploy/conexion/compilar_objeto.py funciones/fn_tiene_rol.sql --esquema WKSP_SYPEXWS
# =============================================================================

import argparse
import os
import sys

import oracledb

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

CONNECT_STRING = (
    "(DESCRIPTION=(RETRY_COUNT=5)(RETRY_DELAY=2)"
    "(ADDRESS=(PROTOCOL=TCPS)(PORT=1521)(HOST=adb.mx-monterrey-1.oraclecloud.com))"
    "(CONNECT_DATA=(SERVICE_NAME=GFD7E2575D251AE_SYPEXSQL_high.adb.oraclecloud.com))"
    "(SECURITY=(SSL_SERVER_DN_MATCH=YES)))"
)


def credenciales():
    datos = {}
    ruta = os.path.join(REPO, ".env")
    if os.path.exists(ruta):
        with open(ruta, encoding="utf-8") as f:
            for linea in f:
                linea = linea.strip()
                if linea and not linea.startswith("#") and "=" in linea:
                    clave, valor = linea.split("=", 1)
                    datos[clave.strip()] = valor.strip()
    datos["DB_USER"] = os.environ.get("DB_USER", datos.get("DB_USER"))
    datos["DB_PASSWORD"] = os.environ.get("DB_PASSWORD", datos.get("DB_PASSWORD"))
    if not datos.get("DB_USER") or not datos.get("DB_PASSWORD"):
        sys.exit("Faltan DB_USER y/o DB_PASSWORD (entorno o .env de la raiz).")
    return datos


def bloques(ruta):
    """Parte el archivo por lineas que sean exactamente '/' y NO filtra nada."""
    with open(ruta, encoding="utf-8") as f:
        lineas = f.read().replace("\r\n", "\n").split("\n")
    buffer, salida = [], []
    for linea in lineas:
        if linea.strip() == "/":
            if "\n".join(buffer).strip():
                salida.append("\n".join(buffer))
            buffer = []
            continue
        buffer.append(linea)
    if "\n".join(buffer).strip():
        salida.append("\n".join(buffer))
    return salida


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("archivo")
    ap.add_argument("--esquema", default="WKSP_SYPEXWS")
    args = ap.parse_args()

    ruta = args.archivo if os.path.isabs(args.archivo) else os.path.join(REPO, args.archivo)
    lista = bloques(ruta)
    print(f"{os.path.basename(ruta)}: {len(lista)} bloque(s)")

    datos = credenciales()
    with oracledb.connect(user=datos["DB_USER"], password=datos["DB_PASSWORD"], dsn=CONNECT_STRING) as con:
        cur = con.cursor()
        cur.execute(f"alter session set current_schema = {args.esquema}")
        for numero, bloque in enumerate(lista, 1):
            cuerpo = bloque.strip()
            if not cuerpo:
                continue
            # NO se quita el ';' final: en un bloque PL/SQL (function, procedure,
            # package, trigger) es parte de la sentencia. El '/' del archivo ya
            # marca donde termina.
            try:
                cur.execute(cuerpo)
            except oracledb.DatabaseError as ex:
                error, = ex.args
                print(f"FALLO en el bloque {numero} (codigo {error.code}): {error.message}")
                print("--- inicio ---")
                print("\n".join(bloque.splitlines()[:12]))
                sys.exit(1)
        con.commit()

    print("compilado sin error")


if __name__ == "__main__":
    main()
