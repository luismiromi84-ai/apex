"""El selector de empresa de la barra no debe validar el formulario (2026-11-18).

Síntoma: al cambiar la empresa estando en una página con campos obligatorios vacíos
(«Gasto Real» 16, «Compra» 28), salían dos o tres avisos «#LABEL# debe tener algún valor.».
La causa: el combo `P0_EMPRESA_ACTIVA` envía la página (`page_action_on_selection=SUBMIT`)
y eso dispara la validación de obligatorios; en esa ruta APEX no resuelve la etiqueta y
queda el token crudo.

  E1  en la 28, cambiar la empresa NO muestra ningún error
  E2  y la empresa elegida queda aplicada
  E3  en la 16, cambiar la empresa tampoco muestra errores
  E4  guardar la 28 vacía sigue avisando, pero con el mensaje de la base (no #LABEL#)

Uso: python deploy/diagnostico/20261118_empresa_selector_verificacion.py
Crea y borra su propio usuario (con dos empresas para poder cambiar).
"""
import json, os, re, subprocess, sys, tempfile, time, urllib.request
import oracledb

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.path.insert(0, r"C:\Users\luism\OneDrive\Documents\Apex_luis\deploy\conexion")
from verificar_conexion import CONNECT_STRING, credenciales

EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
BASE = "https://gfd7e2575d251ae-sypexsql.adb.mx-monterrey-1.oraclecloudapps.com/ords"
USUARIO, CLAVE = "diag.emp", "Diag#2026"
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
            "(select usuario_id from usuario where upper(username)='DIAG.EMP'); commit; "
            "delete from usuario where upper(username)='DIAG.EMP'; commit; end;")
cur.execute("""insert into usuario (username,email,password_hash,estado,id_empresa,rol_id,
                 debe_cambiar_clave,reintentos_fallidos)
               values ('diag.emp','diag.emp@synpex.local', sypex_hash_password('Diag#2026'),
                       'ACTIVO',1,(select id_rol from syn_roles where codigo_rol='ADMIN'),'N',0)""")
cur.execute("""insert into usuario_empresa (usuario_id, id_empresa)
               select u.usuario_id, e.id_empresa from usuario u, empresas e
                where upper(u.username) = 'DIAG.EMP' and e.id_empresa in (1, 2)
                  and not exists (select 1 from usuario_empresa x
                                   where x.usuario_id = u.usuario_id and x.id_empresa = e.id_empresa)""")
con.commit()
con.close()

proc = subprocess.Popen([EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
                         "--remote-debugging-port=9312", "--window-size=1280,900",
                         "--user-data-dir=" + os.path.join(tempfile.gettempdir(), "opencode", "edge-empv"),
                         "about:blank"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def obj():
    for _ in range(40):
        try:
            l = json.loads(urllib.request.urlopen("http://127.0.0.1:9312/json/list", timeout=2).read())
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
        return "EXC: " + str(r["exceptionDetails"].get("exception", {}).get("description"))[:300]
    return r.get("result", {}).get("value")


def esperar(c_, s=40):
    f = time.time() + s
    while time.time() < f:
        if js(c_):
            return True
        time.sleep(0.5)
    return False


def avisos():
    return js('(function(){var o=[];document.querySelectorAll(".a-Notification, .t-Alert")'
              '.forEach(function(e){o.push((e.innerText||"").replace(/\\s+/g," ").trim());});'
              'return o;})()') or []


def empresa():
    return js('(function(){var e=document.getElementById("P0_EMPRESA_ACTIVA");'
              'return e? e.value : "(sin combo)";})()')


def cambia_empresa():
    return js('(function(){var e=document.getElementById("P0_EMPRESA_ACTIVA");'
              'if(!e){return "sin combo";}'
              'var otras=[...e.options].filter(function(o){return o.value && o.value!==e.value;});'
              'if(!otras.length){return "una sola";}'
              'e.value=otras[0].value;e.dispatchEvent(new Event("change",{bubbles:true}));'
              'return otras[0].value;})()')


def ir(pag, ses):
    js('window.location.href="' + BASE + '/f?p=100:%d:%s"' % (pag, ses))
    esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(3)


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
    comprobar("el login entra", m is not None)
    ses = m.group(1) if m else "0"

    # E1/E2 en la 28
    ir(28, ses)
    elegida = cambia_empresa()
    time.sleep(10)
    av = avisos()
    print("  avisos en la 28:", av)
    comprobar("E1 cambiar la empresa en la 28 no muestra errores",
              not any("#LABEL#" in a or "errores" in a.lower() for a in av), av)
    comprobar("E2 la empresa elegida queda aplicada",
              str(empresa()) == str(elegida), (empresa(), elegida))

    # E3 en la 16
    ir(16, ses)
    cambia_empresa()
    time.sleep(10)
    av16 = avisos()
    print("  avisos en la 16:", av16)
    comprobar("E3 cambiar la empresa en la 16 no muestra errores",
              not any("#LABEL#" in a or "errores" in a.lower() for a in av16), av16)

    # E4 guardar vacio -> mensaje de la base, no #LABEL#
    ir(28, ses)
    js('(function(){var b=[...document.querySelectorAll("button")]'
       '.find(function(x){return (x.getAttribute("data-otel-label")||"")==="BTN_GUARDAR_COMPRA";});'
       'if(b){b.click();return "ok";}return "sin boton";})()')
    time.sleep(9)
    av4 = avisos()
    print("  avisos al guardar vacio:", av4)
    comprobar("E4 guardar vacio avisa con el mensaje de la base",
              any("obligatorio" in a.lower() or "necesita un proveedor" in a.lower() for a in av4), av4)
    comprobar("E4 y no aparece el token #LABEL#",
              not any("#LABEL#" in a for a in av4), av4)
finally:
    proc.terminate()
    con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
    cur = con.cursor()
    cur.execute("alter session set current_schema = WKSP_SYPEXWS")
    cur.execute("begin delete from usuario_empresa where usuario_id in "
                "(select usuario_id from usuario where upper(username)='DIAG.EMP'); commit; "
                "delete from usuario where upper(username)='DIAG.EMP'; commit; end;")
    con.commit()
    con.close()

print()
print("RESULTADO: FALLAS=" + str(fallas))
sys.exit(1 if fallas else 0)
