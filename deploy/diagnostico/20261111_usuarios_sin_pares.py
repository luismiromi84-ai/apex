#!/usr/bin/env python3
"""Un DELETE de USUARIO sin borrar antes sus pares de USUARIO_EMPRESA falla.

Desde multiempresa (2026-11-10) `FK_UE_USUARIO` impide borrar un usuario que
tiene filas en `USUARIO_EMPRESA` (NO ACTION, a proposito). Y en esta ADB borrar
el hijo y el padre en la MISMA transaccion da `ORA-12860` (sibling row lock),
asi que el borrado de los pares tiene que ir **antes y con commit en medio**.

Este script recorre los `.sql` versionados y avisa de cada `delete from usuario`
que no vaya precedido, en la misma sentencia o en las 20 lineas anteriores, de
un `delete from usuario_empresa`. Las lineas comentadas (`--`) no cuentan: lo
que se vigila es lo que se ejecuta.

Uso:  python deploy/diagnostico/20261111_usuarios_sin_pares.py
Sale con codigo 1 si encuentra alguno.
"""
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
VENTANA = 20

re_usuario = re.compile(r"^\s*delete\s+from\s+usuario\s", re.IGNORECASE)
re_pares = re.compile(r"delete\s+from\s+usuario_empresa\b", re.IGNORECASE)


def versionados():
    salida = subprocess.run(["git", "ls-files", "*.sql"], cwd=REPO,
                            capture_output=True, text=True, check=True).stdout
    return [l for l in salida.splitlines() if l.strip()]


def main():
    fallas = []
    for rel in versionados():
        ruta = os.path.join(REPO, rel)
        try:
            with open(ruta, encoding="utf-8", errors="replace") as f:
                lineas = f.read().replace("\r\n", "\n").split("\n")
        except OSError:
            continue
        for i, linea in enumerate(lineas):
            if linea.lstrip().startswith("--"):
                continue
            if not re_usuario.match(linea):
                continue
            desde = max(0, i - VENTANA)
            contexto = "\n".join(lineas[desde:i + 1])
            if not re_pares.search(contexto):
                fallas.append("%s:%d" % (rel, i + 1))

    print("=" * 70)
    print("USUARIOS SIN PARES: delete de usuario sin borrar USUARIO_EMPRESA")
    print("=" * 70)
    if fallas:
        print("\n[FALLA] borrados que van a fallar con ORA-02292 / ORA-12860:")
        for f in fallas:
            print("   -", f)
    else:
        print("\n[OK] todos los borrados de usuario limpian antes sus pares")
    print("\nRESULTADO: FALLAS=%d" % len(fallas))
    return 1 if fallas else 0


if __name__ == "__main__":
    sys.exit(main())
