#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Pagina 19 «Administracion»: altura real de la banda azul.

Mide en el navegador (no a ojo) la altura de cada cabecera de region de la
pagina 19 —la de la tarjeta de la pestana y la del selector de pestanas—, el
padding y el tamano del titulo, y deja capturas a 1440 y 500 px.

Uso:
  python deploy/diagnostico/20261121_admin_banda.py [prefijo]
    prefijo  nombre de archivo de las capturas (por defecto
             20261121_admin_banda). Deja <prefijo>_1440.png y <prefijo>_500.png.

Crea y borra su propio usuario; no toca datos de negocio.
"""
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.request

import oracledb
import websocket

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
REPO = r"C:\Users\luism\OneDrive\Documents\Apex_luis"
sys.path.insert(0, os.path.join(REPO, "deploy", "conexion"))
from verificar_conexion import CONNECT_STRING as CS, credenciales  # noqa: E402

EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
BASE = "https://gfd7e2575d251ae-sypexsql.adb.mx-monterrey-1.oraclecloudapps.com/ords"
RES = os.path.join(REPO, "deploy", "resultados")
USUARIO, CLAVE = "diag.banda", "Diag#2026"
PREFIJO = sys.argv[1] if len(sys.argv) > 1 else "20261121_admin_banda"
fallas = []


def comprobar(nombre, condicion, detalle=""):
    print(("  OK   " if condicion else "  FALLA") + " " + nombre +
          ("" if condicion else "  -> " + str(detalle)[:220]))
    if not condicion:
        fallas.append(nombre)


class Nav:
    def __init__(self, puerto=9295):
        self.proc = subprocess.Popen(
            [EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
             "--hide-scrollbars",
             "--remote-debugging-port=%d" % puerto,
             "--user-data-dir=%s" % os.path.join(tempfile.gettempdir(), "opencode", "edge-p19banda"),
             "--window-size=1440,900", "about:blank"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
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
        for m in ("Page.enable", "Runtime.enable"):
            self.cmd(m)

    def cmd(self, method, **params):
        self.n += 1
        self.ws.send(json.dumps({"id": self.n, "method": method, "params": params}))
        while True:
            r = json.loads(self.ws.recv())
            if r.get("id") == self.n:
                return r.get("result", {})

    def js(self, expr):
        try:
            r = self.cmd("Runtime.evaluate", expression=expr, returnByValue=True,
                         awaitPromise=True)
        except Exception as e:
            return "WS: " + str(e)[:120]
        if "exceptionDetails" in r:
            return "EXC: " + str(r["exceptionDetails"].get("exception", {}).get("description"))[:200]
        return r.get("result", {}).get("value")

    def esperar(self, cond, seg=45):
        fin = time.time() + seg
        while time.time() < fin:
            if self.js(cond):
                return True
            time.sleep(0.5)
        return False

    def medida(self, ancho, alto=900):
        self.cmd("Emulation.setDeviceMetricsOverride", width=ancho, height=alto,
                 deviceScaleFactor=1, mobile=False)

    def captura(self, ruta, completo=True):
        import base64
        alto = 900
        if completo:
            h = self.js("Math.min(Math.max(document.documentElement.scrollHeight,"
                        "document.body.scrollHeight), 6500)")
            if isinstance(h, (int, float)) and h > 200:
                alto = int(h)
        r = self.cmd("Page.captureScreenshot", format="png", captureBeyondViewport=completo,
                     clip={"x": 0, "y": 0, "width": self.js("window.innerWidth") or 1440,
                           "height": alto, "scale": 1} if completo else None)
        if r.get("data"):
            with open(ruta, "wb") as fh:
                fh.write(base64.b64decode(r["data"]))
            return True
        return False

    def cerrar(self):
        try:
            self.proc.terminate()
        except Exception:
            pass


MEDIR = """(function(){
  var out = [];
  var hs = document.querySelectorAll(".t-Region-header");
  for (var i = 0; i < hs.length; i++) {
    var h = hs[i];
    var s = getComputedStyle(h);
    var t = h.querySelector(".t-Region-title");
    var ts = t ? getComputedStyle(t) : null;
    if (s.display === "none") { continue; }
    out.push({id: (h.closest(".t-Region") || {}).id || "",
              alto: Math.round(h.getBoundingClientRect().height * 100) / 100,
              ancho: Math.round(h.getBoundingClientRect().width),
              titulo: t ? t.textContent.replace(/\\s+/g, " ").trim() : "",
              padding: s.paddingTop + " " + s.paddingRight + " " + s.paddingBottom + " " + s.paddingLeft,
              fuente: ts ? ts.fontSize : null,
              maxw: s.maxWidth,
              izq: Math.round(h.getBoundingClientRect().left),
              der: Math.round(h.getBoundingClientRect().right)});
  }
  return out;
})()"""

c = credenciales()
con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CS)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")
cur.execute("begin delete from usuario_empresa where usuario_id in "
            "(select usuario_id from usuario where upper(username)=upper(:u)); commit; "
            "delete from usuario where upper(username)=upper(:u); commit; end;", u=USUARIO)
cur.execute("""insert into usuario (username,email,password_hash,estado,id_empresa,rol_id,
                                     debe_cambiar_clave,reintentos_fallidos)
               values (:u,:e,sypex_hash_password(:p),'ACTIVO',1,
                       (select id_rol from syn_roles where codigo_rol='ADMIN'),'N',0)""",
            u=USUARIO, e=USUARIO + "@synpex.local", p=CLAVE)
con.commit()

nav = Nav()
try:
    nav.js('window.location.href="%s/f?p=100:9999"' % BASE)
    nav.esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(1)
    nav.js('(function(){apex.item("P9999_USERNAME").setValue(%s);'
           'apex.item("P9999_PASSWORD").setValue(%s);'
           'var b=[...document.querySelectorAll("button")].find(x=>/sign in|iniciar|entrar/i.test(x.innerText));'
           'if(b){b.click();}})()' % (json.dumps(USUARIO), json.dumps(CLAVE)))
    time.sleep(8)
    ses = nav.js('(function(){try{return apex.env.APP_SESSION;}catch(e){return null;}})()')
    if not ses:
        sys.exit("login fallido")

    nav.medida(1440)
    nav.js('window.location.href="%s/f?p=100:19:%s"' % (BASE, ses))
    if not nav.esperar('document.readyState === "complete" && !!document.querySelector(".t-Region-header")'):
        sys.exit("la pagina 19 no pinto ninguna cabecera de region")
    time.sleep(2)

    # la pestana «Mis empresas» para medir tambien su cabecera
    nav.js("""(function(){var a=document.querySelector('.a-RDS-link[href="#R43000000000000396"]');
               if(a){a.click();}})()""")
    time.sleep(2)

    cab = nav.js(MEDIR) or []
    print("\n--- 1440 px")
    for x in cab:
        print("   %-26s alto=%s ancho=%s padding=%s fuente=%s maxw=%s  x=%s..%s"
              % (x["id"], x["alto"], x["ancho"], x["padding"], x["fuente"], x["maxw"], x["izq"], x["der"]))
    comprobar("hay al menos dos cabeceras (tarjeta + pestanas)",
              isinstance(cab, list) and len(cab) >= 2, len(cab) if isinstance(cab, list) else cab)
    nav.captura(os.path.join(RES, PREFIJO + "_1440.png"))

    nav.medida(500, 900)
    time.sleep(2)
    cabm = nav.js(MEDIR) or []
    print("\n--- 500 px")
    for x in cabm:
        print("   %-26s alto=%s ancho=%s padding=%s fuente=%s maxw=%s  x=%s..%s"
              % (x["id"], x["alto"], x["ancho"], x["padding"], x["fuente"], x["maxw"], x["izq"], x["der"]))
    nav.captura(os.path.join(RES, PREFIJO + "_500.png"))

    cuerpo = nav.js("document.body.innerText") or ""
    comprobar("no salen errores en pantalla",
              "cannot be rendered" not in cuerpo and "ORA-" not in cuerpo, cuerpo[:150])

    print("\nCAPTURAS: %s_1440.png / %s_500.png" % (PREFIJO, PREFIJO))
finally:
    nav.cerrar()
    cur.execute("begin delete from usuario_empresa where usuario_id in "
                "(select usuario_id from usuario where upper(username)=upper(:u)); commit; "
                "delete from usuario where upper(username)=upper(:u); commit; end;", u=USUARIO)
    con.commit()
    con.close()

print("\nRESULTADO: FALLAS=%d" % len(fallas))
sys.exit(1 if fallas else 0)
