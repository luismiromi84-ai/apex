#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Linea de compra (29): el descuento se calcula solo (dueno, 2026-11-26). Navegador real, sin guardar
(abre la linea desde una compra en borrador de la empresa 1 y no pulsa Guardar).

  D1 la cantidad no admite letras: «a20» queda «20»
  D2 cantidad 20 x precio 40 con 5 % -> monto de descuento 40,00 mientras se escribe
  D3 al cambiar la cantidad a 10 el monto se rehace solo -> 20,00
  D4 al escribir el monto (30) el % se rehace -> 7,5
  D5 12.5 en el precio se lee como 12,5 (punto decimal) -> 10 x 12,5 con 7,5 % = 9,38
  D6 al salir del campo, 12.5 queda escrito 12,5 (lo que guardan APEX y la base)

    python deploy/diagnostico/20261126_linea_compra_descuento_navegador.py
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
    print(("  OK   " if cond else "  FALLA") + " " + nombre + ("" if cond else "  -> " + str(det)[:200]))
    if not cond:
        fallas.append(nombre)


c = aud.credenciales()
con = aud.oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=aud.CS)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")
cur.execute("""select id_compra from compras where id_empresa = 1 and estado = 'BORRADOR' and tipo_documento = 'FAC'
                order by id_compra desc fetch first 1 rows only""")
fila = cur.fetchone()
if not fila:
    print("RESULTADO: FALLAS=0 OMITIDOS=1 (la empresa 1 no tiene una compra en borrador)")
    sys.exit(0)
COMPRA = fila[0]
U = "diag.lineacomp"
BORRA = ("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario "
         "where upper(username)=upper(:u)); commit; delete from usuario where upper(username)=upper(:u); commit; end;")
cur.execute(BORRA, u=U)
cur.execute("""insert into usuario (username,email,password_hash,estado,id_empresa,rol_id,debe_cambiar_clave,reintentos_fallidos)
               values (:u,:m,sypex_hash_password(:p),'ACTIVO',1,(select id_rol from syn_roles where codigo_rol='ADMIN'),'N',0)""",
            u=U, m=U + "@synpex.local", p=aud.CLAVE)
con.commit()

nav = aud.Nav(puerto=9319)


# la linea puede abrirse como dialogo (iframe) o como pagina normal
W = '((document.querySelector(".ui-dialog iframe") || {}).contentWindow || window)'


def teclea(item, valor):
    """Escribe como una persona, dentro del dialogo de la linea: valor en el campo y evento input."""
    nav.js('(function(){var w=%s; var e=w.document.getElementById("%s"); e.focus(); e.value="%s";'
           'e.dispatchEvent(new w.Event("input",{bubbles:true}));})()' % (W, item, valor))
    time.sleep(0.5)


def valor(item):
    return str(nav.js('%s.apex.item("%s").getValue()' % (W, item)) or "")


def num(item):
    return nav.js('%s.spxNumero(%s.apex.item("%s").getValue())' % (W, W, item))


try:
    aud.USUARIO = U
    ses = aud.entrar(nav)
    if not ses:
        sys.exit("login fallido")
    # como una persona: Reportes -> Ver de una compra en borrador -> Nueva linea (dialogo)
    nav.js('window.location.href="%s/f?p=100:17:%s"' % (aud.BASE, ses))
    nav.esperar('document.querySelectorAll("table.a-IRR-table").length > 0', 40)
    time.sleep(2)
    url = nav.js("""(function(){var a=[...document.querySelectorAll("table.a-IRR-table td a")].find(function(a){
        return /p28_id_compra=%d(&|$)/.test(decodeURIComponent(a.getAttribute("href")||""));});return a?a.href:"";})()""" % COMPRA)
    if not url:
        sys.exit("no se encontro la compra %d en Reportes" % COMPRA)
    nav.js('window.location.href="%s"' % url)
    nav.esperar('document.readyState === "complete" && !!document.getElementById("B43000000000001034")', 40)
    time.sleep(2)
    nav.js('document.getElementById("B43000000000001034").click()')
    nav.esperar('(function(){try{var w=%s;return !!(w && w.spxDescuento && w.document.getElementById("P29_CANTIDAD"));}'
                'catch(e){return false;}})()' % W, 40)
    time.sleep(2)

    teclea("P29_CANTIDAD", "a20")
    ok("D1 la cantidad no admite letras", valor("P29_CANTIDAD") == "20", valor("P29_CANTIDAD"))
    teclea("P29_PRECIO_UNITARIO", "40")
    teclea("P29_PORCENTAJE_DESCUENTO", "5")
    ok("D2 20 x 40 con 5 % da 40,00 de descuento", num("P29_MONTO_DESCUENTO") == 40, valor("P29_MONTO_DESCUENTO"))
    teclea("P29_CANTIDAD", "10")
    ok("D3 al cambiar la cantidad a 10 el monto pasa a 20,00", num("P29_MONTO_DESCUENTO") == 20, valor("P29_MONTO_DESCUENTO"))
    teclea("P29_MONTO_DESCUENTO", "30")
    ok("D4 al escribir 30 de monto el % pasa a 7,5", num("P29_PORCENTAJE_DESCUENTO") == 7.5, valor("P29_PORCENTAJE_DESCUENTO"))
    teclea("P29_PRECIO_UNITARIO", "12.5")
    ok("D5 12.5 es 12,5: 10 x 12,5 con 7,5 % = 9,38", num("P29_MONTO_DESCUENTO") == 9.38, valor("P29_MONTO_DESCUENTO"))
    nav.js('(function(){var w=%s; var e=w.document.getElementById("P29_PRECIO_UNITARIO");'
           'e.dispatchEvent(new w.Event("blur"));})()' % W)
    time.sleep(0.5)
    crudo = nav.js('%s.document.getElementById("P29_PRECIO_UNITARIO").value' % W)
    ok("D6 al salir del campo 12.5 queda escrito 12,5", crudo == "12,5", crudo)
finally:
    nav.cerrar()
    cur.execute(BORRA, u=U)
    con.close()

print("\nRESULTADO: FALLAS=%d" % len(fallas))
for f in fallas:
    print("  - " + f)
sys.exit(1 if fallas else 0)
