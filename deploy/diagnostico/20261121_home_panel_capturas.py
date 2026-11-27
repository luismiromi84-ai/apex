#!/usr/bin/env python3
# =============================================================================
# 20261121_home_panel_capturas.py
#
# SUPERADA el 2026-11-26 para la Home: las dos tarjetas grandes (synpex-welcome-card) se quitaron
# en la pantalla principal nueva; la prueba vigente es 20261126_home_navegador.py. Lo del Panel
# General (13) sigue valiendo.
#
# Acabado de Home (1) y Panel General (13): capturas y comprobaciones.
#   deploy/resultados/20261121_home_{1440,500}.png
#   deploy/resultados/20261121_panel_{1440,500}.png
#
# Comprueba lo que se cambio (2026-11-21), no la logica: la cabecera de la Home
# con empresa y usuario, las dos tarjetas de acceso apiladas a 500 px, las cinco
# tarjetas del Panel al estilo de la pagina 8, la banda de la tasa y los cuatro
# graficos con su tarjeta y su titulo.
#
# Uso:
#     python deploy/diagnostico/20261121_home_panel_capturas.py
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

USUARIO, CLAVE = "diag.home", "Diag#2026"
SALIDA = os.path.join(REPO, "deploy", "resultados")

REGION_KPI = "R23600000000000010"
REGION_TASA = "R23600000000000070"
REGION_DOCS = "R23600000000000060"


class Nav:
    def __init__(self, puerto=9290):
        self.proc = subprocess.Popen(
            [EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
             "--window-size=1440,1000",
             f"--remote-debugging-port={puerto}",
             f"--user-data-dir={os.path.join(tempfile.gettempdir(), 'opencode', 'edge-home')}",
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


CAJAS = """(function(sel){var l=document.querySelectorAll(sel);var o=[];
  for(var i=0;i<l.length;i++){var r=l[i].getBoundingClientRect();
    o.push([Math.round(r.left),Math.round(r.top),Math.round(r.width),Math.round(r.height)]);}
  return o;})"""

conn = oracledb.connect(user=credenciales()["DB_USER"], password=credenciales()["DB_PASSWORD"], dsn=CS)
cur = conn.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")
cur.execute("delete from syn_login_log where upper(usuario_intentado) = 'DIAG.HOME'")
cur.execute("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario "
            "where upper(username) = 'DIAG.HOME'); commit; "
            "delete from usuario where upper(username) = 'DIAG.HOME'; commit; end;")
cur.execute("""insert into usuario (username, email, password_hash, estado, id_empresa, rol_id,
                                    debe_cambiar_clave, reintentos_fallidos)
               values ('diag.home', 'diag.home@synpex.local', sypex_hash_password('Diag#2026'),
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

    # ---------------- Home (1)
    nav.js('window.location.href="%s/f?p=100:1:%s"' % (BASE, ses))
    nav.esperar('document.readyState === "complete" && !!document.querySelector(".spx-home-cab")')
    time.sleep(5)
    nav.js("window.scrollTo(0,0)")
    time.sleep(1)
    ok = nav.captura(os.path.join(SALIDA, "20261121_home_1440.png"))
    comprobar("captura de Home a 1440", ok)

    cab = nav.js("(function(){var e=document.querySelector('.spx-home-cab');"
                 "return e ? e.innerText.replace(/\\n/g, ' | ') : 'SIN CABECERA';})()")
    comprobar("la Home abre con la cabecera de empresa y usuario",
              "Empresa Principal" in cab and USUARIO in cab, cab)
    comprobar("la cabecera lleva la fecha", re.search(r"\d{2}/\d{2}/\d{4}", cab or "") is not None, cab)
    cuerpo = nav.js("document.body.innerText") or ""
    comprobar("las dos tarjetas de acceso estan",
              "Presupuestos" in cuerpo and "Facturacion" in cuerpo.replace("\u00f3", "o"),
              cuerpo[:80])
    comprobar("los dos botones de acceso siguen",
              cuerpo.count("Gesti") >= 2)
    comprobar("la Home no muestra codigo de region",
              "declare" not in cuerpo and "v_html" not in cuerpo)

    cajas = nav.js(CAJAS + '(".synpex-welcome-card")')
    comprobar("las dos tarjetas van lado a lado a 1440",
              len(cajas) == 2 and cajas[0][1] == cajas[1][1] and cajas[0][0] < cajas[1][0], cajas)
    banda = nav.js("(function(){var e=document.querySelector('.spx-home-cab');"
                   "var r=e.getBoundingClientRect();var c=document.querySelector('.synpex-welcome-card');"
                   "var rc=c.getBoundingClientRect();"
                   "return [Math.round(r.left),Math.round(rc.left),Math.round(r.width)];})()")
    comprobar("la cabecera queda alineada con las tarjetas",
              abs(banda[0] - banda[1]) <= 1, banda)
    comprobar("las tarjetas usan el mismo borde y radio que la app",
              nav.js("(function(){var s=getComputedStyle(document.querySelector('.synpex-welcome-card'));"
                     "return s.borderRadius + ' / ' + s.borderLeftColor + ' / ' + s.boxShadow;})()")
              == "12px / rgb(229, 231, 235) / rgba(0, 0, 0, 0.08) 0px 1px 3px 0px",
              nav.js("(function(){var s=getComputedStyle(document.querySelector('.synpex-welcome-card'));"
                     "return s.borderRadius + ' / ' + s.borderLeftColor + ' / ' + s.boxShadow;})()"))
    comprobar("la animacion del logo sigue definida",
              nav.js("(function(){return !!document.querySelector('style') && document.documentElement.innerHTML.indexOf('spxGlow') > 0;})()") is True)

    nav.tamano(500, 900)
    time.sleep(3)
    nav.js("window.scrollTo(0,0)")
    time.sleep(1)
    ok = nav.captura(os.path.join(SALIDA, "20261121_home_500.png"))
    comprobar("captura de Home a 500", ok)
    cajas500 = nav.js(CAJAS + '(".synpex-welcome-card")')
    comprobar("a 500 las tarjetas se apilan",
              len(cajas500) == 2 and cajas500[0][1] < cajas500[1][1]
              and abs(cajas500[0][0] - cajas500[1][0]) <= 1, cajas500)
    desborde = nav.js("document.documentElement.scrollWidth - window.innerWidth")
    comprobar("Home no desborda a 500 px", (desborde or 0) <= 2, desborde)

    # ---------------- Panel General (13)
    nav.tamano(1440, 1000)
    time.sleep(2)
    nav.js('window.location.href="%s/f?p=100:13:%s"' % (BASE, ses))
    nav.esperar('!!document.getElementById("%s")' % REGION_KPI, 45)
    time.sleep(7)
    nav.js("window.scrollTo(0,0)")
    time.sleep(1)
    ok = nav.captura(os.path.join(SALIDA, "20261121_panel_1440.png"))
    comprobar("captura del Panel a 1440", ok)

    cuerpo13 = nav.js("document.body.innerText") or ""
    comprobar("el Panel no muestra el PL/SQL de una region",
              "v_html" not in cuerpo13 and "declare" not in cuerpo13)
    comprobar("sin error de rejilla",
              "Column 13" not in cuerpo13 and "cannot be rendered" not in cuerpo13)

    valores = nav.js('(function(){var o=[];document.querySelectorAll("#%s .a-CardView").forEach('
                     'function(c){var v=c.querySelector(".spx-val");'
                     'var s=c.querySelector(".spx-sub");'
                     'o.push((v?v.textContent.trim():"?")+"="+(s?s.textContent.trim():""));});'
                     'return o;})()' % REGION_KPI)
    comprobar("las cinco tarjetas llegan partidas en valor y detalle",
              isinstance(valores, list) and len(valores) == 5
              and all("=" in v and v.split("=")[0] for v in valores), valores)
    etiquetas = nav.js('(function(){var o=[];document.querySelectorAll("#%s .a-CardView-title").forEach('
                       'function(c){o.push(c.textContent.trim());});return o;})()' % REGION_KPI)
    comprobar("las etiquetas van en mayusculas, como la pagina 8",
              nav.js('(function(){var t=document.querySelector("#%s .a-CardView-title");'
                     'return getComputedStyle(t).textTransform;})()' % REGION_KPI) == "uppercase",
              etiquetas)
    comprobar("la tarjeta no lleva la linea bajo el titulo",
              nav.js('(function(){var h=document.querySelector("#%s .a-CardView-header");'
                     'return getComputedStyle(h).borderBottomWidth;})()' % REGION_KPI) == "0px")
    kpi = nav.js(CAJAS + '("#%s .a-CardView")' % REGION_KPI)
    comprobar("las cinco tarjetas van en una sola fila a 1440",
              len(kpi) == 5 and len({c[1] for c in kpi}) == 1, kpi)

    tasa = nav.js("(function(){var e=document.getElementById('%s');"
                  "var r=e.getBoundingClientRect();var s=getComputedStyle(e);"
                  "return [Math.round(r.width),Math.round(r.height),s.backgroundColor,s.borderLeftWidth,s.borderLeftColor];})()"
                  % REGION_TASA)
    comprobar("la tasa del dia es una banda a lo ancho",
              tasa[0] > 1000 and tasa[1] <= 60 and tasa[2] == "rgb(248, 250, 252)"
              and tasa[3] == "4px", tasa)
    comprobar("la tasa del dia va en una sola linea",
              nav.js("(function(){var v=document.querySelector('#%s .spx-val');"
                     "var h=document.querySelector('#%s .a-CardView-title');"
                     "return Math.abs(v.getBoundingClientRect().top - h.getBoundingClientRect().top) <= 6;})()"
                     % (REGION_TASA, REGION_TASA)) is True)

    graficos = nav.js('(function(){var o=[];document.querySelectorAll(".spx-chart").forEach(function(r){'
                      'var t=r.querySelector(".t-Region-title");var b=r.getBoundingClientRect();'
                      'o.push([t?t.textContent.trim():"SIN TITULO",Math.round(b.height),'
                      'getComputedStyle(r).borderRadius]);});return o;})()')
    comprobar("los cuatro graficos llevan tarjeta y titulo",
              isinstance(graficos, list) and len(graficos) == 4
              and all(g[0] != "SIN TITULO" and g[2] == "12px" for g in graficos), graficos)
    comprobar("los cuatro graficos tienen la misma altura de tarjeta",
              len({g[1] for g in graficos}) == 1, [g[1] for g in graficos])

    docs = nav.js(CAJAS + '("#%s .a-CardView")' % REGION_DOCS)
    comprobar("los ultimos documentos van en dos columnas",
              len(docs) >= 2 and abs(docs[0][1] - docs[1][1]) <= 1, docs[:2])

    nav.tamano(500, 900)
    time.sleep(3)
    nav.js("window.scrollTo(0,0)")
    time.sleep(1)
    ok = nav.captura(os.path.join(SALIDA, "20261121_panel_500.png"))
    comprobar("captura del Panel a 500", ok)
    kpi500 = nav.js(CAJAS + '("#%s .a-CardView")' % REGION_KPI)
    comprobar("a 500 las tarjetas van en dos columnas",
              len(kpi500) >= 4 and abs(kpi500[0][1] - kpi500[1][1]) <= 1, kpi500[:2])
    graficos500 = nav.js(CAJAS + '(".spx-chart")')
    comprobar("a 500 cada grafico ocupa su fila",
              len(graficos500) == 4 and graficos500[0][1] < graficos500[1][1], graficos500)
    desborde13 = nav.js("document.documentElement.scrollWidth - window.innerWidth")
    comprobar("el Panel no desborda a 500 px", (desborde13 or 0) <= 2, desborde13)
finally:
    nav.cerrar()
    cur.execute("delete from syn_login_log where upper(usuario_intentado) = 'DIAG.HOME'")
    cur.execute("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario "
                "where upper(username) = 'DIAG.HOME'); commit; "
                "delete from usuario where upper(username) = 'DIAG.HOME'; commit; end;")
    conn.commit()
    conn.close()

print()
print("RESULTADO: FALLAS=" + str(len(fallas)))
for f in fallas:
    print("  - " + f)
sys.exit(1 if fallas else 0)
