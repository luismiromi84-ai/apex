#!/usr/bin/env python3
"""Captura el diálogo de presupuesto (7) para ver la rejilla.

Abre la lista de presupuestos (5), marca la primera fila con el botón «Editar» de
la columna y hace la captura del diálogo.
"""
import base64, json, os, re, subprocess, sys, tempfile, time, urllib.request
import websocket

EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
BASE = "https://gfd7e2575d251ae-sypexsql.adb.mx-monterrey-1.oraclecloudapps.com/ords"
REPO = r"C:\Users\luism\OneDrive\Documents\Apex_luis"
sys.path.insert(0, os.path.join(REPO, "deploy", "conexion"))
import oracledb
from verificar_conexion import CONNECT_STRING, credenciales

USUARIO, CLAVE = "diag.p7", "Diag#2026"
c = credenciales()
con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")
cur.execute("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario where upper(username)='DIAG.P7'); commit; delete from usuario where upper(username)='DIAG.P7'; commit; end;")
cur.execute("""insert into usuario (username,email,password_hash,estado,id_empresa,rol_id,debe_cambiar_clave,reintentos_fallidos)
 values ('diag.p7','diag.p7@synpex.local',sypex_hash_password('Diag#2026'),'ACTIVO',1,
 (select id_rol from syn_roles where codigo_rol='ADMIN'),'N',0)""")
con.commit()
con.close()

proc = subprocess.Popen([EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
                         "--remote-debugging-port=9304", "--window-size=1440,900",
                         f"--user-data-dir={os.path.join(tempfile.gettempdir(),'opencode','edge-p7')}",
                         "about:blank"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def obj():
    for _ in range(40):
        try:
            l = json.loads(urllib.request.urlopen("http://127.0.0.1:9304/json/list", timeout=2).read())
            p = [t for t in l if t.get("type") == "page"]
            if p:
                return p[0]
        except Exception:
            pass
        time.sleep(0.5)


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


try:
    js('window.location.href="%s/f?p=100:9999"' % BASE)
    esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(1)
    js('(function(){apex.item("P9999_USERNAME").setValue(%s);apex.item("P9999_PASSWORD").setValue(%s);'
       'var b=[...document.querySelectorAll("button")].find(x=>/sign in|iniciar|entrar/i.test(x.innerText));'
       'if(b){b.click();}})()' % (json.dumps(USUARIO), json.dumps(CLAVE)))
    time.sleep(8)
    ses = re.search(r"session=(\d+)", js("window.location.href")).group(1)

    js('window.location.href="%s/f?p=100:5:%s"' % (BASE, ses))
    esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(4)
    js('(function(){var a=document.querySelector(\'td a[href*="a-dialog-open"]\');if(a){a.click();}})()')
    abierto = esperar('(function(){var f=document.querySelector("iframe");'
                      'return !!(f&&f.contentWindow&&f.contentDocument&&'
                      'f.contentDocument.getElementById("P7_COD_MONEDA"));})()', 40)
    print("dialogo de presupuesto abierto:", abierto)
    time.sleep(2)
    pos = js('(function(){var f=document.querySelector("iframe");var d=f.contentDocument;'
             'function r(id){var e=d.getElementById(id);if(!e){return id+":?";}'
             'var b=e.getBoundingClientRect();return id+"@"+Math.round(b.left)+","+Math.round(b.top);}'
             'return [r("P7_ID_CLIENTE"),r("P7_FOLIO"),r("P7_COD_MONEDA"),r("P7_ESTADO"),'
             'r("P7_FECHA_EMISION"),r("P7_FECHA_VENCIMIENTO"),r("P7_TIPO_CAMBIO")].join(" | ");})()')
    print("  posiciones:", pos)
    png = cmd("Page.captureScreenshot", format="png")["data"]
    ruta = os.path.join(REPO, "deploy", "resultados", "20261118_presupuesto_rejilla.png")
    with open(ruta, "wb") as fh:
        fh.write(base64.b64decode(png))
    print("  captura:", ruta)
finally:
    proc.terminate()
    con2 = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
    cu = con2.cursor()
    cu.execute("alter session set current_schema = WKSP_SYPEXWS")
    cu.execute("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario where upper(username)='DIAG.P7'); commit; delete from usuario where upper(username)='DIAG.P7'; commit; end;")
    con2.commit()
    con2.close()
