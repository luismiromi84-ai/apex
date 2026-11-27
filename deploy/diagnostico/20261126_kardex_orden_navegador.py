#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Kardex (43) legible, 2026-11-26 (captura del dueno: «no entiendo el kardex o esta desordenado»).

  K1 las filas van del movimiento mas antiguo al mas reciente
  K2 el saldo de cada fila = saldo anterior + cantidad (se lee hacia abajo)
  K3 con «Desde» el saldo arrastra lo anterior (antes arrancaba en cero)
  K4 la columna Articulo dice de que articulo es cada fila

Sin modificar datos; usa el articulo con mas movimientos de una empresa real.

    python deploy/diagnostico/20261126_kardex_orden_navegador.py
"""
import importlib.util
import os
import re
import sys
import time

AQUI = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("aud", os.path.join(AQUI, "20261125_auditoria_estandar.py"))
aud = importlib.util.module_from_spec(spec)
spec.loader.exec_module(aud)

fallas = []


def ok(nombre, cond, det=""):
    print(("  OK   " if cond else "  FALLA") + " " + nombre + ("" if cond else "  -> " + str(det)[:300]))
    if not cond:
        fallas.append(nombre)


def num(s):
    s = str(s or "").strip()
    return float(s.replace(".", "").replace(",", ".")) if s else None


c = aud.credenciales()
con = aud.oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=aud.CS)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")
cur.execute("""select m.id_empresa, m.id_producto_servicio, count(*)
                 from kardex_mov m where m.id_empresa < 900000
                group by m.id_empresa, m.id_producto_servicio
               having count(distinct trunc(m.fecha_movimiento)) >= 3
                order by count(*) desc fetch first 1 rows only""")
fila = cur.fetchone()
if not fila:
    print("sin articulo con movimientos en 3 fechas\nRESULTADO: FALLAS=0 OMITIDOS=1")
    sys.exit(0)
EMP, ART, N = fila
cur.execute("select codigo || ' - ' || nombre from producto_servicio where id_producto_servicio = :a", a=ART)
NOMBRE = cur.fetchone()[0]
cur.execute("""select to_char(trunc(fecha_movimiento), 'DD/MM/YYYY'),
                      sum(cantidad * pkg_inventario.fn_signo(tipo_movimiento)) over (order by fecha_movimiento, id_movimiento)
                 from kardex_mov where id_producto_servicio = :a order by fecha_movimiento, id_movimiento""", a=ART)
MOVS = cur.fetchall()
FECHAS = sorted({f for f, _ in MOVS}, key=lambda x: x[6:] + x[3:5] + x[:2])
DESDE = FECHAS[1]   # desde la segunda fecha: hay movimientos anteriores que deben arrastrarse
print("empresa %s articulo %s (%s) con %s movimientos; desde=%s" % (EMP, ART, NOMBRE, N, DESDE))

USUARIO = "diag.kardex"
BORRA = ("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario "
         "where upper(username)=upper(:u)); commit; delete from usuario where upper(username)=upper(:u); commit; end;")
cur.execute(BORRA, u=USUARIO)
cur.execute("""insert into usuario (username,email,password_hash,estado,id_empresa,rol_id,debe_cambiar_clave,reintentos_fallidos)
               values (:u,:m,sypex_hash_password(:p),'ACTIVO',:e,(select id_rol from syn_roles where codigo_rol='ADMIN'),'N',0)""",
            u=USUARIO, m=USUARIO + "@synpex.local", p=aud.CLAVE, e=EMP)
con.commit()

LEER = '''(function(){var t=[...document.querySelectorAll(".a-IRR-table")].pop(); if(!t){return "[]";}
  var cab=[...t.querySelectorAll("th")].map(function(h){return h.innerText.trim();});
  var filas=[...t.querySelectorAll("tr")].filter(function(r){return r.querySelector("td");}).map(function(r){
     var o={}; [...r.querySelectorAll("td")].forEach(function(d,i){o[cab[i]]=d.innerText.trim();}); return o;});
  return JSON.stringify(filas);})()'''


def leer(nav):
    import json
    return json.loads(nav.js(LEER) or "[]")


def filtra(nav, desde):
    nav.js('(function(){apex.item("P43_ID_ARTICULO").setValue("%s"); apex.item("P43_DESDE").setValue("%s");'
           'apex.item("P43_HASTA").setValue(""); apex.item("P43_TIPO").setValue("");})()' % (ART, desde))
    nav.js('(function(){var r=[...document.querySelectorAll(".a-IRR")].pop(); '
           'apex.region(r.closest(".t-Region, .t-IRR-region").id).refresh();})()')
    time.sleep(6)


nav = None
try:
    nav = aud.Nav(puerto=9351)
    aud.USUARIO = USUARIO
    ses = aud.entrar(nav)
    nav.js('window.location.href="%s/f?p=100:43:%s"' % (aud.BASE, ses))
    nav.esperar('document.readyState === "complete" && !!window.apex && !!apex.item("P43_ID_ARTICULO")', 60)
    time.sleep(3)
    filtra(nav, "")
    filas = leer(nav)
    fechas = [f.get("Fecha", "") for f in filas]
    clave = [x[6:] + x[3:5] + x[:2] for x in fechas]
    ok("K1 del mas antiguo al mas reciente (%d filas)" % len(filas), len(filas) >= 3 and clave == sorted(clave), fechas)
    saldos = [num(f.get("Saldo")) for f in filas]
    cants = [num(f.get("Cantidad")) for f in filas]
    cuadra = all(abs(saldos[i] - (saldos[i - 1] + cants[i])) < 0.001 for i in range(1, len(filas)))
    ok("K2 cada saldo = anterior + cantidad", cuadra and abs(saldos[-1] - float(MOVS[-1][1])) < 0.001,
       list(zip(cants, saldos)))
    ok("K4 columna Articulo con el articulo", all(f.get(u"Artículo") == NOMBRE for f in filas), filas[:1])

    filtra(nav, DESDE)
    filas2 = leer(nav)
    previo = [s for f, s in MOVS if (f[6:] + f[3:5] + f[:2]) < (DESDE[6:] + DESDE[3:5] + DESDE[:2])][-1]
    primero = num(filas2[0].get("Saldo")) if filas2 else None
    cant1 = num(filas2[0].get("Cantidad")) if filas2 else None
    ok("K3 con Desde=%s el saldo arrastra lo anterior (%s)" % (DESDE, previo),
       primero is not None and abs(primero - (float(previo) + cant1)) < 0.001, (primero, cant1, previo))
finally:
    if nav:
        nav.cerrar()
    cur.execute(BORRA, u=USUARIO)
    con.close()

print("\nRESULTADO: FALLAS=%d" % len(fallas))
for f in fallas:
    print("  - " + f)
sys.exit(1 if fallas else 0)
