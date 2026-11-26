#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Revision de pantallas pedida por el duenio (2026-11-25), en navegador real y SIN modificar datos.

  R1 Facturacion (8): las facturas PAGADAS no salen en la lista (siguen en Reportes)
  R2 Libro (18): el estado lleva insignia de color
  R3 Libro (18): en una fila de venta la celda «Ver compra» queda vacia (y viceversa)
  R4 Compra impresa (39): boton «Volver a la compra» que regresa a la compra (28)
  R5 Kardex (43) filtrado por un articulo: sin «modelo de formato numerico no valido»
  R6 Panel (13): «Facturas por estado» usa los mismos estados que las listas (PROCESADA, no TIMBRADA)
  R7 Reportes (17): una sola columna «Ver» por fila (venta, compra o presupuesto) y estados en mayuscula
     con insignia
  R8 Recibo impreso (35): boton «Volver a Recibos»
  R9 Recibos (24): Desde y Hasta en la misma fila; Conciliado y Estado debajo, en la misma fila

Usa la empresa con mas documentos de Venezuela y un usuario temporal ADMIN.

    python deploy/diagnostico/20261125_revision_pantallas_navegador.py
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
omitidos = []


def ok(nombre, cond, det=""):
    print(("  OK   " if cond else "  FALLA") + " " + nombre + ("" if cond else "  -> " + str(det)[:240]))
    if not cond:
        fallas.append(nombre)


def omite(nombre, motivo):
    print("  [OMITIDO] " + nombre + ": " + motivo)
    omitidos.append(nombre)


c = aud.credenciales()
con = aud.oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=aud.CS)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")
cur.execute("""select e.id_empresa from empresas e where e.cod_pais = 'VE' and e.id_empresa < 900000
                order by (select count(*) from facturas f where f.id_empresa = e.id_empresa)
                       + (select count(*) from compras c where c.id_empresa = e.id_empresa) desc
                fetch first 1 rows only""")
EMP = cur.fetchone()[0]
cur.execute("""select max(k.id_producto_servicio) from kardex_mov k where k.id_empresa = :e""", e=EMP)
ART = cur.fetchone()[0]

U = "diag.revision"
BORRA = ("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario "
         "where upper(username)=upper(:u)); commit; delete from usuario where upper(username)=upper(:u); commit; end;")
cur.execute(BORRA, u=U)
cur.execute("""insert into usuario (username,email,password_hash,estado,id_empresa,rol_id,debe_cambiar_clave,reintentos_fallidos)
               values (:u,:m,sypex_hash_password(:p),'ACTIVO',:e,(select id_rol from syn_roles where codigo_rol='ADMIN'),'N',0)""",
            u=U, m=U + "@synpex.local", p=aud.CLAVE, e=EMP)
con.commit()

nav = aud.Nav(puerto=9316)


def abre(pag, esp='document.readyState === "complete" && !!window.apex'):
    nav.js('window.location.href="%s/f?p=100:%d:%s"' % (aud.BASE, pag, ses))
    nav.esperar(esp, 40)
    time.sleep(2.5)


def ve(url_js):
    nav.js("window.location.href=" + url_js)
    nav.esperar('document.readyState === "complete" && !!window.apex', 40)
    time.sleep(2.5)


def texto():
    return str(nav.js("document.body.innerText") or "")


try:
    aud.USUARIO = U
    ses = aud.entrar(nav)
    if not ses:
        sys.exit("login fallido")

    # R1
    abre(8)
    estados = nav.js('[...document.querySelectorAll(".status-badge")].map(function(b){return b.innerText.trim();}).join(",")')
    ok("R1 la lista de facturacion no muestra PAGADAS", "PAGADA" not in str(estados).split(","), estados)

    # R2 / R3
    abre(18, 'document.readyState === "complete" && document.querySelectorAll("table.a-IRR-table").length > 0')
    insignias = nav.js('document.querySelectorAll("table.a-IRR-table .status-badge").length')
    filas = nav.js('document.querySelectorAll("table.a-IRR-table tr").length')
    ok("R2 el estado del libro lleva insignia de color", (insignias or 0) > 0, (insignias, filas))
    malas = nav.js('''(function(){var n=0;document.querySelectorAll("table.a-IRR-table td a").forEach(function(a){
        var h=decodeURIComponent(a.getAttribute("href")||"");
        if (/p28_id_compra=(&|,|$)/.test(h) || /p9_id_factura=(&|,|$)/.test(h)) { n++; } });return n;})()''')
    ok("R3 ninguna celda del libro lleva un enlace sin documento", malas == 0, malas)

    # R7 (reportes) y de alli R4 (compra impresa)
    abre(17, 'document.readyState === "complete" && document.querySelectorAll("table.a-IRR-table").length > 0')
    cab = nav.js('[...document.querySelectorAll("table.a-IRR-table th")].map(function(h){return h.innerText.trim();}).join("|")')
    sin_ver = nav.js('''(function(){var n=0;document.querySelectorAll("table.a-IRR-table tr").forEach(function(tr,i){
        if(i===0){return;} if(tr.querySelectorAll("td").length && !tr.querySelector("td a[href]")){n++;} });return n;})()''')
    est = nav.js('[...document.querySelectorAll("table.a-IRR-table td")].filter(function(td){return td.querySelector(".status-dot");})'
                 '.map(function(td){return td.innerText.trim();}).join(",")')
    est_l = [x for x in str(est).split(",") if x and x not in ("Venta", "Compra", "Presupuesto")]
    ok("R7 una sola columna Ver en cada fila y estados en mayuscula con insignia",
       "Ver compra" not in str(cab) and "Ver presup" not in str(cab) and sin_ver == 0
       and est_l and all(x == x.upper() for x in est_l), (cab, sin_ver, est_l[:8]))
    url_compra = nav.js('''(function(){var a=[...document.querySelectorAll("table.a-IRR-table td a")].find(function(a){
        return /p28_id_compra=[0-9]/.test(decodeURIComponent(a.getAttribute("href")||""));});return a?a.href:"";})()''')
    if url_compra:
        ve('"%s"' % url_compra)
        nav.js('document.getElementById("B43000000000001716").click()')
        nav.esperar('document.readyState === "complete" && !!document.getElementById("B43000000000002393")', 40)
        time.sleep(2)
        hay = nav.js('!!document.getElementById("B43000000000002393")')
        nav.js('document.getElementById("B43000000000002393").click()')
        nav.esperar('document.readyState === "complete" && !!document.getElementById("B43000000000001716")', 40)
        vuelta = nav.js('apex.item("P28_ID_COMPRA").getValue()')
        ok("R4 la compra impresa vuelve a su compra", hay and str(vuelta).strip() != "", (hay, vuelta))
    else:
        omite("R4", "la empresa no tiene compras en Reportes")

    # R5
    if ART:
        abre(43, '!!document.getElementById("P43_ID_ARTICULO")')
        nav.js('apex.item("P43_ID_ARTICULO").setValue("%d");apex.item("P43_DESDE").setValue("");' % ART)
        nav.js('apex.submit({request:"FILTRAR"})')
        nav.esperar('document.readyState === "complete" && !!window.apex', 40)
        time.sleep(3)
        tx = texto()
        ok("R5 el kardex filtrado por articulo no da error de formato",
           "formato num" not in tx.lower() and "ORA-" not in tx, tx[-300:])
    else:
        omite("R5", "sin movimientos de kardex")

    # R6
    abre(13, 'document.readyState === "complete" && !!window.apex')
    time.sleep(4)
    tx = texto()
    ok("R6 el panel usa PROCESADA y no TIMBRADA", "TIMBRADA" not in tx, tx[:200])

    # R8 (desde la lista de recibos) y R9
    abre(24, '!!document.getElementById("P24_DESDE")')
    fila = nav.js('''(function(){function y(n){var e=document.getElementById(n+"_CONTAINER")||document.getElementById(n);
        return e?Math.round(e.getBoundingClientRect().top):-1;}
        return [y("P24_DESDE"),y("P24_HASTA"),y("P24_CONCILIADO"),y("P24_ESTADO")].join(",");})()''')
    ys = [int(x) for x in str(fila).split(",")]
    ok("R9 Desde/Hasta en una fila y Conciliado/Estado en la siguiente",
       ys[0] == ys[1] and ys[2] == ys[3] and ys[2] > ys[0] >= 0, fila)
    url_rec = nav.js('''(function(){var a=[...document.querySelectorAll("a[href]")].find(function(a){
        var h=decodeURIComponent(a.getAttribute("href")||"");return /p35_id_recibo=[0-9]/.test(h);});return a?a.href:"";})()''')
    if url_rec:
        ve('"%s"' % url_rec)
        nav.esperar('!!document.getElementById("B43000000000002394")', 30)
        ok("R8 el recibo impreso tiene «Volver a Recibos»", nav.js('!!document.getElementById("B43000000000002394")'))
    else:
        # al recibo impreso se llega desde el dialogo del recibo: se comprueba el boton en el diccionario
        cur.execute("""select count(*) from apex_application_page_buttons
                        where application_id = 100 and page_id = 35 and button_name = 'BTN_VOLVER'
                          and redirect_url like '%:24:%'""")
        ok("R8 el recibo impreso tiene «Volver a Recibos» (diccionario)", cur.fetchone()[0] == 1)
finally:
    nav.cerrar()
    cur.execute(BORRA, u=U)
    con.close()

print("\nRESULTADO: FALLAS=%d%s" % (len(fallas), (" OMITIDOS=%d" % len(omitidos)) if omitidos else ""))
for f in fallas:
    print("  - " + f)
sys.exit(1 if fallas else 0)
