#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Capturas del manual de usuario (docs/imagenes/), con la app tal como esta hoy.

Saca las pantallas de lista (las que ya tenia el manual) y las de TRABAJO que hacen falta para
seguir las pruebas paso a paso: login, dialogos de presupuesto, linea, factura, nota de credito,
cobro, impreso, datos fiscales (rango de control) y secuencias. Entra con un usuario temporal
ADMIN de la empresa 1 (Venezuela) y lo borra al terminar. No guarda nada: solo abre pantallas.

    python deploy/diagnostico/20261125_manual_capturas.py
"""
import base64
import importlib.util
import os
import sys
import time

AQUI = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("aud", os.path.join(AQUI, "20261125_auditoria_estandar.py"))
aud = importlib.util.module_from_spec(spec)
spec.loader.exec_module(aud)

IMG = os.path.join(aud.REPO, "docs", "imagenes")
os.makedirs(IMG, exist_ok=True)
hechas, faltan = [], []


def vista(nav, nombre):
    """Captura solo lo que se ve (para los dialogos, que estan encima de la lista)."""
    r = nav.cmd("Page.captureScreenshot", format="png")
    if r.get("data"):
        with open(os.path.join(IMG, nombre + ".png"), "wb") as fh:
            fh.write(base64.b64decode(r["data"]))
        hechas.append(nombre)
    else:
        faltan.append(nombre)


def completa(nav, nombre):
    nav.captura(os.path.join(IMG, nombre + ".png"))
    hechas.append(nombre)


def abre(nav, ses, pag, espera='document.readyState === "complete" && !!window.apex'):
    nav.js('window.location.href="%s/f?p=100:%s:%s"' % (aud.BASE, pag, ses))
    nav.esperar(espera, 50)
    time.sleep(3)


def dialogo(nav, seg=40):
    ok = nav.esperar('(function(){var f=document.querySelector("iframe");'
                     'return !!(f&&f.contentWindow&&f.contentWindow.apex&&f.contentWindow.apex.item'
                     '&&f.contentDocument.readyState==="complete");})()', seg)
    time.sleep(4)
    return ok


def cierra_dialogo(nav):
    nav.js('(function(){var b=document.querySelector(".ui-dialog-titlebar-close");if(b){b.click();}})()')
    time.sleep(2)


def clic(nav, js_buscar):
    return nav.js('(function(){var e=' + js_buscar + ';if(!e)return "NO";e.click();return "OK";})()')


c = aud.credenciales()
con = aud.oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=aud.CS)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")
USR = "diag.manual"
aud.USUARIO = USR
BORRA = ("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario "
         "where upper(username)=upper(:u)); commit; delete from usuario where "
         "upper(username)=upper(:u); commit; end;")
cur.execute(BORRA, u=USR)
cur.execute("""insert into usuario (username,email,password_hash,estado,id_empresa,rol_id,
                                     debe_cambiar_clave,reintentos_fallidos)
               values (:u,:e,sypex_hash_password(:p),'ACTIVO',1,
                       (select id_rol from syn_roles where codigo_rol='ADMIN'),'N',0)""",
            u=USR, e=USR + "@synpex.local", p=aud.CLAVE)
con.commit()

# documentos de la empresa 1 para abrir sus dialogos
cur.execute("""select max(case when tipo_documento='FAC' and estado='PENDIENTE' then id_factura end),
                      max(case when tipo_documento='FAC' and estado in ('TIMBRADA','PARCIAL') then id_factura end),
                      max(case when tipo_documento='NC' and estado='TIMBRADA' then id_factura end)
                 from facturas where id_empresa = 1""")
F_PEND, F_EMIT, F_NC = cur.fetchone()
cur.execute("select max(id_factura) from facturas f where id_empresa = 1 and fn_factura_cobrable(f.id_factura)")
F_COBRABLE = cur.fetchone()[0]
cur.execute("select max(id_presupuesto) from presupuestos where id_empresa = 1 and estado = 'PENDIENTE'")
P_PEND = cur.fetchone()[0]
print("documentos:", dict(pendiente=F_PEND, emitida=F_EMIT, nc=F_NC, cobrable=F_COBRABLE, presupuesto=P_PEND))

nav = aud.Nav(puerto=9305)
try:
    nav.medida(1440, 900)
    # login (sin sesion)
    nav.js('window.location.href="%s/f?p=100:9999"' % aud.BASE)
    nav.esperar('!!document.getElementById("P9999_USERNAME")', 40)
    time.sleep(3)
    vista(nav, "login")
    ses = aud.entrar(nav)
    if not ses:
        sys.exit("login fallido")
    nav.medida(1440, 900)

    # pantallas de lista (las del manual), ya con el formato y la banda de hoy
    for pag, nombre in [(1, "home"), (19, "administracion"), (3, "usuarios"), (20, "clientes"),
                        (22, "proveedores"), (40, "articulos"), (42, "inventario"), (43, "kardex"),
                        (44, "ajuste_inventario"), (45, "costos_inventario"), (5, "presupuestos"),
                        (8, "facturacion"), (24, "recibos"), (27, "compras"), (28, "compra"),
                        (36, "pagos"), (37, "pago"), (17, "reportes"), (18, "libro"), (13, "panel")]:
        abre(nav, ses, pag)
        completa(nav, nombre)

    # selector de empresa desplegado
    abre(nav, ses, 1)
    nav.js('(function(){var s=document.getElementById("P0_EMPRESA_ACTIVA");if(s){s.focus();'
           's.style.outline="3px solid #f59e0b";}})()')
    vista(nav, "empresa_activa")

    # Datos fiscales (rango de control) y Secuencias, pestanas de la 19
    for tab, nombre in [("Datos fiscales", "datos_fiscales"), ("Secuencias", "secuencias")]:
        abre(nav, ses, 19)
        clic(nav, '[...document.querySelectorAll(".a-RDS-link,.a-Tabs-link,[role=tab] a,a")]'
                  '.find(function(a){return a.textContent.trim()==="%s";})' % tab)
        time.sleep(3)
        completa(nav, nombre)

    # presupuesto nuevo (dialogo 7)
    abre(nav, ses, 5)
    clic(nav, '[...document.querySelectorAll("button")].find(function(b){return /Nuevo|Crear/i.test(b.innerText);})')
    if dialogo(nav):
        vista(nav, "presupuesto_nuevo")
    else:
        faltan.append("presupuesto_nuevo")
    cierra_dialogo(nav)

    # linea de presupuesto (dialogo 6) sobre un presupuesto PENDIENTE
    if P_PEND:
        abre(nav, ses, 5, 'document.querySelectorAll(".js-select-invoice").length>0')
        nav.js('(function(){var c=document.querySelector(\'.js-select-invoice[data-id="%d"]\');'
               'if(c){c.checked=true;c.dispatchEvent(new Event("change",{bubbles:true}));}})()' % P_PEND)
        time.sleep(5)
        clic(nav, '[...document.querySelectorAll("button")].find(function(b){return /Nueva L/i.test(b.innerText)&&!b.disabled;})')
        if dialogo(nav):
            vista(nav, "linea_presupuesto")
        else:
            faltan.append("linea_presupuesto")
        cierra_dialogo(nav)

    # factura nueva (dialogo 9)
    abre(nav, ses, 8)
    clic(nav, '[...document.querySelectorAll("button")].find(function(b){return /Nueva Factura/i.test(b.innerText);})')
    if dialogo(nav):
        vista(nav, "factura_nueva")
    else:
        faltan.append("factura_nueva")
    cierra_dialogo(nav)

    def abre_doc(id_doc, nombre, texto_enlace=None):
        abre(nav, ses, 8, 'document.querySelectorAll(".js-select-invoice").length>0')
        if texto_enlace:
            r = clic(nav, '(function(){var c=document.querySelector(\'.js-select-invoice[data-id="%d"]\');'
                          'if(!c)return null;return [...c.closest("tr").querySelectorAll("a")]'
                          '.find(function(a){return /%s/.test(a.innerText);});})()' % (id_doc, texto_enlace))
        else:
            r = clic(nav, '(function(){var c=document.querySelector(\'.js-select-invoice[data-id="%d"]\');'
                          'return c?c.closest("tr").querySelector(\'a[href*="a-dialog-open"]\'):null;})()' % id_doc)
        if r == "OK" and dialogo(nav):
            vista(nav, nombre)
        else:
            faltan.append(nombre)
        cierra_dialogo(nav)

    if F_EMIT:
        abre_doc(F_EMIT, "factura_emitida")
    if F_NC:
        abre_doc(F_NC, "nota_credito")
    if F_COBRABLE:
        abre_doc(F_COBRABLE, "cobro", "Cobrar")

    # linea de factura (dialogo 10) sobre un borrador
    if F_PEND:
        abre(nav, ses, 8, 'document.querySelectorAll(".js-select-invoice").length>0')
        nav.js('(function(){var c=document.querySelector(\'.js-select-invoice[data-id="%d"]\');'
               'if(c){c.checked=true;c.dispatchEvent(new Event("change",{bubbles:true}));}})()' % F_PEND)
        time.sleep(6)
        completa(nav, "facturacion_seleccion")
        clic(nav, '[...document.querySelectorAll("button")].find(function(b){return /Nueva L/i.test(b.innerText)&&!b.disabled;})')
        if dialogo(nav):
            vista(nav, "linea_factura")
        else:
            faltan.append("linea_factura")
        cierra_dialogo(nav)

    # impreso de factura (11)
    if F_EMIT:
        abre(nav, ses, 8, 'document.querySelectorAll(".js-select-invoice").length>0')
        href = nav.js('(function(){var c=document.querySelector(\'.js-select-invoice[data-id="%d"]\');'
                      'var a=c?[...c.closest("tr").querySelectorAll("a")].find(function(x){return /Imprimir/.test(x.innerText);}):null;'
                      'return a?a.href:null;})()' % F_EMIT)
        if href:
            nav.js('window.location.href=%r' % href)
            nav.esperar('document.readyState === "complete" && !!window.apex', 40)
            time.sleep(4)
            completa(nav, "impreso_factura")
        else:
            faltan.append("impreso_factura")
finally:
    nav.cerrar()
    cur.execute(BORRA, u=USR)
    con.close()

print("\ncapturas hechas (%d): %s" % (len(hechas), ", ".join(hechas)))
print("no se pudieron sacar (%d): %s" % (len(faltan), ", ".join(faltan)))
