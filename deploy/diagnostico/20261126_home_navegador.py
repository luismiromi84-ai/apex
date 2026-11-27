#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Pantalla principal nueva (pagina 1, 2026-11-26), en navegador real y sin modificar datos.

  H1 «Para hoy» muestra las cifras de la base: facturas sin procesar y facturas por cobrar
  H2 «Nueva factura» abre el formulario de la factura en su dialogo
  H3 cancelar el dialogo no recarga; cerrarlo tras guardar recarga la pantalla (cifras al dia)
  H4 FACTURACION ve Ventas y «Nueva factura», pero no Compras, Contabilidad ni «Registrar compra»
  H5 ALMACEN ve Toma fisica y no ve Pagos (antes la tarjeta salia y la pagina lo rechazaba)
  H6 CONSULTA no tiene acciones rapidas (no puede crear documentos)

Usa la empresa de Venezuela con mas facturas y usuarios temporales por rol.

    python deploy/diagnostico/20261126_home_navegador.py
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

fallas = []
IMG = os.path.join(aud.REPO, "docs", "imagenes")


def ok(nombre, cond, det=""):
    print(("  OK   " if cond else "  FALLA") + " " + nombre + ("" if cond else "  -> " + str(det)[:240]))
    if not cond:
        fallas.append(nombre)


c = aud.credenciales()
con = aud.oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=aud.CS)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")
cur.execute("""select e.id_empresa from empresas e where e.cod_pais = 'VE' and e.id_empresa < 900000
                order by (select count(*) from facturas f where f.id_empresa = e.id_empresa) desc fetch first 1 rows only""")
EMP = cur.fetchone()[0]
cur.execute("select count(*) from facturas where id_empresa = :e and tipo_documento = 'FAC' and estado = 'PENDIENTE'", e=EMP)
PEND = cur.fetchone()[0]
cur.execute("""select count(*) from facturas where id_empresa = :e and tipo_documento = 'FAC'
                and estado in ('TIMBRADA', 'PARCIAL') and fn_saldo_factura(id_factura) > 0.01""", e=EMP)
COBRAR = cur.fetchone()[0]

BORRA = ("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario "
         "where upper(username)=upper(:u)); commit; delete from usuario where upper(username)=upper(:u); commit; end;")
USUARIOS = {"ADMIN": "diag.homeadm", "FACTURACION": "diag.homefac", "ALMACEN": "diag.homealm", "CONSULTA": "diag.homecon"}
for rol, u in USUARIOS.items():
    cur.execute(BORRA, u=u)
    cur.execute("""insert into usuario (username,email,password_hash,estado,id_empresa,rol_id,debe_cambiar_clave,reintentos_fallidos)
                   values (:u,:m,sypex_hash_password(:p),'ACTIVO',:e,(select id_rol from syn_roles where codigo_rol=:r),'N',0)""",
                u=u, m=u + "@synpex.local", p=aud.CLAVE, e=EMP, r=rol)
    con.commit()


def textos(nav):
    return {
        "body": str(nav.js("document.body.innerText") or ""),
        "acc": str(nav.js('[...document.querySelectorAll(".spx-acc")].map(function(a){return a.innerText.trim();}).join("|")') or ""),
        "mods": str(nav.js('[...document.querySelectorAll(".spx-mod b")].map(function(a){return a.innerText.trim();}).join("|")') or ""),
    }


def entra(rol, puerto):
    nav = aud.Nav(puerto=puerto)
    aud.USUARIO = USUARIOS[rol]
    ses = aud.entrar(nav)
    nav.js('window.location.href="%s/f?p=100:1:%s"' % (aud.BASE, ses))
    nav.esperar('document.readyState === "complete" && document.querySelectorAll(".spx-mod").length > 0', 40)
    time.sleep(2)
    return nav


nav = None
try:
    # H1-H3 con ADMIN
    nav = entra("ADMIN", 9321)
    nav.cmd("Emulation.setDeviceMetricsOverride", width=1440, height=1000, deviceScaleFactor=1, mobile=False)
    tarjetas = nav.js('''(function(){var o={};document.querySelectorAll(".spx-hoy").forEach(function(a){
        o[a.querySelector("small").innerText.trim()] = a.querySelector("b").innerText.trim() + "|" + a.querySelector(".spx-hoy-txt span").innerText.trim();});
        return JSON.stringify(o);})()''')
    import json
    tj = json.loads(tarjetas or "{}")
    sin = tj.get("FACTURAS SIN PROCESAR", tj.get("Facturas sin procesar", ""))
    cob = tj.get("POR COBRAR", tj.get("Por cobrar", ""))
    ok("H1 Para hoy: %d sin procesar y %d por cobrar como en la base" % (PEND, COBRAR),
       sin.split("|")[0] == str(PEND) and cob.split("|")[1].startswith("%d factura" % COBRAR), tj)
    r = nav.cmd("Page.captureScreenshot", format="png", captureBeyondViewport=True)
    if r.get("data"):
        with open(os.path.join(IMG, "home.png"), "wb") as fh:
            fh.write(base64.b64decode(r["data"]))
    nav.js('window.__marca = 1;')
    nav.js('[...document.querySelectorAll(".spx-acc")].find(function(a){return /Nueva factura/.test(a.innerText);}).click()')
    nav.esperar('!!document.querySelector(".ui-dialog iframe")', 30)
    time.sleep(4)
    src = str(nav.js('(document.querySelector(".ui-dialog iframe")||{}).src || ""'))
    ok("H2 Nueva factura abre su dialogo", "9" in src and ("p9" in src.lower() or ":9:" in src or "facturacion" in src.lower()), src[:160])
    # cancelar (la X) no cambia nada y no recarga; cerrar tras GUARDAR emite apexafterclosedialog y si
    # recarga. Se simula ese evento para no guardar una factura de verdad.
    nav.js('(function(){var b=document.querySelector(".ui-dialog .ui-dialog-titlebar-close");if(b){b.click();}})()')
    time.sleep(3)
    sigue = nav.js('window.__marca === 1')
    nav.js('apex.event.trigger(document.body, "apexafterclosedialog", {});')
    time.sleep(5)
    nav.esperar('document.readyState === "complete" && !!document.querySelector(".spx-mod")', 30)
    ok("H3 cancelar no recarga; cerrar tras guardar recarga la pantalla",
       sigue is True and nav.js('typeof window.__marca === "undefined"'), sigue)
    nav.cerrar()

    # H4 FACTURACION
    nav = entra("FACTURACION", 9322)
    tx = textos(nav)
    ok("H4 FACTURACION: ventas si; compras y contabilidad no",
       "Nueva factura" in tx["acc"] and "Registrar compra" not in tx["acc"] and "Facturación" in tx["mods"]
       and "Compras" not in tx["mods"].split("|") and "Plan de cuentas" not in tx["mods"], tx)
    nav.cerrar()

    # H5 ALMACEN
    nav = entra("ALMACEN", 9323)
    tx = textos(nav)
    ok("H5 ALMACEN ve Toma fisica y no Pagos", "Toma física" in tx["mods"] and "Pagos" not in tx["mods"].split("|"), tx["mods"])
    nav.cerrar()

    # H6 CONSULTA
    nav = entra("CONSULTA", 9324)
    tx = textos(nav)
    ok("H6 CONSULTA no tiene acciones rapidas", tx["acc"] == "" and "Acciones r" not in tx["body"], tx["acc"])
finally:
    if nav:
        nav.cerrar()
    for u in USUARIOS.values():
        cur.execute(BORRA, u=u)
    con.close()

print("\nRESULTADO: FALLAS=%d" % len(fallas))
for f in fallas:
    print("  - " + f)
sys.exit(1 if fallas else 0)
