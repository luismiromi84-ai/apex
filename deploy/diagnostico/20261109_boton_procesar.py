"""El boton Procesar de la pagina 8 debe nombrar el documento elegido.
Comprueba el HTML servido: la casilla lleva data-folio y el JS sabe deducir el tipo."""
import re
import subprocess
import sys
import os
import tempfile
import time
import urllib.request
import json
import websocket

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
BASE = "https://gfd7e2575d251ae-sypexsql.adb.mx-monterrey-1.oraclecloudapps.com/ords"
REPO = r"C:\Users\luism\OneDrive\Documents\Apex_luis"
sys.path.insert(0, os.path.join(REPO, "deploy", "conexion"))
import oracledb
from verificar_conexion import CONNECT_STRING, credenciales
USUARIO, CLAVE = "diag.diseno", "Diag#2026"

fallas = 0
c = credenciales()
con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")
cur.execute("delete from usuario where upper(username)='DIAG.DISENO'")
cur.execute("""insert into usuario (username,email,password_hash,estado,id_empresa,rol_id,debe_cambiar_clave,reintentos_fallidos)
 values ('diag.diseno','diag.diseno@synpex.local',sypex_hash_password('Diag#2026'),'ACTIVO',1,
 (select id_rol from syn_roles where codigo_rol='ADMIN'),'N',0)""")
con.commit()

proc = subprocess.Popen([EDGE, "--headless=new", "--disable-gpu", "--no-first-run", "--remote-debugging-port=9281",
                         f"--user-data-dir={os.path.join(tempfile.gettempdir(),'opencode','edge-b8')}", "about:blank"],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def obj():
    for _ in range(40):
        try:
            l = json.loads(urllib.request.urlopen("http://127.0.0.1:9281/json/list", timeout=2).read())
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
        return "EXC: " + str(r["exceptionDetails"].get("exception", {}).get("description"))[:200]
    return r.get("result", {}).get("value")


def esperar(c_, s=30):
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
       'var b=[...document.querySelectorAll("button")].find(x=>/sign in|iniciar|entrar/i.test(x.innerText));if(b){b.click();}})()'
       % (json.dumps(USUARIO), json.dumps(CLAVE)))
    time.sleep(7)
    ses = re.search(r"session=(\d+)", js("window.location.href") or "")
    if not ses:
        print("  MAL no pudo entrar")
        raise SystemExit(1)
    js('window.location.href="%s/f?p=100:8:%s"' % (BASE, ses.group(1)))
    esperar('!!document.getElementById("P8_ID_FACTURAS")', 40)
    time.sleep(5)

    folios = js('(function(){return [...document.querySelectorAll(".js-select-invoice")]'
                '.map(function(c){return c.getAttribute("data-folio");}).join(",");})()')
    print("  folios en las casillas:", folios)
    if not folios or "NC-" not in (folios or ""):
        fallas += 1
        print("  MAL la casilla no trae data-folio con la nota")

    # marcar la fila de la nota y leer el texto del boton
    js('(function(){var c=[...document.querySelectorAll(".js-select-invoice")]'
       '.find(function(x){return (x.getAttribute("data-folio")||"").indexOf("NC-")===0;});'
       'if(c){c.click();}})()')
    time.sleep(4)
    texto = js('(function(){var b=[...document.querySelectorAll("button")]'
               '.find(function(x){return /Procesar/i.test(x.innerText);});'
               'return b ? (b.innerText.trim()+" | disabled="+b.disabled) : "SIN BOTON";})()')
    print("  boton con la nota marcada:", texto)
    if "nota de cr" not in (texto or "").lower():
        fallas += 1
        print("  MAL el boton no dice 'Procesar nota de credito'")
finally:
    proc.terminate()
    cur.execute("delete from usuario where upper(username)='DIAG.DISENO'")
    con.commit()
    con.close()

print("RESULTADO: FALLAS=%d" % fallas)
sys.exit(1 if fallas else 0)
