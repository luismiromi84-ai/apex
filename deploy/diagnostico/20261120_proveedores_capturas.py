#!/usr/bin/env python3
# =============================================================================
# 20261120_proveedores_capturas.py
#
# Acabado de Proveedores (paginas 22 y 23), con navegador real:
#   20261120_proveedores_1440.png   la lista (22) a 1440 px
#   20261120_proveedores_500.png    la misma a 500 px (movil)
#   20261120_proveedores_p23.png    el dialogo del proveedor (23)
#
# Comprueba ademas que la fila de indicadores dice los numeros de la base y que
# las dos columnas nuevas son insignias (chip de retencion y de SPE).
#
# Por que existe: la 23 es un cuadro de dialogo y NO se puede pedir por HTTP
# (devuelve 400). La unica forma de verla es abrirla con un clic real.
#
# Uso:
#     python deploy/diagnostico/20261120_proveedores_capturas.py
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

USUARIO, CLAVE = "diag.prov22", "Diag#2026"
SALIDA = os.path.join(REPO, "deploy", "resultados")
fallas = []


def comprobar(texto, ok, detalle=""):
    print(("  OK  " if ok else "  MAL ") + texto + ("" if ok else " " + str(detalle)))
    if not ok:
        fallas.append(texto)


class Nav:
    def __init__(self, puerto=9286):
        self.proc = subprocess.Popen(
            [EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
             "--window-size=1440,1000",
             "--remote-debugging-port=%d" % puerto,
             "--user-data-dir=" + os.path.join(tempfile.gettempdir(), "opencode", "edge-prov22"),
             "about:blank"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        objetivo = None
        for _ in range(40):
            try:
                lista = json.loads(urllib.request.urlopen(
                    "http://127.0.0.1:%d/json/list" % puerto, timeout=2).read())
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
cur.execute("delete from syn_login_log where upper(usuario_intentado) = 'DIAG.PROV22'")
cur.execute("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario "
            "where upper(username) = 'DIAG.PROV22'); commit; "
            "delete from usuario where upper(username) = 'DIAG.PROV22'; commit; end;")
cur.execute("""insert into usuario (username, email, password_hash, estado, id_empresa, rol_id,
                                    debe_cambiar_clave, reintentos_fallidos)
               values ('diag.prov22', 'diag.prov22@synpex.local', sypex_hash_password('Diag#2026'),
                       'ACTIVO', 1, (select id_rol from syn_roles where codigo_rol = 'ADMIN'), 'N', 0)""")
conn.commit()

# Los numeros que tiene que decir la fila de indicadores.
cur.execute("""select count(*),
                      count(case when estado = 'ACTIVO' then 1 end),
                      count(case when nvl(es_spe, 'N') = 'S' then 1 end),
                      count(case when nvl(retener_iva, 'N') = 'S' then 1 end)
                 from proveedores where id_empresa = 1""")
esperado = cur.fetchone()
print("  indicadores esperados (proveedores/activos/SPE/retienen):", esperado)

nav = Nav()
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

    # --- pagina 22 a 1440
    nav.js('window.location.href="%s/f?p=100:22:%s"' % (BASE, ses))
    nav.esperar('!!document.querySelector(".spx-kpis")', 40)
    time.sleep(4)

    kpis = nav.js('(function(){var t=[];document.querySelectorAll(".spx-card").forEach(function(c){'
                  't.push(c.querySelector(".spx-card-lbl").innerText.trim()+"="+'
                  'c.querySelector(".spx-card-val").innerText.trim());});return t.join(" | ");})()')
    print("  tarjetas:", kpis)
    comprobar("E1 salen las cuatro tarjetas", (kpis or "").count("=") == 4, kpis)
    kpi_txt = (kpis or "").upper()
    comprobar("E1 los numeros son los de la base",
              ("PROVEEDORES=%d" % esperado[0]) in kpi_txt
              and ("ACTIVOS=%d" % esperado[1]) in kpi_txt
              and ("SPE=%d" % esperado[2]) in kpi_txt
              and ("RETIENEN IVA=%d" % esperado[3]) in kpi_txt, kpis)

    chips = nav.js('(function(){var c=document.querySelectorAll("#R43000000000000600 .spx-chip");'
                   'var t=[];c.forEach(function(x){t.push(x.className.replace("spx-chip ",""));});'
                   'return t.join(",");})()')
    print("  chips de la lista:", chips)
    comprobar("E2 la retencion y el SPE salen como insignias",
              "spx-chip--" in (chips or ""), chips)
    badges = nav.js('(function(){return document.querySelectorAll('
                    '"#R43000000000000600 .status-badge").length;})()')
    print("  insignias de estado:", badges)
    comprobar("E2 el estado sigue siendo una insignia", (badges or 0) >= 1, badges)

    ok = nav.captura(os.path.join(SALIDA, "20261120_proveedores_1440.png"))
    comprobar("E3 captura a 1440", ok)

    # --- la misma a 500 (movil)
    nav.tamano(500, 900)
    time.sleep(3)
    ok = nav.captura(os.path.join(SALIDA, "20261120_proveedores_500.png"))
    comprobar("E3 captura a 500", ok)

    # --- el dialogo del proveedor (23)
    nav.tamano(1440, 1000)
    time.sleep(2)
    nav.js('(function(){var a=document.querySelector("#R43000000000000600 a[href*=p23_id_proveedor]");'
           'if(a){a.click();return "ok";}return "sin enlace";})()')
    abierto = nav.esperar('(function(){var f=document.querySelector("iframe");'
                          'return !!(f&&f.contentDocument&&'
                          'f.contentDocument.getElementById("P23_RAZON_SOCIAL"));})()', 45)
    comprobar("E4 el dialogo del proveedor abre", abierto)
    if abierto:
        time.sleep(3)
        ficha = nav.js('(function(){var d=document.querySelector("iframe").contentDocument;'
                       'var f=d.querySelector(".spx-ficha");return f?f.innerText.replace(/\\n/g," | "):"";})()')
        print("  ficha:", ficha)
        comprobar("E4 la ficha trae nombre, RIF, estado, retencion y credito",
                  bool(ficha) and "J-" in ficha and ("ACTIVO" in ficha or "INACTIVO" in ficha)
                  and ("Retenci" in ficha or "Sin retenci" in ficha)
                  and ("dito" in ficha or "Contado" in ficha), ficha)
        secciones = nav.js('(function(){var d=document.querySelector("iframe").contentDocument;'
                           'var t=[];d.querySelectorAll(".t-Region-title").forEach(function(x){'
                           't.push(x.innerText.trim());});return t.join(" | ");})()')
        print("  secciones:", secciones)
        for s in ("Datos fiscales", "Contacto", "fiscal", "Condiciones comerciales"):
            comprobar("E5 la seccion «%s» esta" % s, s in (secciones or ""), secciones)
        area = nav.js('(function(){var d=document.querySelector("iframe").contentDocument;'
                      'var el=d.getElementById("P23_DIRECCION");'
                      'return el?el.tagName:"sin item";})()')
        comprobar("E5 la direccion es un area de texto", (area or "").upper() == "TEXTAREA", area)
        nav.js('(function(){var w=document.querySelector(".ui-dialog");'
               'if(w){w.style.top="8px"; w.style.maxHeight="980px";}})()')
        time.sleep(1)
        ok = nav.captura(os.path.join(SALIDA, "20261120_proveedores_p23.png"))
        comprobar("E6 captura del dialogo", ok)
finally:
    nav.cerrar()
    cur.execute("delete from syn_login_log where upper(usuario_intentado) = 'DIAG.PROV22'")
    cur.execute("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario "
                "where upper(username) = 'DIAG.PROV22'); commit; "
                "delete from usuario where upper(username) = 'DIAG.PROV22'; commit; end;")
    conn.commit()
    conn.close()

print()
print("RESULTADO: FALLAS=" + str(len(fallas)))
for f in fallas:
    print("  - " + f)
sys.exit(1 if fallas else 0)
