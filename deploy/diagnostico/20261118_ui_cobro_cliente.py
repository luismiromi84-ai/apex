#!/usr/bin/env python3
# temporal: mira el dialogo de Cobro (25) y el de Cliente (21) en el navegador
import base64, json, os, re, subprocess, sys, tempfile, time, urllib.request
import websocket

EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
BASE = "https://gfd7e2575d251ae-sypexsql.adb.mx-monterrey-1.oraclecloudapps.com/ords"
REPO = r"C:\Users\luism\OneDrive\Documents\Apex_luis"
sys.path.insert(0, os.path.join(REPO, "deploy", "conexion"))
import oracledb
from verificar_conexion import CONNECT_STRING, credenciales

USUARIO, CLAVE = "diag.ui", "Diag#2026"

c = credenciales()
con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")
cur.execute("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario where upper(username)='DIAG.UI'); commit; delete from usuario where upper(username)='DIAG.UI'; commit; end;")
cur.execute("""insert into usuario (username,email,password_hash,estado,id_empresa,rol_id,debe_cambiar_clave,reintentos_fallidos)
 values ('diag.ui','diag.ui@synpex.local',sypex_hash_password('Diag#2026'),'ACTIVO',1,
 (select id_rol from syn_roles where codigo_rol='ADMIN'),'N',0)""")
con.commit()
cur.execute("select cod_pais from empresas where id_empresa = 1")
print("pais de la empresa 1:", cur.fetchone()[0])
con.close()

proc = subprocess.Popen([EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
                         "--remote-debugging-port=9301", "--window-size=1440,900",
                         f"--user-data-dir={os.path.join(tempfile.gettempdir(),'opencode','edge-ui')}",
                         "about:blank"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def obj():
    for _ in range(40):
        try:
            l = json.loads(urllib.request.urlopen("http://127.0.0.1:9301/json/list", timeout=2).read())
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


def esperar(c_, s=40):
    f = time.time() + s
    while time.time() < f:
        if js(c_):
            return True
        time.sleep(0.5)
    return False


def en_frame(campo):
    return ('(function(){var f=document.querySelector("iframe");'
            'return !!(f&&f.contentWindow&&f.contentDocument&&'
            'f.contentDocument.getElementById("%s"));})()' % campo)


try:
    js('window.location.href="%s/f?p=100:9999"' % BASE)
    esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(1)
    js('(function(){apex.item("P9999_USERNAME").setValue(%s);apex.item("P9999_PASSWORD").setValue(%s);'
       'var b=[...document.querySelectorAll("button")].find(x=>/sign in|iniciar|entrar/i.test(x.innerText));'
       'if(b){b.click();}})()' % (json.dumps(USUARIO), json.dumps(CLAVE)))
    time.sleep(8)
    m = re.search(r"session=(\d+)", js("window.location.href") or "")
    ses = m.group(1)

    # --- Cobro (25) desde Cobros (24)
    js('window.location.href="%s/f?p=100:24:%s"' % (BASE, ses))
    esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(3)
    js('(function(){var b=document.getElementById("B43000000000000803")||document.querySelector(\'[data-otel-label="BTN_NUEVO_COBRO"]\');'
       'if(b){b.click();}else{var x=[...document.querySelectorAll("button,a")].find(y=>/nuevo cobro/i.test(y.innerText));if(x){x.click();}}})()')
    abierto = esperar(en_frame("P25_COD_MONEDA"), 40)
    print("cobro abierto:", abierto)
    if abierto:
        monedas = js('(function(){var f=document.querySelector("iframe");var s=f.contentDocument.getElementById("P25_COD_MONEDA");'
                     'return [...s.options].map(function(o){return o.value;}).join(",");})()')
        print("  monedas ofrecidas:", monedas)
        js('(function(){var f=document.querySelector("iframe");var w=f.contentWindow;'
           'var s=f.contentDocument.getElementById("P25_COD_MONEDA");s.value="USD";'
           's.dispatchEvent(new Event("change",{bubbles:true}));return true;})()')
        time.sleep(6)
        tasa = js('(function(){var f=document.querySelector("iframe");'
                  'return f.contentWindow.apex.item("P25_TIPO_CAMBIO").getValue();})()')
        print("  tasa al elegir USD:", tasa)
        botones = js('(function(){var f=document.querySelector("iframe");'
                     'return [...f.contentDocument.querySelectorAll("button")].map(function(b){'
                     'var r=b.getBoundingClientRect();return b.innerText.trim()+"@"+Math.round(r.left);}).join(" | ");})()')
        print("  botones (texto@x):", botones)
        png = cmd("Page.captureScreenshot", format="png")["data"]
        open(os.path.join(REPO, "deploy", "resultados", "20261118_cobro.png"), "wb").write(base64.b64decode(png))

    # --- Cliente (21) desde Clientes (20)
    js('window.location.href="%s/f?p=100:20:%s"' % (BASE, ses))
    esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(3)
    js('(function(){var b=document.getElementById("B43000000000000511")||document.querySelector(\'[data-otel-label="BTN_NUEVO_CLIENTE"]\');'
       'if(b){b.click();}else{var x=[...document.querySelectorAll("button,a")].find(y=>/nuevo cliente/i.test(y.innerText));if(x){x.click();}}})()')
    abierto2 = esperar(en_frame("P21_RAZON_SOCIAL"), 40)
    print("cliente abierto:", abierto2)
    if abierto2:
        pos = js('(function(){var f=document.querySelector("iframe");var d=f.contentDocument;'
                 'function r(id){var e=d.getElementById(id);if(!e){return id+":?";}var b=e.getBoundingClientRect();'
                 'return id+"@"+Math.round(b.left)+","+Math.round(b.top);}'
                 'return [r("P21_TIPO_RIF"),r("P21_RIF"),r("P21_RAZON_SOCIAL"),r("P21_COD_PAIS")].join(" | ");})()')
        print("  posiciones:", pos)
        botones2 = js('(function(){var f=document.querySelector("iframe");'
                      'return [...f.contentDocument.querySelectorAll("button")].map(function(b){'
                      'var r=b.getBoundingClientRect();return b.innerText.trim()+"@"+Math.round(r.left);}).join(" | ");})()')
        print("  botones (texto@x):", botones2)
        png = cmd("Page.captureScreenshot", format="png")["data"]
        open(os.path.join(REPO, "deploy", "resultados", "20261118_cliente.png"), "wb").write(base64.b64decode(png))
finally:
    proc.terminate()
    con2 = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
    cu = con2.cursor()
    cu.execute("alter session set current_schema = WKSP_SYPEXWS")
    cu.execute("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario where upper(username)='DIAG.UI'); commit; delete from usuario where upper(username)='DIAG.UI'; commit; end;")
    con2.commit()
    con2.close()
