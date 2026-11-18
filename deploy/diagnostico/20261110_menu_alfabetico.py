"""El menu lateral: Home primero y el resto en orden alfabetico, con el grupo Compras.

Comprueba las dos caras: la secuencia guardada en APEX (APEX_APPLICATION_LIST_ENTRIES) y el
orden que pinta el navegador de verdad (Edge headless por CDP, con un ADMIN temporal).

Desde el 2026-11-18 «Proveedores» ya no es una entrada de primer nivel: cuelga del grupo
«Compras», que la plantilla pinta plegado y despliega al pulsarlo. El orden alfabetico se
comprueba en el PRIMER nivel; aparte se comprueba que el grupo tenga sus dos hijas.
"""
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

USUARIO, CLAVE = "diag.menu3", "Diag#2026"
ESPERADO = ["Home", "Administración", "Compras", "Clientes", "Facturación", "Cobros",
            "Reportes Factura y Notas C/D", "Libro de compras y ventas",
            "Gestión de Usuarios", "Panel general", "Presupuestos"]
HIJOS = ["Facturas de compras", "Proveedores"]
fallas = 0

c = credenciales()
con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")

# 1) Metadatos: el orden alfabetico del PRIMER nivel de la lista.
cur.execute("""select entry_text, display_sequence
                 from apex_application_list_entries
                where application_id = 100 and list_name = 'Navigation Menu'
                  and list_entry_parent_id is null
                order by display_sequence""")
filas = cur.fetchall()
print("  menu guardado en APEX (primer nivel, en orden):")
for texto, seq in filas:
    print("    %3s  %s" % (seq, texto))
orden_apex = [t for t, _ in filas]
if orden_apex != ESPERADO:
    fallas += 1
    print("  MAL el orden guardado no es el orden esperado (Home primero):", orden_apex)

# 1b) Las hijas del grupo Compras
cur.execute("""select c.entry_text
                 from apex_application_list_entries c
                 join apex_application_list_entries p
                   on p.list_entry_id = c.list_entry_parent_id
                where c.application_id = 100 and c.list_name = 'Navigation Menu'
                  and p.static_id = 'compras-grupo'
                order by c.display_sequence""")
hijas = [r[0] for r in cur.fetchall()]
if hijas != HIJOS:
    fallas += 1
    print("  MAL las hijas del grupo Compras son", hijas)

# 2) El render real del navegador.
# Se borran tambien los usuarios viejos de esta prueba (diag.menu / diag.menu2 quedaron
# de corridas anteriores) y todo va con el nombre en un bind, no escrito a mano.
cur.execute("""begin
                 for r in (select usuario_id from usuario
                            where upper(username) in ('DIAG.MENU', 'DIAG.MENU2', :u)) loop
                     delete from usuario_empresa where usuario_id = r.usuario_id;
                     commit;
                     delete from usuario where usuario_id = r.usuario_id;
                     commit;
                 end loop;
               end;""", u=USUARIO.upper())
cur.execute("""insert into usuario (username,email,password_hash,estado,id_empresa,rol_id,debe_cambiar_clave,reintentos_fallidos)
 values (:u, :u || '@synpex.local', sypex_hash_password(:c), 'ACTIVO', 1,
 (select id_rol from syn_roles where codigo_rol='ADMIN'), 'N', 0)""", u=USUARIO, c=CLAVE)
con.commit()

proc = subprocess.Popen([EDGE, "--headless=new", "--disable-gpu", "--no-first-run", "--remote-debugging-port=9296",
                         "--window-size=1440,900",
                         f"--user-data-dir={os.path.join(tempfile.gettempdir(),'opencode','edge-menu')}", "about:blank"],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def obj():
    for _ in range(40):
        try:
            l = json.loads(urllib.request.urlopen("http://127.0.0.1:9296/json/list", timeout=2).read())
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
    ses = re.search(r"session=(\d+)", js("window.location.href") or "")
    if not ses:
        print("  MAL login fallido")
        raise SystemExit(1)
    js('window.location.href="%s/f?p=100:1:%s"' % (BASE, ses.group(1)))
    esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(3)
    # el menu lateral sale plegado: hay que abrirlo antes de leerlo
    js('(function(){var b=document.getElementById("t_Button_navControl");'
       'if(b && b.getAttribute("aria-expanded")==="false"){b.click();}return true;})()')
    time.sleep(1.5)
    # la plantilla tarda un poco en pintar el arbol: se espera por condicion, no por reloj
    esperar('document.querySelectorAll(\'a[aria-level="1"]\').length > 4', 25)
    # el grupo Compras sale plegado: se despliega para ver a sus hijas
    js('(function(){var n=document.getElementById("t_TreeNav");'
       'if(!n){return false;}'
       'var li=[...n.querySelectorAll("li")].find(function(x){'
       'return (x.textContent||"").indexOf("Compras")>=0;});'
       'var t=li? li.querySelector(".a-TreeView-toggle"):null;'
       'if(t){t.click();}return !!t;})()')
    esperar('document.querySelectorAll(\'a[aria-level="2"]\').length > 0', 25)

    pintado = js('(function(){var n=document.querySelector("#t_TreeNav, .t-TreeNav");'
                 'if(!n){return "SIN NAV";}'
                 'return [...n.querySelectorAll(\'a[aria-level="1"]\')]'
                 '.map(function(x){return x.textContent.trim();})})()')
    print("  menu pintado en pantalla (primer nivel, en orden):")
    for t in pintado or []:
        print("    -", t.replace("\n", " "))
    if pintado != ESPERADO:
        fallas += 1
        print("  MAL el menu no sale en orden alfabetico:", pintado)

    hijos = js('(function(){var n=document.querySelector("#t_TreeNav, .t-TreeNav");'
               'if(!n){return "SIN NAV";}'
               'return [...n.querySelectorAll(\'a[aria-level="2"]\')]'
               '.map(function(x){return x.textContent.trim();})})()')
    print("  hijas del grupo:", hijos)
    if hijos != HIJOS:
        fallas += 1
        print("  MAL las hijas del grupo no son", HIJOS)

    # Captura para el ojo humano: con el menu desplegado, si hace falta.
    import base64
    js('(function(){var b=document.getElementById("t_Button_navControl");'
       'if(b && b.getAttribute("aria-expanded")==="false"){b.click();}return true;})()')
    time.sleep(1.5)
    png = cmd("Page.captureScreenshot", format="png")["data"]
    ruta = os.path.join(REPO, "deploy", "resultados", "20261110_menu_alfabetico.png")
    with open(ruta, "wb") as f:
        f.write(base64.b64decode(png))
    print("  captura:", ruta)
finally:
    proc.terminate()
    cur.execute("""begin
                     for r in (select usuario_id from usuario
                                where upper(username) in ('DIAG.MENU', 'DIAG.MENU2', :u)) loop
                         delete from usuario_empresa where usuario_id = r.usuario_id;
                         commit;
                         delete from usuario where usuario_id = r.usuario_id;
                         commit;
                     end loop;
                   end;""", u=USUARIO.upper())
    con.commit()
    con.close()

print("RESULTADO: FALLAS=%d" % fallas)
sys.exit(1 if fallas else 0)
