"""Las pantallas leen la empresa activa (tarea 3 del plan empresa-activa).

Navegador real (Edge headless por CDP) con un usuario de DOS empresas:

  N1  sin empresa elegida, la lista de Presupuestos (5) y la de Facturas (8) salen vacias
  N2  al elegir la empresa 1, la lista de Presupuestos trae exactamente las suyas
  N3  al cambiar a la empresa 2, la lista cambia (las suyas, que son otras)
  N4  la lista de Clientes (20) trae solo los de la empresa activa
  N5  el dialogo de la factura (9) sigue abriendo y su empresa es la activa
  N6  el Panel (13) pinta sus indicadores con la empresa activa

Uso:  python deploy/diagnostico/20261117_empresa_activa_filtros_navegador.py
Sale con codigo 1 si hay fallas. Crea y borra su propio usuario temporal `diag.barra`.
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

import websocket

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
BASE = "https://gfd7e2575d251ae-sypexsql.adb.mx-monterrey-1.oraclecloudapps.com/ords"
REPO = r"C:\Users\luism\OneDrive\Documents\Apex_luis"
sys.path.insert(0, os.path.join(REPO, "deploy", "conexion"))
import oracledb
from verificar_conexion import CONNECT_STRING, credenciales

USUARIO, CLAVE = "diag.barra", "Diag#2026"
R_LISTA_PRES = "R11950647600514906"
R_LISTA_FAC = "R29963866505095675"
R_CLIENTES = "R43000000000000501"
fallas = 0


def comprobar(texto, ok, detalle=""):
    global fallas
    print(("  OK  " if ok else "  MAL ") + texto + (" | " + str(detalle) if detalle else ""))
    if not ok:
        fallas += 1


c = credenciales()
con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")

cur.execute("begin delete from usuario_empresa where usuario_id in "
            "(select usuario_id from usuario where upper(username)='DIAG.BARRA'); commit; "
            "delete from usuario where upper(username)='DIAG.BARRA'; commit; end;")
cur.execute("""insert into usuario (username,email,password_hash,estado,id_empresa,rol_id,
                 debe_cambiar_clave,reintentos_fallidos)
               values ('diag.barra','diag.barra@synpex.local',
                 sypex_hash_password('Diag#2026'),'ACTIVO',1,
                 (select id_rol from syn_roles where codigo_rol='ADMIN'),'N',0)""")
con.commit()
cur.execute("""insert into usuario_empresa (usuario_id, id_empresa)
               select usuario_id, 2 from usuario where upper(username)='DIAG.BARRA'""")
con.commit()


def cuenta(sql, emp):
    cur.execute(sql, emp=emp)
    return cur.fetchone()[0]


pres = {e: cuenta("""select count(*) from presupuestos p
                      where p.id_empresa = :emp and p.estado <> 'CANCELADO'
                        and exists (select 1 from clientes c
                                     where c.id_cliente = p.id_cliente
                                       and c.id_empresa = p.id_empresa)""", e) for e in (1, 2)}
fac = {e: cuenta("select count(*) from facturas where id_empresa = :emp", e) for e in (1, 2)}
cli = {e: cuenta("select count(*) from clientes where id_empresa = :emp", e) for e in (1, 2)}
print("  en la base: presupuestos", pres, "facturas", fac, "clientes", cli)

proc = subprocess.Popen([EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
                         "--remote-debugging-port=9299", "--window-size=1440,900",
                         f"--user-data-dir={os.path.join(tempfile.gettempdir(),'opencode','edge-filtros')}",
                         "about:blank"],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def obj():
    for _ in range(40):
        try:
            l = json.loads(urllib.request.urlopen("http://127.0.0.1:9299/json/list", timeout=2).read())
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


FILAS = ("(function(){var r=document.getElementById('%s');if(!r){return -1;}"
         "var t=r.querySelectorAll('table.a-IRR-table tbody tr');var k=0;"
         "for(var i=0;i<t.length;i++){if((t[i].className||'').indexOf('noData')<0 && t[i].querySelectorAll('td').length>0){k++;}}"
         "return k;})()")


def ir(pag, ses):
    js('window.location.href="%s/f?p=100:%s:%s"' % (BASE, pag, ses))
    esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(4)


def elige(valor):
    js('(function(){var s=document.getElementById("P0_EMPRESA_ACTIVA");s.value="%s";'
       's.dispatchEvent(new Event("change",{bubbles:true}));return true;})()' % valor)
    time.sleep(8)


try:
    js('window.location.href="%s/f?p=100:9999"' % BASE)
    esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(1)
    js('(function(){apex.item("P9999_USERNAME").setValue(%s);apex.item("P9999_PASSWORD").setValue(%s);'
       'var b=[...document.querySelectorAll("button")].find(x=>/sign in|iniciar|entrar/i.test(x.innerText));'
       'if(b){b.click();}})()' % (json.dumps(USUARIO), json.dumps(CLAVE)))
    time.sleep(8)
    m = re.search(r"session=(\d+)", js("window.location.href") or "")
    if not m:
        print("  MAL login fallido")
        raise SystemExit(1)
    ses = m.group(1)

    # N1: sin empresa elegida, listas vacias
    ir(5, ses)
    n5 = js(FILAS % R_LISTA_PRES)
    comprobar("N1 sin empresa elegida la lista de Presupuestos (5) sale vacia", n5 == 0, n5)
    ir(8, ses)
    n8 = js(FILAS % R_LISTA_FAC)
    comprobar("N1 sin empresa elegida la lista de Facturas (8) sale vacia", n8 == 0, n8)

    # N2: empresa 1
    ir(5, ses)
    elige("1")
    n5 = js(FILAS % R_LISTA_PRES)
    comprobar("N2 con la empresa 1 la lista trae solo sus presupuestos", n5 == pres[1], (n5, pres[1]))

    # N4: clientes de la empresa 1
    ir(20, ses)
    nc = js(FILAS % R_CLIENTES)
    comprobar("N4 la lista de Clientes (20) trae solo los de la empresa 1", nc == cli[1], (nc, cli[1]))

    # N5: el dialogo de la factura sigue abriendo y su empresa es la activa
    ir(8, ses)
    js('(function(){var a=document.querySelector(\'td a[href*="a-dialog-open"]\');if(a){a.click();}})()')
    abierto = esperar('(function(){var f=document.querySelector("iframe");'
                      'return !!(f&&f.contentWindow&&f.contentDocument&&'
                      'f.contentDocument.getElementById("P9_TIPO_DOCUMENTO"));})()', 40)
    comprobar("N5 el dialogo de la factura (9) abre", abierto)
    if abierto:
        emp9 = js('(function(){var f=document.querySelector("iframe");'
                  'return f.contentWindow.apex.item("P9_ID_EMPRESA").getValue();})()')
        comprobar("N5 la empresa del formulario es la activa", str(emp9) == "1", emp9)

    # N3: empresa 2
    ir(5, ses)
    elige("2")
    n5b = js(FILAS % R_LISTA_PRES)
    comprobar("N3 al cambiar a la empresa 2 la lista cambia", n5b == pres[2], (n5b, pres[2]))

    # N6: el Panel pinta con la empresa activa
    ir(13, ses)
    emp13 = js('(function(){var e=document.getElementById("P13_ID_EMPRESA");return e?e.value:"SIN ITEM";})()')
    comprobar("N6 el Panel (13) toma la empresa activa", str(emp13) == "2", emp13)
    # N6: el Panel pinta con la empresa activa.
    # 2026-11-21: las etiquetas del Panel van en mayusculas por CSS, como las de
    # la pagina 8 (innerText devuelve el texto ya transformado): se compara sin
    # distinguir mayusculas.
    tarjetas = js('(function(){var t=(document.body.innerText||"").toUpperCase();'
                  'return t.indexOf("FACTURADO DEL MES")>=0 && t.indexOf("TASA MXN A VES")>=0;})()')
    comprobar("N6 el Panel pinta sus indicadores con la moneda de la empresa activa", tarjetas is True, tarjetas)

    png = cmd("Page.captureScreenshot", format="png")["data"]
    ruta = os.path.join(REPO, "deploy", "resultados", "20261117_empresa_activa_filtros.png")
    with open(ruta, "wb") as f:
        f.write(base64.b64decode(png))
    print("  captura:", ruta)
finally:
    proc.terminate()
    cur.execute("begin delete from usuario_empresa where usuario_id in "
                "(select usuario_id from usuario where upper(username)='DIAG.BARRA'); commit; "
                "delete from usuario where upper(username)='DIAG.BARRA'; commit; end;")
    con.commit()
    con.close()

print("RESULTADO: FALLAS=%d" % fallas)
sys.exit(1 if fallas else 0)
