#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""La cabecera azul mide lo mismo en todas las pantallas (44 px).

El dueno pidio, despues de dejar la 19 en 44 px, «aplicalo en todos los demas». Se anadio el
mismo bloque de anulacion al final del CSS de las 22 paginas que pintan la banda. Esta prueba
recorre las pantallas de verdad con un usuario temporal y mide, en el navegador, el alto de cada
cabecera de region y el tamano del titulo. Ademas abre un dialogo desde Facturacion para medir la
barra del modal, que la pinta la pagina padre.

Uso:
  python deploy/diagnostico/20261121_cabecera_global.py

Crea y borra su propio usuario; no toca datos de negocio.
"""
import base64
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
BASE = "https://gfd7e2575d251ae-sypxsql.adb.mx-monterrey-1.oraclecloudapps.com/ords".replace("sypxsql", "sypexsql")
RES = os.path.join(REPO, "deploy", "resultados")
USUARIO, CLAVE = "diag.cab", "Diag#2026"

# Paginas normales que se pueden abrir por URL. Fuera las de cuadro de dialogo (se prueba una
# aparte), las de impresion y la 28: desde el 2026-11-20 la 28 lleva el **titulo al tema** (sin
# banda azul) por decision del dueno, asi que su cabecera no tiene por que medir 44.
PAGINAS = [3, 5, 8, 13, 16, 17, 18, 19, 20, 22, 24, 27, 29, 32, 33, 34]
CAPTURAS = {5: "20261121_cab_global_p5", 8: "20261121_cab_global_p8",
            27: "20261121_cab_global_p27"}

ALTO_MIN, ALTO_MAX = 36, 52
FUENTE = 15.2

fallas = []


def comprobar(nombre, condicion, detalle=""):
    print(("  OK   " if condicion else "  FALLA") + " " + nombre +
          ("" if condicion else "  -> " + str(detalle)[:220]))
    if not condicion:
        fallas.append(nombre)


class Nav:
    def __init__(self, puerto=9297):
        self.proc = subprocess.Popen(
            [EDGE, "--headless=new", "--disable-gpu", "--no-first-run", "--hide-scrollbars",
             "--remote-debugging-port=%d" % puerto,
             "--user-data-dir=%s" % os.path.join(tempfile.gettempdir(), "opencode", "edge-cabglobal"),
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

    def captura(self, ruta):
        h = self.js("Math.min(Math.max(document.documentElement.scrollHeight,"
                    "document.body.scrollHeight), 6500)")
        alto = int(h) if isinstance(h, (int, float)) and h > 200 else 900
        r = self.cmd("Page.captureScreenshot", format="png", captureBeyondViewport=True,
                     clip={"x": 0, "y": 0, "width": self.js("window.innerWidth") or 1440,
                           "height": alto, "scale": 1})
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
  var out = [], hs = document.querySelectorAll('.t-Region-header');
  for (var i = 0; i < hs.length; i++) {
    var h = hs[i];
    if (getComputedStyle(h).display === 'none') { continue; }
    var r = h.getBoundingClientRect();
    if (r.height === 0) { continue; }
    var t = h.querySelector('.t-Region-title');
    out.push({alto: Math.round(r.height * 10) / 10,
              fuente: t ? Math.round(parseFloat(getComputedStyle(t).fontSize) * 10) / 10 : null,
              texto: t ? t.textContent.replace(/\\s+/g, ' ').trim().slice(0, 30) : ''});
  }
  return out;})()"""

# --- usuario temporal ----------------------------------------------------------
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
    nav.medida(1440)
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

    print("== alto de la banda y tamano del titulo, pantalla por pantalla ==")
    for pag in PAGINAS:
        nav.js('window.location.href="%s/f?p=100:%d:%s"' % (BASE, pag, ses))
        ok = nav.esperar('document.readyState === "complete" && !!window.apex')
        time.sleep(2.5)
        datos = nav.js(MEDIR)
        if not isinstance(datos, list):
            comprobar("pagina %d responde" % pag, False, datos)
            continue
        visibles = [d for d in datos if d.get("alto", 0) >= 8]
        if not visibles:
            print("  [--]  pagina %-3d sin cabeceras visibles" % pag)
            continue
        altos = [d["alto"] for d in visibles]
        fuentes = [d["fuente"] for d in visibles if d.get("fuente")]
        ok_alto = all(ALTO_MIN <= a <= ALTO_MAX for a in altos)
        ok_fuente = all(abs(f - FUENTE) <= 0.6 for f in fuentes) if fuentes else False
        comprobar("pagina %-3d %d cabeceras, alto %s"
                  % (pag, len(visibles), sorted(set(altos))), ok_alto and ok_fuente,
                  "altos=%s fuentes=%s" % (sorted(set(altos)), sorted(set(fuentes))))

        if pag in CAPTURAS and ok:
            nav.captura(os.path.join(RES, CAPTURAS[pag] + "_1440.png"))

    print("== la barra del cuadro de dialogo (la pinta el padre) ==")
    nav.js('window.location.href="%s/f?p=100:8:%s"' % (BASE, ses))
    nav.esperar('document.readyState === "complete" && !!document.querySelector("td a[href*=a-dialog-open]")')
    time.sleep(2)
    nav.js("""(function(){var a=document.querySelector('td a[href*="a-dialog-open"]');
                 if(a){a.click();}})()""")
    time.sleep(6)
    barra = nav.js("""(function(){var b=document.querySelector('.ui-dialog-titlebar');
        if(!b) return null;
        var t=b.querySelector('.ui-dialog-title');
        return {alto: Math.round(b.getBoundingClientRect().height*10)/10,
                relleno: getComputedStyle(b).padding,
                fuente: t ? Math.round(parseFloat(getComputedStyle(t).fontSize)*10)/10 : null};})()""")
    if isinstance(barra, dict):
        comprobar("la barra del dialogo queda entre 36 y 56 px",
                  36 <= barra["alto"] <= 56, barra)
        comprobar("el titulo del dialogo no se dispara", barra["fuente"] and barra["fuente"] <= 17,
                  barra)
        print("     barra: alto=%(alto)s relleno=%(relleno)s fuente=%(fuente)s" % barra)
    else:
        comprobar("abre el cuadro de dialogo", False, barra)

finally:
    nav.cerrar()
    cur.execute("begin delete from usuario_empresa where usuario_id in "
                "(select usuario_id from usuario where upper(username)=upper(:u)); commit; "
                "delete from usuario where upper(username)=upper(:u); commit; end;", u=USUARIO)
    con.close()

print()
print("RESULTADO: FALLAS=" + str(len(fallas)))
for f in fallas:
    print("  - " + f)
sys.exit(1 if fallas else 0)
