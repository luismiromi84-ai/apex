#!/usr/bin/env python3
# =============================================================================
# 20261120_presupuestos_capturas.py
#
# Saca las capturas del acabado de Presupuestos (pagina 5):
#   20261120_presupuestos_1440.png   lista + KPIs a 1440 px
#   20261120_presupuestos_500.png    la misma a 500 px (movil)
#
# Ademas lee de la pagina en vivo las cuatro tarjetas de la fila de indicadores
# y cuenta las insignias de estado, para que el informe no dependa de una
# lectura a ojo de la captura.
#
# Uso:
#     python deploy/diagnostico/20261120_presupuestos_capturas.py
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

USUARIO, CLAVE = "diag.pres", "Diag#2026"
SALIDA = os.path.join(REPO, "deploy", "resultados")


class Nav:
    def __init__(self, puerto=9287):
        self.proc = subprocess.Popen(
            [EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
             "--window-size=1440,1000",
             f"--remote-debugging-port={puerto}",
             f"--user-data-dir={os.path.join(tempfile.gettempdir(), 'opencode', 'edge-pres')}",
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


conn = oracledb.connect(user=credenciales()["DB_USER"], password=credenciales()["DB_PASSWORD"], dsn=CS)
cur = conn.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")
cur.execute("delete from syn_login_log where upper(usuario_intentado) = 'DIAG.PRES'")
cur.execute("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario "
            "where upper(username) = 'DIAG.PRES'); commit; "
            "delete from usuario where upper(username) = 'DIAG.PRES'; commit; end;")
cur.execute("""insert into usuario (username, email, password_hash, estado, id_empresa, rol_id,
                                    debe_cambiar_clave, reintentos_fallidos)
               values ('diag.pres', 'diag.pres@synpex.local', sypex_hash_password('Diag#2026'),
                       'ACTIVO', 1, (select id_rol from syn_roles where codigo_rol = 'ADMIN'), 'N', 0)""")
conn.commit()

nav = Nav()
fallas = []
valores = []
insignias = {}
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
        print("FALLO el login:", (nav.js("document.body.innerText") or "")[:160])
        raise SystemExit(1)
    ses = m.group(1)

    nav.js('window.location.href="%s/f?p=100:5:%s"' % (BASE, ses))
    nav.esperar('!!document.getElementById("P5_ID_PRESUPUESTO")', 40)
    time.sleep(4)

    # --- las cuatro tarjetas, leidas de la pagina en vivo
    tarjetas = nav.js('(function(){var out=[];'
                      'document.querySelectorAll("#R43000000000001410 .spx-card").forEach(function(c){'
                      'var l=c.querySelector(".spx-card-lbl"), v=c.querySelector(".spx-card-val");'
                      'out.push((l?l.innerText:"")+" = "+(v?v.innerText:""));});'
                      'return JSON.stringify(out);})()')
    try:
        valores = json.loads(tarjetas) if tarjetas else []
    except Exception:
        valores = []
    print("  tarjetas:", valores)
    if len(valores) != 4:
        fallas.append("la fila de indicadores no tiene cuatro tarjetas")

    # --- las insignias: cuantas y de que clases
    clases = nav.js('(function(){var o={};'
                    'document.querySelectorAll(".status-badge").forEach(function(s){'
                    'o[s.className]=(o[s.className]||0)+1;});'
                    'return JSON.stringify(o);})()')
    try:
        insignias = json.loads(clases) if clases else {}
    except Exception:
        insignias = {}
    print("  insignias:", insignias)

    # --- pagina 5 a 1440
    ok = nav.captura(os.path.join(SALIDA, "20261120_presupuestos_1440.png"))
    print(("  OK  " if ok else "  MAL ") + "captura a 1440")
    if not ok:
        fallas.append("captura 1440")

    # --- pagina 5 a 500 (movil)
    nav.tamano(500, 900)
    time.sleep(3)
    ok = nav.captura(os.path.join(SALIDA, "20261120_presupuestos_500.png"))
    print(("  OK  " if ok else "  MAL ") + "captura a 500")
    if not ok:
        fallas.append("captura 500")
finally:
    nav.cerrar()
    cur.execute("delete from syn_login_log where upper(usuario_intentado) = 'DIAG.PRES'")
    cur.execute("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario "
                "where upper(username) = 'DIAG.PRES'); commit; "
                "delete from usuario where upper(username) = 'DIAG.PRES'; commit; end;")
    conn.commit()
    conn.close()

print()
print("RESULTADO: FALLAS=" + str(len(fallas)))
sys.exit(1 if fallas else 0)
