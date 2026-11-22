#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Paginas 36 «Pagos» y 37 «Pago» (2026-11-21).

Comprueba en el navegador que la lista abre con su boton, que la pagina del pago
trae el formulario, que al elegir el proveedor salen sus facturas abiertas, que
«Aplicar todo» reparte el monto y deja el sobrante a favor, y que Guardar crea el
pago de verdad (y despues lo anula para no dejar basura).

Uso:
  python deploy/diagnostico/20261121_pagos_paginas.py

Crea y borra su propio usuario; el pago que crea lo anula al final.
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
USUARIO, CLAVE = "diag.pagos", "Diag#2026"
fallas = []


def comprobar(nombre, condicion, detalle=""):
    print(("  OK   " if condicion else "  FALLA") + " " + nombre +
          ("" if condicion else "  -> " + str(detalle)[:220]))
    if not condicion:
        fallas.append(nombre)


class Nav:
    def __init__(self, puerto=9288):
        self.proc = subprocess.Popen(
            [EDGE, "--headless=new", "--disable-gpu", "--no-first-run", "--hide-scrollbars",
             "--remote-debugging-port=%d" % puerto,
             "--user-data-dir=%s" % os.path.join(tempfile.gettempdir(), "opencode", "edge-pagos"),
             "--window-size=1440,900", "about:blank"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        objetivo = None
        for _ in range(40):
            try:
                lista = json.loads(urllib.request.urlopen(
                    "http://127.0.0.1:%d/json/list" % puerto, timeout=2).read())
                pg = [t for t in lista if t.get("type") == "page"]
                if pg:
                    objetivo = pg[0]
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

    def captura(self, ruta):
        import base64
        h = self.js("Math.min(Math.max(document.documentElement.scrollHeight,"
                    "document.body.scrollHeight), 4000)")
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

# proveedor con facturas pendientes
prov = cur.execute(
    "select min(c.id_proveedor) from compras c where c.id_empresa = 1 "
    "and c.estado in ('REGISTRADA','PARCIAL')").fetchone()[0]
pagos_antes = cur.execute("select nvl(max(id_pago), 0) from pagos").fetchone()[0]

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

    # N1: la lista ---------------------------------------------------------
    nav.js('window.location.href="%s/f?p=100:36:%s"' % (BASE, ses))
    ok = nav.esperar('document.readyState === "complete" && !!document.getElementById("R43000000000001570")')
    time.sleep(2)
    comprobar("N1 la lista de pagos abre", ok)
    comprobar("N1 trae el boton Nuevo pago",
              nav.js('!!document.querySelector("[data-otel-label=\\"BTN_NUEVO_PAGO\\"]")'
                     ' || /Nuevo pago/i.test(document.body.innerText)'))
    nav.captura(os.path.join(RES, "20261121_pagos_lista.png"))

    # N2: la pagina del pago ------------------------------------------------
    nav.js('window.location.href="%s/f?p=100:37:%s"' % (BASE, ses))
    ok = nav.esperar('document.readyState === "complete" && !!apex.item("P37_MONTO")')
    time.sleep(2)
    comprobar("N2 la pagina del pago abre con su formulario", ok)

    # N2b: al elegir el proveedor salen sus facturas ------------------------
    # setValue no dispara el change: hay que lanzarlo para que la accion dinamica
    # recargue la lista de facturas del proveedor
    nav.js('apex.item("P37_COD_MONEDA").setValue("VES");'
           'apex.item("P37_TIPO_CAMBIO").setValue(1);'
           'apex.item("P37_MONTO").setValue(50);')
    nav.js('apex.item("P37_ID_PROVEEDOR").setValue(%s);' % json.dumps(str(prov)))
    nav.js("""(function(){var b=[...document.querySelectorAll('button')]
                 .find(x=>/Ver facturas/i.test(x.innerText)); if(b){b.click();} return !!b;})()""")
    time.sleep(12)
    filas = nav.js("document.querySelectorAll('.spx-pago-fila').length")
    comprobar("N2b aparecen las facturas abiertas del proveedor", isinstance(filas, int) and filas > 0,
              filas)

    if isinstance(filas, int) and filas > 0:
        # N3: aplicar todo reparte y deja el sobrante a favor
        nav.js("spxAplicarTodo();")
        time.sleep(1)
        resumen = nav.js("(document.getElementById('spx-resumen')||{}).innerText || ''")
        aplicado = nav.js("""(function(){var t=0,fs=document.querySelectorAll('.spx-pago-fila');
            for(var i=0;i<fs.length;i++){var c=fs[i].querySelector('.spx-sel'),m=fs[i].querySelector('.spx-monto');
              if(c&&c.checked&&m){t=t+parseFloat(String(m.value).replace(',','.'));}}return t;})()""")
        comprobar("N3 Aplicar todo marca filas y escribe el resumen",
                  isinstance(aplicado, (int, float)) and aplicado > 0 and "Aplicado a facturas" in str(resumen),
                  (aplicado, resumen)) 

        nav.captura(os.path.join(RES, "20261121_pagos_reparto.png"))

        # N4: guardar
        nav.js("spxGuardar();")
        time.sleep(10)
        pagos_despues = cur.execute("select nvl(max(id_pago), 0) from pagos").fetchone()[0]
        comprobar("N4 el pago se guarda", pagos_despues > pagos_antes,
                  (pagos_antes, pagos_despues))

        if pagos_despues > pagos_antes:
            det = cur.execute("select count(*) from pagos_detalle where id_pago = :p",
                              p=pagos_despues).fetchone()[0]
            comprobar("N4 y guarda su reparto", det > 0, det)

            # N5: abrir el pago desde la lista TRAE sus datos y no ofrece Guardar
            nav.js('window.location.href="%s/f?p=100:36:%s"' % (BASE, ses))
            nav.esperar('document.readyState === "complete" && !!document.getElementById("R43000000000001570")')
            time.sleep(3)
            abierto = nav.js("""(function(){
                var a=[...document.querySelectorAll('a')].find(function(x){
                    return x.getAttribute('href') && x.getAttribute('href').indexOf('p37_id_pago') >= 0; });
                if(!a){return 'SIN ENLACE';} a.click(); return 'CLIC';})()""")
            time.sleep(9)
            comprobar("N5 el pago se abre desde la lista", abierto == "CLIC", abierto)
            monto = nav.js('apex.item("P37_MONTO").getValue()')
            comprobar("N5 el formulario trae el monto del pago", str(monto).startswith("50"), monto)
            proveedor = nav.js('apex.item("P37_ID_PROVEEDOR").getValue()')
            comprobar("N5 y su proveedor", str(proveedor) != "", proveedor)
            guardar = nav.js("/Guardar pago/i.test(document.body.innerText)")
            comprobar("N5 un pago guardado no ofrece Guardar", guardar is False, guardar)
            nav.captura(os.path.join(RES, "20261122_pago_cargado.png"))

            # limpieza: se anula el pago de prueba
            cur.execute("begin pkg_pagos.prc_anular_pago(:p, :u); commit; end;",
                        p=pagos_despues, u=USUARIO)
            est = cur.execute("select estado from pagos where id_pago = :p",
                              p=pagos_despues).fetchone()[0]
            comprobar("N4 el pago de prueba queda ANULADO", est == "ANULADO", est)

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
