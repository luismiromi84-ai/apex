#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Toma fisica (47) y conciliacion bancaria (48), en navegador real (2026-11-25).

  T1 Nueva toma crea la toma con los productos de la empresa
  T2 lo contado se guarda (Guardar conteo) y la diferencia se ve en vivo
  T3 Anular toma la deja ANULADA sin mover el kardex
     (aplicar la toma esta probado en 20261125_toma_fisica_verificacion.sql con una empresa temporal:
      aqui se usan los articulos reales de la empresa 1 y no se aplica)
  B1 abrir una conciliacion de una cuenta temporal para octubre
  B2 marcar el cobro y el pago: el saldo segun el sistema y la diferencia se calculan en vivo
  B3 con el banco en 80 no cierra y lo explica
  B4 con el banco en 68 cierra (CERRADA, diferencia 0)

    python deploy/diagnostico/20261125_toma_conciliacion_navegador.py
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
    print(("  OK   " if cond else "  FALLA") + " " + nombre + ("" if cond else "  -> " + str(det)[:220]))
    if not cond:
        fallas.append(nombre)


c = aud.credenciales()
con = aud.oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=aud.CS)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")


def limpia():
    cur.execute("update recibos set id_conciliacion = null where referencia = 'DIAG-CONC-N'")
    cur.execute("update pagos set id_conciliacion = null where referencia = 'DIAG-CONC-N'")
    con.commit()
    cur.execute("delete from recibos where referencia = 'DIAG-CONC-N'")
    con.commit()
    cur.execute("delete from pagos where referencia = 'DIAG-CONC-N'")
    con.commit()
    cur.execute("delete from conciliaciones where id_cuenta in (select id_cuenta from cuentas_fondos where nombre = 'DIAG CONC N')")
    con.commit()
    cur.execute("delete from cuentas_fondos where nombre = 'DIAG CONC N'")
    con.commit()


limpia()
cur.execute("select count(*) from tomas_fisicas where id_empresa = 1 and estado = 'BORRADOR'")
TOMA_PREVIA = cur.fetchone()[0]
cur.execute("""insert into cuentas_fondos (id_empresa, nombre, tipo, banco, cod_moneda, es_principal, estado, creado_por)
               values (1, 'DIAG CONC N', 'BANCO', 'Banco DIAG', 'VES', 'N', 'ACTIVO', 'DIAG')""")
con.commit()
cur.execute("select id_cuenta from cuentas_fondos where nombre = 'DIAG CONC N'")
CTA = cur.fetchone()[0]
cur.execute("""insert into recibos (id_empresa, id_factura, fecha_cobro, cod_moneda, tipo_cambio, monto_cobrado, monto_bs,
                     monto_factura, aplica_igtf, igtf_monto, igtf_bs, retencion_iva_bs, monto_neto,
                     referencia, conciliado, estado, creado_por, id_cuenta)
               select 1, (select max(id_factura) from facturas where id_empresa = 1), date '2026-10-10', 'VES', 1,
                      100, 100, 100, 'N', 0, 0, 0, 100, 'DIAG-CONC-N', 'N', 'ACTIVO', 'DIAG', :c from dual""", c=CTA)
con.commit()
cur.execute("""insert into pagos (id_empresa, id_proveedor, fecha_pago, cod_moneda, tipo_cambio, monto, monto_bs,
                   referencia, aplica_igtf, igtf_monto, igtf_bs, estado, creado_por, id_cuenta)
               select 1, (select max(id_proveedor) from proveedores where id_empresa = 1), date '2026-10-12', 'VES', 1,
                      30, 30, 'DIAG-CONC-N', 'S', 2, 2, 'ACTIVO', 'DIAG', :c from dual""", c=CTA)
con.commit()

USR = "diag.tomaconc"
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

nav = aud.Nav(puerto=9308)
TOMA = None


def abre(pag, esp='document.readyState === "complete" && !!window.apex'):
    nav.js('window.location.href="%s/f?p=100:%d:%s"' % (aud.BASE, pag, ses))
    nav.esperar(esp, 40)
    time.sleep(2.5)


def foto(nombre):
    r = nav.cmd("Page.captureScreenshot", format="png")
    if r.get("data"):
        with open(os.path.join(IMG, nombre + ".png"), "wb") as fh:
            fh.write(base64.b64decode(r["data"]))


def texto():
    return str(nav.js("document.body.innerText") or "")


try:
    ses = aud.entrar(nav)
    if not ses:
        sys.exit("login fallido")

    # ------------------------------------------------------------- toma fisica
    if TOMA_PREVIA:
        print("  [OMITIDO] T1-T3: la empresa 1 ya tiene una toma abierta (no se toca)")
    else:
        abre(47)
        nav.js('document.getElementById("B43000000000002245").click()')
        nav.esperar('document.readyState === "complete" && document.querySelectorAll("input.spx-conteo").length > 0', 40)
        time.sleep(2)
        cur.execute("select max(id_toma) from tomas_fisicas where id_empresa = 1 and estado = 'BORRADOR'")
        TOMA = cur.fetchone()[0]
        n_in = nav.js('document.querySelectorAll("input.spx-conteo").length')
        ok("T1 Nueva toma crea la toma con sus articulos", TOMA is not None and (n_in or 0) > 0, (TOMA, n_in))
        # se cuenta el primer articulo con su existencia actual + 1
        nav.js('(function(){var i=document.querySelector("input.spx-conteo");'
               'var a=parseFloat(i.getAttribute("data-actual")||"0");'
               'i.value=String(a+1).replace(".",apex.locale.getDecimalSeparator());spxDif(i);})()')
        dif = nav.js('document.querySelector(".spx-dif").textContent')
        foto("toma_fisica")
        nav.js('document.getElementById("B43000000000002246").click()')
        nav.esperar('document.readyState === "complete" && /Conteo guardado/.test(document.body.innerText)', 40)
        cur.execute("select count(*) from tomas_fisicas_det where id_toma = :t and conteo is not null", t=TOMA)
        ok("T2 el conteo se guarda y la diferencia se ve en vivo", cur.fetchone()[0] == 1 and "+" in str(dif), dif)
        nav.js('document.getElementById("B43000000000002248").click()')
        time.sleep(2)
        nav.js('(function(){var b=[...document.querySelectorAll(".ui-dialog button, .a-AlertDialog button")]'
               '.find(function(x){return !/Cancelar/i.test(x.innerText) && x.offsetParent;});if(b){b.click();}})()')
        nav.esperar('document.readyState === "complete" && /Toma anulada/.test(document.body.innerText)', 40)
        cur.execute("select estado from tomas_fisicas where id_toma = :t", t=TOMA)
        cur2 = con.cursor()
        cur2.execute("select count(*) from kardex_mov where motivo like 'Toma fisica N. ' || :t || ' %'", t=TOMA)
        ok("T3 anular deja la toma ANULADA sin mover el kardex",
           cur.fetchone()[0] == "ANULADA" and cur2.fetchone()[0] == 0, texto()[:150])

    # ------------------------------------------------------------- conciliacion
    abre(48, '!!document.getElementById("P48_ID_CUENTA")')
    nav.js('apex.item("P48_ID_CUENTA").setValue("%d");apex.item("P48_DESDE").setValue("01/10/2026");'
           'apex.item("P48_HASTA").setValue("31/10/2026");' % CTA)
    nav.js('document.getElementById("B43000000000002266").click()')
    nav.esperar('document.readyState === "complete" && document.querySelectorAll("input.spx-mov").length > 0', 40)
    time.sleep(2)
    cur.execute("select max(id_conciliacion) from conciliaciones where id_cuenta = :c and estado = 'ABIERTA'", c=CTA)
    CONC = cur.fetchone()[0]
    ok("B1 abre la conciliacion con los movimientos del periodo",
       CONC is not None and nav.js('document.querySelectorAll("input.spx-mov").length') == 2, CONC)

    nav.js('document.querySelectorAll("input.spx-mov").forEach(function(c){c.checked=true;});'
           'var b=document.getElementById("spx-cc-banco");b.value="80";spxCuadre();')
    sis = nav.js('document.getElementById("spx-cc-sis").textContent')
    dif = nav.js('document.getElementById("spx-cc-dif").className')
    ok("B2 el saldo segun el sistema y la diferencia se calculan en vivo", str(sis).startswith("68") and dif == "mal", (sis, dif))

    nav.js('spxEnviaConc("CERRAR")')
    nav.esperar('/No cuadra/.test(document.body.innerText)', 20)
    cur.execute("select estado from conciliaciones where id_conciliacion = :c", c=CONC)
    ok("B3 con el banco en 80 no cierra, lo explica y no envia",
       "No cuadra" in texto() and cur.fetchone()[0] == "ABIERTA", texto()[:200])
    nav.js('(function(){var b=[...document.querySelectorAll(".ui-dialog button")].find(function(x){return x.offsetParent;});if(b){b.click();}})()')

    abre(48, 'document.querySelectorAll("input.spx-mov").length > 0')
    nav.js('document.querySelectorAll("input.spx-mov").forEach(function(c){c.checked=true;});'
           'var b=document.getElementById("spx-cc-banco");b.value="68";spxCuadre();')
    foto("conciliacion")
    nav.js('spxEnviaConc("CERRAR")')
    time.sleep(2)
    nav.js('(function(){var b=[...document.querySelectorAll(".ui-dialog button, .a-AlertDialog button")]'
           '.find(function(x){return !/Cancelar/i.test(x.innerText) && x.offsetParent;});if(b){b.click();}})()')
    nav.esperar('document.readyState === "complete" && /cuadra con el banco/.test(document.body.innerText)', 40)
    cur.execute("select estado, diferencia from conciliaciones where id_conciliacion = :c", c=CONC)
    est = cur.fetchone()
    ok("B4 con el banco en 68 la conciliacion queda CERRADA", est and est[0] == "CERRADA" and float(est[1]) == 0, est)
finally:
    nav.cerrar()
    if TOMA:
        cur.execute("delete from tomas_fisicas_det where id_toma = :t", t=TOMA)
        con.commit()
        cur.execute("delete from tomas_fisicas where id_toma = :t", t=TOMA)
        con.commit()
    limpia()
    cur.execute(BORRA, u=USR)
    con.close()

print("\nRESULTADO: FALLAS=%d" % len(fallas))
for f in fallas:
    print("  - " + f)
sys.exit(1 if fallas else 0)
