#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Cobro (25): el comprobante de retencion de la factura llega solo (2026-11-25).

  R1 al abrir el cobro desde «Cobrar» de una factura con comprobante, el campo viene relleno
  R2 el mensaje del package, si falta el comprobante con retencion, dice que hacer

Usa una factura cobrable de la empresa 1 con retencion; si no tiene comprobante le pone uno de
prueba y lo restaura al final.

    python deploy/diagnostico/20261125_cobro_comprobante_navegador.py
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
cur.execute("""select f.id_factura, f.folio_factura, f.id_empresa, f.nro_comprobante_retencion
                 from facturas f join empresas e on e.id_empresa = f.id_empresa
                where e.cod_pais = 'VE' and fn_factura_cobrable(f.id_factura)
                order by f.id_factura desc fetch first 1 rows only""")
fila = cur.fetchone()
if not fila:
    sys.exit("no hay factura cobrable en Venezuela para probar")
ID_F, FOLIO, EMP, COMP_ORIG = fila
COMP = COMP_ORIG or "20261100009999"
if not COMP_ORIG:
    cur.execute("update facturas set nro_comprobante_retencion = :c where id_factura = :f", c=COMP, f=ID_F)
    con.commit()
print("factura %s (%s) empresa %s comprobante %s" % (FOLIO, ID_F, EMP, COMP))

USR = "diag.comp"
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

nav = aud.Nav(puerto=9304)
try:
    ses = aud.entrar(nav)
    if not ses:
        sys.exit("login fallido")
    nav.js('window.location.href="%s/f?p=100:8:%s"' % (aud.BASE, ses))
    nav.esperar('document.readyState==="complete" && document.querySelectorAll(".js-select-invoice").length>0', 50)
    time.sleep(2)
    pulsado = nav.js('(function(){var c=document.querySelector(\'.js-select-invoice[data-id="%d"]\');'
                     'if(!c)return "SIN FILA";var a=[...c.closest("tr").querySelectorAll("a")]'
                     '.find(function(x){return /Cobrar/.test(x.innerText);});'
                     'if(!a)return "SIN COBRAR";a.click();return "OK";})()' % ID_F)
    nav.esperar('(function(){var f=document.querySelector("iframe");'
                'return !!(f&&f.contentWindow&&f.contentWindow.apex&&f.contentWindow.apex.item);})()', 40)
    time.sleep(4)
    valor = nav.js('(function(){var w=document.querySelector("iframe").contentWindow;'
                   'return w.apex.item("P25_NRO_COMPROBANTE").getValue();})()')
    ok("R1 el cobro trae el comprobante de la factura", str(valor) == COMP, (pulsado, valor))
finally:
    nav.cerrar()
    cur.execute(BORRA, u=USR)
    if not COMP_ORIG:
        cur.execute("update facturas set nro_comprobante_retencion = null where id_factura = :f", f=ID_F)
    con.commit()

cur.execute("select text from all_source where owner='WKSP_SYPEXWS' and name='PKG_COBROS' "
            "and type='PACKAGE BODY' and instr(text, 'deja la retencion en 0') > 0")
ok("R2 el mensaje dice que hacer si falta el comprobante", cur.fetchone() is not None)
con.close()

print("\nRESULTADO: FALLAS=%d" % len(fallas))
for f in fallas:
    print("  - " + f)
sys.exit(1 if fallas else 0)
