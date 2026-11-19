"""Estetica del modulo de Compras (27 · 28 · 29), con navegador real.

El dueno pidio (2026-11-19) que «se vea profesional»: las paginas 28 y 29 no
tenian la cabecera azul del estandar (27, 3, 5, 8) y en la 29 los dos primeros
campos ocupaban la fila entera.

  E1  la 27 pinta la cabecera de la lista en azul (gradiente del estandar)
  E2  la 28 pinta la tarjeta «Compra» con cabecera azul (antes la ocultaba)
  E3  la 28 mantiene la rejilla de dos columnas (Proveedor y Tipo en la misma fila)
  E4  la 29 pinta su cabecera en azul
  E5  la 29 pone Producto y Descripcion en la misma fila (media fila cada uno)
  E6  ninguna de las tres devuelve el error de rejilla de 12 columnas

Uso: python deploy/diagnostico/20261119_compras_estetica.py
Crea y borra su propio usuario; no deja datos de negocio.
"""
import json, os, subprocess, sys, tempfile, time, urllib.request
import oracledb, websocket

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
REPO = r"C:\Users\luism\OneDrive\Documents\Apex_luis"
sys.path.insert(0, os.path.join(REPO, "deploy", "conexion"))
from verificar_conexion import CONNECT_STRING as CS, credenciales  # noqa: E402

EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
BASE = "https://gfd7e2575d251ae-sypexsql.adb.mx-monterrey-1.oraclecloudapps.com/ords"
USUARIO, CLAVE = "diag.estetica", "Diag#2026"
fallas = []


def comprobar(nombre, condicion, detalle=""):
    print(("  OK  " if condicion else "  MAL ") + nombre + ("" if condicion else " " + str(detalle)))
    if not condicion:
        fallas.append(nombre)


class Nav:
    def __init__(self, puerto=9294):
        self.proc = subprocess.Popen(
            [EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
             f"--remote-debugging-port={puerto}",
             f"--user-data-dir={os.path.join(tempfile.gettempdir(), 'opencode', 'edge-estetica')}",
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
        self.ws = websocket.create_connection(objetivo["webSocketDebuggerUrl"], timeout=60)
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
        try:
            r = self.cmd("Runtime.evaluate", expression=expr, returnByValue=True, awaitPromise=True)
        except Exception as e:
            return "WS: " + str(e)[:120]
        if "exceptionDetails" in r:
            return "EXC: " + str(r["exceptionDetails"].get("exception", {}).get("description"))[:200]
        return r.get("result", {}).get("value")

    def esperar(self, cond, seg=40):
        fin = time.time() + seg
        while time.time() < fin:
            if self.js(cond):
                return True
            time.sleep(0.5)
        return False

    def cerrar(self):
        try:
            self.proc.terminate()
        except Exception:
            pass

    def captura(self, ruta):
        import base64
        r = self.cmd("Page.captureScreenshot", format="png")
        if r.get("data"):
            with open(ruta, "wb") as fh:
                fh.write(base64.b64decode(r["data"]))
            return ruta
        return "SIN CAPTURA"


c = credenciales()
con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CS)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")
cur.execute("begin delete from usuario_empresa where usuario_id in "
            "(select usuario_id from usuario where upper(username)='DIAG.ESTETICA'); commit; "
            "delete from usuario where upper(username)='DIAG.ESTETICA'; commit; end;")
cur.execute("""insert into usuario (username,email,password_hash,estado,id_empresa,rol_id,
                 debe_cambiar_clave,reintentos_fallidos)
               values ('diag.estetica','diag.estetica@synpex.local',
                 sypex_hash_password('Diag#2026'),'ACTIVO',1,
                 (select id_rol from syn_roles where codigo_rol='ADMIN'),'N',0)""")
con.commit()
cur.execute("""select min(i.id_impuesto)
                 from impuestos i join empresas e on e.cod_pais = i.cod_pais
                where e.id_empresa = 1 and i.estado = 'ACTIVO'
                  and nvl(i.aplica_en, 'LINEA') = 'LINEA'
                  and i.porcentage = 0""")
imp_exento = cur.fetchone()[0]
con.close()

nav = Nav()
try:
    nav.js('window.location.href="%s/f?p=100:9999"' % BASE)
    nav.esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(1)
    nav.js('(function(){apex.item("P9999_USERNAME").setValue(' + json.dumps(USUARIO) +
           ');apex.item("P9999_PASSWORD").setValue(' + json.dumps(CLAVE) + ');'
           'var b=[...document.querySelectorAll("button")].find(x=>/sign in|iniciar|entrar/i.test(x.innerText));'
           'if(b){b.click();}})()')
    time.sleep(9)
    ses = nav.js('(function(){try{return apex.env.APP_SESSION;}catch(e){return null;}})()')
    if not ses:
        import re as _re
        m = _re.search(r"session=(\d+)", nav.js("window.location.href") or "")
        ses = m.group(1) if m else ""
    print("  sesion:", ses)

    # E1: la lista (27) con su cabecera azul
    nav.js('window.location.href="%s/f?p=100:27:%s"' % (BASE, ses))
    nav.esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(5)
    grad27 = nav.js('(function(){var h=[...document.querySelectorAll(".t-Region-header")]'
                    '.find(function(x){return /Facturas de Compras/i.test(x.innerText);});'
                    'if(!h) return "SIN CABECERA";'
                    'return getComputedStyle(h).backgroundImage.slice(0,40);})()')
    comprobar("E1 la 27 pinta la cabecera en azul", "linear-gradient" in str(grad27), grad27)
    print("  captura:", nav.captura(os.path.join(REPO, "deploy", "resultados",
                                                "20261119_compras_27.png")))

    # a la compra existente: «Editar» de la primera fila de la lista
    abierto = nav.js('(function(){var a=[...document.querySelectorAll("td a")].find(function(x){'
                     'return /editar/i.test(x.innerText) || x.querySelector(".fa-pencil");});'
                     'if(!a) return "SIN ENLACE"; a.click(); return "CLIC";})()')
    time.sleep(10)
    print("  abrir compra:", abierto)
    if abierto != "CLIC":
        nav.js('(function(){var b=[...document.querySelectorAll("button,a")].find(function(x){'
               'return (x.getAttribute("data-otel-label")||"")==="BTN_NUEVA_COMPRA";});'
               'if(b) b.click();})()')
        time.sleep(10)

    # E2 y E3: la compra (28)
    grad28 = nav.js('(function(){var h=document.querySelector(".t-Region-header");'
                    'if(!h) return "SIN CABECERA";'
                    'return getComputedStyle(h).backgroundImage.slice(0,40) + "|" + h.innerText.trim()'
                    ' + "|" + (document.getElementById("P28_ID_PROVEEDOR") ? "CON ITEMS" : "SIN ITEMS");})()')
    comprobar("E2 la 28 pinta la tarjeta con cabecera azul",
              "linear-gradient" in str(grad28) and "CON ITEMS" in str(grad28), grad28)

    fila28 = nav.js('(function(){var a=document.getElementById("P28_ID_PROVEEDOR"),'
                    'b=document.getElementById("P28_TIPO_DOCUMENTO");'
                    'if(!a||!b) return "SIN ITEMS";'
                    'var ra=a.closest(".col").getBoundingClientRect(), rb=b.closest(".col").getBoundingClientRect();'
                    'return Math.abs(ra.top-rb.top) < 3 ? "MISMA FILA" : ("DISTINTAS " + ra.top + "/" + rb.top);})()')
    comprobar("E3 la 28 mantiene las dos columnas", fila28 == "MISMA FILA", fila28)
    print("  captura:", nav.captura(os.path.join(REPO, "deploy", "resultados",
                                                "20261119_compras_28.png")))

    texto28 = nav.js("document.body.innerText") or ""
    comprobar("E6 la 28 abre sin error de rejilla",
              "cannot be rendered" not in texto28 and "12 Columns" not in texto28)

    # a la linea (29)
    nav.js('(function(){var b=[...document.querySelectorAll("button,a")].find(function(x){'
           'return (x.getAttribute("data-otel-label")||"")==="BTN_LINEA_COMPRA";});'
           'if(b) b.click();})()')
    time.sleep(10)

    grad29 = nav.js('(function(){var h=document.querySelector(".t-Region-header");'
                    'if(!h) return "SIN CABECERA";'
                    'return getComputedStyle(h).backgroundImage.slice(0,40) + "|" + h.innerText.trim()'
                    ' + "|" + (document.getElementById("P29_ID_PRODUCTO_SERVICIO") ? "CON ITEMS" : "SIN ITEMS");})()')
    comprobar("E4 la 29 pinta su cabecera en azul",
              "linear-gradient" in str(grad29) and "CON ITEMS" in str(grad29), grad29)

    fila29 = nav.js('(function(){var a=document.getElementById("P29_ID_PRODUCTO_SERVICIO"),'
                    'b=document.getElementById("P29_DESCRIPCION");'
                    'if(!a||!b) return "SIN ITEMS";'
                    'var ca=a.closest(".col").getBoundingClientRect(),'
                    '    cb=b.closest(".col").getBoundingClientRect();'
                    'if(Math.abs(ca.top-cb.top) > 3) return "DISTINTAS " + ca.top + "/" + cb.top;'
                    'var w=ca.width + cb.width;'
                    'return Math.abs(ca.width-cb.width) < 12 && w > 400 ? "MISMA FILA" : ("ANCHOS " + ca.width + "/" + cb.width);})()')
    comprobar("E5 la 29 pone Producto y Descripcion en la misma fila", fila29 == "MISMA FILA", fila29)

    texto29 = nav.js("document.body.innerText") or ""
    comprobar("E6 la 29 abre sin error de rejilla",
              "cannot be rendered" not in texto29 and "12 Columns" not in texto29)
    comprobar("E6 la 29 no muestra el PL/SQL de ninguna region",
              "fn_clean_num" not in texto29 and "v_html" not in texto29)

    # E7 (2026-11-19): la cantidad nace VACIA; la teclea el usuario
    cantidad = nav.js('(function(){var el=document.getElementById("P29_CANTIDAD");'
                      'return el ? (el.value === "" ? "VACIA" : el.value) : "SIN ITEM";})()')
    comprobar("E7 la cantidad nace vacia (la teclea el usuario)", cantidad == "VACIA", cantidad)

    # E8 (2026-11-19): elegir «Exento (0 %)» deja el % en 0 (antes seguia en 16)
    nav.js('(function(){apex.item("P29_ID_IMPUESTO").setValue("%s");'
           'var el=document.getElementById("P29_ID_IMPUESTO");'
           'if(el){el.dispatchEvent(new Event("change",{bubbles:true}));}return "OK";})()'
           % imp_exento)
    time.sleep(5)
    pct = nav.js('apex.item("P29_PORCENTAJE_IMPUESTO").getValue()')
    comprobar("E8 el impuesto exento deja el % en 0", str(pct) in ("0", "0.00"), pct)
    print("  captura:", nav.captura(os.path.join(REPO, "deploy", "resultados",
                                                "20261119_compras_29.png")))
finally:
    nav.cerrar()
    con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CS)
    cur = con.cursor()
    cur.execute("alter session set current_schema = WKSP_SYPEXWS")
    cur.execute("begin delete from usuario_empresa where usuario_id in "
                "(select usuario_id from usuario where upper(username)='DIAG.ESTETICA'); commit; "
                "delete from usuario where upper(username)='DIAG.ESTETICA'; commit; end;")
    con.close()

print()
print("RESULTADO: FALLAS=" + str(len(fallas)))
for f in fallas:
    print("  - " + f)
sys.exit(1 if fallas else 0)
