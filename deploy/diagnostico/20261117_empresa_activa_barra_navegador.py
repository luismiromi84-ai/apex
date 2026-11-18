"""El combo de empresa activa en la barra (tarea 2 del plan empresa-activa).

Comprueba con el navegador de verdad (Edge headless por CDP) lo que los metadatos no
pueden: que el combo sale EN LA BARRA de todas las paginas, que lista las empresas del
usuario, y que al elegir una la pagina se reenvia y la seleccion queda guardada en la
sesion de APEX.

  N1  el combo se pinta dentro de la cabecera (`t-Header-nav`), no en el cuerpo
  N2  trae la opcion vacia («Elige empresa») y las empresas del usuario
  N3  al elegir otra empresa la pagina se reenvia y el combo queda con ese valor
  N4  en una pagina distinta (Panel General) el combo sigue con la empresa elegida

Uso:  python deploy/diagnostico/20261117_empresa_activa_barra_navegador.py
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
fallas = 0

c = credenciales()
con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")

# usuario temporal con DOS empresas (el combo solo tiene sentido con varias)
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
cur.execute("""select e.id_empresa, e.nombre_empresa
                 from v_empresas_usuario e where upper(e.username)='DIAG.BARRA'
                order by e.nombre_empresa""")
empresas = cur.fetchall()
print("  empresas del usuario de prueba:", empresas)

proc = subprocess.Popen([EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
                         "--remote-debugging-port=9298", "--window-size=1440,900",
                         f"--user-data-dir={os.path.join(tempfile.gettempdir(),'opencode','edge-barra')}",
                         "about:blank"],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def obj():
    for _ in range(40):
        try:
            l = json.loads(urllib.request.urlopen("http://127.0.0.1:9298/json/list", timeout=2).read())
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

    # N1/N2: el combo en la barra de la pagina 5
    js('window.location.href="%s/f?p=100:5:%s"' % (BASE, ses))
    esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(3)
    dentro = js('(function(){var s=document.getElementById("P0_EMPRESA_ACTIVA");'
                'if(!s){return "SIN COMBO";}'
                'return s.closest("header") ? "BARRA" : "CUERPO";})()')
    print("  N1 el combo esta en:", dentro)
    if dentro != "BARRA":
        fallas += 1
        print("  MAL el combo no esta en la barra azul")

    izq = js('(function(){var s=document.getElementById("P0_EMPRESA_ACTIVA");'
             'var u=document.querySelector(".has-username");'
             'if(!s||!u){return "SIN DATOS";}'
             'var a=s.getBoundingClientRect(), b=u.getBoundingClientRect();'
             'return a.right <= b.left + 2 ? "IZQUIERDA" : ("DERECHA (" + Math.round(a.left) + " vs " + Math.round(b.right) + ")");})()')
    print("  N1b el combo esta a la", izq)
    if izq != "IZQUIERDA":
        fallas += 1
        print("  MAL el combo no queda a la izquierda del usuario")

    opciones = js('(function(){var s=document.getElementById("P0_EMPRESA_ACTIVA");if(!s){return null;}'
                  'return [...s.options].map(function(o){return o.value+"|"+o.textContent.trim();});})()')
    print("  N2 opciones:", opciones)
    if not opciones or len(opciones) != len(empresas) + 1:
        fallas += 1
        print("  MAL el combo no trae la opcion vacia mas las empresas del usuario")
    else:
        if not opciones[0].startswith("|"):
            fallas += 1
            print("  MAL la primera opcion no es la vacia («Elige empresa»)")
        if len({o.split("|")[1] for o in opciones[1:]}) != len(empresas):
            fallas += 1
            print("  MAL las empresas listadas no son las del usuario")

    # N3: elegir la otra empresa -> la pagina se reenvia y el combo queda con ese valor
    otra = [str(i) for i, _ in empresas if str(i) != "1"][0]
    js('(function(){var s=document.getElementById("P0_EMPRESA_ACTIVA");s.value="%s";'
       's.dispatchEvent(new Event("change",{bubbles:true}));return true;})()' % otra)
    time.sleep(8)
    valor = js('(function(){var s=document.getElementById("P0_EMPRESA_ACTIVA");'
               'return s ? s.value : "SIN COMBO";})()')
    print("  N3 valor tras enviar la pagina:", valor, "(se eligio la empresa %s)" % otra)
    if str(valor) != otra:
        fallas += 1
        print("  MAL la seleccion no quedo guardada en la sesion")

    # N4: en otra pagina el combo sigue con la empresa elegida
    js('window.location.href="%s/f?p=100:13:%s"' % (BASE, ses))
    esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(3)
    valor13 = js('(function(){var s=document.getElementById("P0_EMPRESA_ACTIVA");'
                 'return s ? s.value : "SIN COMBO";})()')
    print("  N4 valor en el Panel General:", valor13)
    if str(valor13) != otra:
        fallas += 1
        print("  MAL la empresa elegida no se mantiene al cambiar de pagina")

    png = cmd("Page.captureScreenshot", format="png")["data"]
    ruta = os.path.join(REPO, "deploy", "resultados", "20261117_empresa_activa_barra.png")
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
