#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Pago (37): el caso del duenio del 2026-11-26, en navegador real y SIN guardar nada.

Un pago de 996.27 en VES con la compra en USD daba «Lo aplicado a la compra 3328 supera su saldo»:
«996.27» se leia como 99.627 (en Venezuela el punto es de miles) y la pantalla dejaba enviar un
aplicado mayor que el pago.

  A1 lectura de importes: 996.27 -> 996,27; 1.500 -> 1500; 1.234,56 -> 1234,56; 12,5 -> 12,5
  A2 la misma lectura en toma fisica (47), conciliacion (48) y asientos (51)
  A3 con un pago en VES y la factura en USD, «Guardar pago» no envia si lo aplicado supera el pago
     y lo explica (la factura esta en otra moneda); no se crea ningun pago
  A4 el resumen se recalcula al cambiar el monto del pago
  A5 el mensaje del servidor usa el numero de la compra y su moneda, no el id interno

Usa la empresa de Venezuela con compras abiertas en USD y un usuario temporal ADMIN.

    python deploy/diagnostico/20261126_pago_aplicar_navegador.py
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
    print(("  OK   " if cond else "  FALLA") + " " + nombre + ("" if cond else "  -> " + str(det)[:240]))
    if not cond:
        fallas.append(nombre)


c = aud.credenciales()
con = aud.oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=aud.CS)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")
cur.execute("""select c.id_empresa, c.id_proveedor, c.id_compra, c.folio_factura
                 from compras c join empresas e on e.id_empresa = c.id_empresa
                where e.cod_pais = 'VE' and c.cod_moneda = 'USD' and fn_compra_pagable(c.id_compra) = 'S'
                order by c.id_compra desc fetch first 1 rows only""")
fila = cur.fetchone()
if not fila:
    print("RESULTADO: FALLAS=0 OMITIDOS=1 (no hay compras abiertas en USD)")
    sys.exit(0)
EMP, PROV, COMPRA, FOLIO = fila

U = "diag.pagoapl"
BORRA = ("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario "
         "where upper(username)=upper(:u)); commit; delete from usuario where upper(username)=upper(:u); commit; end;")
cur.execute(BORRA, u=U)
cur.execute("""insert into usuario (username,email,password_hash,estado,id_empresa,rol_id,debe_cambiar_clave,reintentos_fallidos)
               values (:u,:m,sypex_hash_password(:p),'ACTIVO',:e,(select id_rol from syn_roles where codigo_rol='ADMIN'),'N',0)""",
            u=U, m=U + "@synpex.local", p=aud.CLAVE, e=EMP)
con.commit()
cur.execute("select count(*) from pagos where id_empresa = :e", e=EMP)
PAGOS_ANTES = cur.fetchone()[0]

nav = aud.Nav(puerto=9318)


def abre(pag, esp='document.readyState === "complete" && !!window.apex'):
    nav.js('window.location.href="%s/f?p=100:%d:%s"' % (aud.BASE, pag, ses))
    nav.esperar(esp, 40)
    time.sleep(2.5)


LECTURAS = '[spxNum("996.27"), spxNum("1.500"), spxNum("1.234,56"), spxNum("12,5")].join("|")'
ESPERADO = "996.27|1500|1234.56|12.5"
try:
    aud.USUARIO = U
    ses = aud.entrar(nav)
    if not ses:
        sys.exit("login fallido")

    # A1
    abre(37, '!!document.getElementById("P37_MONTO")')
    lect = nav.js(LECTURAS)
    ok("A1 lectura de importes en el pago (VE)", lect == ESPERADO, lect)

    # A3 / A4
    nav.js('$s("P37_ID_PROVEEDOR","%d")' % PROV)
    time.sleep(1)
    nav.js('document.getElementById("B43000000000001624").click()')
    nav.esperar('document.readyState === "complete" && document.querySelectorAll(".spx-pago-fila").length > 0', 40)
    time.sleep(2)
    nav.js('$s("P37_COD_MONEDA","VES")')
    nav.esperar('String(apex.item("P37_TIPO_CAMBIO").getValue()).trim() === "1"', 20)
    # como lo escribe una persona: en el campo, con punto decimal
    nav.js('var m=document.getElementById("P37_MONTO"); m.value="996.27"; apex.jQuery(m).trigger("change");')
    time.sleep(1)
    resumen = nav.js('(document.getElementById("spx-resumen")||{}).innerText || ""')
    ok("A4 el resumen toma el monto nuevo (996,27)", "996,27" in str(resumen), resumen)
    nav.js('''(function(){var f=[...document.querySelectorAll(".spx-pago-fila")].find(function(r){
        return r.getAttribute("data-compra")==="%d";}); if(!f){return;}
        f.querySelector(".spx-sel").checked=true; f.querySelector(".spx-monto").value="996.27"; spxResumen();})()''' % COMPRA)
    nav.js('window.__alerta=""; var _a=apex.message.alert; apex.message.alert=function(m,c){window.__alerta=m; return _a.apply(apex.message, arguments);};')
    nav.js('spxGuardar()')
    time.sleep(2)
    aviso = str(nav.js('window.__alerta || ""') or "")
    time.sleep(2)
    cur.execute("select count(*) from pagos where id_empresa = :e", e=EMP)
    ok("A3 no envia un aplicado mayor que el pago y explica la otra moneda",
       "supera" not in aviso.lower() and "otra moneda" in aviso and cur.fetchone()[0] == PAGOS_ANTES, aviso[:200])
    nav.js('(function(){var b=[...document.querySelectorAll(".ui-dialog button")].find(function(x){return x.offsetParent;});if(b){b.click();}})()')

    # A2
    vistos = []
    for pag, item in [(47, "P47_ID_TOMA"), (48, "P48_ID_CUENTA"), (51, "P51_DESDE")]:
        abre(pag, 'document.readyState === "complete" && typeof spxNum === "function"')
        r = nav.js(LECTURAS)
        vistos.append("%d:%s" % (pag, r))
    ok("A2 la misma lectura en toma fisica, conciliacion y asientos",
       all(v.split(":", 1)[1] == ESPERADO for v in vistos), vistos)

    # A5 el mensaje del servidor: se aplica mas que el saldo y la llamada se revierte (no queda pago)
    cur.execute("select fn_saldo_compra(:c) from dual", c=COMPRA)
    monto = round(float(cur.fetchone()[0]) + 1000, 2)
    apl = '[{"id_compra":%d,"monto":%.2f}]' % (COMPRA, monto)
    msg = "sin error"
    try:
        cur.execute("""declare v_id number; begin
                         pkg_pagos.prc_registrar_pago(p_id_proveedor => :p, p_fecha => trunc(sysdate), p_moneda => 'USD',
                                                      p_tasa => fn_tasa_ves(trunc(sysdate), 'USD'), p_monto => :m, p_aplicaciones => :a,
                                                      p_usuario => :u, p_id_pago => v_id);
                       end;""", p=PROV, m=monto, a=apl, u=U)
    except Exception as x:
        msg = str(x)
    con.rollback()
    ok("A5 el mensaje usa el numero de la compra (%s) y su moneda" % FOLIO,
       ("N. %s " % FOLIO) in msg and "USD" in msg, msg[:220])
finally:
    nav.cerrar()
    cur.execute(BORRA, u=U)
con.close()

print("\nRESULTADO: FALLAS=%d" % len(fallas))
for f in fallas:
    print("  - " + f)
sys.exit(1 if fallas else 0)
