#!/usr/bin/env python3
# =============================================================================
# 20261120_facturacion_capturas.py
#
# Saca las capturas del acabado de Facturacion:
#   20261120_facturacion_1440.png   lista de facturas (8) a 1440 px
#   20261120_facturacion_500.png    la misma a 500 px (movil)
#   20261120_facturacion_p9.png     el dialogo de la factura (9)
#
# Por que existe: la pagina 9 es un cuadro de dialogo y NO se puede pedir por
# HTTP (devuelve 400 con "La pagina 9 de cuadro de dialogo no se puede presentar
# correctamente"). La unica forma de verla es abrirla con un clic real, que es
# lo que hace este script.
#
# Uso:
#     python deploy/diagnostico/20261120_facturacion_capturas.py
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

USUARIO, CLAVE = "diag.fact", "Diag#2026"
SALIDA = os.path.join(REPO, "deploy", "resultados")


class Nav:
    def __init__(self, puerto=9285):
        self.proc = subprocess.Popen(
            [EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
             "--window-size=1440,1000",
             f"--remote-debugging-port={puerto}",
             f"--user-data-dir={os.path.join(tempfile.gettempdir(), 'opencode', 'edge-fact')}",
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
        for m in ("Page.enable", "Runtime.enable", "Emulation.setDeviceMetricsOverride"):
            pass
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

    def clic(self, expr):
        r = self.js(expr)
        if not r or r == "null":
            return False
        d = json.loads(r)
        self.cmd("Input.dispatchMouseEvent", type="mousePressed", x=d["x"], y=d["y"],
                 button="left", clickCount=1)
        self.cmd("Input.dispatchMouseEvent", type="mouseReleased", x=d["x"], y=d["y"],
                 button="left", clickCount=1)
        return True

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
cur.execute("delete from syn_login_log where upper(usuario_intentado) = 'DIAG.FACT'")
cur.execute("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario "
            "where upper(username) = 'DIAG.FACT'); commit; "
            "delete from usuario where upper(username) = 'DIAG.FACT'; commit; end;")
cur.execute("""insert into usuario (username, email, password_hash, estado, id_empresa, rol_id,
                                    debe_cambiar_clave, reintentos_fallidos)
               values ('diag.fact', 'diag.fact@synpex.local', sypex_hash_password('Diag#2026'),
                       'ACTIVO', 1, (select id_rol from syn_roles where codigo_rol = 'ADMIN'), 'N', 0)""")
conn.commit()

nav = Nav()
fallas = []
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

    # --- pagina 8 a 1440
    nav.js('window.location.href="%s/f?p=100:8:%s"' % (BASE, ses))
    nav.esperar('!!document.getElementById("P8_ID_FACTURAS")', 40)
    time.sleep(4)
    ok = nav.captura(os.path.join(SALIDA, "20261120_facturacion_1440.png"))
    print(("  OK  " if ok else "  MAL ") + "captura a 1440")

    # --- pagina 8 a 500 (movil)
    nav.tamano(500, 900)
    time.sleep(3)
    ok = nav.captura(os.path.join(SALIDA, "20261120_facturacion_500.png"))
    print(("  OK  " if ok else "  MAL ") + "captura a 500")
    if not ok:
        fallas.append("captura 500")

    # --- dialogo de la factura (9) a 1440
    nav.tamano(1440, 1000)
    time.sleep(2)
    nav.clic('(function(){var as=[...document.querySelectorAll("td a")].filter(function(a){'
             'return /Editar/.test(a.innerText);});'
             'if(!as.length) return null; as[0].scrollIntoView({block:"center"});'
             'var r=as[0].getBoundingClientRect();'
             'return JSON.stringify({x:r.left+r.width/2,y:r.top+r.height/2});})()')
    abierto = nav.esperar('(function(){var f=document.querySelector("iframe");'
                          'return !!(f&&f.contentDocument&&'
                          'f.contentDocument.getElementById("P9_TIPO_DOCUMENTO"));})()', 40)
    print(("  OK  " if abierto else "  MAL ") + "el dialogo de la factura abre")
    if not abierto:
        fallas.append("dialogo p9")
    time.sleep(3)
    # El dialogo es mas alto que la ventana: se le da margen para que quepa entero.
    nav.js('(function(){var w=document.querySelector(".ui-dialog");'
           'if(w){w.style.top="8px"; w.style.maxHeight="980px";}})()')
    time.sleep(1)
    ok = nav.captura(os.path.join(SALIDA, "20261120_facturacion_p9.png"))
    print(("  OK  " if ok else "  MAL ") + "captura del dialogo")
    if not ok:
        fallas.append("captura p9")

    # --- el pie del dialogo: tarjetas de totales y acciones. El cuerpo del modal
    #     scrollea dentro del iframe (div.t-Dialog-bodyWrapperIn, 840 de 1392 px):
    #     se baja hasta el final y se comprueba que realmente se movio.
    bajo = nav.js('(function(){var f=document.querySelector("iframe");'
                  'if(!f||!f.contentDocument) return "no";'
                  'var d=f.contentDocument, el=d.querySelector(".t-Dialog-bodyWrapperIn");'
                  'if(!el) return "sin cuerpo";'
                  'el.scrollTop = el.scrollHeight;'
                  'return el.scrollTop + "/" + el.scrollHeight;})()')
    print("      scroll del dialogo:", bajo)
    time.sleep(2)
    ok = nav.captura(os.path.join(SALIDA, "20261120_facturacion_p9_totales.png"))
    print(("  OK  " if ok else "  MAL ") + "captura de los totales")
    if not ok:
        fallas.append("captura totales")
finally:
    nav.cerrar()
    cur.execute("delete from syn_login_log where upper(usuario_intentado) = 'DIAG.FACT'")
    cur.execute("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario "
                "where upper(username) = 'DIAG.FACT'); commit; "
                "delete from usuario where upper(username) = 'DIAG.FACT'; commit; end;")
    conn.commit()
    conn.close()

print()
print("RESULTADO: FALLAS=" + str(len(fallas)))
sys.exit(1 if fallas else 0)
