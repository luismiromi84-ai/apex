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
pago_prueba = None
fav_prov = fav_compra = fav_pago = None
compra_saldo = None

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
    comprobar("N2c un pago nuevo si ofrece Aplicar todo",
              "aplicar todo" in str(nav.js("document.body.innerText") or "").lower())

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
        pago_prueba = pagos_despues if pagos_despues > pagos_antes else None
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

            # N6: un pago registrado se ve en SOLO LECTURA (2026-11-22).
            # El reparto de un pago no se puede cambiar: antes salia «Aplicar todo»
            # y dejaba teclear importes que no se guardaban en ningun sitio.
            texto = str(nav.js("document.body.innerText") or "")
            comprobar("N6 el pago abierto no ofrece Aplicar todo",
                      "aplicar todo" not in texto.lower(), texto[:120])
            comprobar("N6 ni deja teclear importes",
                      nav.js("document.querySelectorAll('.spx-monto').length") == 0,
                      nav.js("document.querySelectorAll('.spx-monto').length"))
            comprobar("N6 ni pinta casillas de seleccion",
                      nav.js("document.querySelectorAll('.spx-sel').length") == 0,
                      nav.js("document.querySelectorAll('.spx-sel').length"))
            comprobar("N6 muestra las facturas pagadas con este pago",
                      "facturas pagadas" in texto.lower(), texto[:120])
            folio = cur.execute(
                "select c.folio_factura from pagos_detalle d "
                "join compras c on c.id_compra = d.id_compra where d.id_pago = :p",
                p=pagos_despues).fetchone()
            comprobar("N6 y la factura que pago",
                      folio is not None and str(folio[0]) in texto, (folio, texto[:120]))
            comprobar("N6 explica como corregirlo",
                      "anula este pago" in texto.lower(), texto[:120])
            comprobar("N6 el boton Ver facturas tampoco sale",
                      nav.js("!!document.querySelector('[data-otel-label=\"BTN_VER_FACTURAS\"]')") is False)
            nav.captura(os.path.join(RES, "20261122_pago_cargado.png"))

            # N10: el comprobante de pago en papel (pagina 38 clic real desde la 37)
            impr = nav.js("""(function(){
                var b=[...document.querySelectorAll('button,a')]
                       .find(function(x){return (x.getAttribute('data-otel-label')||'')==='BTN_IMPRIMIR_PAGO';});
                if(!b){return 'NO';} b.click(); return 'CLIC';})()""")
            comprobar("N10 el pago abierto ofrece «Imprimir comprobante»", impr == "CLIC", impr)
            time.sleep(10)
            cuerpo38 = str(nav.js("document.body.innerText") or "")
            comprobar("N10 abre el comprobante de pago",
                      "COMPROBANTE DE PAGO" in cuerpo38.upper(), cuerpo38[:150])
            comprobar("N10 y trae el numero del pago",
                      str(pagos_despues) in cuerpo38, cuerpo38[:200])
            comprobar("N10 con su total pagado",
                      "TOTAL PAGADO" in cuerpo38.upper(), cuerpo38[:200])
            nav.captura(os.path.join(RES, "20261122_comprobante_pago.png"))

            # N7: usar el credito del proveedor ------------------------------
            # Un anticipo (pago sin reparto) y una factura nueva del mismo
            # proveedor: la pantalla ofrece el credito y lo aplica.
            vid = cur.var(oracledb.NUMBER)
            cur.execute("insert into proveedores (id_empresa, rif, razon_social) "
                        "values (1, 'DIAG-FAV-1', 'Proveedor credito diag') "
                        "returning id_proveedor into :1", [vid])
            fav_prov = int(vid.getvalue()[0])
            vc = cur.var(oracledb.NUMBER)
            cur.execute("insert into compras (id_empresa, id_proveedor, tipo_documento, "
                        "folio_factura, fecha_emision, cod_moneda, tipo_cambio, monto_total, estado) "
                        "values (1, :p, 'FAC', 'DIAG-FAV-1', sysdate, 'VES', 1, 100, 'REGISTRADA') "
                        "returning id_compra into :2", [fav_prov, vc])
            fav_compra = int(vc.getvalue()[0])
            vp = cur.var(oracledb.NUMBER)
            cur.execute("insert into pagos (id_empresa, id_proveedor, fecha_pago, cod_moneda, "
                        "tipo_cambio, monto, monto_bs, conciliado, estado, creado_por) "
                        "values (1, :p, sysdate, 'VES', 1, 40, 40, 'N', 'ACTIVO', :u) "
                        "returning id_pago into :2", [fav_prov, USUARIO, vp])
            fav_pago = int(vp.getvalue()[0])
            con.commit()

            nav.js('window.location.href="%s/f?p=100:36:%s"' % (BASE, ses))
            nav.esperar('document.readyState === "complete" '
                        '&& !!document.getElementById("R43000000000001570")')
            time.sleep(2)
            nuevo = nav.js("""(function(){var b=[...document.querySelectorAll('button')]
                                  .find(x=>/Nuevo pago/i.test(x.innerText));
                                  if(b){b.click();return 'CLIC';} return 'SIN BOTON';})()""")
            comprobar("N7 «Nuevo pago» abre un pago nuevo", nuevo == "CLIC", nuevo)
            time.sleep(10)
            idp = nav.js('apex.item("P37_ID_PAGO").getValue()')
            comprobar("N7 y no reabre el pago que se estaba viendo",
                      str(idp or "") == "", idp)
            nav.js('apex.item("P37_COD_MONEDA").setValue("VES");'
                   'apex.item("P37_TIPO_CAMBIO").setValue(1);')
            nav.js('apex.item("P37_ID_PROVEEDOR").setValue(%s);' % json.dumps(str(fav_prov)))
            nav.js("""(function(){var b=[...document.querySelectorAll('button')]
                         .find(x=>/Ver facturas/i.test(x.innerText)); if(b){b.click();} return !!b;})()""")
            time.sleep(12)
            credito = nav.js("(document.querySelector('.spx-credito')||{}).innerText || ''")
            comprobar("N7 sale el credito del proveedor", "40.00" in str(credito), credito)
            usar = nav.js("""(function(){var a=document.querySelector('a.spx-usar');
                                  if(!a){return 'SIN ENLACE';} a.click(); return 'CLIC';})()""")
            comprobar("N7 hay un enlace Usar por fila", usar == "CLIC", usar)
            time.sleep(12)
            texto = str(nav.js("document.body.innerText") or "")
            comprobar("N7 aplica el credito y lo dice",
                      "Se aplicaron 40.00" in texto, texto[:150])
            det = cur.execute("select monto_aplicado from pagos_detalle where id_pago = :p",
                              p=fav_pago).fetchone()
            comprobar("N7 el reparto queda guardado",
                      det is not None and float(det[0]) == 40.0, det)
            est = cur.execute("select estado from compras where id_compra = :c",
                              c=fav_compra).fetchone()[0]
            comprobar("N7 la compra queda Abonada", est == "PARCIAL", est)
            saldo = cur.execute("select fn_saldo_compra(:c) from dual", c=fav_compra).fetchone()[0]
            comprobar("N7 y su saldo baja a 60", float(saldo) == 60.0, saldo)
            nav.captura(os.path.join(RES, "20261122_favor_aplicado.png"))
            con.commit()

            # N8: el saldo no es un diferencial cambiario -------------------
            # Total 1.480 USD con 54.998,86 Bs de retencion de IVA: el saldo son
            # 1.420 (60 de retencion), y las columnas tienen que cuadrar a la vista.
            vs = cur.var(oracledb.NUMBER)
            cur.execute("insert into compras (id_empresa, id_proveedor, tipo_documento, "
                        "folio_factura, fecha_emision, cod_moneda, tipo_cambio, monto_total, "
                        "retencion_iva_bs, estado) "
                        "values (1, :p, 'FAC', 'DIAG-1480', sysdate, 'USD', 916.6477, 1480, "
                        "54998.86, 'REGISTRADA') returning id_compra into :2", [fav_prov, vs])
            compra_saldo = int(vs.getvalue()[0])
            con.commit()

            nav.js('window.location.href="%s/f?p=100:36:%s"' % (BASE, ses))
            nav.esperar('document.readyState === "complete" '
                        '&& !!document.getElementById("R43000000000001570")')
            time.sleep(2)
            nav.js("""(function(){var b=[...document.querySelectorAll('button')]
                          .find(x=>/Nuevo pago/i.test(x.innerText)); if(b){b.click();}})()""")
            time.sleep(10)
            nav.js('apex.item("P37_COD_MONEDA").setValue("USD");'
                   'apex.item("P37_TIPO_CAMBIO").setValue(916.6477);')
            nav.js('apex.item("P37_ID_PROVEEDOR").setValue(%s);' % json.dumps(str(fav_prov)))
            nav.js("""(function(){var b=[...document.querySelectorAll('button')]
                         .find(x=>/Ver facturas/i.test(x.innerText)); if(b){b.click();}})()""")
            time.sleep(12)
            fila = nav.js("""(function(){
                var fs=document.querySelectorAll('.spx-pago-fila');
                for(var i=0;i<fs.length;i++){
                    if(fs[i].innerText.indexOf('DIAG-1480') >= 0){
                        return JSON.stringify([...fs[i].querySelectorAll('td')].map(function(t){
                            return t.innerText.trim();}));
                    }
                }
                return 'SIN FILA';})()""")
            try:
                celdas = json.loads(fila)
            except Exception:
                celdas = []
            print("  fila 1480:", celdas)
            comprobar("N8 el total sale en la moneda de la factura",
                      len(celdas) > 6 and celdas[5] in ("1480.00", "1,480.00"), celdas)
            comprobar("N8 la retencion de IVA son 60 USD (no 54.998,86 Bs)",
                      len(celdas) > 7 and celdas[7] in ("60.00", "60,00"), celdas)
            comprobar("N8 el saldo son 1.420 y cuadra con el total",
                      len(celdas) > 10 and celdas[10] in ("1420.00", "1,420.00"), celdas)
            nota = str(nav.js("(function(){var n=document.querySelectorAll('.spx-nota');"
                              "for(var i=0;i<n.length;i++){if(/SENIAT/i.test(n[i].innerText)){return n[i].innerText;}}"
                              "return '';})()") or "")
            comprobar("N8 la nota dice que la retencion se entera al SENIAT",
                      "SENIAT" in nota, nota[:120])
            nav.captura(os.path.join(RES, "20261122_saldo_1420.png"))

            # N9: «Pagar» desde la lista de compras --------------------------
            # La columna Pagar abre la 37 con el proveedor ya elegido y sus
            # facturas abiertas (sin pulsar «Ver facturas»).
            nav.js('window.location.href="%s/f?p=100:27:%s"' % (BASE, ses))
            nav.esperar('document.readyState === "complete" '
                        '&& !!document.getElementById("R43000000000001000")')
            time.sleep(4)
            control = nav.js("""(function(){
                var fs=[...document.querySelectorAll('#R43000000000001000 tbody tr')];
                var con=0, sen=0, mal=0;
                fs.forEach(function(tr){
                    var tds=[...tr.querySelectorAll('td')];
                    if(tds.length < 10){return;}
                    var est=(tds[12].innerText||'').trim();
                    var hay=!!tr.querySelector('a[href*="p37_id_proveedor"]');
                    if(['Procesada','Abonada','Pagada'].indexOf(est)>=0){
                        con++; if(!hay){mal++;}
                    } else {
                        sen++; if(hay){mal++;}
                    }
                });
                return JSON.stringify({con:con,sen:sen,mal:mal});})()""")
            try:
                ctl = json.loads(control)
            except Exception:
                ctl = None
            comprobar("N9 «Pagar» solo en facturas procesadas, abonadas o pagadas",
                      bool(ctl) and ctl["mal"] == 0 and ctl["con"] >= 1, control)
            ir = nav.js("""(function(){
                var fs=[...document.querySelectorAll('#R43000000000001000 tbody tr')];
                for(var i=0;i<fs.length;i++){
                    if(fs[i].innerText.indexOf('DIAG-1480') >= 0){
                        var a=fs[i].querySelector('a[href*="p37_id_proveedor"]');
                        if(!a){return 'SIN ENLACE';}
                        a.click(); return 'CLIC';
                    }
                }
                return 'SIN FILA';})()""")
            comprobar("N9 la lista de compras tiene el enlace Pagar", ir == "CLIC", ir)
            time.sleep(10)
            prov37 = nav.js('apex.item("P37_ID_PROVEEDOR").getValue()')
            comprobar("N9 abre la 37 con el proveedor elegido",
                      str(prov37) == str(fav_prov), (prov37, fav_prov))
            filas37 = nav.js("document.querySelectorAll('.spx-pago-fila').length")
            comprobar("N9 y con sus facturas abiertas a la vista",
                      isinstance(filas37, int) and filas37 == 2, filas37)
            comprobar("N9 spxNum entiende 1.420,00", nav.js('spxNum("1.420,00")') == 1420,
                      nav.js('spxNum("1.420,00")'))
            comprobar("N9 spxNum entiende 1,420.00", nav.js('spxNum("1,420.00")') == 1420,
                      nav.js('spxNum("1,420.00")'))
            comprobar("N9 spxNum sigue entendiendo 1420", nav.js('spxNum("1420")') == 1420)

            # limpieza: se anula el pago de prueba
            cur.execute("begin pkg_pagos.prc_anular_pago(:p, :u); commit; end;",
                        p=pagos_despues, u=USUARIO)
            est = cur.execute("select estado from pagos where id_pago = :p",
                              p=pagos_despues).fetchone()[0]
            comprobar("N4 el pago de prueba queda ANULADO", est == "ANULADO", est)

finally:
    nav.cerrar()
    if pago_prueba:
        # Un pago de prueba no se queda en la base ni ANULADO: ensucia la lista y
        # las verificaciones de saldo (el detalle y la cabecera no se borran en la
        # misma transaccion: ORA-12860, por eso hay commit en medio).
        try:
            cur.execute("begin delete from pagos_detalle where id_pago = :p; commit; "
                        "delete from pagos where id_pago = :p; commit; end;", p=pago_prueba)
        except Exception as e:
            print("  (no se pudo borrar el pago de prueba %s: %s)" % (pago_prueba, e))
    # La escena del credito tambien se limpia (N7).
    for sql, val in (("begin delete from pagos_detalle where id_pago = :x; commit; "
                      "delete from pagos where id_pago = :x; commit; end;", fav_pago),
                     ("begin delete from compras where id_compra = :x; commit; end;", fav_compra),
                     ("begin delete from compras where id_compra = :x; commit; end;", compra_saldo),
                     ("begin delete from proveedores where id_proveedor = :x; commit; end;", fav_prov)):
        if not val:
            continue
        try:
            cur.execute(sql, x=val)
        except Exception as e:
            print("  (no se pudo limpiar N7 %s: %s)" % (val, e))
    cur.execute("begin delete from usuario_empresa where usuario_id in "
                "(select usuario_id from usuario where upper(username)=upper(:u)); commit; "
                "delete from usuario where upper(username)=upper(:u); commit; end;", u=USUARIO)
    con.close()

print()
print("RESULTADO: FALLAS=" + str(len(fallas)))
for f in fallas:
    print("  - " + f)
sys.exit(1 if fallas else 0)
