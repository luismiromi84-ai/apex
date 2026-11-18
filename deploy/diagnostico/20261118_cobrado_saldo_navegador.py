#!/usr/bin/env python3
"""Abre la factura (9) desde la lista (8) y lee «Cobrado» y «Saldo».

Los dos ítems eran PL/SQL EXPRESSION con un bloque DECLARE…BEGIN…END: APEX los
evalúa como `valor := <fuente>`, así que un bloque ahí no compila (PLS-00103 al
calcular P9_COBRADO) y la página 9 no abría. Ahora son subconsultas escalares.

Uso: python deploy/diagnostico/20261118_cobrado_saldo_navegador.py
Sale con código 1 si no abre o si los dos ítems quedan vacíos.
"""
import json, os, re, subprocess, sys, tempfile, time, urllib.request
import websocket

EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
BASE = "https://gfd7e2575d251ae-sypexsql.adb.mx-monterrey-1.oraclecloudapps.com/ords"
REPO = r"C:\Users\luism\OneDrive\Documents\Apex_luis"
sys.path.insert(0, os.path.join(REPO, "deploy", "conexion"))
import oracledb
from verificar_conexion import CONNECT_STRING, credenciales

USUARIO, CLAVE = "diag.cobrado", "Diag#2026"
fallas = 0
c = credenciales()
con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")
cur.execute("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario where upper(username)='DIAG.COBRADO'); commit; delete from usuario where upper(username)='DIAG.COBRADO'; commit; end;")
cur.execute("""insert into usuario (username,email,password_hash,estado,id_empresa,rol_id,debe_cambiar_clave,reintentos_fallidos)
 values ('diag.cobrado','diag.cobrado@synpex.local',sypex_hash_password('Diag#2026'),'ACTIVO',1,
 (select id_rol from syn_roles where codigo_rol='ADMIN'),'N',0)""")
con.commit()
con.close()

proc = subprocess.Popen([EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
                         "--remote-debugging-port=9303", "--window-size=1440,900",
                         f"--user-data-dir={os.path.join(tempfile.gettempdir(),'opencode','edge-cobrado')}",
                         "about:blank"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def obj():
    for _ in range(40):
        try:
            l = json.loads(urllib.request.urlopen("http://127.0.0.1:9303/json/list", timeout=2).read())
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

    js('window.location.href="%s/f?p=100:8:%s"' % (BASE, ses))
    esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(4)
    js('(function(){var a=document.querySelector(\'td a[href*="a-dialog-open"]\');if(a){a.click();}})()')
    abierto = esperar('(function(){var f=document.querySelector("iframe");'
                      'return !!(f&&f.contentWindow&&f.contentDocument&&'
                      'f.contentDocument.getElementById("P9_COBRADO"));})()', 40)
    print("dialogo de la factura abierto:", abierto)
    if not abierto:
        fallas += 1
    else:
        cobrado = js('(function(){var f=document.querySelector("iframe");'
                     'return f.contentWindow.apex.item("P9_COBRADO").getValue();})()')
        saldo = js('(function(){var f=document.querySelector("iframe");'
                   'return f.contentWindow.apex.item("P9_SALDO").getValue();})()')
        error = js('(function(){var f=document.querySelector("iframe");'
                   'var t=f.contentDocument.body.innerText||"";'
                   'return t.indexOf("PLS-00103")>=0 || t.indexOf("Error al calcular")>=0;})()')
        print("  P9_COBRADO:", cobrado)
        print("  P9_SALDO  :", saldo)
        rif = js('(function(){var f=document.querySelector("iframe");'
                 'return f.contentWindow.apex.item("P9_RFC_EMISOR").getValue();})()')
        print("  P9_RFC_EMISOR:", rif)
        if rif and "-" not in str(rif):
            fallas += 1
            print("  MAL el RIF del emisor sale sin guiones")
        print("  error en pantalla:", error)
        if error is True:
            fallas += 1
        if not cobrado or not saldo:
            fallas += 1
            print("  MAL alguno de los dos ítems quedó vacío")
finally:
    proc.terminate()
    con2 = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
    cu = con2.cursor()
    cu.execute("alter session set current_schema = WKSP_SYPEXWS")
    cu.execute("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario where upper(username)='DIAG.COBRADO'); commit; delete from usuario where upper(username)='DIAG.COBRADO'; commit; end;")
    con2.commit()
    con2.close()

print("RESULTADO: FALLAS=%d" % fallas)
sys.exit(1 if fallas else 0)
