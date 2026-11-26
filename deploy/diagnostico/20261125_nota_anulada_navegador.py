#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""La nota de credito que crea «Anular» (2026-11-25), en navegador real.

Usa la ultima nota de credito PROCESADA de una empresa venezolana que venga de anular una factura.

  A1 en la lista (8) la nota muestra el estado PROCESADA con insignia de color
  A2 al marcar la nota, el detalle de la lista trae sus lineas (antes salia vacio)
  A3 el boton dice «Procesar nota de credito» bien escrito y esta deshabilitado
  A4 «Nueva Linea» queda deshabilitado (la nota ya no es PENDIENTE)
  A5 en el dialogo (9) la etiqueta dice «N. Nota de credito» y la factura origen su folio
  A6 en el dialogo no sale la region para elegir lineas ni el boton Anular
  A7 la tarjeta de totales no falla al marcar la factura ANULADA

    python deploy/diagnostico/20261125_nota_anulada_navegador.py
"""
import importlib.util
import os
import sys
import time

AQUI = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("aud", os.path.join(AQUI, "20261125_auditoria_estandar.py"))
aud = importlib.util.module_from_spec(spec)
spec.loader.exec_module(aud)

fallas = []


def ok(nombre, cond, det=""):
    print(("  OK   " if cond else "  FALLA") + " " + nombre + ("" if cond else "  -> " + str(det)[:220]))
    if not cond:
        fallas.append(nombre)


c = aud.credenciales()
con = aud.oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=aud.CS)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")
cur.execute("""select nc.id_factura, nc.folio_factura, nc.id_empresa, o.id_factura, o.folio_factura
                 from facturas nc
                 join facturas o on o.id_factura = nc.id_factura_origen
                 join empresas e on e.id_empresa = nc.id_empresa
                where nc.tipo_documento = 'NC' and nc.estado = 'TIMBRADA' and o.estado = 'ANULADA'
                  and e.cod_pais = 'VE'
                order by nc.id_factura desc fetch first 1 rows only""")
fila = cur.fetchone()
if not fila:
    sys.exit("no hay una nota de credito de anulacion para probar")
ID_NC, FOLIO_NC, EMP, ID_ORIG, FOLIO_ORIG = fila
print("nota %s (%s) de la factura %s, empresa %s" % (FOLIO_NC, ID_NC, FOLIO_ORIG, EMP))

USR = "diag.nota"
BORRA = ("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario "
         "where upper(username)=upper(:u)); commit; delete from usuario where "
         "upper(username)=upper(:u); commit; end;")
cur.execute(BORRA, u=USR)
cur.execute("""insert into usuario (username,email,password_hash,estado,id_empresa,rol_id,
                                     debe_cambiar_clave,reintentos_fallidos)
               values (:u,:e,sypex_hash_password(:p),'ACTIVO',:emp,
                       (select id_rol from syn_roles where codigo_rol='ADMIN'),'N',0)""",
            u=USR, e=USR + "@synpex.local", p=aud.CLAVE, emp=EMP)
con.commit()
aud.USUARIO = USR

nav = aud.Nav(puerto=9303)
try:
    ses = aud.entrar(nav)
    if not ses:
        sys.exit("login fallido")
    nav.js('window.location.href="%s/f?p=100:8:%s"' % (aud.BASE, ses))
    nav.esperar('document.readyState==="complete" && document.querySelectorAll(".js-select-invoice").length>0', 50)
    time.sleep(2)

    insignia = nav.js('(function(){var c=document.querySelector(\'.js-select-invoice[data-id="%d"]\');'
                      'if(!c)return "SIN FILA";var b=c.closest("tr").querySelector(".status-badge");'
                      'return b?(b.className+"|"+getComputedStyle(b).backgroundColor):"SIN INSIGNIA";})()' % ID_NC)
    ok("A1 la nota sale PROCESADA con insignia de color",
       "status-PROCESADA" in str(insignia) and "rgba(0, 0, 0, 0)" not in str(insignia), insignia)

    nav.js('(function(){var c=document.querySelector(\'.js-select-invoice[data-id="%d"]\');'
           'c.checked=true;c.dispatchEvent(new Event("change",{bubbles:true}));})()' % ID_NC)
    time.sleep(6)
    lineas = nav.js('document.querySelectorAll("#R29979947211096273 table.a-IRR-table tr td").length')
    ok("A2 el detalle de la lista trae las lineas de la nota", (lineas or 0) > 0, lineas)
    boton = nav.js('(function(){var b=document.querySelector(\'[data-otel-label="BTN_PROCESAR"]\');'
                   'return b?(b.innerText.trim()+"|"+b.disabled):"SIN BOTON";})()')
    ok("A3 el boton dice «Procesar nota de credito» y esta deshabilitado",
       str(boton).startswith("Procesar nota de crédito") and str(boton).endswith("|true"), boton)
    nueva = nav.js('(function(){var b=document.querySelector(\'[data-otel-label="BTN_NUEVO_DETALLE"]\');'
                   'return b?b.disabled:"SIN BOTON";})()')
    ok("A4 Nueva Linea deshabilitado en una nota procesada", nueva is True, nueva)

    nav.js('(function(){var c=document.querySelector(\'.js-select-invoice[data-id="%d"]\');'
           'if(c){c.checked=true;c.dispatchEvent(new Event("change",{bubbles:true}));}})()' % ID_ORIG)
    time.sleep(6)
    tarjeta = nav.js('(function(){var r=document.getElementById("R30554313608864005");'
                     'return r?r.innerText.replace(/\\s+/g," ").slice(0,120):"SIN TARJETA";})()')
    ok("A7 la tarjeta de totales de la factura ANULADA no falla",
       "Total" in str(tarjeta) and "error" not in str(tarjeta).lower(), tarjeta)

    nav.js('(function(){var c=document.querySelector(\'.js-select-invoice[data-id="%d"]\');'
           'var a=c.closest("tr").querySelector(\'a[href*="a-dialog-open"]\');if(a){a.click();}})()' % ID_NC)
    nav.esperar('(function(){var f=document.querySelector("iframe");'
                'return !!(f&&f.contentWindow&&f.contentWindow.apex&&f.contentWindow.apex.item);})()', 40)
    time.sleep(4)
    d = nav.js("""(function(){var w=document.querySelector("iframe").contentWindow, doc=w.document;
        var lb=doc.getElementById("P9_FOLIO_FACTURA_LABEL");
        var org=doc.getElementById("P9_ID_FACTURA_ORIGEN");
        var orgTxt=org?(org.value||org.textContent||""):"";
        var disp=doc.querySelector("#P9_ID_FACTURA_ORIGEN_DISPLAY, input[name='P9_ID_FACTURA_ORIGEN_DISPLAY']");
        var picker=doc.querySelectorAll(".js-linea-sel").length;
        var anular=[...doc.querySelectorAll("button")].some(function(b){return /Anular/.test(b.innerText);});
        return {lb: lb?lb.textContent.trim():null, org: disp?disp.value:(doc.body.innerText.indexOf("%s")>=0?"%s":orgTxt),
                picker: picker, anular: anular};})()""" % (FOLIO_ORIG, FOLIO_ORIG))
    print("  dialogo:", d)
    ok("A5 la etiqueta dice Nota de credito", isinstance(d, dict) and "Nota de cr" in str(d.get("lb")), d)
    ok("A5 la factura origen muestra su folio", isinstance(d, dict) and FOLIO_ORIG in str(d.get("org")), d)
    ok("A6 no sale la region para elegir lineas", isinstance(d, dict) and d.get("picker") == 0, d)
    ok("A6 no sale el boton Anular en una nota", isinstance(d, dict) and d.get("anular") is False, d)
finally:
    nav.cerrar()
    cur.execute(BORRA, u=USR)
    con.close()

print("\nRESULTADO: FALLAS=%d" % len(fallas))
for f in fallas:
    print("  - " + f)
sys.exit(1 if fallas else 0)
