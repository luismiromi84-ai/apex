"""El dialogo de Recibo (25) no debe inundar de AJAX (2026-11-19).

Sintoma que reporto el dueno: «Error: error - Too Many Requests» al cambiar la
moneda del cobro, y no podia guardar.

Causa raiz medida con esta misma sonda: las cinco acciones `calcula-cobro-*`
tenian `suppress_change_event => 'N'`, asi que cada una volvia a disparar el
`change` de los items que ella misma escribia. Al abrir el dialogo y cambiar la
moneda se hacian **~200 peticiones AJAX** y ORDS empezaba a responder **429**;
desde ahi todo el dialogo fallaba.

  R1  el dialogo abre y no hay NINGUNA peticion con error
  R2  abrir + cambiar la moneda hace menos de 30 peticiones (antes: ~224)
  R3  el dialogo no muestra el aviso «Too Many Requests»

Uso: python deploy/diagnostico/20261119_cobro_sin_rafaga.py
Crea y borra su propio usuario; no registra ningun cobro.
"""
import json, os, subprocess, sys, tempfile, time, urllib.request
import oracledb, websocket

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
REPO = r"C:\Users\luism\OneDrive\Documents\Apex_luis"
sys.path.insert(0, os.path.join(REPO, "deploy", "conexion"))
from verificar_conexion import CONNECT_STRING as CS, credenciales  # noqa: E402

EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
BASE = "https://gfd7e2575d251ae-sypexsql.adb.mx-monterrey-1.oraclecloudapps.com/ords"
USUARIO, CLAVE = "diag.rafaga", "Diag#2026"
fallas = []


def comprobar(nombre, condicion, detalle=""):
    print(("  OK  " if condicion else "  MAL ") + nombre + ("" if condicion else " " + str(detalle)))
    if not condicion:
        fallas.append(nombre)


class Nav:
    def __init__(self, puerto=9297):
        self.proc = subprocess.Popen(
            [EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
             f"--remote-debugging-port={puerto}",
             f"--user-data-dir={os.path.join(tempfile.gettempdir(), 'opencode', 'edge-rafaga')}",
             "--window-size=1440,900", "about:blank"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        objetivo = None
        for _ in range(40):
            try:
                lista = json.loads(urllib.request.urlopen(
                    f"http://127.0.0.1:{puerto}/json/list", timeout=2).read())
                pag = [t for t in lista if t.get("type") == "page"]
                if pag:
                    objetivo = pag[0]
                    break
            except Exception:
                pass
            time.sleep(0.5)
        self.ws = websocket.create_connection(objetivo["webSocketDebuggerUrl"], timeout=90)
        self.n = 0
        for m in ("Page.enable", "Runtime.enable"):
            self.cmd(m)

    def cmd(self, method, **params):
        self.n += 1
        self.ws.send(json.dumps({"id": self.n, "method": method, "params": params}))
        while True:
            r = json.loads(self.ws.recv())
            if r.get("id") == self.n:
                return r.get("result", {})

    def js(self, expr):
        r = self.cmd("Runtime.evaluate", expression=expr, returnByValue=True, awaitPromise=True)
        if "exceptionDetails" in r:
            return "EXC: " + str(r["exceptionDetails"].get("exception", {}).get("description"))[:200]
        return r.get("result", {}).get("value")

    def cerrar(self):
        try:
            self.proc.terminate()
        except Exception:
            pass


c = credenciales()
con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CS)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")
cur.execute("begin delete from usuario_empresa where usuario_id in "
            "(select usuario_id from usuario where upper(username)='DIAG.RAFAGA'); commit; "
            "delete from usuario where upper(username)='DIAG.RAFAGA'; commit; end;")
cur.execute("""insert into usuario (username,email,password_hash,estado,id_empresa,rol_id,
                 debe_cambiar_clave,reintentos_fallidos)
               values ('diag.rafaga','diag.rafaga@synpex.local',
                 sypex_hash_password('Diag#2026'),'ACTIVO',1,
                 (select id_rol from syn_roles where codigo_rol='ADMIN'),'N',0)""")
con.commit()
con.close()

nav = Nav()
try:
    nav.js('window.location.href="%s/f?p=100:9999"' % BASE)
    time.sleep(4)
    nav.js('(function(){apex.item("P9999_USERNAME").setValue(' + json.dumps(USUARIO) +
           ');apex.item("P9999_PASSWORD").setValue(' + json.dumps(CLAVE) + ');'
           'var b=[...document.querySelectorAll("button")].find(x=>/sign in|iniciar|entrar/i.test(x.innerText));'
           'if(b){b.click();}})()')
    time.sleep(9)
    ses = nav.js('(function(){try{return apex.env.APP_SESSION;}catch(e){return null;}})()')

    nav.js('window.location.href="%s/f?p=100:24:%s"' % (BASE, ses))
    time.sleep(6)
    nav.js('(function(){var b=[...document.querySelectorAll("button,a")].find(function(x){'
           'return /Registrar cobro/i.test(x.innerText);}); if(b) b.click();})()')
    time.sleep(10)

    abierto = nav.js('(function(){var f=document.querySelector("iframe");'
                     'return !!(f&&f.contentDocument&&f.contentDocument.getElementById("P25_COD_MONEDA"));})()')
    comprobar("R1 el dialogo de Recibo abre", abierto is True, abierto)

    # cambiar la moneda, que es la accion que disparaba la avalancha
    nav.js('(function(){var w=document.querySelector("iframe").contentWindow;'
           '(function(apex){apex.item("P25_COD_MONEDA").setValue("USD");})(w.apex);'
           'var el=w.document.getElementById("P25_COD_MONEDA");'
           'if(el){el.dispatchEvent(new Event("change",{bubbles:true}));}return "OK";})()')
    time.sleep(8)

    datos = nav.js('(function(){var w=document.querySelector("iframe").contentWindow;'
                   'var l=w.performance.getEntriesByType("resource");'
                   'var malas=l.filter(function(e){return e.responseStatus>=400;})'
                   '  .map(function(e){return e.responseStatus;});'
                   'return {total:l.length, malas:malas};})()')
    if not isinstance(datos, dict):
        datos = {"total": 999, "malas": ["?"]}

    comprobar("R1 ninguna peticion del dialogo falla", not datos["malas"], datos["malas"])
    comprobar("R2 la rafaga esta contenida (< 30 peticiones)",
              datos["total"] < 30, datos["total"])
    texto = nav.js('(function(){var w=document.querySelector("iframe").contentWindow;'
                   'return w.document.body.innerText;})()') or ""
    comprobar("R3 el dialogo no avisa de Too Many Requests",
              "Too Many Requests" not in str(texto))
finally:
    nav.cerrar()
    con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CS)
    cur = con.cursor()
    cur.execute("alter session set current_schema = WKSP_SYPEXWS")
    cur.execute("begin delete from usuario_empresa where usuario_id in "
                "(select usuario_id from usuario where upper(username)='DIAG.RAFAGA'); commit; "
                "delete from usuario where upper(username)='DIAG.RAFAGA'; commit; end;")
    con.close()

print()
print("RESULTADO: FALLAS=" + str(len(fallas)))
for f in fallas:
    print("  - " + f)
sys.exit(1 if fallas else 0)
