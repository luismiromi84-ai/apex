#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Pago (37) y Compra (28): lo que corrigio la auditoria del 2026-11-25, en navegador real.

  T1 la 37 abre con la moneda local de la empresa activa y su tasa (VES -> 1), no USD con tasa 1
  T2 al pasar la moneda a USD la tasa trae la del dia (fn_tasa_ves), sin teclearla
  T3 al volver a VES la tasa vuelve a 1
  T4 en la 28 ninguna etiqueta flotante queda encima del «-- Seleccione --» de una lista
  T5 las paginas 37, 42, 43, 44 y 45 pintan la banda azul del estandar

    python deploy/diagnostico/20261125_pago_tasa_navegador.py
"""
import importlib.util
import json
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


con = aud.oracledb.connect(**{k: v for k, v in zip(("user", "password"),
                                                    (aud.credenciales()["DB_USER"],
                                                     aud.credenciales()["DB_PASSWORD"]))},
                           dsn=aud.CS)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")
cur.execute(aud.BORRA if hasattr(aud, "BORRA") else
            "begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario "
            "where upper(username)=upper(:u)); commit; delete from usuario where "
            "upper(username)=upper(:u); commit; end;", u=aud.USUARIO)
cur.execute("""insert into usuario (username,email,password_hash,estado,id_empresa,rol_id,
                                     debe_cambiar_clave,reintentos_fallidos)
               values (:u,:e,sypex_hash_password(:p),'ACTIVO',1,
                       (select id_rol from syn_roles where codigo_rol='ADMIN'),'N',0)""",
            u=aud.USUARIO, e=aud.USUARIO + "@synpex.local", p=aud.CLAVE)
con.commit()
cur.execute("select fn_tasa_ves(trunc(sysdate),'USD') from dual")
tasa_usd = float(cur.fetchone()[0])

nav = aud.Nav(puerto=9302)
try:
    ses = aud.entrar(nav)
    if not ses:
        sys.exit("login fallido")

    def abrir(pag):
        nav.js('window.location.href="%s/f?p=100:%d:%s"' % (aud.BASE, pag, ses))
        nav.esperar('document.readyState === "complete" && !!window.apex', 40)
        time.sleep(2.5)

    abrir(37)
    mon = nav.js('apex.item("P37_COD_MONEDA").getValue()')
    tasa = nav.js('apex.item("P37_TIPO_CAMBIO").getValue()')
    ok("T1 la 37 abre con VES y tasa 1", mon == "VES" and str(tasa).strip() in ("1", "1.00", "1,00"),
       "%s / %s" % (mon, tasa))

    nav.js('$s("P37_COD_MONEDA","USD")')
    nav.esperar('Number(String(apex.item("P37_TIPO_CAMBIO").getValue()).replace(",", ".")) > 1', 20)
    tasa = nav.js('apex.item("P37_TIPO_CAMBIO").getValue()')
    try:
        v = float(str(tasa).replace(",", "."))
    except ValueError:
        v = -1
    ok("T2 con USD trae la tasa del dia (%s)" % tasa_usd, abs(v - tasa_usd) < 0.0001, tasa)

    nav.js('$s("P37_COD_MONEDA","VES")')
    nav.esperar('String(apex.item("P37_TIPO_CAMBIO").getValue()).trim() === "1"', 20)
    ok("T3 al volver a VES la tasa es 1", str(nav.js('apex.item("P37_TIPO_CAMBIO").getValue()')).strip() == "1",
       nav.js('apex.item("P37_TIPO_CAMBIO").getValue()'))

    abrir(28)
    d = nav.js(aud.MEDIR)
    ok("T4 en la 28 ninguna etiqueta tapa el valor", isinstance(d, dict) and not d.get("etiqueta_tapa"),
       (d or {}).get("etiqueta_tapa") if isinstance(d, dict) else d)

    for pag in (37, 42, 43, 44, 45):
        abrir(pag)
        d = nav.js(aud.MEDIR)
        cab = [x for x in (d.get("cabeceras") or []) if x["alto"] > 8] if isinstance(d, dict) else []
        ok("T5 la %d pinta la banda azul en sus %d cabeceras" % (pag, len(cab)),
           cab and all(x["azul"] and x["alto"] <= 52 for x in cab), cab)
finally:
    nav.cerrar()
    cur.execute("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario "
                "where upper(username)=upper(:u)); commit; delete from usuario where "
                "upper(username)=upper(:u); commit; end;", u=aud.USUARIO)
    con.close()

print("\nRESULTADO: FALLAS=%d" % len(fallas))
for f in fallas:
    print("  - " + f)
sys.exit(1 if fallas else 0)
