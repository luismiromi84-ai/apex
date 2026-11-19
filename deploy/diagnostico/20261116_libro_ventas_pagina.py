#!/usr/bin/env python3
"""Pagina 18 «Libro de ventas»: comprueba en navegador real (Edge headless)

  - que pinte el informe con sus columnas y la region de totales;
  - que el Total Bs de una factura y el total del mes cuadren con la base;
  - que un mes sin documentos deje el informe vacio;
  - que CONSULTA entre y VENTAS reciba «No tiene permisos para esta pagina.».

Uso:  python deploy/diagnostico/20261116_libro_ventas_pagina.py
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

USUARIO, CLAVE = "diag.libro", "Diag#2026"
CONSULTA, CLAVE_C = "diag.libro.c", "Diag#2026"
VENTAS, CLAVE_V = "diag.libro.v", "Diag#2026"
fallas = 0


def comprueba(ok, texto, detalle=""):
    global fallas
    print("  [%s] %s%s" % ("OK   " if ok else "FALLA", texto,
                           "" if not detalle else " (%s)" % detalle))
    if not ok:
        fallas += 1


def numero(txt):
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

# Total Bs del mes (misma formula del libro) y el de una factura concreta.
cur.execute("""select round(nvl(sum(sg * nvl(d.total_bs, nvl(d.subtotal_bs, 0) + nvl(d.monto_impuesto, 0)
                          * nvl(d.tasa_cambio_aplicada, f.tipo_cambio))), 0), 2)
                 from (select f.id_factura, f.tipo_documento, f.estado, f.tipo_cambio,
                              case when f.estado = 'ANULADA' then 0 else 1 end
                                * case when f.tipo_documento = 'NC' then -1 else 1 end as sg
                         from facturas f
                        where f.id_empresa = 1
                          and f.fecha_emision >= trunc(sysdate, 'MM')
                          and f.fecha_emision <  add_months(trunc(sysdate, 'MM'), 1)) f
                 left join facturas_det d on d.id_factura = f.id_factura""")
TOTAL_MES = float(cur.fetchone()[0])

cur.execute("""select f.folio_factura,
                      round(nvl(sum(nvl(d.total_bs, nvl(d.subtotal_bs, 0) + nvl(d.monto_impuesto, 0)
                                   * nvl(d.tasa_cambio_aplicada, f.tipo_cambio))), 0), 2)
                 from facturas f
                 left join facturas_det d on d.id_factura = f.id_factura
                where f.id_empresa = 1 and f.tipo_documento = 'FAC'
                  and f.fecha_emision >= trunc(sysdate, 'MM')
                group by f.folio_factura
                order by f.folio_factura fetch first 1 rows only""")
fila = cur.fetchone()
FOLIO, TOTAL_FAC = fila[0], float(fila[1])
print("  mes: total %.2f · factura %s: %.2f" % (TOTAL_MES, FOLIO, TOTAL_FAC))

for u, rol in ((USUARIO, "ADMIN"), (CONSULTA, "CONSULTA"), (VENTAS, "VENTAS")):
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
                         "--remote-debugging-port=9302",
                         "--user-data-dir=%s" % os.path.join(tempfile.gettempdir(),
                                                             "opencode", "edge-libro"),
                         "about:blank"],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def objetivo():
    for _ in range(40):
        try:
            lista = json.loads(urllib.request.urlopen(
                "http://127.0.0.1:9302/json/list", timeout=2).read())
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


def entrar(u, clave, pagina=18):
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
    ses = entrar(USUARIO, CLAVE)
    if not ses:
        sys.exit("login fallido")
    if not esperar('document.readyState === "complete" && !!document.getElementById("P18_MES")'):
        sys.exit("la pagina 18 no pinto los filtros")
    time.sleep(3)

    comprueba("libro de compras y ventas" in (js("document.title") or "").lower(),
              "el titulo es «Libro de compras y ventas»", repr(js("document.title")))
    texto = js("document.body.innerText") or ""
    # Los rotulos de la pantalla llevan espacio antes del simbolo («Base 16 %»), asi
    # que se comparan sin espacios (2026-11-18).
    texto_plano = re.sub(r"\s+", "", texto)
    for col in ("Control", "Base 16%", "IVA 16%", "IGTF 3%", "Total Bs",
                "Documento afectado"):
        comprueba(re.sub(r"\s+", "", col) in texto_plano, "la columna «%s» esta" % col)

    fila_txt = js("""(function(){
        var trs=[...document.querySelectorAll('table.a-IRR-table tr')];
        for (var i=0;i<trs.length;i++){
          if (trs[i].innerText.indexOf(%s)>=0) return trs[i].innerText;
        }
        return '';})()""" % json.dumps(FOLIO))
    comprueba(bool(fila_txt), "la factura %s aparece" % FOLIO)
    valores = [numero(x) for x in re.findall(r"-?[\d.,]+", fila_txt or "")]
    valores = [v for v in valores if v is not None]
    comprueba(any(abs(v - TOTAL_FAC) < 0.02 for v in valores),
              "el Total Bs de la factura cuadra", "esperado %.2f" % TOTAL_FAC)

    if not esperar('(document.getElementById("R43000000000000730")||{}).innerText && '
                   'document.getElementById("R43000000000000730").innerText.length > 10', 40):
        comprueba(False, "la region «Totales del mes» no pinto")
    else:
        tot_txt = js("document.getElementById('R43000000000000730').innerText") or ""
        valores = [numero(x) for x in re.findall(r"-?[\d.,]+", tot_txt)]
        valores = [v for v in valores if v is not None]
        comprueba(any(abs(v - TOTAL_MES) < 0.05 for v in valores),
                  "el total del mes cuadra", "esperado %.2f" % TOTAL_MES)
        comprueba("Aviso" not in tot_txt, "el libro cuadra (sin aviso de diferencia)")

    # Mes sin documentos.
    js('apex.item("P18_MES").setValue("1")')
    js('apex.item("P18_ANIO").setValue("2020")')
    js('apex.submit({request:"APLICAR", showWait:true})')
    esperar('document.readyState === "complete" && !!window.apex', 60)
    time.sleep(3)
    filas = js("document.querySelectorAll('table.a-IRR-table tbody tr').length")
    texto2 = js("document.body.innerText") or ""
    comprueba((filas or 0) == 0 or "No hay documentos" in texto2,
              "un mes sin documentos deja el libro vacio", str(filas))

    entrar(CONSULTA, CLAVE_C)
    esperar('document.readyState === "complete" && !!window.apex', 60)
    time.sleep(3)
    comprueba("libro de compras y ventas" in (js("document.title") or "").lower()
              and "No tiene permisos" not in (js("document.body.innerText") or ""),
              "CONSULTA puede ver el libro")

    entrar(VENTAS, CLAVE_V)
    esperar('document.readyState === "complete" && !!window.apex', 60)
    time.sleep(3)
    comprueba("No tiene permisos para esta pagina" in (js("document.body.innerText") or ""),
              "VENTAS recibe «No tiene permisos para esta pagina.»")
finally:
    proc.terminate()
    for u in (USUARIO, CONSULTA, VENTAS):
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
