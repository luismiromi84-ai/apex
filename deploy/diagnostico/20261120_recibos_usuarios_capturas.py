#!/usr/bin/env python3
# =============================================================================
# 20261120_recibos_usuarios_capturas.py
#
# Saca las capturas del acabado de Recibos (24) y Gestion de Usuarios (3) y lee
# los cuatro indicadores de cada una:
#   20261120_recibos_1440.png / _500.png
#   20261120_usuarios_1440.png / _500.png
#
# Por que existe: las dos paginas se pueden pedir por HTTP, pero el acabado (la
# fila de tarjetas, las insignias y el orden en movil) hay que verlo. Y los cuatro
# numeros se leen del DOM, no de una copia a mano.
#
# Uso:
#     python deploy/diagnostico/20261120_recibos_usuarios_capturas.py
# Requiere: websocket-client, oracledb y Edge instalado.
# =============================================================================
import base64
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.request

import oracledb
import websocket

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
BASE = "https://gfd7e2575d251ae-sypexsql.adb.mx-monterrey-1.oraclecloudapps.com/ords"
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(REPO, "deploy", "conexion"))
from verificar_conexion import CONNECT_STRING as CS, credenciales  # noqa: E402

USUARIO, CLAVE = "diag.kpi", "Diag#2026"
SALIDA = os.path.join(REPO, "deploy", "resultados")

REGION_RECIBOS = "R43000000000001440"
REGION_USUARIOS = "R43000000000001441"


class Nav:
    def __init__(self, puerto=9287):
        self.proc = subprocess.Popen(
            [EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
             "--window-size=1440,1000",
             f"--remote-debugging-port={puerto}",
             f"--user-data-dir={os.path.join(tempfile.gettempdir(), 'opencode', 'edge-kpi')}",
             "about:blank"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        objetivo = None
        for _ in range(40):
            try:
                lista = json.loads(urllib.request.urlopen(
                    f"http://127.0.0.1:{puerto}/json/list", timeout=2).read())
                pag = [t for t in lista if t.get("type") == "page"]
                if pag:
                    objetivo = pag[0]
                    break
            except Exception:
                pass
            time.sleep(0.5)
        self.ws = websocket.create_connection(objetivo["webSocketDebuggerUrl"], timeout=60)
        self.n = 0
        self.cmd("Page.enable")
        self.cmd("Runtime.enable")

    def cmd(self, method, **params):
        self.n += 1
        self.ws.send(json.dumps({"id": self.n, "method": method, "params": params}))
        while True:
            r = json.loads(self.ws.recv())
            if r.get("id") == self.n:
                return r.get("result", {})

    def js(self, expr):
        r = self.cmd("Runtime.evaluate", expression=expr, returnByValue=True, awaitPromise=True)
        if "exceptionDetails" in r:
            return "EXC: " + str(r["exceptionDetails"].get("exception", {}).get("description"))[:300]
        return r.get("result", {}).get("value")

    def esperar(self, cond, seg=40):
        fin = time.time() + seg
        while time.time() < fin:
            if self.js(cond):
                return True
            time.sleep(0.5)
        return False

    def tamano(self, ancho, alto):
        self.cmd("Emulation.setDeviceMetricsOverride", width=ancho, height=alto,
                 deviceScaleFactor=1, mobile=False)

    def captura(self, ruta):
        r = self.cmd("Page.captureScreenshot", format="png")
        datos = r.get("data")
        if not datos:
            return False
        with open(ruta, "wb") as fh:
            fh.write(base64.b64decode(datos))
        return True

    def cerrar(self):
        try:
            self.proc.terminate()
        except Exception:
            pass


def kpis(nav, region):
    """Los pares etiqueta/valor de la fila de indicadores de esa region."""
    expr = ('(function(){var r=document.getElementById("%s"); if(!r) return "SIN REGION";'
            'var l=r.querySelectorAll(".spx-card"); var o=[];'
            'for (var i=0;i<l.length;i++){var a=l[i].querySelector(".spx-card-lbl");'
            'var b=l[i].querySelector(".spx-card-val");'
            'o.push((a?a.textContent.trim():"?")+"="+(b?b.textContent.trim():"?"));}'
            'return o.join(" | ");})()' % region)
    return nav.js(expr)


conn = oracledb.connect(user=credenciales()["DB_USER"], password=credenciales()["DB_PASSWORD"], dsn=CS)
cur = conn.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")
cur.execute("delete from syn_login_log where upper(usuario_intentado) = 'DIAG.KPI'")
cur.execute("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario "
            "where upper(username) = 'DIAG.KPI'); commit; "
            "delete from usuario where upper(username) = 'DIAG.KPI'; commit; end;")
cur.execute("""insert into usuario (username, email, password_hash, estado, id_empresa, rol_id,
                                    debe_cambiar_clave, reintentos_fallidos)
               values ('diag.kpi', 'diag.kpi@synpex.local', sypex_hash_password('Diag#2026'),
                       'ACTIVO', 1, (select id_rol from syn_roles where codigo_rol = 'ADMIN'), 'N', 0)""")
conn.commit()

nav = Nav()
fallas = []


def comprobar(nombre, ok, detalle=""):
    print(("  OK  " if ok else "  MAL ") + nombre + (" " + str(detalle) if detalle else ""))
    if not ok:
        fallas.append(nombre)


try:
    nav.tamano(1440, 1000)
    nav.js('window.location.href="%s/f?p=100:9999"' % BASE)
    nav.esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(1)
    nav.js('(function(){apex.item("P9999_USERNAME").setValue(%s);apex.item("P9999_PASSWORD").setValue(%s);'
           'var b=[...document.querySelectorAll("button")].find(x=>/sign in|iniciar|entrar/i.test(x.innerText));'
           'if(b){b.click();}})()' % (json.dumps(USUARIO), json.dumps(CLAVE)))
    time.sleep(8)
    m = re.search(r"session=(\d+)", nav.js("window.location.href") or "")
    if not m:
        print("FALLO el login:", (nav.js("document.body.innerText") or "")[:200])
        raise SystemExit(1)
    ses = m.group(1)

    # ---------------- Recibos (24)
    nav.js('window.location.href="%s/f?p=100:24:%s"' % (BASE, ses))
    nav.esperar('!!document.getElementById("%s")' % REGION_RECIBOS, 40)
    time.sleep(4)
    nav.js("window.scrollTo(0,0)")
    time.sleep(1)
    ok = nav.captura(os.path.join(SALIDA, "20261120_recibos_1440.png"))
    comprobar("captura de Recibos a 1440", ok)
    print("      KPI 24:", kpis(nav, REGION_RECIBOS))
    cuerpo = nav.js("document.body.innerText") or ""
    comprobar("la lista pinta las insignias de estado", "EMITIDO" in cuerpo or "ANULADO" in cuerpo,
              cuerpo[:120])
    comprobar("sin error de rejilla", "Column 13" not in cuerpo and "cannot be rendered" not in cuerpo)

    nav.tamano(500, 900)
    time.sleep(3)
    nav.js("window.scrollTo(0,0)")
    time.sleep(1)
    ok = nav.captura(os.path.join(SALIDA, "20261120_recibos_500.png"))
    comprobar("captura de Recibos a 500", ok)

    # ---------------- Gestion de Usuarios (3)
    nav.tamano(1440, 1000)
    time.sleep(2)
    nav.js('window.location.href="%s/f?p=100:3:%s"' % (BASE, ses))
    nav.esperar('!!document.getElementById("%s")' % REGION_USUARIOS, 40)
    time.sleep(4)
    nav.js("window.scrollTo(0,0)")
    time.sleep(1)
    ok = nav.captura(os.path.join(SALIDA, "20261120_usuarios_1440.png"))
    comprobar("captura de Usuarios a 1440", ok)
    print("      KPI 3:", kpis(nav, REGION_USUARIOS))
    cuerpo3 = nav.js("document.body.innerText") or ""
    comprobar("la lista pinta las insignias", "ACTIVO" in cuerpo3, cuerpo3[:120])
    comprobar("las tres pestanas siguen", "Ultimos errores" in cuerpo3 and "ltimos intentos" in cuerpo3)

    nav.tamano(500, 900)
    time.sleep(3)
    nav.js("window.scrollTo(0,0)")
    time.sleep(1)
    ok = nav.captura(os.path.join(SALIDA, "20261120_usuarios_500.png"))
    comprobar("captura de Usuarios a 500", ok)
finally:
    nav.cerrar()
    cur.execute("delete from syn_login_log where upper(usuario_intentado) = 'DIAG.KPI'")
    cur.execute("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario "
                "where upper(username) = 'DIAG.KPI'); commit; "
                "delete from usuario where upper(username) = 'DIAG.KPI'; commit; end;")
    conn.commit()
    conn.close()

print()
print("RESULTADO: FALLAS=" + str(len(fallas)))
for f in fallas:
    print("  - " + f)
sys.exit(1 if fallas else 0)
