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
ESPERADO = ["Home", "Administración", "Compras", "Facturación", "Gestión de Usuarios",
            "Impuestos", "Inventario", "Panel general", "Presupuestos",
            "Recibos", "Reportes"]
# 2026-11-19: «Clientes» colgaba de Facturación y «Gasto real» de Presupuestos
# 2026-11-20: «Facturación» es el grupo y «Factura de Venta» (la pagina 8) su primera hija
# 2026-11-20: «Conceptos de ISLR» (pagina 34) cuelga de Administración. No lo
#             introdujo el acabado del 2026-11-21: la entrada existe desde el
#             catalogo de ISLR y esta prueba se quedo con la lista vieja.
# 2026-11-24: «Inventario» sube a primer nivel (abre la 42) con «Articulos y
#             Servicios» y «Costo de Inventario»; «Clientes» pasa a Presupuestos
#             (Presupuesto · Gasto real · Clientes) y «Reportes» es el grupo de
#             «Reportes de Facturación».
# 2026-11-24 (tarde): «Impuestos» es un grupo nuevo con «Conceptos de ISLR» y
#             «Libro de compras y ventas» (que deja el primer nivel).
HIJOS = {"Compras": ["Facturas de compras", "Proveedores", "Pagos"],
         "Facturación": ["Factura de Venta", "Clientes"],
         "Impuestos": ["Conceptos de ISLR", "Libro de compras y ventas"],
         "Inventario": ["Artículos y Servicios", "Costo de Inventario"],
         "Presupuestos": ["Presupuesto", "Gasto real", "Clientes"],
         "Reportes": ["Reportes de Facturación"]}
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

# 1b) Las hijas de cada grupo (Compras, Facturacion y Presupuestos)
for padre, esperadas in HIJOS.items():
    cur.execute("""select c.entry_text
                     from apex_application_list_entries c
                     join apex_application_list_entries p
                       on p.list_entry_id = c.list_entry_parent_id
                    where c.application_id = 100 and c.list_name = 'Navigation Menu'
                      and p.entry_text = :p
                    order by c.display_sequence""", p=padre)
    hijas = [r[0] for r in cur.fetchall()]
    if hijas != esperadas:
        fallas += 1
        print("  MAL las hijas de «%s» son %s (se esperaban %s)" % (padre, hijas, esperadas))

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
    # los grupos salen plegados. Se despliega UNO por vuelta y se vuelve a
    # consultar el DOM: pulsar varios toggles de una vez deja nodos sueltos
    # porque el widget rehace el <li> (medido el 2026-11-20). Se exige que el
    # <li> tenga triangulo: sin eso se elige «Home», que no lo tiene, y el
    # bucle termina sin desplegar nada.
    for _ in range(10):
        r = js("""(function(){var n=document.getElementById("t_TreeNav"); if(!n){return -1;}
var li=[...n.querySelectorAll("li")].filter(function(l){
return l.querySelector('a[aria-level="1"]') && !l.querySelector('a[aria-level="2"]')
    && l.querySelector(".a-TreeView-toggle");})[0];
if(!li){return 0;}
li.querySelector(".a-TreeView-toggle").click(); return 1;})()""")
        if r != 1:
            break
        time.sleep(0.6)
    esperar('document.querySelectorAll(\'a[aria-level="2"]\').length >= 13', 25)

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
    print("  hijas de los grupos:", hijos)
    # orden esperado: el de los grupos en el primer nivel
    planas = []
    for p in ESPERADO:
        planas.extend(HIJOS.get(p, []))
    if hijos != planas:
        fallas += 1
        print("  MAL las hijas de los grupos no son", planas)

    # N1-N3: los padres de grupo deben ABRIR su pagina (el triangulo solo
    # despliega). Sin esto, la 42 solo se alcanzaria escribiendo la URL.
    # APEX los pinta como URL amigable con el alias: /synpex/inventario,
    # /synpex/presupuestos y /synpex/documentos (la 17).
    hrefs = js("""(function(){var n=document.getElementById("t_TreeNav"); if(!n){return "SIN NAV";}
return JSON.stringify([...n.querySelectorAll('a[aria-level="1"]')]
.map(function(x){return [x.textContent.trim(), x.getAttribute("href")||""];}));})()""")
    pares = json.loads(hrefs) if isinstance(hrefs, str) and hrefs.startswith("[") else []
    mapa = dict(pares)
    for nombre, alias in (("Inventario", "inventario"), ("Presupuestos", "presupuestos"),
                          ("Reportes", "documentos")):
        if alias not in (mapa.get(nombre) or "").lower():
            fallas += 1
            print("  MAL «%s» no abre su pagina (href=%s)" % (nombre, mapa.get(nombre)))

    # N4: pulsar «Inventario» abre la 42 y alli esta el boton «Ajuste de inventario»
    # (hasta el 2026-11-24 la 44 no tenia por donde entrar).
    js('(function(){var n=document.getElementById("t_TreeNav"); if(!n){return false;}'
       'var a=[...n.querySelectorAll(\'a[aria-level="1"]\')].find(function(x){'
       'return x.textContent.trim()==="Inventario";}); if(!a){return false;} a.click(); return true;})()')
    if not esperar('document.body.innerText.indexOf("Ajuste de inventario") >= 0', 40):
        fallas += 1
        print("  MAL «Inventario» no abre la 42 o no trae el boton «Ajuste de inventario»")
    js('window.location.href="%s/f?p=100:1:%s"' % (BASE, ses.group(1)))
    esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(2)

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
