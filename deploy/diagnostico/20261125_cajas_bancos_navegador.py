#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Cajas y bancos (pagina 46) y el destino del cobro (2026-11-25), en navegador real.

  K1 la 46 abre con la Caja principal de la empresa y la tabla de saldos
  K2 un banco sin nombre de banco no se guarda y lo explica
  K3 crear un banco funciona y sale en la lista
  K4 marcar el banco como principal le quita la marca a la caja (una sola principal)
  K5 el recibo (25) ofrece «Destino» con la cuenta principal puesta
  K6 sin principal no se puede quedar: quitarle la marca a la unica principal se rechaza

Usa la empresa 1 con un usuario temporal ADMIN; borra el banco de prueba y devuelve la marca de
principal a la caja al terminar.

    python deploy/diagnostico/20261125_cajas_bancos_navegador.py
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
BANCO = "Banco DIAG prueba"


def ok(nombre, cond, det=""):
    print(("  OK   " if cond else "  FALLA") + " " + nombre + ("" if cond else "  -> " + str(det)[:220]))
    if not cond:
        fallas.append(nombre)


c = aud.credenciales()
con = aud.oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=aud.CS)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")
cur.execute("select id_cuenta from cuentas_fondos where id_empresa = 1 and es_principal = 'S'")
CAJA = cur.fetchone()[0]


def limpia():
    cur.execute("update cuentas_fondos set es_principal = 'N' where id_empresa = 1 and nombre = :n", n=BANCO)
    cur.execute("update cuentas_fondos set es_principal = 'S' where id_cuenta = :c", c=CAJA)
    cur.execute("delete from cuentas_fondos where id_empresa = 1 and nombre = :n", n=BANCO)
    con.commit()


limpia()
USR = "diag.cajas"
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

nav = aud.Nav(puerto=9306)


def abre46():
    nav.js('window.location.href="%s/f?p=100:46:%s"' % (aud.BASE, ses))
    nav.esperar('document.readyState === "complete" && !!document.getElementById("P46_NOMBRE")', 40)
    time.sleep(2)


def texto():
    return str(nav.js("document.body.innerText") or "")


def guardar():
    nav.js('document.getElementById("B43000000000002220").click()')
    nav.esperar('document.readyState === "complete" && !!document.getElementById("P46_NOMBRE")', 40)
    time.sleep(3)


try:
    ses = aud.entrar(nav)
    if not ses:
        sys.exit("login fallido")
    abre46()
    tx = texto()
    ok("K1 la 46 abre con la Caja principal y los saldos",
       "Caja principal" in tx and "Principal" in tx and "Saldo (Bs)" in tx, tx[:300])
    nav.captura(os.path.join(aud.REPO, "docs", "imagenes", "cajas_bancos.png"))

    # K2: banco sin nombre de banco
    nav.js('apex.item("P46_NOMBRE").setValue(%r);apex.item("P46_TIPO").setValue("BANCO");' % BANCO)
    guardar()
    ok("K2 un banco sin nombre de banco no se guarda y lo explica",
       "necesita el nombre del banco" in texto(), texto()[:200])

    # K3: alta del banco
    abre46()
    nav.js('apex.item("P46_NOMBRE").setValue(%r);apex.item("P46_TIPO").setValue("BANCO");'
           'apex.item("P46_BANCO").setValue("Banco de Venezuela");'
           'apex.item("P46_NUMERO_CUENTA").setValue("0102-0000-00-0000000000");' % BANCO)
    guardar()
    cur.execute("select count(*) from cuentas_fondos where id_empresa = 1 and nombre = :n", n=BANCO)
    ok("K3 el banco se guarda y sale en la lista", cur.fetchone()[0] == 1 and BANCO in texto(), texto()[:200])

    # K4: el banco pasa a principal
    cur.execute("select id_cuenta from cuentas_fondos where id_empresa = 1 and nombre = :n", n=BANCO)
    ID_B = cur.fetchone()[0]
    nav.js('(function(){var a=[...document.querySelectorAll("a")].find(function(x){'
           'return /p46_id_cuenta=%d(\\D|$)/i.test(decodeURIComponent(x.href));});if(a){a.click();}})()' % ID_B)
    nav.esperar('document.readyState === "complete" && apex.item("P46_NOMBRE").getValue() === %r' % BANCO, 40)
    time.sleep(2)
    nav.js('apex.item("P46_ES_PRINCIPAL").setValue("S");')
    guardar()
    cur.execute("select nombre from cuentas_fondos where id_empresa = 1 and es_principal = 'S'")
    filas = [r[0] for r in cur.fetchall()]
    ok("K4 el banco queda como unica principal", filas == [BANCO], filas)

    # K5: el recibo ofrece el destino con la principal puesta
    cur.execute("select max(id_factura) from facturas f where id_empresa = 1 and fn_factura_cobrable(f.id_factura)")
    ID_F = cur.fetchone()[0]
    if ID_F:
        nav.js('window.location.href="%s/f?p=100:8:%s"' % (aud.BASE, ses))
        nav.esperar('document.querySelectorAll(".js-select-invoice").length > 0', 40)
        time.sleep(2)
        nav.js('(function(){var c=document.querySelector(\'.js-select-invoice[data-id="%d"]\');'
               'var a=c?[...c.closest("tr").querySelectorAll("a")].find(function(x){return /Cobrar/.test(x.innerText);}):null;'
               'if(a){a.click();}})()' % ID_F)
        nav.esperar('(function(){var f=document.querySelector("iframe");return !!(f&&f.contentWindow'
                    '&&f.contentWindow.apex&&f.contentWindow.apex.item);})()', 40)
        time.sleep(4)
        d = nav.js('(function(){var w=document.querySelector("iframe").contentWindow;'
                   'var s=w.document.getElementById("P25_ID_CUENTA");'
                   'return s?{v:s.value,t:s.options[s.selectedIndex].text,n:s.options.length}:null;})()')
        ok("K5 el recibo trae Destino con la principal", isinstance(d, dict) and str(d.get("v")) == str(ID_B), d)
    else:
        print("  [OMITIDO] K5: no hay factura cobrable en la empresa 1")

    # K6: quitarle la marca a la unica principal
    abre46()
    nav.js('(function(){var a=[...document.querySelectorAll("a")].find(function(x){'
           'return /p46_id_cuenta=%d(\\D|$)/i.test(decodeURIComponent(x.href));});if(a){a.click();}})()' % ID_B)
    nav.esperar('document.readyState === "complete" && apex.item("P46_NOMBRE").getValue() === %r' % BANCO, 40)
    time.sleep(2)
    nav.js('apex.item("P46_ES_PRINCIPAL").setValue("N");')
    guardar()
    ok("K6 no se puede quedar sin principal", "necesita una caja principal" in texto(), texto()[:200])
finally:
    nav.cerrar()
    limpia()
    cur.execute(BORRA, u=USR)
    con.close()

print("\nRESULTADO: FALLAS=%d" % len(fallas))
for f in fallas:
    print("  - " + f)
sys.exit(1 if fallas else 0)
