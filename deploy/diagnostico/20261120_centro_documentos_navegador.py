#!/usr/bin/env python3
# =============================================================================
# 20261120_centro_documentos_navegador.py
#
# Centro de documentos (pagina 17): comprueba con navegador real que el
# informe une VENTAS y COMPRAS y que el filtro de modulo funciona.
#
#   C1  la pagina abre con el filtro «Modulo» en Todos
#   C2  con Todos salen filas de los dos modulos (insignias Venta y Compra)
#   C3  la venta F-1042 sigue mostrando su saldo (se compara con la base)
#   C4  la compra del proveedor 1 sale con su «Ver» a la pagina 28
#   C5  la compra no ofrece «Imprimir» (la celda queda vacia) y la venta si
#   C6  los totales del periodo traen una fila de Venta y otra de Compra
#   C7  con modulo Ventas no queda ninguna fila de Compra
#   C8  con modulo Compras solo quedan compras y los totales solo de Compra
#   C9  con modulo Compras el filtro «Cliente» no recorta (es de ventas)
#
# Deja las capturas a 1440 px:
#   deploy/resultados/20261120_documentos_todos.png
#   deploy/resultados/20261120_documentos_ventas.png
#   deploy/resultados/20261120_documentos_compras.png
#
# Uso:  python deploy/diagnostico/20261120_centro_documentos_navegador.py
# Sale con codigo 1 si algo falla.
# =============================================================================
import base64
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.request

import oracledb
import websocket

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
BASE = "https://gfd7e2575d251ae-sypexsql.adb.mx-monterrey-1.oraclecloudapps.com/ords"
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(REPO, "deploy", "conexion"))
from verificar_conexion import CONNECT_STRING as CS, credenciales  # noqa: E402

USUARIO, CLAVE = "diag.docs", "Diag#2026"
SALIDA = os.path.join(REPO, "deploy", "resultados")
fallas = 0


def comprueba(ok, texto, detalle=""):
    global fallas
    print("  [%s] %s%s" % ("OK   " if ok else "FALLA", texto,
                           "" if not detalle else " (%s)" % detalle))
    if not ok:
        fallas += 1


class Nav:
    def __init__(self, puerto=9311):
        self.proc = subprocess.Popen(
            [EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
             "--window-size=1440,1000",
             "--remote-debugging-port=%d" % puerto,
             "--user-data-dir=%s" % os.path.join(tempfile.gettempdir(), "opencode", "edge-docs"),
             "about:blank"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        objetivo = None
        for _ in range(40):
            try:
                lista = json.loads(urllib.request.urlopen(
                    "http://127.0.0.1:%d/json/list" % puerto, timeout=2).read())
                pag = [t for t in lista if t.get("type") == "page"]
                if pag:
                    objetivo = pag[0]
                    break
            except Exception:
                pass
            time.sleep(0.5)
        self.ws = websocket.create_connection(objetivo["webSocketDebuggerUrl"], timeout=60)
        self.n = 0
        self.cmd("Page.enable")
        self.cmd("Runtime.enable")

    def cmd(self, method, **params):
        self.n += 1
        self.ws.send(json.dumps({"id": self.n, "method": method, "params": params}))
        while True:
            r = json.loads(self.ws.recv())
            if r.get("id") == self.n:
                return r.get("result", {})

    def js(self, expr):
        r = self.cmd("Runtime.evaluate", expression=expr, returnByValue=True, awaitPromise=True)
        if "exceptionDetails" in r:
            return "EXC: " + str(r["exceptionDetails"].get("exception", {}).get("description"))[:300]
        return r.get("result", {}).get("value")

    def esperar(self, cond, seg=40):
        fin = time.time() + seg
        while time.time() < fin:
            if self.js(cond):
                return True
            time.sleep(0.5)
        return False

    def tamano(self, ancho, alto):
        self.cmd("Emulation.setDeviceMetricsOverride", width=ancho, height=alto,
                 deviceScaleFactor=1, mobile=False)

    def captura(self, ruta):
        r = self.cmd("Page.captureScreenshot", format="png")
        datos = r.get("data")
        if not datos:
            return False
        with open(ruta, "wb") as fh:
            fh.write(base64.b64decode(datos))
        return True

    def cerrar(self):
        try:
            self.proc.terminate()
        except Exception:
            pass


conn = oracledb.connect(user=credenciales()["DB_USER"], password=credenciales()["DB_PASSWORD"], dsn=CS)
cur = conn.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")

# --- datos de control sacados de la base (no escritos a mano)
cur.execute("""select f.folio_factura, fn_saldo_factura(f.id_factura)
                 from facturas f
                where f.id_empresa = 1 and f.tipo_documento = 'FAC'
                  and f.estado <> 'ANULADA'
                  and fn_saldo_factura(f.id_factura) is not null
                order by f.id_factura desc fetch first 1 rows only""")
FOLIO_VENTA, SALDO_VENTA = cur.fetchone()
cur.execute("""select co.folio_factura, p.razon_social, co.id_compra
                 from compras co join proveedores p on p.id_proveedor = co.id_proveedor
                where co.id_empresa = 1 and co.estado <> 'ANULADA'
                order by co.id_compra fetch first 1 rows only""")
FOLIO_COMPRA, PROVEEDOR, ID_COMPRA = cur.fetchone()
print("  venta de prueba:", FOLIO_VENTA, "saldo", SALDO_VENTA)
print("  compra de prueba:", FOLIO_COMPRA, PROVEEDOR, "id", ID_COMPRA)

cur.execute("delete from syn_login_log where upper(usuario_intentado) = 'DIAG.DOCS'")
cur.execute("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario "
            "where upper(username) = 'DIAG.DOCS'); commit; "
            "delete from usuario where upper(username) = 'DIAG.DOCS'; commit; end;")
cur.execute("""insert into usuario (username, email, password_hash, estado, id_empresa, rol_id,
                                    debe_cambiar_clave, reintentos_fallidos)
               values ('diag.docs', 'diag.docs@synpex.local', sypex_hash_password('Diag#2026'),
                       'ACTIVO', 1, (select id_rol from syn_roles where codigo_rol = 'ADMIN'), 'N', 0)""")
conn.commit()

nav = Nav()
try:
    nav.tamano(1440, 1000)
    nav.js('window.location.href="%s/f?p=100:9999"' % BASE)
    nav.esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(1)
    nav.js('(function(){apex.item("P9999_USERNAME").setValue(%s);apex.item("P9999_PASSWORD").setValue(%s);'
           'var b=[...document.querySelectorAll("button")].find(x=>/sign in|iniciar|entrar/i.test(x.innerText));'
           'if(b){b.click();}})()' % (json.dumps(USUARIO), json.dumps(CLAVE)))
    time.sleep(8)
    m = re.search(r"session=(\d+)", nav.js("window.location.href") or "")
    if not m:
        print("FALLO el login:", (nav.js("document.body.innerText") or "")[:200])
        raise SystemExit(1)
    ses = m.group(1)

    nav.js('window.location.href="%s/f?p=100:17:%s"' % (BASE, ses))
    nav.esperar('!!document.getElementById("P17_MODULO")', 60)
    time.sleep(4)

    # --- C1
    comprueba(nav.js('(apex.item("P17_MODULO")||{}).getValue ? apex.item("P17_MODULO").getValue() : "?"')
              == "TODOS", "la pagina abre con el filtro Modulo en Todos",
              str(nav.js('apex.item("P17_MODULO").getValue()')))

    def filas():
        return nav.js("""(function(){
            return [...document.querySelectorAll('table.a-IRR-table tbody tr')]
              .filter(function(tr){ return !!tr.querySelector('span.status-badge'); })
              .map(function(tr){
                return {texto: tr.innerText.replace(/\\s+/g,' '),
                        enlaces:[...tr.querySelectorAll('a')].map(function(a){
                            return decodeURIComponent(a.getAttribute('href')||'');})};
            });})()""") or []

    def totales():
        return nav.js('(document.getElementById("R43000000000000547")||{}).innerText') or ""

    def cambia(modulo):
        nav.js('apex.item("P17_MODULO").setValue("%s"); apex.submit({request:"APLICAR", showWait:true});'
               % modulo)
        nav.esperar('document.readyState === "complete" && !!window.apex', 60)
        nav.esperar('!!document.getElementById("P17_MODULO")', 60)
        time.sleep(4)

    # --- TODOS
    r = filas()
    ventas = [f for f in r if "Venta" in f["texto"]]
    compras = [f for f in r if "Compra" in f["texto"]]
    comprueba(bool(ventas) and bool(compras),
              "con Todos salen filas de los dos modulos",
              "ventas=%d compras=%d" % (len(ventas), len(compras)))

    fila_v = next((f for f in ventas if FOLIO_VENTA in f["texto"]), None)
    esperado = "%.2f" % float(SALDO_VENTA)
    comprueba(fila_v is not None and esperado in fila_v["texto"].replace(",", ""),
              "la venta %s conserva su saldo" % FOLIO_VENTA,
              (fila_v or {}).get("texto", "")[:150])

    fila_c = next((f for f in compras if PROVEEDOR in f["texto"]), None)
    comprueba(fila_c is not None, "la compra de %s sale en el informe" % PROVEEDOR,
              (fila_c or {}).get("texto", "")[:150])
    comprueba(fila_c is not None and any("p28_id_compra=%d" % ID_COMPRA in h for h in fila_c["enlaces"]),
              "el «Ver» de la compra abre la pagina 28",
              str((fila_c or {}).get("enlaces", []))[:150])
    comprueba(fila_c is not None and not any("p11_id_factura" in h for h in fila_c["enlaces"]),
              "la compra no ofrece «Imprimir»",
              str((fila_c or {}).get("enlaces", []))[:150])
    comprueba(fila_v is not None and any("p11_id_factura" in h for h in fila_v["enlaces"]),
              "la venta si ofrece «Imprimir»",
              str((fila_v or {}).get("enlaces", []))[:150])

    t = totales()
    comprueba("Venta" in t and "Compra" in t,
              "los totales traen fila de Venta y de Compra", t.replace("\n", " / ")[:160])
    nav.captura(os.path.join(SALIDA, "20261120_documentos_todos.png"))

    # --- VENTAS
    cambia("VENTAS")
    r = filas()
    comprueba(all("Venta" in f["texto"] for f in r) and bool(r),
              "con modulo Ventas no queda ninguna compra", "%d filas" % len(r))
    t = totales()
    comprueba("Venta" in t and "Compra" not in t,
              "los totales con Ventas solo suman ventas", t.replace("\n", " / ")[:160])
    nav.captura(os.path.join(SALIDA, "20261120_documentos_ventas.png"))

    # --- COMPRAS
    cambia("COMPRAS")
    r = filas()
    comprueba(all("Compra" in f["texto"] for f in r) and bool(r),
              "con modulo Compras solo quedan compras", "%d filas" % len(r))
    t = totales()
    comprueba("Compra" in t and "Venta" not in t,
              "los totales con Compras solo suman compras", t.replace("\n", " / ")[:160])
    nav.captura(os.path.join(SALIDA, "20261120_documentos_compras.png"))

    # --- C9: el filtro Cliente no recorta las compras (es de ventas)
    nav.js('apex.item("P17_CLIENTE").setValue("1"); apex.submit({request:"APLICAR", showWait:true});')
    nav.esperar('document.readyState === "complete" && !!window.apex', 60)
    time.sleep(4)
    r2 = filas()
    comprueba(len(r2) == len(r),
              "con modulo Compras el filtro Cliente no recorta",
              "antes %d, ahora %d" % (len(r), len(r2)))
finally:
    nav.cerrar()
    try:
        cur.execute("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario "
                    "where upper(username) = 'DIAG.DOCS'); commit; "
                    "delete from usuario where upper(username) = 'DIAG.DOCS'; commit; end;")
        conn.commit()
    except Exception:
        pass
    conn.close()

print("\nRESULTADO: FALLAS=%d" % fallas)
sys.exit(1 if fallas else 0)
