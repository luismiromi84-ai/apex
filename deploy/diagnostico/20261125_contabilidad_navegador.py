#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Contabilidad, fase 3: paginas 50-54 en navegador real (2026-11-25).

  C1 Plan de cuentas: sin plan avisa; «Instalar plan de cuentas» copia el plan del contador
     (216 cuentas + la subcuenta de la caja) y la tabla las muestra
  C2 pulsar una fila llena el formulario; se crea la cuenta 6.1.1.40.950 bajo su grupo
  C3 Asientos: un asiento cuadrado (116 = 100 + 16) se confirma con el numero 1 del mes
  C4 un asiento descuadrado no se envia: el navegador lo explica y la base no cambia
  C5 Libros: el balance de comprobacion cuadra y la descarga a Excel trae el balance
  C6 Cierre mensual: cerrar el mes lo deja CERRADO; reabrir lo deja ABIERTO
  C7 un rol sin contabilidad (FACTURACION) no entra al plan de cuentas (-20003)
  C8 «Contabilizar» del cierre mensual responde con el resumen del lote
  C9 estado de resultados y balance general en pantalla, con la descarga a Excel
  C10 el pago al SENIAT no deja pagar mas de lo pendiente
  C11 «Cierre anual» crea el asiento de cierre del ano

Empresa temporal 900281 con su caja y dos usuarios temporales; se purga al final.

    python deploy/diagnostico/20261125_contabilidad_navegador.py
"""
import base64
import datetime
import importlib.util
import os
import shutil
import sys
import tempfile
import time

AQUI = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("aud", os.path.join(AQUI, "20261125_auditoria_estandar.py"))
aud = importlib.util.module_from_spec(spec)
spec.loader.exec_module(aud)

fallas = []
E = 900281
IMG = os.path.join(aud.REPO, "docs", "imagenes")
DESC = os.path.join(tempfile.gettempdir(), "opencode", "descargas-ctb")
shutil.rmtree(DESC, ignore_errors=True)
os.makedirs(DESC, exist_ok=True)
HOY = datetime.date.today()


def ok(nombre, cond, det=""):
    print(("  OK   " if cond else "  FALLA") + " " + nombre + ("" if cond else "  -> " + str(det)[:220]))
    if not cond:
        fallas.append(nombre)


c = aud.credenciales()
con = aud.oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=aud.CS)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")

BORRA = ("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario "
         "where upper(username)=upper(:u)); commit; delete from usuario where "
         "upper(username)=upper(:u); commit; end;")


def limpia():
    cur.execute("begin pkg_contabilidad.prc_purgar_prueba(:e); commit; end;", e=E)
    for u in ("diag.ctbnav", "diag.ctbfac"):
        cur.execute(BORRA, u=u)
    for s in ("delete from cuentas_fondos where id_empresa = :e", "delete from usuario_empresa where id_empresa = :e",
              "delete from empresas where id_empresa = :e"):
        cur.execute(s, e=E)
        con.commit()


limpia()
cur.execute("""insert into empresas (id_empresa, nombre_empresa, cod_pais, tipo_ident_fiscal, rfc, estado)
               values (:e, 'DIAG CONTABILIDAD NAV', 'VE', 'RIF', 'J-90028100-1', 'ACTIVO')""", e=E)
cur.execute("""insert into cuentas_fondos (id_empresa, nombre, tipo, cod_moneda, es_principal, estado, creado_por)
               values (:e, 'Caja principal', 'CAJA', 'VES', 'S', 'ACTIVO', 'DIAG')""", e=E)
con.commit()


def usuario(u, rol):
    cur.execute("""insert into usuario (username,email,password_hash,estado,id_empresa,rol_id,
                                         debe_cambiar_clave,reintentos_fallidos)
                   values (:u,:m,sypex_hash_password(:p),'ACTIVO',:e,
                           (select id_rol from syn_roles where codigo_rol=:r),'N',0)""",
                u=u, m=u + "@synpex.local", p=aud.CLAVE, e=E, r=rol)
    con.commit()
    # el trigger del usuario suele crear ya el par con su empresa principal
    cur.execute("""insert into usuario_empresa (usuario_id, id_empresa)
                   select usuario_id, :e from usuario u where username = :u
                      and not exists (select 1 from usuario_empresa x where x.usuario_id = u.usuario_id and x.id_empresa = :e)""",
                e=E, u=u)
    con.commit()


usuario("diag.ctbnav", "ADMIN")
usuario("diag.ctbfac", "FACTURACION")

nav = aud.Nav(puerto=9311)


def abre(pag, esp='document.readyState === "complete" && !!window.apex'):
    nav.js('window.location.href="%s/f?p=100:%d:%s"' % (aud.BASE, pag, ses))
    nav.esperar(esp, 40)
    time.sleep(2.5)


def texto():
    return str(nav.js("document.body.innerText") or "")


def acepta_dialogo():
    time.sleep(1.5)
    nav.js('(function(){var b=[...document.querySelectorAll(".ui-dialog button, .a-AlertDialog button")]'
           '.find(function(x){return !/Cancelar/i.test(x.innerText) && x.offsetParent;});if(b){b.click();}})()')


def foto(nombre):
    r = nav.cmd("Page.captureScreenshot", format="png")
    if r.get("data"):
        with open(os.path.join(IMG, nombre + ".png"), "wb") as fh:
            fh.write(base64.b64decode(r["data"]))


def uno(sql, **k):
    cur.execute(sql, **k)
    return cur.fetchone()[0]


try:
    aud.USUARIO = "diag.ctbnav"
    ses = aud.entrar(nav)
    if not ses:
        sys.exit("login fallido")
    nav.cmd("Browser.setDownloadBehavior", behavior="allow", downloadPath=DESC)

    # C1
    abre(50)
    sin_plan = "no tiene plan de cuentas" in texto()
    nav.js('document.getElementById("B43000000000002312").click()')
    acepta_dialogo()
    nav.esperar('document.readyState === "complete" && /Plan de cuentas instalado/.test(document.body.innerText)', 60)
    time.sleep(2)
    filas = nav.js('document.getElementById("spx-plan") ? document.getElementById("spx-plan").querySelectorAll("tbody tr").length : 0')
    n_db = uno("select count(*) from ctb_cuentas where id_empresa = :e", e=E)
    foto("contabilidad_plan")
    ok("C1 instalar el plan copia 217 cuentas y la tabla las muestra", sin_plan and n_db == 217 and filas == 217,
       (sin_plan, n_db, filas))

    # C2
    nav.js('document.querySelector("#spx-plan tr[data-cod=\'6.1.1.40.900\']").click()')
    time.sleep(0.5)
    lleno = nav.js('apex.item("P50_CODIGO").getValue()')
    nav.js('apex.item("P50_CODIGO").setValue("6.1.1.40.950");apex.item("P50_NOMBRE").setValue("gastos de prueba");')
    nav.js('document.getElementById("B43000000000002317").click()')
    nav.esperar('document.readyState === "complete" && /Cuenta 6.1.1.40.950 guardada/.test(document.body.innerText)', 40)
    n2 = uno("select count(*) from ctb_cuentas where id_empresa = :e and codigo = '6.1.1.40.950' and nombre = 'GASTOS DE PRUEBA'", e=E)
    ok("C2 la fila llena el formulario y se crea la cuenta bajo su grupo", lleno == "6.1.1.40.900" and n2 == 1, (lleno, n2))

    # C3
    abre(51)
    nav.js('document.getElementById("B43000000000002336").click()')
    nav.esperar('document.readyState === "complete" && !!document.getElementById("spx-lin-body")', 40)
    time.sleep(2)
    nav.js('apex.item("P51_CONCEPTO").setValue("Factura de prueba en navegador");'
           'spxLinea();'
           'var f=document.getElementById("spx-lin-body").querySelectorAll("tr");'
           'var dsep=apex.locale.getDecimalSeparator();'
           'function pon(tr,c,d,h){var i=tr.querySelector(".spx-cta");i.value=c;spxNombre(i);'
           'tr.querySelector(".spx-debe").value=d;tr.querySelector(".spx-haber").value=h;}'
           'pon(f[0],"1.1.2.10.010","116"+dsep+"00","");pon(f[1],"4.1.2.10.010","","100");pon(f[2],"2.1.6.10.010","","16");'
           'spxTotales();')
    dif_cls = nav.js('document.getElementById("spx-dif").className')
    nombre = nav.js('document.getElementById("spx-lin-body").querySelector(".spx-nom").textContent')
    foto("contabilidad_asiento")
    nav.js('spxEnviaAsiento("CONFIRMAR")')
    acepta_dialogo()
    nav.esperar('document.readyState === "complete" && /confirmado/.test(document.body.innerText)', 40)
    est = None
    cur.execute("""select estado, numero, total_debe from ctb_asientos where id_empresa = :e
                    and concepto = 'Factura de prueba en navegador'""", e=E)
    est = cur.fetchone()
    ok("C3 el asiento cuadrado se confirma con el numero 1 del mes",
       dif_cls == "ok" and "COBRAR" in str(nombre) and est and est[0] == "CONFIRMADO" and est[1] == 1 and float(est[2]) == 116,
       (dif_cls, nombre, est))

    # C4
    antes = uno("select count(*) from ctb_asientos where id_empresa = :e", e=E)
    nav.js('document.getElementById("B43000000000002336").click()')
    nav.esperar('document.readyState === "complete" && !!document.getElementById("spx-lin-body")', 40)
    time.sleep(2)
    nav.js('apex.item("P51_CONCEPTO").setValue("Descuadrado");'
           'var f=document.getElementById("spx-lin-body").querySelectorAll("tr");'
           'f[0].querySelector(".spx-cta").value="1.1.2.10.010";f[0].querySelector(".spx-debe").value="100";'
           'f[1].querySelector(".spx-cta").value="4.1.2.10.010";f[1].querySelector(".spx-haber").value="90";'
           'spxEnviaAsiento("CONFIRMAR");')
    time.sleep(2)
    aviso = "no cuadra" in texto()
    despues = uno("select count(*) from ctb_asientos where id_empresa = :e", e=E)
    ok("C4 el asiento descuadrado no se envia y se explica", aviso and antes == despues, (aviso, antes, despues))
    nav.js('(function(){var b=[...document.querySelectorAll(".ui-dialog button")].find(function(x){return x.offsetParent;});if(b){b.click();}})()')

    # C5
    # la pagina abre con el balance del mes (no hace falta pulsar Ver; pulsarlo y luego Excel
    # dejaba el segundo clic en plena navegacion)
    abre(53, 'document.readyState === "complete" && /Total balance de comprobaci/.test(document.body.innerText)')
    tx = texto()
    foto("contabilidad_balance")
    nav.js('document.getElementById("B43000000000002377").click()')
    archivo = None
    fin = time.time() + 40
    while time.time() < fin and not archivo:
        for f in os.listdir(DESC):
            if f.startswith("balance-comprobacion-") and f.endswith(".xls"):
                time.sleep(1)
                archivo = os.path.join(DESC, f)
        time.sleep(0.5)
    xls = open(archivo, encoding="utf-8", errors="replace").read() if archivo else ""
    ok("C5 el balance cuadra en pantalla y se descarga a Excel",
       "Cuadra" in tx and "NO CUADRA" not in tx and "1.1.2.10.010" in tx and "Balance de comprobaci" in xls
       and "1.1.2.10.010" in xls, ("Cuadra" in tx, "1.1.2.10.010" in tx, archivo, os.listdir(DESC), xls[:120]))

    # C6
    abre(52, '!!document.getElementById("P52_ANIO")')
    nav.js('spxPeriodo("CERRAR", %d, true)' % HOY.month)
    acepta_dialogo()
    nav.esperar('document.readyState === "complete" && /Mes cerrado/.test(document.body.innerText)', 40)
    e1 = uno("select max(estado) from ctb_periodos where id_empresa = :e and anio = :a and mes = :m", e=E, a=HOY.year, m=HOY.month)
    foto("contabilidad_cierre")
    nav.js('spxPeriodo("REABRIR", %d, true)' % HOY.month)
    acepta_dialogo()
    nav.esperar('document.readyState === "complete" && /Mes reabierto/.test(document.body.innerText)', 40)
    e2 = uno("select max(estado) from ctb_periodos where id_empresa = :e and anio = :a and mes = :m", e=E, a=HOY.year, m=HOY.month)
    ok("C6 cerrar y reabrir el mes", e1 == "CERRADO" and e2 == "ABIERTO", (e1, e2))

    # C8 contabilizar el mes desde la pantalla (la empresa temporal no tiene documentos: 0 asientos)
    nav.js('spxPeriodo("CONTABILIZAR", %d, true)' % HOY.month)
    acepta_dialogo()
    nav.esperar('document.readyState === "complete" && /Contabilizado:/.test(document.body.innerText)', 60)
    tx = texto()
    ok("C8 Contabilizar el mes responde con el resumen", "Contabilizado: 0 asientos nuevos" in tx, tx[:200])

    # C9 estados financieros: resultados (venta de 100 de C3) y balance general, mas su Excel
    abre(53, '!!document.getElementById("P53_LIBRO")')
    nav.js('apex.item("P53_LIBRO").setValue("RESULTADOS");apex.item("P53_DESDE").setValue("01/01/%d");'
           'apex.item("P53_HASTA").setValue("31/12/%d");' % (HOY.year, HOY.year))
    nav.js('document.getElementById("B43000000000002376").click()')
    nav.esperar('document.readyState === "complete" && /DEL PER/.test(document.body.innerText)', 40)
    time.sleep(2)
    tx_r = texto()
    foto("contabilidad_resultados")
    nav.js('document.getElementById("B43000000000002377").click()')
    arch = None
    fin = time.time() + 40
    while time.time() < fin and not arch:
        for f in os.listdir(DESC):
            if f.startswith("estado-resultados-") and f.endswith(".xls"):
                time.sleep(1)
                arch = f
        time.sleep(0.5)
    abre(53, '!!document.getElementById("P53_LIBRO")')
    nav.js('apex.item("P53_LIBRO").setValue("SITUACION");')
    nav.js('document.getElementById("B43000000000002376").click()')
    nav.esperar('document.readyState === "complete" && /CUADRA|Cuadra/.test(document.body.innerText)', 40)
    time.sleep(2)
    tx_s = texto()
    foto("contabilidad_situacion")
    ok("C9 estado de resultados (utilidad 100), balance general cuadrado y Excel",
       "UTILIDAD DEL PER" in tx_r and "Cuadra: activo" in tx_s and arch is not None,
       (tx_r[-160:], tx_s[-160:], arch))

    # C10 pago al SENIAT sin nada pendiente: no se registra y lo explica
    abre(52, '!!document.getElementById("P52_SEN_MONTO")')
    nav.js('apex.item("P52_SEN_MONTO").setValue("10");apex.item("P52_SEN_REF").setValue("PRUEBA");')
    nav.js('document.getElementById("B43000000000002408").click()')
    acepta_dialogo()
    nav.esperar('document.readyState === "complete" && /supera lo pendiente/.test(document.body.innerText)', 40)
    n_sen = uno("select count(*) from ctb_asientos where id_empresa = :e and doc_tipo = 'SENIAT'", e=E)
    foto("contabilidad_seniat")
    ok("C10 el pago al SENIAT no deja pagar mas de lo pendiente", "supera lo pendiente" in texto() and n_sen == 0, n_sen)

    # C11 cierre anual del ano en curso
    abre(52, '!!document.getElementById("P52_ANIO")')
    nav.js('document.getElementById("B43000000000002400").click()')
    acepta_dialogo()
    nav.esperar('document.readyState === "complete" && /Ejercicio cerrado/.test(document.body.innerText)', 40)
    n_ci = uno("select count(*) from ctb_asientos where id_empresa = :e and origen = 'CIERRE' and estado = 'CONFIRMADO'", e=E)
    ok("C11 el cierre anual crea su asiento", n_ci == 1, n_ci)
    nav.cerrar()

    # C7
    nav = aud.Nav(puerto=9312)
    aud.USUARIO = "diag.ctbfac"
    ses = aud.entrar(nav)
    abre(50, 'document.readyState === "complete"')
    tx = texto()
    ok("C7 FACTURACION no entra al plan de cuentas", "No tiene permisos" in tx, tx[:150])
finally:
    nav.cerrar()
    limpia()
    con.close()

print("\nRESULTADO: FALLAS=%d" % len(fallas))
for f in fallas:
    print("  - " + f)
sys.exit(1 if fallas else 0)
