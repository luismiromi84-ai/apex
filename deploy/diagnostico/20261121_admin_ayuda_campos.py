#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Pagina 19, pestana «Datos fiscales»: las ayudas de la providencia y el rango.

El dueno no tiene la providencia SENIAT y va a cargar solo el rango de control.
Los tres campos ganaron un texto de ayuda (opcional / formato del rango). Esta
prueba comprueba en el navegador que el texto se sirve, que los campos lo
muestran y deja la captura de la pestana.

Uso:
  python deploy/diagnostico/20261121_admin_ayuda_campos.py [prefijo]

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
BASE = "https://gfd7e2575d251ae-sypexsql.adb.mx-monterrey-1.oraclecloudapps.com/ords"
RES = os.path.join(REPO, "deploy", "resultados")
USUARIO, CLAVE = "diag.ayuda", "Diag#2026"
PREFIJO = sys.argv[1] if len(sys.argv) > 1 else "20261121_admin_ayuda"
fallas = []


def comprobar(nombre, condicion, detalle=""):
    print(("  OK   " if condicion else "  FALLA") + " " + nombre +
          ("" if condicion else "  -> " + str(detalle)[:220]))
    if not condicion:
        fallas.append(nombre)


class Nav:
    def __init__(self, puerto=9291):
        self.proc = subprocess.Popen(
            [EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
             "--hide-scrollbars",
             "--remote-debugging-port=%d" % puerto,
             "--user-data-dir=%s" % os.path.join(tempfile.gettempdir(), "opencode", "edge-p19ayuda"),
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


# --- el texto de ayuda tiene que estar en el diccionario de APEX ---------------
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
    if not nav.esperar('document.readyState === "complete" && !!document.querySelector(".a-RDS-link")'):
        sys.exit("la pagina 19 no pinto el selector de pestanas")
    time.sleep(2)

    nav.js("""(function(){var l=[...document.querySelectorAll('.a-RDS-link')]
                 .find(a=>/datos fiscales/i.test(a.textContent));
               if(l){l.click();}})()""")
    time.sleep(3)

    print("== la pestana «Datos fiscales» muestra las ayudas ==")

    ITEMS = {"providencia": "43000000000000419",
             "control desde": "43000000000000420",
             "control hasta": "43000000000000421"}
    ESPERADO = {"providencia": "Opcional. El Nro. de control",
                "control desde": "Primer Nro. de control del rango",
                "control hasta": "Fin del rango de control"}

    botones = nav.js("""(function(){
        var ids = %s, out = {};
        for (var k in ids) {
          out[k] = !!document.querySelector('[data-itemhelp="' + ids[k] + '"]');
        }
        return out;})()""" % json.dumps(ITEMS))
    if not isinstance(botones, dict):
        comprobar("la pestana responde", False, botones)
        botones = {}

    for campo, esperado in ESPERADO.items():
        comprobar("«%s» pinta su boton de ayuda" % campo, botones.get(campo) is True, botones)

        # el texto viaja por AJAX: hay que abrir la ayuda y leerla
        nav.js("""(function(){var b=document.querySelector('[data-itemhelp="%s"]');
                     if(b){b.click();}})()""" % ITEMS[campo])
        time.sleep(2)
        texto = nav.js("""(function(){var d=document.querySelector('.ui-dialog--helpDialog');
                                      return d ? (d.innerText || '') : '';})()""")
        comprobar("la ayuda de «%s» trae su texto" % campo,
                  isinstance(texto, str) and esperado in texto, (texto or "")[:80])
        nav.js("""(function(){var c=document.querySelector('.ui-dialog--helpDialog .ui-dialog-titlebar-close');
                     if(c){c.click();}})()""")
        time.sleep(1)

    ok = nav.captura(os.path.join(RES, PREFIJO + "_1440.png"))
    comprobar("captura a 1440", ok)

    nav.medida(500, 900)
    time.sleep(2)
    ok = nav.captura(os.path.join(RES, PREFIJO + "_500.png"))
    comprobar("captura a 500", ok)

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
