#!/usr/bin/env python3
"""Reproduce el submit de la página 5 con una fila marcada.

El error que reportó el dueño era «Violación de la protección del estado de la sesión:
P5_TOTAL»: el ítem estaba `value_protected = Y` y su origen es una consulta que el
servidor recalcula, así que el valor que manda el navegador ya no cuadra con el checksum.

Uso: python deploy/diagnostico/20261118_p5_submit.py  (sale 1 si aparece el error)
"""
import json, os, re, subprocess, sys, tempfile, time, urllib.request
import websocket

EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
BASE = "https://gfd7e2575d251ae-sypexsql.adb.mx-monterrey-1.oraclecloudapps.com/ords"
REPO = r"C:\Users\luism\OneDrive\Documents\Apex_luis"
sys.path.insert(0, os.path.join(REPO, "deploy", "conexion"))
import oracledb
from verificar_conexion import CONNECT_STRING, credenciales

USUARIO, CLAVE = "diag.p5", "Diag#2026"
fallas = 0
c = credenciales()
con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")
cur.execute("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario where upper(username)='DIAG.P5'); commit; delete from usuario where upper(username)='DIAG.P5'; commit; end;")
cur.execute("""insert into usuario (username,email,password_hash,estado,id_empresa,rol_id,debe_cambiar_clave,reintentos_fallidos)
 values ('diag.p5','diag.p5@synpex.local',sypex_hash_password('Diag#2026'),'ACTIVO',1,
 (select id_rol from syn_roles where codigo_rol='ADMIN'),'N',0)""")
con.commit()
con.close()

proc = subprocess.Popen([EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
                         "--remote-debugging-port=9305", "--window-size=1440,900",
                         f"--user-data-dir={os.path.join(tempfile.gettempdir(),'opencode','edge-p5')}",
                         "about:blank"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def obj():
    for _ in range(40):
        try:
            l = json.loads(urllib.request.urlopen("http://127.0.0.1:9305/json/list", timeout=2).read())
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

    # marcar la primera fila (como hace el usuario) y esperar el refresco
    js('(function(){var c=document.querySelector("input.js-select-invoice");if(c){c.click();return true;}return false;})()')
    time.sleep(5)
    print("P5_TOTAL en el navegador:", js('(function(){var i=document.getElementById("P5_TOTAL");return i?i.value:"SIN ITEM";})()'))

    # enviar la página (equivalente a pulsar un botón de la región)
    js('apex.submit({request:"APLICAR"});')
    time.sleep(8)
    texto = js('(function(){return document.body.innerText||"";})()') or ""
    error = "Violación de la protección" in texto or "protección del estado de la sesión" in texto
    print("error de protección tras el submit:", error)
    if error:
        fallas += 1
        i = texto.find("Violación")
        print("  ->", texto[max(0, i - 80):i + 200].replace("\n", " "))
    else:
        print("  OK el submit no da error de checksum")
finally:
    proc.terminate()
    con2 = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
    cu = con2.cursor()
    cu.execute("alter session set current_schema = WKSP_SYPEXWS")
    cu.execute("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario where upper(username)='DIAG.P5'); commit; delete from usuario where upper(username)='DIAG.P5'; commit; end;")
    con2.commit()
    con2.close()

print("RESULTADO: FALLAS=%d" % fallas)
sys.exit(1 if fallas else 0)
