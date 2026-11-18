"""La referencia bancaria se bloquea si la forma de pago no la pide (2026-11-19).

  R1  con «Efectivo» el campo queda de solo lectura y vacio
  R2  con «Transferencia Bancaria» vuelve a ser editable
  R3  al volver a «Efectivo», se vuelve a bloquear y se limpia

Uso: python deploy/diagnostico/20261119_cobro_referencia_navegador.py
Sale con codigo 1 si hay fallas. Crea y borra su propio usuario temporal.
"""
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
USUARIO, CLAVE = "diag.ref", "Diag#2026"
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
            "(select usuario_id from usuario where upper(username)='DIAG.REF'); commit; "
            "delete from usuario where upper(username)='DIAG.REF'; commit; end;")
cur.execute("""insert into usuario (username,email,password_hash,estado,id_empresa,rol_id,
                 debe_cambiar_clave,reintentos_fallidos)
               values ('diag.ref','diag.ref@synpex.local',
                 sypex_hash_password('Diag#2026'),'ACTIVO',1,
                 (select id_rol from syn_roles where codigo_rol='ADMIN'),'N',0)""")
con.commit()
con.close()

proc = subprocess.Popen([EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
                         "--remote-debugging-port=9292", "--window-size=1440,900",
                         "--user-data-dir=" + os.path.join(tempfile.gettempdir(), "opencode", "edge-ref"),
                         "about:blank"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def obj():
    for _ in range(40):
        try:
            l = json.loads(urllib.request.urlopen("http://127.0.0.1:9292/json/list", timeout=2).read())
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


def en_dialogo(expr):
    return js('(function(){var f=document.querySelector("iframe");if(!f){return "SIN DIALOGO";}'
              'var w=f.contentWindow;var d=w.document;var apex=w.apex;' + expr + '})()')


def poner_forma(valor):
    # como lo haria el usuario: se elige en la lista y el change dispara el
    # submit que repinta la pagina (el solo lectura es de servidor).
    en_dialogo('apex.item("P25_ID_FORMA_PAGO").setValue("%s");'
               'var s=d.getElementById("P25_ID_FORMA_PAGO");'
               's.dispatchEvent(new Event("change",{bubbles:true}));' % valor)
    time.sleep(9)


def estado_ref():
    # APEX marca el solo lectura con readonly, aria-readonly o una clase; se
    # miran las tres porque el tema cambia segun el tipo de item.
    return en_dialogo('var i=d.getElementById("P25_REFERENCIA");'
                      'if(!i){return "SIN CAMPO";}'
                      'var ro = i.readOnly || i.getAttribute("aria-readonly")==="true";'
                      'return JSON.stringify({ro: ro, val: i.value});')


try:
    js('window.location.href="' + BASE + '/f?p=100:9999"')
    esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(1)
    js('(function(){apex.item("P9999_USERNAME").setValue(' + json.dumps(USUARIO) +
       ');apex.item("P9999_PASSWORD").setValue(' + json.dumps(CLAVE) + ');'
       'var b=[...document.querySelectorAll("button")].find(x=>/sign in|iniciar|entrar/i.test(x.innerText));'
       'if(b){b.click();}})()')
    time.sleep(8)
    ses = re.search(r"session=(\d+)", js("window.location.href") or "").group(1)

    js('window.location.href="' + BASE + '/f?p=100:24:' + ses + '"')
    esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(4)
    js('(function(){var b=[...document.querySelectorAll("button,a")].find(function(x){'
       'return (x.getAttribute("data-otel-label")||"")==="BTN_NUEVO_COBRO" || /Registrar cobro/i.test(x.innerText);});'
       'if(b){b.click();return "CLIC";}return "NO";})()')
    time.sleep(8)
    print("  dialogo:", js("document.querySelectorAll('iframe').length"))

    # Efectivo (4)
    poner_forma(4)
    e = estado_ref()
    print("  Efectivo:", e)
    comprobar("R1 con Efectivo la referencia es de solo lectura y vacia",
              '"ro":true' in e and '"val":""' in e, e)

    # Transferencia (2)
    poner_forma(2)
    e = estado_ref()
    print("  Transferencia:", e)
    comprobar("R2 con Transferencia vuelve a ser editable", '"ro":false' in e, e)

    # se escribe algo y se vuelve a Efectivo
    en_dialogo('apex.item("P25_REFERENCIA").setValue("TRF-123");')
    time.sleep(2)
    poner_forma(4)
    e = estado_ref()
    print("  vuelve a Efectivo:", e)
    comprobar("R3 al volver a Efectivo se bloquea y se limpia",
              '"ro":true' in e and '"val":""' in e, e)

finally:
    proc.terminate()
    con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
    cur = con.cursor()
    cur.execute("alter session set current_schema = WKSP_SYPEXWS")
    cur.execute("begin delete from usuario_empresa where usuario_id in "
                "(select usuario_id from usuario where upper(username)='DIAG.REF'); commit; "
                "delete from usuario where upper(username)='DIAG.REF'; commit; end;")
    con.commit()
    con.close()

print()
print("RESULTADO: FALLAS=" + str(fallas))
sys.exit(1 if fallas else 0)
