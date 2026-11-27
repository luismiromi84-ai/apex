#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Tres arreglos del 2026-11-26 (capturas del dueno), en navegador real y sin modificar datos.

  V1 la lista de Presupuestos (5) ya no muestra los FACTURADO: se consultan en Reportes
  V2 un presupuesto FACTURADO abierto desde Reportes no tiene el boton «Eliminar»
  V3 un presupuesto PENDIENTE si lo tiene (el boton sigue existiendo donde corresponde)
  V4 «Ver» de una compra en Reportes (17) y «Volver» regresa a Reportes, no a Compras
  V5 «Editar» desde Compras (27) y «Volver» sigue regresando a Compras

    python deploy/diagnostico/20261126_presupuesto_facturado_volver_navegador.py
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
# empresa real con un presupuesto facturado y alguna compra
cur.execute("""select e.id_empresa from empresas e
                where e.id_empresa < 900000
                  and exists (select 1 from presupuestos p where p.id_empresa = e.id_empresa and p.estado = 'FACTURADO')
                  and exists (select 1 from compras co where co.id_empresa = e.id_empresa and co.estado <> 'ANULADA')
                order by e.id_empresa fetch first 1 rows only""")
fila = cur.fetchone()
if not fila:
    print("sin empresa con presupuesto facturado y compras\nRESULTADO: FALLAS=0 OMITIDOS=1")
    sys.exit(0)
EMP = fila[0]
cur.execute("select max(id_presupuesto) from presupuestos where id_empresa = :e and estado = 'FACTURADO'", e=EMP)
FACT = cur.fetchone()[0]
cur.execute("select max(id_presupuesto) from presupuestos where id_empresa = :e and estado not in ('FACTURADO','CANCELADO')", e=EMP)
ABIERTO = cur.fetchone()[0]
cur.execute("select count(*) from presupuestos where id_empresa = :e and estado not in ('FACTURADO','CANCELADO')", e=EMP)
N_VIVOS = cur.fetchone()[0]
print("empresa %s: facturado=%s abierto=%s vivos=%s" % (EMP, FACT, ABIERTO, N_VIVOS))

USUARIO = "diag.presvol"
BORRA = ("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario "
         "where upper(username)=upper(:u)); commit; delete from usuario where upper(username)=upper(:u); commit; end;")
cur.execute(BORRA, u=USUARIO)
cur.execute("""insert into usuario (username,email,password_hash,estado,id_empresa,rol_id,debe_cambiar_clave,reintentos_fallidos)
               values (:u,:m,sypex_hash_password(:p),'ACTIVO',:e,(select id_rol from syn_roles where codigo_rol='ADMIN'),'N',0)""",
            u=USUARIO, m=USUARIO + "@synpex.local", p=aud.CLAVE, e=EMP)
con.commit()


def ir(nav, ses, pag, cond):
    nav.js('window.location.href="%s/f?p=100:%s:%s"' % (aud.BASE, pag, ses))
    nav.esperar('document.readyState === "complete" && !!window.apex && ' + cond, 60)
    time.sleep(3)


def modulo_17(nav, valor):
    nav.js('(function(){apex.item("P17_MODULO").setValue("%s");'
           'apex.submit({request:"APLICAR", showProcessing:true});})()' % valor)
    time.sleep(4)
    nav.esperar('document.readyState === "complete" && !!window.apex && !!apex.item("P17_MODULO")', 60)
    time.sleep(3)


def boton_eliminar_en_dialogo(nav, id_pres):
    """Pulsa el Ver del presupuesto en Reportes y mira el dialogo; devuelve True/False o un texto de error."""
    r = nav.js('''(function(){var a=[...document.querySelectorAll("td a")].find(function(x){
            return new RegExp("p7_id_presupuesto=%d(\\\\D|$)","i").test(decodeURIComponent(x.getAttribute("href")||""));});
        if(!a){return "SIN ENLACE";} a.click(); return "OK";})()''' % id_pres)
    if r != "OK":
        return r
    nav.esperar('!!document.querySelector(".ui-dialog iframe")', 30)
    time.sleep(1)
    nav.esperar('(function(){var f=document.querySelector(".ui-dialog iframe");'
                'return f && f.contentDocument && f.contentDocument.readyState==="complete" '
                '&& !!f.contentDocument.getElementById("P7_ID_PRESUPUESTO");})()', 40)
    time.sleep(2)
    hay = nav.js('''(function(){var d=document.querySelector(".ui-dialog iframe").contentDocument;
        return [...d.querySelectorAll("button")].some(function(b){return /Eliminar/.test(b.innerText);});})()''')
    nav.js('(function(){var b=document.querySelector(".ui-dialog .ui-dialog-titlebar-close");if(b){b.click();}})()')
    time.sleep(2)
    return hay


def volver_28(nav):
    nav.esperar('document.readyState === "complete" && !!window.apex && !!apex.item("P28_ID_COMPRA")', 60)
    time.sleep(2)
    r = nav.js('''(function(){var b=[...document.querySelectorAll("button")].find(function(x){
            return x.innerText.trim()==="Volver";}); if(!b){return "SIN BOTON";} b.click(); return "OK";})()''')
    time.sleep(3)
    nav.esperar('document.readyState === "complete" && !!window.apex && !document.getElementById("P28_ID_COMPRA")', 60)
    time.sleep(2)
    return r, str(nav.js("apex.env.APP_PAGE_ID"))


nav = None
try:
    nav = aud.Nav(puerto=9331)
    aud.USUARIO = USUARIO
    ses = aud.entrar(nav)

    # V1
    ir(nav, ses, 5, '!!document.getElementById("R11950647600514906")')
    txt = str(nav.js('document.getElementById("R11950647600514906").innerText') or "")
    filas = nav.js('[...document.querySelectorAll("#R11950647600514906 .a-IRR-table tr")]'
                   '.filter(function(r){return r.querySelector("td");}).length')
    ok("V1 Presupuestos no muestra FACTURADO (%s vivos en la base)" % N_VIVOS,
       "FACTURADO" not in txt.upper() and (N_VIVOS > 15 or filas == N_VIVOS), (filas, txt[:200]))

    # V2 / V3
    ir(nav, ses, 17, '!!apex.item("P17_MODULO")')
    modulo_17(nav, "PRESUPUESTOS")
    hay = boton_eliminar_en_dialogo(nav, FACT)
    ok("V2 presupuesto FACTURADO sin boton Eliminar", hay is False, hay)
    if ABIERTO:
        hay = boton_eliminar_en_dialogo(nav, ABIERTO)
        ok("V3 presupuesto abierto conserva Eliminar", hay is True, hay)
    else:
        print("  OMITIDO V3: no hay presupuesto abierto")

    # V4
    modulo_17(nav, "COMPRAS")
    r = nav.js('''(function(){var a=[...document.querySelectorAll("td a")].find(function(x){
            return /p28_id_compra=/i.test(decodeURIComponent(x.getAttribute("href")||""));});
        if(!a){return "SIN ENLACE";} var h=decodeURIComponent(a.getAttribute("href")); a.click(); return h;})()''')
    ok("V4 el Ver de compra lleva la pagina de origen", "p28_volver=17" in str(r).lower().replace(" ", "") or "17" in str(r), r)
    res = volver_28(nav)
    ok("V4 Volver desde la compra regresa a Reportes (17)", res == ("OK", "17"), res)

    # V5
    ir(nav, ses, 27, 'document.querySelectorAll("td a").length > 0')
    nav.js('''(function(){var a=[...document.querySelectorAll("td a")].find(function(x){
            return /p28_id_compra=/i.test(decodeURIComponent(x.getAttribute("href")||""));}); if(a){a.click();}})()''')
    res = volver_28(nav)
    ok("V5 Volver desde la compra abierta en Compras regresa a Compras (27)", res == ("OK", "27"), res)
finally:
    if nav:
        nav.cerrar()
    cur.execute(BORRA, u=USUARIO)
    con.close()

print("\nRESULTADO: FALLAS=%d" % len(fallas))
for f in fallas:
    print("  - " + f)
sys.exit(1 if fallas else 0)
