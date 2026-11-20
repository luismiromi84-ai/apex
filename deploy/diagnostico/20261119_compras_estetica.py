"""Estetica del modulo de Compras (27 · 28 · 29), con navegador real.

El dueno pidio (2026-11-19) que «se vea profesional»: las paginas 28 y 29 no
tenian la cabecera azul del estandar (27, 3, 5, 8) y en la 29 los dos primeros
campos ocupaban la fila entera.

  E1  la 27 pinta la cabecera de la lista en azul (gradiente del estandar)
  E2  la 28 deja el titulo al tema y pinta la banda de la compra (folio, estado, fecha)
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

# una compra en BORRADOR propia: la prueba necesita una que ofrezca «Nueva linea»
cur.execute("delete from compras_det where id_compra in "
            "(select id_compra from compras where folio_factura = 'EST-ZZ-1')")
con.commit()
cur.execute("delete from compras where folio_factura = 'EST-ZZ-1'")
con.commit()
cur.execute("select min(id_proveedor) from proveedores where id_empresa = 1")
prov1 = cur.fetchone()[0]
cur.execute("""insert into compras (id_empresa, id_proveedor, tipo_documento, folio_factura,
                 nro_control, fecha_emision, cod_moneda, tipo_cambio, porcentaje_retencion)
               values (1, :p, 'FAC', 'EST-ZZ-1', '00-000999', sysdate, 'VES', 1, 75)""", p=prov1)
con.commit()
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

    # a la compra (28): «Editar» de la primera fila, que es la compra en BORRADOR
    # que acaba de crear la prueba
    abierto = nav.js('(function(){var a=[...document.querySelectorAll("td a")].find(function(x){'
                     'return /editar/i.test(x.innerText) || x.querySelector(".fa-pencil");});'
                     'if(!a) return "SIN ENLACE"; a.click(); return "CLIC";})()')
    time.sleep(10)
    print("  abrir compra:", abierto)

    # E2 y E3: la compra (28). Desde el 2026-11-20 la 28 NO lleva el degradado azul:
    # el dueno pidio una banda con folio/proveedor/estado/fecha y el titulo al tema.
    cab28 = nav.js('(function(){var h=document.querySelector(".t-Region-header");'
                   'var c=document.querySelector(".spx-cab");'
                   'if(!h) return "SIN CABECERA";'
                   'return getComputedStyle(h).backgroundImage.slice(0,20) + "|"'
                   ' + (c ? "CON BANDA" : "SIN BANDA") + "|"'
                   ' + (document.getElementById("P28_ID_PROVEEDOR") ? "CON ITEMS" : "SIN ITEMS");})()')
    comprobar("E2 la 28 deja el titulo al tema y pinta la banda de la compra",
              "none" in str(cab28) and "CON BANDA" in str(cab28) and "CON ITEMS" in str(cab28),
              cab28)

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

    # a la linea (29): esperar a que el boton exista y, si no navega, reintentar
    def ir_a_linea():
        for _ in range(20):
            if nav.js('(function(){return !![...document.querySelectorAll("button,a")]'
                      '.find(function(x){return (x.getAttribute("data-otel-label")||"")'
                      '==="BTN_LINEA_COMPRA";});})()'):
                break
            time.sleep(1)
        nav.js('(function(){var b=[...document.querySelectorAll("button,a")].find(function(x){'
               'return (x.getAttribute("data-otel-label")||"")==="BTN_LINEA_COMPRA";});'
               'if(b) b.click();})()')
        for _ in range(20):
            time.sleep(1)
            if nav.js('(function(){return !!document.getElementById("P29_CANTIDAD");})()'):
                return True
        return False

    if not ir_a_linea():
        ir_a_linea()

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

    # E9 (2026-11-19): el descuento se calcula — 30 x 30 al 5 % son 45.00
    nav.js('(function(){apex.item("P29_CANTIDAD").setValue(30);'
           'apex.item("P29_PRECIO_UNITARIO").setValue(30);'
           'apex.item("P29_PORCENTAJE_DESCUENTO").setValue(5);'
           'var el=document.getElementById("P29_PORCENTAJE_DESCUENTO");'
           'if(el){el.dispatchEvent(new Event("change",{bubbles:true}));}return "OK";})()')
    time.sleep(4)
    monto_desc = nav.js('apex.item("P29_MONTO_DESCUENTO").getValue()')
    comprobar("E9 el 5 % de 900 son 45.00 de descuento",
              str(monto_desc).replace(",", ".") in ("45", "45.0", "45.00"), monto_desc)

    # E10: al reves, teclear 90 de descuento deja el % en 10
    nav.js('(function(){apex.item("P29_MONTO_DESCUENTO").setValue(90);'
           'var el=document.getElementById("P29_MONTO_DESCUENTO");'
           'if(el){el.dispatchEvent(new Event("change",{bubbles:true}));}return "OK";})()')
    time.sleep(4)
    pct_desc = nav.js('apex.item("P29_PORCENTAJE_DESCUENTO").getValue()')
    comprobar("E10 90 de 900 son el 10 %",
              str(pct_desc).replace(",", ".") in ("10", "10.0", "10.00"), pct_desc)

    # E11 (2026-11-19): la «Factura afectada» solo sale en una nota (NC/ND)
    nav.js('window.location.href="%s/f?p=100:28:%s"' % (BASE, ses))
    time.sleep(8)
    visible = ('(function(){var el=document.getElementById("P28_ID_COMPRA_ORIGEN");'
               'if(!el) return "SIN ITEM";'
               'var col=el.closest(".col")||el.parentElement;'
               'return (col && col.offsetParent!==null) ? "VISIBLE" : "OCULTA";})()')

    def pon_tipo(t):
        nav.js('(function(){apex.item("P28_TIPO_DOCUMENTO").setValue("%s");'
               'var el=document.getElementById("P28_TIPO_DOCUMENTO");'
               'if(el){el.dispatchEvent(new Event("change",{bubbles:true}));}return "OK";})()' % t)
        time.sleep(4)

    pon_tipo("NC")
    comprobar("E11 con Nota de Crédito sale la factura afectada", nav.js(visible) == "VISIBLE",
              nav.js(visible))
    pon_tipo("FAC")
    comprobar("E11 con Factura se oculta la factura afectada", nav.js(visible) == "OCULTA",
              nav.js(visible))
    print("  captura:", nav.captura(os.path.join(REPO, "deploy", "resultados",
                                                "20261119_compras_29.png")))
finally:
    nav.cerrar()
    con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CS)
    cur = con.cursor()
    cur.execute("alter session set current_schema = WKSP_SYPEXWS")
    # la compra de prueba (y sus lineas) se van con la prueba
    cur.execute("delete from compras_det where id_compra in "
                "(select id_compra from compras where folio_factura = 'EST-ZZ-1')")
    con.commit()
    cur.execute("delete from compras where folio_factura = 'EST-ZZ-1'")
    con.commit()
    cur.execute("begin delete from usuario_empresa where usuario_id in "
                "(select usuario_id from usuario where upper(username)='DIAG.ESTETICA'); commit; "
                "delete from usuario where upper(username)='DIAG.ESTETICA'; commit; end;")
    con.close()

print()
print("RESULTADO: FALLAS=" + str(len(fallas)))
for f in fallas:
    print("  - " + f)
sys.exit(1 if fallas else 0)
