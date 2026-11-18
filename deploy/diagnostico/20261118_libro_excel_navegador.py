#!/usr/bin/env python3
"""Descarga el «Excel fiscal» del Libro (pagina 18) haciendo CLIC en el boton.

Comprueba, sobre el archivo que queda en la carpeta de descargas:
  - que se descarga (nombre libro-<libro>-<mes>-<anio>.xls)
  - membrete (empresa, RIF con guiones, periodo)
  - cabecera fiscal y fila de TOTALES
  - que los importes van con formato contable y RIF/N control como texto

Uso: python deploy/diagnostico/20261118_libro_excel_navegador.py
Sale 1 si algo falla.
"""
import json, os, re, subprocess, sys, tempfile, time, urllib.request
import websocket

EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
BASE = "https://gfd7e2575d251ae-sypexsql.adb.mx-monterrey-1.oraclecloudapps.com/ords"
REPO = r"C:\Users\luism\OneDrive\Documents\Apex_luis"
sys.path.insert(0, os.path.join(REPO, "deploy", "conexion"))
import oracledb
from importar_export import credenciales, CONNECT_STRING

USUARIO, CLAVE = "diag.xls", "Diag#2026"
DESCARGAS = os.path.join(tempfile.gettempdir(), "opencode", "descargas-xls")

fallas = 0


def limpia_usuario():
    c = credenciales()
    con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
    cu = con.cursor()
    cu.execute("alter session set current_schema = WKSP_SYPEXWS")
    cu.execute("begin delete from usuario_empresa where usuario_id in "
               "(select usuario_id from usuario where upper(username)='DIAG.XLS'); commit; "
               "delete from usuario where upper(username)='DIAG.XLS'; commit; end;")
    con.commit()
    con.close()


os.makedirs(DESCARGAS, exist_ok=True)
for f in os.listdir(DESCARGAS):
    os.remove(os.path.join(DESCARGAS, f))

limpia_usuario()
c = credenciales()
con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
cu = con.cursor()
cu.execute("alter session set current_schema = WKSP_SYPEXWS")
cu.execute("""insert into usuario (username,email,password_hash,estado,id_empresa,rol_id,
                                    debe_cambiar_clave,reintentos_fallidos)
 values ('diag.xls','diag.xls@synpex.local',sypex_hash_password('Diag#2026'),'ACTIVO',1,
 (select id_rol from syn_roles where codigo_rol='ADMIN'),'N',0)""")
con.commit()
con.close()

proc = subprocess.Popen([EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
                         "--remote-debugging-port=9311", "--window-size=1440,900",
                         "--user-data-dir=" + os.path.join(tempfile.gettempdir(), "opencode", "edge-xls4"),
                         "about:blank"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def objetivo():
    for _ in range(40):
        try:
            lista = json.loads(urllib.request.urlopen("http://127.0.0.1:9311/json/list", timeout=2).read())
            paginas = [t for t in lista if t.get("type") == "page"]
            if paginas:
                return paginas[0]
        except Exception:
            pass
        time.sleep(0.5)
    raise SystemExit("Edge no respondio por CDP")


ws = websocket.create_connection(objetivo()["webSocketDebuggerUrl"], timeout=60)
ws.settimeout(60)
n = [0]


def cmd(metodo, **params):
    n[0] += 1
    ws.send(json.dumps({"id": n[0], "method": metodo, "params": params}))
    while True:
        r = json.loads(ws.recv())
        if r.get("id") == n[0]:
            return r.get("result", {})


for m in ("Page.enable", "Runtime.enable"):
    cmd(m)


def js(expr):
    r = cmd("Runtime.evaluate", expression=expr, returnByValue=True, awaitPromise=True)
    if "exceptionDetails" in r:
        return "EXC: " + str(r["exceptionDetails"].get("exception", {}).get("description"))[:200]
    return r.get("result", {}).get("value")


def esperar(cond, seg=40):
    fin = time.time() + seg
    while time.time() < fin:
        if js(cond):
            return True
        time.sleep(0.5)
    return False


try:
    cmd("Browser.setDownloadBehavior", behavior="allow", downloadPath=DESCARGAS, eventsEnabled=True)

    js('window.location.href="%s/f?p=100:9999"' % BASE)
    esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(1)
    js('(function(){apex.item("P9999_USERNAME").setValue(%s);'
       'apex.item("P9999_PASSWORD").setValue(%s);'
       'var b=[...document.querySelectorAll("button")].find(x=>/sign in|iniciar|entrar/i.test(x.innerText));'
       'if(b){b.click();}})()' % (json.dumps(USUARIO), json.dumps(CLAVE)))
    time.sleep(8)
    m = re.search(r"session=(\d+)", js("window.location.href") or "")
    if not m:
        raise SystemExit("no se pudo entrar: " + str(js("window.location.href")))
    ses = m.group(1)

    js('window.location.href="%s/f?p=100:18:%s"' % (BASE, ses))
    esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(4)

    # Clic real sobre el boton «Excel fiscal»
    caja = js('(function(){var b=document.querySelector(\'[data-otel-label="BTN_EXCEL_LIBRO"]\')'
              '||document.getElementById("B43000000000000973");'
              'if(!b){return null;}var r=b.getBoundingClientRect();'
              'return JSON.stringify({x:Math.round(r.left+r.width/2),y:Math.round(r.top+r.height/2)});})()')
    print("boton en la pagina:", bool(caja))
    if not caja:
        fallas += 1
    else:
        d = json.loads(caja)
        cmd("Input.dispatchMouseEvent", type="mousePressed", x=d["x"], y=d["y"], button="left", clickCount=1)
        cmd("Input.dispatchMouseEvent", type="mouseReleased", x=d["x"], y=d["y"], button="left", clickCount=1)

    fichero = None
    for _ in range(45):
        lista = [f for f in os.listdir(DESCARGAS) if f.lower().endswith((".xls", ".xlsx"))]
        if lista:
            fichero = lista[0]
            break
        time.sleep(1)

    print("archivo descargado:", fichero)
    if not fichero:
        fallas += 1
    else:
        print("  nombre:", fichero, "| cuadra el patron:",
              bool(re.fullmatch(r"libro-(todos|ventas|compras)-\d{2}-\d{4}\.xls", fichero)))
        if not re.fullmatch(r"libro-(todos|ventas|compras)-\d{2}-\d{4}\.xls", fichero):
            fallas += 1
        texto = open(os.path.join(DESCARGAS, fichero), encoding="utf-8", errors="replace").read()
        pruebas = [
            ("membrete con la empresa", "Empresa Principal" in texto),
            ("RIF con guiones", "J-12345678-9" in texto),
            ("periodo en el membrete", "Libro de compras y ventas -" in texto),
            ("cabecera fiscal", "Total Bs" in texto and "IVA 16%" in texto
                                and "control" in texto.lower()
                                and "IVA retenido Bs" in texto),
            ("importes como numero", texto.count('class="num"') >= 10),
            ("RIF y control como texto", texto.count('class="txt"') >= 10),
            ("fila de TOTALES", "TOTALES" in texto),
            ("formato contable de Excel", 'mso-number-format:"#\\,##0\\.00"' in texto),
            ("ceros del control conservados", "00-000123" in texto),
        ]
        for nombre, ok in pruebas:
            print(("  OK  " if ok else "  MAL ") + nombre)
            if not ok:
                fallas += 1
finally:
    proc.terminate()
    limpia_usuario()

print("RESULTADO: FALLAS=%d" % fallas)
sys.exit(1 if fallas else 0)
