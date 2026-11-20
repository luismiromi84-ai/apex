#!/usr/bin/env python3
"""Pagina 17 «Facturas y notas»: reporte de documentos del periodo.

Comprueba con un navegador real (Edge headless por CDP):
  - la pagina responde y pinta el Interactive Report con sus columnas;
  - el saldo de una factura con notas coincide con la base;
  - «Imprimir» apunta a la 11 con su cs y «Ver» a la 9;
  - un filtro de fechas futuro deja el informe vacio;
  - CONSULTA entra y VENTAS recibe «No tiene permisos para esta pagina.».

Uso:  python deploy/diagnostico/20261116_reporte_documentos_pagina.py
Sale con codigo 1 si algo falla.
"""
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.request

import websocket

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
BASE = "https://gfd7e2575d251ae-sypexsql.adb.mx-monterrey-1.oraclecloudapps.com/ords"
REPO = r"C:\Users\luism\OneDrive\Documents\Apex_luis"
sys.path.insert(0, os.path.join(REPO, "deploy", "conexion"))
import oracledb
from verificar_conexion import CONNECT_STRING, credenciales

USUARIO, CLAVE = "diag.reporte", "Diag#2026"
VENTAS, CLAVE_V = "diag.reporte.v", "Diag#2026"
CONSULTA, CLAVE_C = "diag.reporte.c", "Diag#2026"
fallas = 0


def comprueba(ok, texto, detalle=""):
    global fallas
    print("  [%s] %s%s" % ("OK   " if ok else "FALLA", texto,
                           "" if not detalle else " (%s)" % detalle))
    if not ok:
        fallas += 1


def numero(txt):
    """'1.392,00' o '1,392.00' -> 1392.0"""
    t = re.sub(r"[^0-9,.\-]", "", (txt or "").replace("\u00a0", ""))
    if not t or not re.search(r"\d", t):
        return None
    if "," in t and "." in t:
        if t.rfind(",") > t.rfind("."):
            t = t.replace(".", "").replace(",", ".")
        else:
            t = t.replace(",", "")
    elif "," in t:
        t = t.replace(".", "").replace(",", ".")
    try:
        return float(t)
    except ValueError:
        return None


c = credenciales()
con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")

# Factura con notas (no anuladas) para comparar el saldo.
cur.execute("""select f.folio_factura,
                      f.monto_total - (select nvl(sum(n.monto_total), 0)
                                         from facturas n
                                        where n.id_factura_origen = f.id_factura
                                          and n.id_empresa = f.id_empresa
                                          and n.tipo_documento = 'NC'
                                          and n.estado <> 'ANULADA') as saldo
                 from facturas f
                where f.tipo_documento = 'FAC'
                  and f.estado <> 'ANULADA'
                  and exists (select 1 from facturas n
                               where n.id_factura_origen = f.id_factura
                                 and n.id_empresa = f.id_empresa
                                 and n.tipo_documento = 'NC'
                                 and n.estado <> 'ANULADA')
                order by f.id_factura desc fetch first 1 rows only""")
fila = cur.fetchone()
if not fila:
    sys.exit("no hay facturas con notas para probar el saldo")
FOLIO, SALDO = fila[0], float(fila[1])
print("  factura de prueba:", FOLIO, "saldo", SALDO)

for u, rol in ((USUARIO, "ADMIN"), (VENTAS, "VENTAS"), (CONSULTA, "CONSULTA")):
    cur.execute("begin delete from usuario_empresa where usuario_id in "
                "(select usuario_id from usuario where upper(username)=upper(:u)); commit; "
                "delete from usuario where upper(username)=upper(:u); commit; end;", u=u)
    cur.execute("""insert into usuario (username,email,password_hash,estado,id_empresa,rol_id,
                                         debe_cambiar_clave,reintentos_fallidos)
                   values (:u,:e,sypex_hash_password(:p),'ACTIVO',1,
                           (select id_rol from syn_roles where codigo_rol=:r),'N',0)""",
                u=u, e=u + "@synpex.local", p=CLAVE, r=rol)
con.commit()

proc = subprocess.Popen([EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
                         "--remote-debugging-port=9301",
                         "--user-data-dir=%s" % os.path.join(tempfile.gettempdir(),
                                                             "opencode", "edge-rep"),
                         "about:blank"],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def objetivo():
    for _ in range(40):
        try:
            lista = json.loads(urllib.request.urlopen(
                "http://127.0.0.1:9301/json/list", timeout=2).read())
            paginas = [t for t in lista if t.get("type") == "page"]
            if paginas:
                return paginas[0]
        except Exception:
            pass
        time.sleep(0.5)


ws = websocket.create_connection(objetivo()["webSocketDebuggerUrl"], timeout=60)
ws.settimeout(60)
n = [0]


def cmd(m, **p):
    n[0] += 1
    ws.send(json.dumps({"id": n[0], "method": m, "params": p}))
    while True:
        r = json.loads(ws.recv())
        if r.get("id") == n[0]:
            return r.get("result", {})


for m in ("Page.enable", "Runtime.enable"):
    cmd(m)


def js(e):
    r = cmd("Runtime.evaluate", expression=e, returnByValue=True, awaitPromise=True)
    if "exceptionDetails" in r:
        return "EXC: " + str(r["exceptionDetails"].get("exception", {}).get("description"))[:200]
    return r.get("result", {}).get("value")


def esperar(cond, s=40):
    f = time.time() + s
    while time.time() < f:
        if js(cond):
            return True
        time.sleep(0.5)
    return False


def entrar(u, clave, pagina):
    js('window.location.href="%s/f?p=100:9999"' % BASE)
    esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(1)
    js('(function(){apex.item("P9999_USERNAME").setValue(%s);apex.item("P9999_PASSWORD").setValue(%s);'
       'var b=[...document.querySelectorAll("button")].find(x=>/sign in|iniciar|entrar/i.test(x.innerText));if(b){b.click();}})()'
       % (json.dumps(u), json.dumps(clave)))
    time.sleep(7)
    m = re.search(r"session=(\d+)", js("window.location.href") or "")
    if not m:
        return None
    ses = m.group(1)
    js('window.location.href="%s/f?p=100:%d:%s"' % (BASE, pagina, ses))
    return ses


try:
    ses = entrar(USUARIO, CLAVE, 17)
    if not ses:
        sys.exit("login fallido")
    if not esperar('document.readyState === "complete" && !!document.getElementById("P17_TIPO")'):
        sys.exit("la pagina 17 no pinto los filtros")
    time.sleep(3)

    html = js("document.body.innerHTML") or ""
    # El titulo cambio el 2026-11-18 a «Reportes Factura y Notas C/D»: se comprueba
    # que nombre el reporte (factura + nota) sin atarlo a la frase exacta.
    titulo = (js("document.title") or "").lower()
    comprueba("factura" in titulo and "nota" in titulo,
              "el titulo nombra el reporte de facturas y notas", repr(js("document.title")))
    texto = js("document.body.innerText") or ""
    for col in ("Folio", "Tipo", "Cliente", "Total", "Saldo", "Estado"):
        comprueba(col in texto, "la columna «%s» esta" % col)

    # Totales del período: la tarjeta sale y su saldo en USD cuadra con la base.
    if not esperar('(document.getElementById("R43000000000000547")||{}).innerText && '
                   'document.getElementById("R43000000000000547").innerText.indexOf("USD") >= 0', 40):
        comprueba(False, "la region «Totales del período» no pinto el bloque de USD",
                  ((js("(document.getElementById('R43000000000000547')||{}).innerText") or "")
                   or texto)[:120].replace("\n", " / "))
    else:
        cur.execute("""select nvl(sum(case when f.tipo_documento = 'NC' then -f.monto_total
                                           else f.monto_total end), 0)
                         from facturas f
                        where f.id_empresa = 1
                          and f.cod_moneda = 'USD'
                          and f.estado <> 'ANULADA'
                          and f.fecha_emision >= trunc(sysdate, 'MM')""")
        esperado_tot = float(cur.fetchone()[0])
        cuerpo_tot = js("document.getElementById('R43000000000000547').innerText") or ""
        comprueba(("%.2f" % esperado_tot).replace(".", ".") in cuerpo_tot
                  or ("{:,.2f}".format(esperado_tot)) in cuerpo_tot,
                  "el saldo del período en USD cuadra con la base",
                  "esperado %.2f" % esperado_tot)

    fila_txt = js("""(function(){
        var trs=[...document.querySelectorAll('table.a-IRR-table tr')];
        for (var i=0;i<trs.length;i++){
          if (trs[i].innerText.indexOf(%s)>=0) return trs[i].innerText;
        }
        return '';
      })()""" % json.dumps(FOLIO))
    comprueba(bool(fila_txt), "la factura %s aparece en el informe" % FOLIO,
              (fila_txt or "")[:120].replace("\n", " / "))
    valores = [numero(x) for x in re.findall(r"-?[\d.,]+", fila_txt or "")]
    valores = [v for v in valores if v is not None]
    comprueba(any(abs(v - SALDO) < 0.01 for v in valores),
              "el saldo mostrado coincide con la base", "esperado %.2f" % SALDO)
    esperado = ("%.2f" % SALDO).replace(".", ".")
    comprueba(esperado in (fila_txt or "") or esperado.replace(".", ",") in (fila_txt or ""),
              "el saldo sale con formato de dos decimales", esperado)

    href_imp = js("""(function(){
        var a=[...document.querySelectorAll('a')].find(function(x){
          return /Imprimir/.test(x.innerText) && (x.getAttribute('href')||'').indexOf('p11_id_factura')>=0;});
        return a ? a.getAttribute('href') : '';})()""")
    comprueba("p11_id_factura" in (href_imp or "") and "cs=" in (href_imp or ""),
              "«Imprimir» lleva a la 11 con checksum", (href_imp or "")[:110])

    href_ver = js("""(function(){
        var a=[...document.querySelectorAll('a')].find(function(x){
          return /Ver/.test(x.innerText) && (x.getAttribute('href')||'').indexOf('p9_id_factura')>=0;});
        return a ? a.getAttribute('href') : '';})()""")
    comprueba("p9_id_factura" in (href_ver or ""), "«Ver» lleva a la 9", (href_ver or "")[:110])

    # El «Ver» tiene que abrir la factura en CONSULTA: detalle y sin Guardar.
    # Se abre la fila de la factura con notas (FOLIO), no la primera del informe.
    js("""(function(){
        var trs=[...document.querySelectorAll('table.a-IRR-table tr')];
        for (var i=0;i<trs.length;i++){
          if (trs[i].innerText.indexOf(%s)>=0){
            var a=trs[i].querySelector('a[href*="p9_id_factura"]');
            if(a){a.click(); return;}
          }
        }})()""" % json.dumps(FOLIO))
    time.sleep(6)
    dialogo = js("""(function(){
        var fs=[...document.querySelectorAll('iframe')];
        for (var i=0;i<fs.length;i++){
          try{ var d=fs[i].contentDocument;
               if(d && d.body && d.body.innerText.length>50){ return d.body.innerText; }
          }catch(e){}
        }
        return '';})()""")
    comprueba("Detalle de la factura" in (dialogo or ""),
              "«Ver» muestra el detalle de la factura", (dialogo or "")[:120].replace("\n", " / "))
    comprueba("Guardar" not in (dialogo or ""),
              "el modo consulta no muestra «Guardar»")
    comprueba("Imprimir" in (dialogo or ""),
              "el modo consulta ofrece «Imprimir»")
    comprueba("Líneas de la factura que acredita" not in (dialogo or ""),
              "el modo consulta no muestra el selector de líneas de la nota",
              (dialogo or "")[:150].replace("\n", " / "))
    pos_det = (dialogo or "").find("Detalle de la factura")
    pos_sal = (dialogo or "").find("Salir")
    comprueba(pos_det >= 0 and pos_sal > pos_det,
              "los botones quedan despues del detalle", "detalle=%d salir=%d" % (pos_det, pos_sal))
    solo_lectura = js("""(function(){
        var fs=[...document.querySelectorAll('iframe')];
        for (var i=0;i<fs.length;i++){
          try{ var d=fs[i].contentDocument;
               if(d && d.querySelector('[aria-readonly="true"]')){ return true; }
          }catch(e){}
        }
        return false;})()""")
    comprueba(solo_lectura is True, "los campos se ven en solo lectura")
    comprueba("Notas de esta factura" in (dialogo or "") and "NC-" in (dialogo or ""),
              "la factura muestra sus notas de crédito/débito",
              (dialogo or "")[:200].replace("\n", " / "))
    comprueba("92.70" in (dialogo or "") or "92,70" in (dialogo or ""),
              "el detalle sale con formato numerico", "92.70")
    comprueba("no data found" not in (dialogo or ""),
              "el detalle no muestra «no data found»")

    # Volver a la lista para el resto de la prueba.
    js('window.location.href="%s/f?p=100:17:%s"' % (BASE, ses))
    esperar('document.readyState === "complete" && !!document.getElementById("P17_TIPO")', 60)
    time.sleep(3)

    # Filtro futuro: sin filas.
    js('apex.item("P17_DESDE").setValue("01/01/2099")')
    js('apex.item("P17_HASTA").setValue("31/12/2099")')
    js('apex.submit({request:"APLICAR", showWait:true})')
    esperar('document.readyState === "complete" && !!window.apex', 60)
    time.sleep(3)
    filas = js("document.querySelectorAll('table.a-IRR-table tbody tr').length")
    texto2 = js("document.body.innerText") or ""
    comprueba((filas or 0) == 0 or "No hay documentos" in texto2,
              "un periodo futuro deja el informe vacio", str(filas))

    # Roles.
    entrar(CONSULTA, CLAVE_C, 17)
    esperar('document.readyState === "complete" && !!window.apex', 60)
    time.sleep(3)
    comprueba("factura" in (js("document.title") or "").lower()
              and "No tiene permisos" not in (js("document.body.innerText") or ""),
              "CONSULTA puede ver el reporte")

    entrar(VENTAS, CLAVE_V, 17)
    esperar('document.readyState === "complete" && !!window.apex', 60)
    time.sleep(3)
    comprueba("No tiene permisos para esta pagina" in (js("document.body.innerText") or ""),
              "VENTAS recibe «No tiene permisos para esta pagina.»")
finally:
    proc.terminate()
    for u in (USUARIO, VENTAS, CONSULTA):
        try:
            cur.execute("begin delete from usuario_empresa where usuario_id in "
                        "(select usuario_id from usuario where upper(username)=upper(:u)); commit; "
                        "delete from usuario where upper(username)=upper(:u); commit; end;", u=u)
        except Exception:
            pass
    con.commit()
    con.close()

print("\nRESULTADO: FALLAS=%d" % fallas)
sys.exit(1 if fallas else 0)
