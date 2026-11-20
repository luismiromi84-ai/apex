"""Comprueba que el bloque IGTF ya no sale en la empresa mexicana y que el libro MX trae compras."""
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
sys.path.insert(0, r"C:\Users\luism\OneDrive\Documents\Apex_luis\deploy\conexion")
from verificar_conexion import CONNECT_STRING, credenciales  # noqa: E402

EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
BASE = "https://gfd7e2575d251ae-sypexsql.adb.mx-monterrey-1.oraclecloudapps.com/ords"
USUARIO, CLAVE = "diag.mx", "Diag#2026"

c = credenciales()
con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")
cur.execute("begin delete from usuario_empresa where usuario_id in "
            "(select usuario_id from usuario where upper(username)='DIAG.MX'); commit; "
            "delete from usuario where upper(username)='DIAG.MX'; commit; end;")
cur.execute("""insert into usuario (username,email,password_hash,estado,id_empresa,rol_id,
                 debe_cambiar_clave,reintentos_fallidos)
               values ('diag.mx','diag.mx@synpex.local', sypex_hash_password('Diag#2026'),
                       'ACTIVO',2,(select id_rol from syn_roles where codigo_rol='ADMIN'),'N',0)""")
con.commit()
con.close()

proc = subprocess.Popen([EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
                         "--remote-debugging-port=9316", "--window-size=1500,950",
                         "--user-data-dir=" + os.path.join(tempfile.gettempdir(), "opencode", "edge-mx2"),
                         "about:blank"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

objetivo = None
for _ in range(40):
    try:
        lista = json.loads(urllib.request.urlopen("http://127.0.0.1:9316/json/list", timeout=2).read())
        pag = [t for t in lista if t.get("type") == "page"]
        if pag:
            objetivo = pag[0]
            break
    except Exception:
        pass
    time.sleep(0.5)
ws = websocket.create_connection(objetivo["webSocketDebuggerUrl"], timeout=60)
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
        return "EXC: " + str(r["exceptionDetails"].get("exception", {}).get("description"))[:300]
    return r.get("result", {}).get("value")


def esperar(c_, s=40):
    f = time.time() + s
    while time.time() < f:
        if js(c_):
            return True
        time.sleep(0.5)
    return False


fallas = 0


def comprobar(t, ok, det=""):
    global fallas
    print(("  OK  " if ok else "  MAL ") + t + ("" if ok else " " + str(det)))
    if not ok:
        fallas += 1


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
    comprobar("el login entra", bool(m))
    ses = m.group(1)
    js('window.location.href="' + BASE + '/f?p=100:18:' + ses + '"')
    esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(6)
    titulos = js('(function(){var o=[];document.querySelectorAll(".t-Region-title")'
                 '.forEach(function(e){o.push((e.innerText||"").trim());});return o;})()')
    print("  regiones:", titulos)
    comprobar("X1 el libro de Mexico sale", any("Libro de Mexico" in t for t in titulos), titulos)
    comprobar("X2 el bloque IGTF ya no sale en Mexico",
              not any("IGTF percibido" in t for t in titulos), titulos)
    cabeceras = js('(function(){var o=[];document.querySelectorAll("th")'
                   '.forEach(function(e){o.push((e.innerText||"").trim());});return o;})()')
    comprobar("X3 la tabla trae Ver compra y Libro",
              "Ver compra" in cabeceras and "Libro" in cabeceras, cabeceras[:8])
finally:
    proc.terminate()
    con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
    cur = con.cursor()
    cur.execute("alter session set current_schema = WKSP_SYPEXWS")
    cur.execute("begin delete from usuario_empresa where usuario_id in "
                "(select usuario_id from usuario where upper(username)='DIAG.MX'); commit; "
                "delete from usuario where upper(username)='DIAG.MX'; commit; end;")
    con.commit()
    con.close()

print()
print("RESULTADO: FALLAS=" + str(fallas))
sys.exit(1 if fallas else 0)
