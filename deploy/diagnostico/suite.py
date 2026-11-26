#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Suite de verificaciones de Synpex: un solo comando (2026-11-26).

Corre las verificaciones listadas en `deploy/diagnostico/suite.txt`, por grupos:

  post        chequeos despues de cada import (procesos, rejilla, portada)            ~2 min
  sql         verificaciones SQL que se corren SIN el fixture (multiempresa, folios...)
  fixture     verificaciones SQL que necesitan el fixture: se monta antes y se limpia despues
  navegador   pruebas en Edge headless (las mas lentas)                                 ~30 min

Cada verificacion termina en «RESULTADO: FALLAS=N»: es verde con FALLAS=0, aunque el runner de SQL
lo reporte como «FALLO» (un ORA-20100 con FALLAS=0 es verde). Un corte de red (DPY-4011, DPY-6005)
se reintenta una vez.

Uso (desde la raiz del repo):
  python deploy/diagnostico/suite.py                 # post + sql + fixture (sin navegador)
  python deploy/diagnostico/suite.py --completa      # todo, navegador incluido
  python deploy/diagnostico/suite.py --grupo navegador
  python deploy/diagnostico/suite.py --solo contabilidad      # las que contienen ese texto
  python deploy/diagnostico/suite.py --descubrir     # corre TODOS los .sql de verificacion (para
                                                     # mantener suite.txt) y dice cuales pasan hoy
  python deploy/diagnostico/suite.py --descubrir --parte 1/4    # en tandas (cada una < 10 min)

Deja el resumen en deploy/resultados/AAAAMMDD_suite.txt y sale con 1 si algo fallo.
"""
import argparse
import datetime
import os
import re
import subprocess
import sys
import time

AQUI = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(AQUI))
RUNNER = os.path.join(REPO, "deploy", "conexion", "importar_export.py")
LISTA = os.path.join(AQUI, "suite.txt")
FIXTURE = os.path.join(AQUI, "20261108_fixture_prueba.sql")
LIMPIAR = os.path.join(AQUI, "20261108_limpiar_fixture.sql")
GRUPOS = ["post", "sql", "fixture", "navegador"]
RED = re.compile(r"DPY-4011|DPY-6005|DPY-6000|ORA-12506|ORA-03113|connection was closed|timed out", re.I)


def lee_lista():
    """suite.txt: «grupo archivo  # comentario». Las lineas con # al inicio se ignoran."""
    items = []
    with open(LISTA, encoding="utf-8") as f:
        for linea in f:
            linea = linea.split("#", 1)[0].strip()
            if not linea:
                continue
            grupo, archivo = linea.split(None, 1)
            if grupo not in GRUPOS:
                raise SystemExit("suite.txt: grupo desconocido %r" % grupo)
            items.append((grupo, archivo.strip()))
    return items


def ejecuta(archivo, timeout):
    """Corre una verificacion. Devuelve (estado, fallas, segundos, detalle)."""
    ruta = os.path.join(AQUI, archivo)
    if not os.path.exists(ruta):
        return "NO EXISTE", None, 0, ""
    cmd = [sys.executable, RUNNER, ruta] if archivo.endswith(".sql") else [sys.executable, ruta]
    for intento in (1, 2):
        t0 = time.time()
        try:
            p = subprocess.run(cmd, cwd=REPO, capture_output=True, text=True, timeout=timeout,
                               encoding="utf-8", errors="replace")
            salida = (p.stdout or "") + (p.stderr or "")
        except subprocess.TimeoutExpired:
            return "TIEMPO", None, round(time.time() - t0), "supero %d s" % timeout
        seg = round(time.time() - t0)
        m = re.findall(r"RESULTADO: FALLAS=(\d+)", salida)
        if m:
            n = int(m[-1])
            det = ""
            if n:
                det = " | ".join(l.strip() for l in salida.splitlines()
                                 if re.search(r"FALLA|MAL |  - |falla\(", l))[:400]
            return ("OK" if n == 0 else "FALLA"), n, seg, det
        if intento == 1 and RED.search(salida):
            time.sleep(10)
            continue
        ultimo = [l for l in salida.splitlines() if l.strip()][-3:]
        return "SIN RESULTADO", None, seg, " | ".join(ultimo)[:400]
    return "RED", None, 0, "corte de red dos veces"


def main():
    # la consola de Windows (cp1252) no imprime todo lo que devuelven las verificaciones
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    ap = argparse.ArgumentParser(description="Suite de verificaciones de Synpex.")
    ap.add_argument("--completa", action="store_true", help="incluye las pruebas de navegador")
    ap.add_argument("--grupo", choices=GRUPOS, action="append", help="solo este grupo (se puede repetir)")
    ap.add_argument("--solo", default=None, help="solo las verificaciones cuyo nombre contiene este texto")
    ap.add_argument("--descubrir", action="store_true",
                    help="corre todos los *_verificacion.sql para mantener suite.txt")
    ap.add_argument("--timeout", type=int, default=900, help="segundos por verificacion (900)")
    ap.add_argument("--parte", default=None, help="k/n: corre solo la parte k de n (para tandas cortas)")
    args = ap.parse_args()

    if args.descubrir:
        todos = sorted(f for f in os.listdir(AQUI) if f.endswith("_verificacion.sql"))
        sin_fix = [f for f in todos if re.search(r"multiempresa|folio", f)]
        con_fix = [f for f in todos if f not in sin_fix]
        items = [("sql", f) for f in sin_fix] + [("fixture", f) for f in con_fix]
    else:
        items = lee_lista()
        grupos = args.grupo or (GRUPOS if args.completa else ["post", "sql", "fixture"])
        items = [(g, a) for g, a in items if g in grupos]
    if args.solo:
        items = [(g, a) for g, a in items if args.solo.lower() in a.lower()]
    if args.parte:
        k, n = [int(x) for x in args.parte.split("/")]
        items = [it for i, it in enumerate(items) if i % n == k - 1]
    if not items:
        print("No hay verificaciones que correr.")
        return 0

    filas = []
    inicio = time.time()
    fixture_montado = False
    try:
        for grupo in GRUPOS:
            del_grupo = [a for g, a in items if g == grupo]
            if not del_grupo:
                continue
            print("\n== %s (%d)" % (grupo, len(del_grupo)))
            if grupo == "fixture" and not fixture_montado:
                est, n, seg, det = ejecuta(os.path.basename(FIXTURE), args.timeout)
                print("   [fixture montado: %s]" % est if est in ("OK", "SIN RESULTADO") else "   [fixture: %s %s]" % (est, det))
                fixture_montado = True
            for archivo in del_grupo:
                est, n, seg, det = ejecuta(archivo, args.timeout)
                if grupo == "navegador" and est != "OK":
                    # el navegador headless falla a veces por tiempos (descargas, dialogos): se repite
                    # una vez y, si pasa, queda marcado para que se vea en el resumen
                    est2, n2, seg2, det2 = ejecuta(archivo, args.timeout)
                    if est2 == "OK":
                        est, n, seg, det = "OK", 0, seg + seg2, "OK al 2.o intento (1.o: %s)" % det[:120]
                filas.append((grupo, archivo, est, n, seg, det))
                print("   %-13s %4ds  %s%s" % (est, seg, archivo, ("  -> " + det[:160]) if est != "OK" and det else ""))
    finally:
        if fixture_montado:
            est, n, seg, det = ejecuta(os.path.basename(LIMPIAR), args.timeout)
            print("   [fixture limpiado: %s]" % est)

    ok = sum(1 for f in filas if f[2] == "OK")
    malas = [f for f in filas if f[2] != "OK"]
    total = round(time.time() - inicio)
    print("\nRESULTADO SUITE: %d de %d en verde (%d min)" % (ok, len(filas), total // 60))
    for f in malas:
        print("  - %-13s %s" % (f[2], f[1]))
    for f in filas:
        if f[2] == "OK" and f[5].startswith("OK al 2.o intento"):
            print("  * OK al 2.o intento: %s" % f[1])

    hoy = datetime.date.today().strftime("%Y%m%d")
    sufijo = ("_descubrir" if args.descubrir else "") + (("_parte" + args.parte.replace("/", "de")) if args.parte else "")
    destino = os.path.join(REPO, "deploy", "resultados", "%s_suite%s.txt" % (hoy, sufijo))
    with open(destino, "w", encoding="utf-8") as fh:
        fh.write("Suite de verificaciones %s: %d de %d en verde, %d s\n\n" % (hoy, ok, len(filas), total))
        for g, a, est, n, seg, det in filas:
            fh.write("%-9s %-13s %5ds  %s%s\n" % (g, est, seg, a, ("  -> " + det) if det else ""))
    print("Resumen en", os.path.relpath(destino, REPO))
    return 1 if malas else 0


if __name__ == "__main__":
    sys.exit(main())
