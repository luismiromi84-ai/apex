"""El menu «Compras» con «Proveedores» como subentrada (2026-11-18).

  N1  el menu pintado trae el grupo «Compras»
  N2  dentro del grupo estan «Facturas de compras» y «Proveedores»
  N3  «Proveedores» lleva a la pagina 22
  N4  «Facturas de compras» lleva a la pagina 27
  N5  captura en deploy/resultados/20261118_menu_compras.png
  N6  en la 22 se marca «Proveedores» y no el grupo
  N7  en la 27 se marca la hija «Facturas de compras» y no el grupo

Es la primera vez que esta app usa un menu de dos niveles. Medido el 2026-11-18: la
plantilla lo pinta PLEGADO por defecto (el padre sale como nodo expandible y los
hijos solo aparecen al desplegarlo), asi que el script lo despliega antes de
mirar dentro. Ese estado inicial lo decide la plantilla, no la app.

Uso: python deploy/diagnostico/20261118_menu_compras_navegador.py
Sale con codigo 1 si hay fallas. Crea y borra su propio usuario.
"""
import base64, json, os, re, subprocess, sys, tempfile, time, urllib.request
import oracledb

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.path.insert(0, r"C:\Users\luism\OneDrive\Documents\Apex_luis\deploy\conexion")
from verificar_conexion import CONNECT_STRING, credenciales

EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
BASE = "https://gfd7e2575d251ae-sypexsql.adb.mx-monterrey-1.oraclecloudapps.com/ords"
REPO = r"C:\Users\luism\OneDrive\Documents\Apex_luis"
USUARIO, CLAVE = "diag.menu2", "Diag#2026"
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
            "(select usuario_id from usuario where upper(username)='DIAG.MENU2'); commit; "
            "delete from usuario where upper(username)='DIAG.MENU2'; commit; end;")
cur.execute("""insert into usuario (username,email,password_hash,estado,id_empresa,rol_id,
                 debe_cambiar_clave,reintentos_fallidos)
               values ('diag.menu2','diag.menu2@synpex.local', sypex_hash_password('Diag#2026'),
                       'ACTIVO',1,(select id_rol from syn_roles where codigo_rol='ADMIN'),'N',0)""")
con.commit()
con.close()

proc = subprocess.Popen([EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
                         "--remote-debugging-port=9297", "--window-size=1440,900",
                         "--user-data-dir=" + os.path.join(tempfile.gettempdir(), "opencode", "edge-mcomp"),
                         "about:blank"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def obj():
    for _ in range(40):
        try:
            l = json.loads(urllib.request.urlopen("http://127.0.0.1:9297/json/list", timeout=2).read())
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
        return "EXC: " + str(r["exceptionDetails"].get("exception", {}).get("description"))[:200]
    return r.get("result", {}).get("value")


def esperar(c_, s=40):
    f = time.time() + s
    while time.time() < f:
        if js(c_):
            return True
        time.sleep(0.5)
    return False


def abrir_menu():
    """Abre la barra lateral y despliega el grupo. La plantilla lo pinta plegado."""
    js('(function(){var b=document.getElementById("t_Button_navControl");'
       'if(b && b.getAttribute("aria-expanded")==="false"){b.click();}return true;})()')
    esperar('document.querySelectorAll(\'#t_TreeNav a[aria-level]\').length > 4', 25)
    js('(function(){var n=document.getElementById("t_TreeNav");'
       'if(!n){return false;}'
       'var li=[...n.querySelectorAll("li")].find(function(x){'
       'return (x.textContent||"").indexOf("Compras")>=0;});'
       'if(!li){return false;}'
       'if((li.className||"").indexOf("is-collapsible")>=0){return "ya";}'
       'var t=li.querySelector(".a-TreeView-toggle");'
       'if(t){t.click();}return "desplegado";})()')
    esperar('document.querySelectorAll(\'#t_TreeNav a[aria-level="2"]\').length > 0', 25)


def corrientes():
    """Entradas marcadas como pagina actual (texto@nivel)."""
    return js('(function(){var n=document.getElementById("t_TreeNav");'
              'if(!n){return "SIN NAV";}'
              'return [...n.querySelectorAll("a")].filter(function(a){'
              'return a.getAttribute("aria-current")==="true"'
              '   || /is-current/.test(a.className||"");})'
              '.map(function(a){return (a.textContent||"").trim()+"@"+a.getAttribute("aria-level");});})()')


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
    comprobar("el login entra", m is not None, js("window.location.href"))
    ses = m.group(1) if m else "0"

    js('window.location.href="' + BASE + '/f?p=100:1:' + ses + '"')
    esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(3)

    # N1/N2: estructura del menu pintado. Se deja el menu abierto por si sale plegado.
    js('(function(){var b=document.getElementById("t_Button_navControl");'
       'if(b && b.getAttribute("aria-expanded")==="false"){b.click();}return true;})()')
    time.sleep(1.5)

    # la plantilla pinta el grupo PLEGADO: se despliega antes de mirar dentro
    js('(function(){var n=document.getElementById("t_TreeNav");'
       'var li=[...n.querySelectorAll("li")].find(function(x){'
       'return (x.textContent||"").indexOf("Compras")>=0;});'
       'var t=li? li.querySelector(".a-TreeView-toggle"):null;'
       'if(t){t.click();return "expandido";}return "sin toggle";})()')
    time.sleep(3)

    textos = js('(function(){var n=document.querySelector("#t_TreeNav, .t-TreeNav");'
                'if(!n){return "SIN NAV";}'
                'return [...n.querySelectorAll("a, span")]'
                '.map(function(x){return x.textContent.trim();})'
                '.filter(function(t){return t;})})()')
    print("  menu pintado:", textos)
    comprobar("N1 el menu trae «Compras»", isinstance(textos, list) and "Compras" in textos, textos)
    comprobar("N2 el menu trae «Proveedores»", isinstance(textos, list) and "Proveedores" in textos,
              textos)

    # la relacion padre/hijo: el hijo tiene aria-level 2 dentro del arbol
    anidado = js('(function(){var n=document.querySelector("#t_TreeNav, .t-TreeNav");'
                 'if(!n){return false;}'
                 'var hijos=[...n.querySelectorAll(\'a[aria-level="2"]\')]'
                 '.map(function(x){return (x.textContent||"").trim();});'
                 'return hijos;})()')
    print("  hijos del grupo:", anidado)
    comprobar("N2b «Facturas de compras» y «Proveedores» estan anidados (nivel 2)",
              isinstance(anidado, list) and "Facturas de compras" in anidado and "Proveedores" in anidado,
              anidado)

    # N3: pulsar la hija Proveedores
    js('(function(){var n=document.querySelector("#t_TreeNav, .t-TreeNav");'
       'var a=[...n.querySelectorAll(\'a[aria-level="2"]\')].find(function(x){'
       'return (x.textContent||"").trim()==="Proveedores";});'
       'if(a){a.click();}return !!a;})()')
    time.sleep(6)
    url = js("window.location.href") or ""
    titulo = js("document.title") or ""
    print("  tras Proveedores:", url, "|", titulo)
    comprobar("N3 «Proveedores» abre la 22",
              "proveedores" in url.lower() or ":22" in url or "proveedores" in titulo.lower(),
              (url, titulo))

    # N6: en la 22 se marca «Proveedores» y NO el padre
    abrir_menu()
    act = corrientes()
    print("  marcado en la 22:", act)
    comprobar("N6 en la 22 se marca solo «Proveedores» y no el grupo",
              isinstance(act, list) and act == ["Proveedores@2"], act)

    # N4: volver, desplegar y pulsar la hija Compras
    js('window.location.href="' + BASE + '/f?p=100:1:' + ses + '"')
    esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(3)
    js('(function(){var b=document.getElementById("t_Button_navControl");'
       'if(b && b.getAttribute("aria-expanded")==="false"){b.click();}return true;})()')
    time.sleep(1.5)
    js('(function(){var n=document.getElementById("t_TreeNav");'
       'var li=[...n.querySelectorAll("li")].find(function(x){'
       'return (x.textContent||"").indexOf("Compras")>=0;});'
       'var t=li? li.querySelector(".a-TreeView-toggle"):null;'
       'if(t){t.click();}return !!t;})()')
    time.sleep(3)
    js('(function(){var n=document.querySelector("#t_TreeNav, .t-TreeNav");'
       'var a=[...n.querySelectorAll(\'a[aria-level="2"]\')].find(function(x){'
       'return (x.textContent||"").trim()==="Facturas de compras";});'
       'if(a){a.click();}return !!a;})()')
    time.sleep(6)
    url2 = js("window.location.href") or ""
    titulo2 = js("document.title") or ""
    print("  tras Facturas de compras:", url2, "|", titulo2)
    comprobar("N4 «Facturas de compras» abre la 27",
              re.search(r"(compras|:27)", url2.lower()) is not None or "compras" in titulo2.lower(),
              (url2, titulo2))

    # N7: en la 27 se marca la hija «Facturas de compras» y NO el padre (el padre no navega)
    abrir_menu()
    act2 = corrientes()
    print("  marcado en la 27:", act2)
    comprobar("N7 en la 27 se marca la hija «Facturas de compras» y no el grupo",
              isinstance(act2, list) and act2 == ["Facturas de compras@2"], act2)

    # N5: captura (con el grupo desplegado, para que se vea el anidado)
    js('window.location.href="' + BASE + '/f?p=100:1:' + ses + '"')
    esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(3)
    js('(function(){var b=document.getElementById("t_Button_navControl");'
       'if(b && b.getAttribute("aria-expanded")==="false"){b.click();}return true;})()')
    time.sleep(1.5)
    js('(function(){var n=document.getElementById("t_TreeNav");'
       'var li=[...n.querySelectorAll("li")].find(function(x){'
       'return (x.textContent||"").indexOf("Compras")>=0;});'
       'var t=li? li.querySelector(".a-TreeView-toggle"):null;'
       'if(t){t.click();}return !!t;})()')
    time.sleep(2)
    png = cmd("Page.captureScreenshot", format="png")["data"]
    ruta = os.path.join(REPO, "deploy", "resultados", "20261118_menu_compras.png")
    with open(ruta, "wb") as f:
        f.write(base64.b64decode(png))
    comprobar("N5 captura guardada", os.path.exists(ruta), ruta)
    print("  captura:", ruta)
finally:
    proc.terminate()
    con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
    cur = con.cursor()
    cur.execute("alter session set current_schema = WKSP_SYPEXWS")
    cur.execute("begin delete from usuario_empresa where usuario_id in "
                "(select usuario_id from usuario where upper(username)='DIAG.MENU2'); commit; "
                "delete from usuario where upper(username)='DIAG.MENU2'; commit; end;")
    con.commit()
    con.close()

print()
print("RESULTADO: FALLAS=" + str(fallas))
sys.exit(1 if fallas else 0)
