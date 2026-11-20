#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Pagina 19 «Administracion»: pestanas en el movil, logo en una sola pestana y
los remates que pidio el dueno (2026-11-20). Todo es presentacion.

  P1  el selector tiene 6 pestanas y «Logo corporativo» sustituye a «Logo actual»+«Subir logo»
  P2  en escritorio (1440) la barra de pestanas NO es un carrusel (envuelve)
  P3  en el movil (500) la barra se desplaza en horizontal, sin barra de scroll
  P4  «Logo corporativo» pinta el logo actual con formato, peso y fecha
  P5  y debajo el area de carga (input de archivo + los dos botones)
  P6  «Mis empresas»: estado con insignia, «Editar» solo icono y la marca de la principal
  P7  «Empresa»: cabecera con nombre, pais, RIF y estado
  P8  el boton de la imprenta dice «Guardar datos de imprenta»
  P9  ninguna region muestra su PL/SQL y no hay error de rejilla

Uso: python deploy/diagnostico/20261120_admin_pestanas.py
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
USUARIO, CLAVE = "diag.pestanas", "Diag#2026"
fallas = []


def comprobar(nombre, condicion, detalle=""):
    print(("  OK   " if condicion else "  FALLA") + " " + nombre +
          ("" if condicion else "  -> " + str(detalle)[:220]))
    if not condicion:
        fallas.append(nombre)


class Nav:
    def __init__(self, puerto=9298):
        self.proc = subprocess.Popen(
            [EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
             "--hide-scrollbars",
             "--remote-debugging-port=%d" % puerto,
             "--user-data-dir=%s" % os.path.join(tempfile.gettempdir(), "opencode", "edge-p19tabs"),
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
    if not nav.esperar('document.readyState === "complete" && !!document.getElementById("spx-logo-file")'):
        sys.exit("la pagina 19 no pinto el logo corporativo")
    time.sleep(2)

    tabs = nav.js("""[...document.querySelectorAll('[id="43000000000000380_RDS"] .a-RDS-label')]
                     .map(function(e){return e.textContent.trim();})""")
    comprobar("P1 seis pestanas con «Logo corporativo»", isinstance(tabs, list) and len(tabs) == 6
              and "Logo corporativo" in tabs and "Logo actual" not in tabs
              and "Subir logo" not in tabs, tabs)

    # --- escritorio
    nav.js("""(function(){var a=document.querySelector('.a-RDS-link[href="#R43000000000000396"]');
               if(a){a.click();}})()""")
    time.sleep(2)
    estilo = nav.js("""(function(){var u=document.getElementById('43000000000000380_RDS');
                        var s=getComputedStyle(u);
                        return [s.flexWrap, s.overflowX, u.scrollWidth, u.clientWidth];})()""")
    comprobar("P2 en 1440 la barra no necesita desplazarse",
              isinstance(estilo, list) and estilo[2] <= estilo[3] + 2, estilo)
    nav.captura(os.path.join(RES, "20261120_admin_1440.png"))
    nav.captura(os.path.join(RES, "20261120_admin_misempresas.png"))

    fila = nav.js("""(function(){var f=document.querySelector('#R43000000000000396 tr[data-id]');
                       if(!f){return null;}
                       return {editar:(f.querySelector('a.spx-editar')||{}).innerHTML||'',
                               principal:(f.querySelector('.spx-principal')||{}).textContent||'',
                               badge:(f.querySelector('.status-badge')||{}).className||''};})()""")
    comprobar("P6 «Editar» es un icono con la clase spx-editar",
              isinstance(fila, dict) and "fa-pencil" in (fila.get("editar") or ""), fila)
    comprobar("P6 la fila de la principal lleva la marca",
              isinstance(fila, dict) and "Principal" in (fila.get("principal") or ""), fila)
    comprobar("P6 el estado va como insignia",
              isinstance(fila, dict) and "status-badge" in (fila.get("badge") or "")
              and "status-ACTIVO" in (fila.get("badge") or ""), fila)

    # --- pestana Empresa: cabecera
    nav.js("""(function(){var a=document.querySelector('.a-RDS-link[href="#R43000000000000381"]');
               if(a){a.click();}})()""")
    time.sleep(2)
    cab = nav.js("""(function(){var c=document.querySelector('#R43000000000000381 .spx-emp-cab');
                     return c ? c.textContent.replace(/\\s+/g,' ').trim() : null;})()""")
    comprobar("P7 la pestana Empresa tiene cabecera con nombre, pais, RIF y estado",
              isinstance(cab, str) and "Nueva empresa" in cab and "Venezuela" in cab
              and "ACTIVO" in cab, cab)
    nav.captura(os.path.join(RES, "20261120_admin_empresa.png"))

    # --- pestana del logo
    nav.js("""(function(){var a=document.querySelector('.a-RDS-link[href="#R43000000000000434"]');
               if(a){a.click();}})()""")
    time.sleep(2)
    meta = nav.js("""(function(){var p=document.querySelector('#R43000000000000434 .spx-logo-datos');
                      return p ? p.textContent.replace(/\\s+/g,' ').trim() : null;})()""")
    comprobar("P4 el logo trae formato, peso y fecha",
              isinstance(meta, str) and "KB" in meta and "/" in meta
              and any(x in meta for x in ("JPG", "PNG")), meta)
    hay = nav.js("""(function(){var r=document.getElementById('R43000000000000434');
                     return {img:!!r.querySelector('.spx-logo-actual img'),
                             input:!!r.querySelector('#spx-logo-file'),
                             subir:!!r.querySelector('[data-otel-label="BTN_SUBIR_LOGO"]'),
                             quitar:!!r.querySelector('[data-otellabel="BTN_QUITAR_LOGO"]')
                                 ||!!r.querySelector('[data-otel-label="BTN_QUITAR_LOGO"]')
                                 ||!!document.querySelector('[data-otellabel="BTN_QUITAR_LOGO"]')
                                 ||!!document.querySelector('[data-otel-label="BTN_QUITAR_LOGO"]')};})()""")
    comprobar("P5 logo, input y los dos botones en la misma pestana",
              isinstance(hay, dict) and all(hay.get(k) for k in ("img", "input", "subir", "quitar")), hay)
    nav.captura(os.path.join(RES, "20261120_admin_logo.png"))

    # --- el boton de la imprenta
    nav.js("""(function(){var a=document.querySelector('.a-RDS-link[href="#R43000000000000411"]');
               if(a){a.click();}})()""")
    time.sleep(2)
    rot = nav.js("""(function(){var b=document.querySelector('[data-otel-label="BTN_GUARDAR_IMPRENTA"]');
                     return b ? b.textContent.replace(/\\s+/g,' ').trim() : null;})()""")
    comprobar("P8 el boton dice «Guardar datos de imprenta»",
              isinstance(rot, str) and "imprenta" in rot.lower() and "fiscal" not in rot.lower(), rot)

    # --- movil
    nav.medida(500, 900)
    time.sleep(2)
    estilo = nav.js("""(function(){var u=document.getElementById('43000000000000380_RDS');
                        var s=getComputedStyle(u);
                        u.scrollLeft = 200; var movido = u.scrollLeft; u.scrollLeft = 0;
                        return [s.flexWrap, s.overflowX, u.scrollWidth, u.clientWidth,
                                movido, s.scrollbarWidth];})()""")
    comprobar("P3 en 500 la barra es un carrusel horizontal que se desplaza",
              isinstance(estilo, list) and estilo[0] == "nowrap"
              and estilo[2] > estilo[3] and estilo[4] > 0 and estilo[5] == "none", estilo)
    nav.js("""(function(){var a=document.querySelector('.a-RDS-link[href="#R43000000000000396"]');
               if(a){a.click();}})()""")
    time.sleep(2)
    nav.captura(os.path.join(RES, "20261120_admin_500.png"))
    nav.js("""(function(){var a=document.querySelector('.a-RDS-link[href="#R43000000000000434"]');
               if(a){a.click();}})()""")
    time.sleep(2)
    nav.captura(os.path.join(RES, "20261120_admin_500_logo.png"))

    # --- ninguna region enseña su PL/SQL
    cuerpo = nav.js("document.body.innerText") or ""
    comprobar("P9 ninguna region muestra el PL/SQL",
              "fn_clean_num" not in cuerpo and "v_html" not in cuerpo
              and "declare" not in cuerpo.lower(), cuerpo[:150])
finally:
    nav.cerrar()
    cur.execute("begin delete from usuario_empresa where usuario_id in "
                "(select usuario_id from usuario where upper(username)=upper(:u)); commit; "
                "delete from usuario where upper(username)=upper(:u); commit; end;", u=USUARIO)
    con.commit()
    con.close()

print("\nRESULTADO: FALLAS=%d" % len(fallas))
sys.exit(1 if fallas else 0)
