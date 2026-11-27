#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Saldo inicial de cajas y cuentas (pagina 46), 2026-11-26, en navegador real.

  S1 «Editar» de una cuenta muestra el campo «Saldo inicial»
  S2 guardar 1.000,50 (con puntos de miles y coma) lo graba como 1000.50
  S3 el resumen suma el saldo inicial: Saldo = inicial + entradas - salidas
  S4 la conciliacion abierta (primera de la cuenta) arranca con ese saldo inicial
  S5 «Efectivo Divisas» se rotula «(genera IGTF)» en el pago a proveedor

Usa una cuenta real con conciliacion abierta y sin cierres; al final deja sus valores como estaban.

    python deploy/diagnostico/20261126_saldo_inicial_cuenta_navegador.py
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
cur.execute("""select f.id_cuenta, f.id_empresa, f.nombre, f.saldo_inicial, f.fecha_saldo_inicial,
                      (select max(c.id_conciliacion) from conciliaciones c where c.id_cuenta = f.id_cuenta and c.estado = 'ABIERTA')
                 from cuentas_fondos f
                where f.id_empresa < 900000 and f.cod_moneda = 'VES' and f.estado = 'ACTIVO'
                  and not exists (select 1 from conciliaciones c where c.id_cuenta = f.id_cuenta and c.estado = 'CERRADA')
                order by case when exists (select 1 from conciliaciones c where c.id_cuenta = f.id_cuenta
                                            and c.estado = 'ABIERTA') then 0 else 1 end, f.id_cuenta
                fetch first 1 rows only""")
fila = cur.fetchone()
if not fila:
    print("sin cuenta en Bs sin conciliaciones cerradas\nRESULTADO: FALLAS=0 OMITIDOS=1")
    sys.exit(0)
CTA, EMP, NOMBRE, INI0, FINI0, CONC = fila
INI_CONC0 = None
if CONC:
    cur.execute("select saldo_inicial from conciliaciones where id_conciliacion = :c", c=CONC)
    INI_CONC0 = cur.fetchone()[0]
print("cuenta %s (%s) empresa %s; saldo inicial %s; conciliacion abierta %s" % (CTA, NOMBRE, EMP, INI0, CONC))

USUARIO = "diag.saldoini"
BORRA = ("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario "
         "where upper(username)=upper(:u)); commit; delete from usuario where upper(username)=upper(:u); commit; end;")
cur.execute(BORRA, u=USUARIO)
cur.execute("""insert into usuario (username,email,password_hash,estado,id_empresa,rol_id,debe_cambiar_clave,reintentos_fallidos)
               values (:u,:m,sypex_hash_password(:p),'ACTIVO',:e,(select id_rol from syn_roles where codigo_rol='ADMIN'),'N',0)""",
            u=USUARIO, m=USUARIO + "@synpex.local", p=aud.CLAVE, e=EMP)
con.commit()

FILA_JS = '''(function(){var r=[...document.querySelectorAll("table.spx-cta tbody tr")].find(function(x){
    var b=x.querySelector("td b"); return b && b.innerText.trim()===%s;}); if(!r){return "";}
    return [...r.querySelectorAll("td")].map(function(d){return d.innerText.trim().split(String.fromCharCode(10))[0];}).join("|");})()'''


nav = None
try:
    nav = aud.Nav(puerto=9371)
    aud.USUARIO = USUARIO
    ses = aud.entrar(nav)
    nav.js('window.location.href="%s/f?p=100:46:%s"' % (aud.BASE, ses))
    nav.esperar('document.readyState === "complete" && document.querySelectorAll("table.spx-cta").length > 0', 60)
    time.sleep(2)
    import json
    nav.js('''(function(){var r=[...document.querySelectorAll("table.spx-cta tbody tr")].find(function(x){
        var b=x.querySelector("td b"); return b && b.innerText.trim()===%s;}); r.querySelector("a[href]").click();})()''' % json.dumps(NOMBRE))
    nav.esperar('document.readyState === "complete" && !!document.getElementById("P46_SALDO_INICIAL") '
                '&& apex.item("P46_NOMBRE").getValue() !== ""', 60)
    time.sleep(2)
    ok("S1 Editar muestra Saldo inicial", nav.js('!!document.getElementById("P46_SALDO_INICIAL")'))
    nav.js('(function(){document.getElementById("P46_SALDO_INICIAL").value="1.000,50";'
           'apex.item("P46_FECHA_SALDO_INICIAL").setValue("01/11/2026");'
           'var b=[...document.querySelectorAll("button")].find(function(x){return x.innerText.trim()==="Guardar";});b.click();})()')
    time.sleep(4)
    nav.esperar('document.readyState === "complete" && document.querySelectorAll("table.spx-cta").length > 0', 60)
    time.sleep(2)
    cur.execute("select saldo_inicial, to_char(fecha_saldo_inicial,'DD/MM/YYYY') from cuentas_fondos where id_cuenta = :c", c=CTA)
    v, f = cur.fetchone()
    ok("S2 se grabo 1000.50 con fecha 01/11/2026", float(v) == 1000.5 and f == "01/11/2026", (v, f))
    celdas = str(nav.js(FILA_JS % json.dumps(NOMBRE)) or "").split("|")
    # Caja | Tipo | Moneda | Saldo inicial | Cobros | Entradas | Pagos | Salidas | Saldo | Editar
    try:
        ini, ent, sal, sdo = num(celdas[3]), num(celdas[5]), num(celdas[7]), num(celdas[8])
        cuadra = abs(ini - 1000.5) < 0.001 and abs(sdo - (ini + ent - sal)) < 0.01
    except Exception as e:
        cuadra = False
    ok("S3 resumen: saldo inicial 1.000,50 y Saldo = inicial + entradas - salidas", cuadra, celdas)
    if CONC:
        cur.execute("select saldo_inicial from conciliaciones where id_conciliacion = :c", c=CONC)
        ok("S4 la conciliacion abierta arranca en 1.000,50", float(cur.fetchone()[0]) == 1000.5)
    else:
        print("  OMITIDO S4: la cuenta no tiene conciliacion abierta")
    cur.execute("""select count(*) from apex_application_page_items where application_id = 100 and page_id = 37
                    and item_name = 'P37_ID_FORMA_PAGO' and lov_definition like '%(genera IGTF)%'""")
    ok("S5 la forma de pago con IGTF dice (genera IGTF)", cur.fetchone()[0] == 1)
finally:
    if nav:
        nav.cerrar()
    cur.execute("update cuentas_fondos set saldo_inicial = :v, fecha_saldo_inicial = :f where id_cuenta = :c",
                v=INI0, f=FINI0, c=CTA)
    if CONC:
        cur.execute("update conciliaciones set saldo_inicial = :v where id_conciliacion = :c", v=INI_CONC0, c=CONC)
    con.commit()
    cur.execute(BORRA, u=USUARIO)
    con.close()

print("\nRESULTADO: FALLAS=%d" % len(fallas))
for f in fallas:
    print("  - " + f)
sys.exit(1 if fallas else 0)
