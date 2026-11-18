"""El atajo «Cobrar» en la lista (8) y en la factura (9), con navegador real.

Comprueba:
  C1  en la lista, la factura TIMBRADA con saldo muestra «Cobrar»
  C2  una PENDIENTE no muestra «Cobrar»
  C3  el enlace lleva y abre la 25 con ESA factura cargada
  C4  en el dialogo de una factura cobrable sale el boton «Cobrar»
  C5  en el de una PENDIENTE no sale

Uso:  python deploy/diagnostico/20261119_cobrar_atajo_navegador.py
Sale con codigo 1 si hay fallas. Crea y borra su propio usuario temporal.
"""
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

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.path.insert(0, r"C:\Users\luism\OneDrive\Documents\Apex_luis\deploy\conexion")
from verificar_conexion import CONNECT_STRING, credenciales

EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
BASE = "https://gfd7e2575d251ae-sypexsql.adb.mx-monterrey-1.oraclecloudapps.com/ords"
REPO = r"C:\Users\luism\OneDrive\Documents\Apex_luis"
USUARIO, CLAVE = "diag.cobrar", "Diag#2026"
fallas = 0


def comprobar(texto, ok, detalle=""):
    global fallas
    print(("  OK  " if ok else "  MAL ") + texto + ("" if ok else " " + str(detalle)))
    if not ok:
        fallas += 1


c = credenciales()
con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")
cur.execute("begin delete from usuario_empresa where usuario_id in "
            "(select usuario_id from usuario where upper(username)='DIAG.COBRAR'); commit; "
            "delete from usuario where upper(username)='DIAG.COBRAR'; commit; end;")
cur.execute("""insert into usuario (username,email,password_hash,estado,id_empresa,rol_id,
                 debe_cambiar_clave,reintentos_fallidos)
               values ('diag.cobrar','diag.cobrar@synpex.local',
                 sypex_hash_password('Diag#2026'),'ACTIVO',1,
                 (select id_rol from syn_roles where codigo_rol='ADMIN'),'N',0)""")
con.commit()

cur.execute("""select f.id_factura, f.folio_factura, f.estado
                 from facturas f
                where f.id_empresa = 1 and f.tipo_documento = 'FAC'
                  and f.estado in ('TIMBRADA', 'PARCIAL')
                  and fn_saldo_factura(f.id_factura) > 0.01
                order by f.id_factura desc fetch first 1 rows only""")
cobrable = cur.fetchone()
cur.execute("""select f.id_factura, f.folio_factura
                 from facturas f
                where f.id_empresa = 1 and f.estado = 'PENDIENTE'
                order by f.id_factura desc fetch first 1 rows only""")
pendiente = cur.fetchone()
con.close()
print("  cobrable:", cobrable, " pendiente:", pendiente)

proc = subprocess.Popen([EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
                         "--remote-debugging-port=9297", "--window-size=1440,900",
                         "--user-data-dir=" + os.path.join(tempfile.gettempdir(), "opencode", "edge-cobrar"),
                         "about:blank"],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def obj():
    for _ in range(40):
        try:
            l = json.loads(urllib.request.urlopen("http://127.0.0.1:9297/json/list", timeout=2).read())
            p = [t for t in l if t.get("type") == "page"]
            if p:
                return p[0]
        except Exception:
            pass
        time.sleep(0.5)


import websocket
ws = websocket.create_connection(obj()["webSocketDebuggerUrl"], timeout=60)
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
        return "EXC: " + str(r["exceptionDetails"].get("exception", {}).get("description"))[:160]
    return r.get("result", {}).get("value")


def esperar(c_, s=40):
    f = time.time() + s
    while time.time() < f:
        if js(c_):
            return True
        time.sleep(0.5)
    return False


def celda_cobrar(ident):
    return js('(function(){var tr=document.querySelector(\'tr[data-id="' + str(ident) + '"]\');'
              'if(!tr){return "SIN FILA";}'
              'var td=tr.querySelector(\'td[headers*="43000000000000898"]\');'
              'return td ? (td.innerText || "").trim() : "SIN CELDA";})()')


try:
    js('window.location.href="' + BASE + '/f?p=100:9999"')
    esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(1)
    js('(function(){apex.item("P9999_USERNAME").setValue(' + json.dumps(USUARIO) +
       ');apex.item("P9999_PASSWORD").setValue(' + json.dumps(CLAVE) + ');'
       'var b=[...document.querySelectorAll("button")].find(x=>/sign in|iniciar|entrar/i.test(x.innerText));'
       'if(b){b.click();}})()')
    time.sleep(8)
    m = re.search(r"session=(\d+)", js("window.location.href") or "")
    if not m:
        print("  MAL login fallido")
        raise SystemExit(1)
    ses = m.group(1)

    # C1 / C2: la lista
    js('window.location.href="' + BASE + '/f?p=100:8:' + ses + '"')
    esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(4)
    print("  celda de la cobrable:", repr(celda_cobrar(cobrable[0])))
    print("  celda de la pendiente:", repr(celda_cobrar(pendiente[0])))
    comprobar("C1 la factura cobrable muestra Cobrar", "Cobrar" in str(celda_cobrar(cobrable[0])))
    comprobar("C2 la PENDIENTE no muestra Cobrar", "Cobrar" not in str(celda_cobrar(pendiente[0])))

    # C3: el enlace abre el dialogo con esa factura
    marca = "p25_id_factura%3D" + str(cobrable[0])
    sel = ('[...document.querySelectorAll("a[href*=a-dialog-open]")]'
           '.find(function(x){return x.getAttribute("href").indexOf("' + marca + '")>=0;})')
    enlace = js('(function(){var a=' + sel + ';return a ? a.getAttribute("href") : "SIN ENLACE";})()')
    comprobar("C3 el enlace lleva la factura " + str(cobrable[0]), marca in str(enlace))
    js('(function(){var a=' + sel + ';if(a){a.click();}})()')
    time.sleep(7)
    dentro = js('(function(){var f=document.querySelector("iframe");'
                'if(!f){return "SIN DIALOGO";}'
                'var d=f.contentWindow.document;'
                'var s=d.getElementById("P25_ID_FACTURA");'
                'return s ? s.value : "SIN CAMPO";})()')
    comprobar("C3b el dialogo abre con la factura cargada", str(cobrable[1]) in str(dentro),
              "(" + str(dentro) + ")")
    js('apex.navigation.dialog.close(true);')
    time.sleep(2)

    # C4 / C5: el boton en la 9
    def abrir_factura(id_factura):
        js('window.location.href="' + BASE + '/f?p=100:8:' + ses + '"')
        esperar('document.readyState === "complete" && !!window.apex')
        time.sleep(3)
        marca9 = "p9_id_factura=" + str(id_factura)
        js('(function(){var m=' + json.dumps(marca9) + ';'
           'var a=[...document.querySelectorAll(\'a[href*="p9_id_factura"]\')]'
           '.find(function(x){return decodeURIComponent(x.getAttribute("href")||"").indexOf(m)>=0;});'
           'if(a){a.click();return "CLIC";}return "NO";})()')
        time.sleep(7)
        return js('(function(){var f=document.querySelector("iframe");'
                  'if(!f){return "SIN DIALOGO";}'
                  'var b=f.contentWindow.document.querySelector(\'[data-otel-label="BTN_COBRAR"]\');'
                  'if(!b){return "NO";}'
                  'return b.offsetParent === null ? "OCULTO" : "VISIBLE";})()')

    r1 = abrir_factura(cobrable[0])
    comprobar("C4 en una factura cobrable sale el boton Cobrar", r1 == "VISIBLE", "(" + str(r1) + ")")
    png = cmd("Page.captureScreenshot", format="png")["data"]
    ruta = os.path.join(REPO, "deploy", "resultados", "20261119_cobrar_p9.png")
    with open(ruta, "wb") as f:
        f.write(base64.b64decode(png))
    print("  captura:", ruta)
    js('apex.navigation.dialog.close(true);')
    time.sleep(2)

    r2 = abrir_factura(pendiente[0])
    comprobar("C5 en una factura PENDIENTE no sale", r2 in ("NO", "OCULTO"), "(" + str(r2) + ")")

finally:
    proc.terminate()
    con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
    cur = con.cursor()
    cur.execute("alter session set current_schema = WKSP_SYPEXWS")
    cur.execute("begin delete from usuario_empresa where usuario_id in "
                "(select usuario_id from usuario where upper(username)='DIAG.COBRAR'); commit; "
                "delete from usuario where upper(username)='DIAG.COBRAR'; commit; end;")
    con.commit()
    con.close()

print()
print("RESULTADO: FALLAS=" + str(fallas))
sys.exit(1 if fallas else 0)
