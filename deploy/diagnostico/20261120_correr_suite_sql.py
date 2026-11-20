#!/usr/bin/env python3
# =============================================================================
# 20261120_correr_suite_sql.py
#
# Corre las verificaciones SQL de deploy/diagnostico/ que terminan en
#   RESULTADO: FALLAS=n
# en UNA sola conexion y devuelve una tabla. Usa el mismo troceado de
# sentencias que deploy/conexion/importar_export.py (las lineas que empiezan
# por SET/EXIT/PROMPT/... se descartan, igual que en el runner del repo).
#
# Uso:
#   python deploy/diagnostico/20261120_correr_suite_sql.py            # todas
#   python deploy/diagnostico/20261120_correr_suite_sql.py a.sql b.sql
#
# Las que NO llevan el fixture (20261110_multiempresa, 20261118_folios) se
# pasan a mano despues de limpiar el fixture.
# =============================================================================

import os
import re
import sys

import oracledb

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(REPO, "deploy", "conexion"))

from importar_export import CONNECT_STRING, credenciales, sentencias  # noqa: E402

DIAG = os.path.join(REPO, "deploy", "diagnostico")

SIN_FIXTURE = {"20261110_multiempresa_verificacion.sql", "20261118_folios_verificacion.sql"}


def archivos():
    nombres = []
    for nombre in sorted(os.listdir(DIAG)):
        if not nombre.endswith(".sql"):
            continue
        if nombre in SIN_FIXTURE:
            continue
        ruta = os.path.join(DIAG, nombre)
        with open(ruta, encoding="utf-8", errors="replace") as f:
            texto = f.read()
        if "RESULTADO: FALLAS=" in texto:
            nombres.append(nombre)
    return nombres


def correr(cur, nombre):
    ruta = os.path.join(DIAG, nombre)
    for bloque in sentencias(ruta):
        if not bloque.strip(" ;\n"):
            continue
        cuerpo = bloque.rstrip()
        es_plsql = cuerpo.lstrip().lower().startswith(("begin", "declare", "create or replace"))
        if cuerpo.endswith(";") and not es_plsql:
            cuerpo = cuerpo[:-1]
        try:
            cur.execute(cuerpo)
        except oracledb.DatabaseError as ex:
            error, = ex.args
            mensaje = error.message or ""
            if abs(error.code) == 20100 and "RESULTADO: FALLAS=" in mensaje:
                m = re.search(r"RESULTADO: FALLAS=(\d+)", mensaje)
                resto = mensaje.split("RESULTADO: FALLAS=", 1)[1]
                detalle = resto.split("|", 1)[1].strip() if "|" in resto else ""
                return int(m.group(1)), detalle
            return None, f"ERROR {error.code}: {mensaje[:300]}"
    return None, "sin RESULTADO (no llego al raise final)"


def main():
    nombres = sys.argv[1:] or archivos()
    nombres = [os.path.basename(n) for n in nombres]
    datos = credenciales()
    filas = []
    with oracledb.connect(user=datos["DB_USER"], password=datos["DB_PASSWORD"], dsn=CONNECT_STRING) as con:
        cur = con.cursor()
        for nombre in nombres:
            fallas, detalle = correr(cur, nombre)
            try:
                con.rollback()
            except oracledb.DatabaseError:
                pass
            filas.append((nombre, fallas, detalle))
            estado = "?" if fallas is None else ("OK" if fallas == 0 else "ROJO")
            corto = " ".join(detalle.split())[:200]
            print(f"{estado:4} {nombre}  FALLAS={fallas}  {corto}", flush=True)

    rojos = [f for f in filas if f[1] != 0]
    print()
    print(f"total={len(filas)} verdes={len(filas) - len(rojos)} rojos={len(rojos)}")
    return 0 if not rojos else 1


if __name__ == "__main__":
    sys.exit(main())
