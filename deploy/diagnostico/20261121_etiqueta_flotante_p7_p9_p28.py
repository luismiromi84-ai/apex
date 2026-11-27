#!/usr/bin/env python3
# =============================================================================
# 20261121_etiqueta_flotante_p7_p9_p28.py
#
# La etiqueta flotante dejaba de tapar la cifra en la 25 (recibo) y seguia
# tapandola en las paginas 7 (presupuesto), 9 (factura) y 28 (compra): cuando
# una accion dinamica devuelve un valor a un campo, APEX no le pone la clase
# js-show-label y el rotulo se queda ENCIMA del numero ("Tasa (Bs por unidad)"
# sobre "918.7662"). No es un fallo de la accion: el navegador nunca ve el
# "change" que haria el usuario. Se corrige con un JS de pagina
# (spxFlotaEtiquetas) que vuelve a decidir la etiqueta con el valor REAL, al
# cargar, tras cada refresco parcial y tras cada ajax.
#
# La prueba es de DOM, no de captura, y busca el caso de verdad: un campo que
# nace VACIO y SIN la clase (el estado que APEX deja cuando el valor llega por
# JavaScript) y al que la accion le pone un valor. Despues del cambio la clase
# tiene que estar.
#
#   D1  pagina 9 (factura nueva): la tasa nace vacia y sin la clase
#   D2  pagina 9: al elegir la moneda la accion escribe la tasa y la etiqueta
#       queda marcada
#   D3  pagina 9: ningun contenedor con valor se queda sin "js-show-label"
#   D4  pagina 7 (presupuesto nuevo): al cambiar la moneda la tasa llega por
#       accion y su etiqueta queda marcada
#   D5  pagina 7: ningun contenedor con valor se queda sin "js-show-label"
#   D6  pagina 28 (compra nueva): el % de retencion nace vacio y sin la clase
#   D7  pagina 28: al elegir el proveedor la accion propone el % y la etiqueta
#       queda marcada
#   D8  pagina 28: al cambiar la moneda la tasa llega por accion y su etiqueta
#       queda marcada
#   D9  pagina 28: ningun contenedor con valor se queda sin "js-show-label"
#
# Uso: python deploy/diagnostico/20261121_etiqueta_flotante_p7_p9_p28.py
# No escribe nada de negocio: los documentos se abren NUEVOS y no se guardan
# (los folios que se ven son la vista previa de fn_siguiente_folio, que no
# mueve el contador). Solo crea y borra su propio usuario.
# =============================================================================
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.request

import oracledb
import websocket

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
BASE = "https://gfd7e2575d251ae-sypexsql.adb.mx-monterrey-1.oraclecloudapps.com/ords"
REPO = r"C:\Users\luism\OneDrive\Documents\Apex_luis"
SALIDA = os.path.join(REPO, "deploy", "resultados")
sys.path.insert(0, os.path.join(REPO, "deploy", "conexion"))
from verificar_conexion import CONNECT_STRING as CS, credenciales  # noqa: E402

USUARIO, CLAVE = "diag.flota", "Diag#2026"
fallas = []


def comprobar(nombre, condicion, detalle=""):
    print(("  OK  " if condicion else "  MAL ") + nombre + ("" if condicion else " " + str(detalle)))
    if not condicion:
        fallas.append(nombre)


# Contenedores de campo del documento dado: los que tienen valor y NO llevan la
# clase que sube la etiqueta. Es el invariante que rompia el defecto.
REVISA = """(function (doc) {
    var faltan = [];
    doc.querySelectorAll('.t-Form-fieldContainer').forEach(function (c) {
        var i = c.querySelector('input, select, textarea');
        if (!i) { return; }
        var v = (i.value || '').toString().trim();
        if (v !== '' && !c.classList.contains('js-show-label')) {
            faltan.push((i.id || i.name || '?') + '=' + v);
        }
    });
    return faltan;
})(%s)"""


class Nav:
    def __init__(self, puerto=9301):
        self.proc = subprocess.Popen(
            [EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
             f"--remote-debugging-port={puerto}",
             f"--user-data-dir={os.path.join(tempfile.gettempdir(), 'opencode', 'edge-flota')}",
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

    def esperar(self, cond, seg=45):
        fin = time.time() + seg
        while time.time() < fin:
            v = self.js(cond)
            if v not in (False, None, "", "false") and not (
                    isinstance(v, str) and (v.startswith("EXC") or v.startswith("WS:"))):
                return True
            time.sleep(0.5)
        return False

    def clic(self, expr):
        r = self.js(expr)
        if not r or r in ("null", "SIN ENLACE", "SIN BOTON"):
            return False
        d = json.loads(r)
        self.cmd("Input.dispatchMouseEvent", type="mousePressed", x=d["x"], y=d["y"],
                 button="left", clickCount=1)
        self.cmd("Input.dispatchMouseEvent", type="mouseReleased", x=d["x"], y=d["y"],
                 button="left", clickCount=1)
        return True

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


# --- utilidades de dialogo ---------------------------------------------------
# `code` es un CUERPO (sentencias, con su `return` si hace falta). En el dialogo
# corre dentro del iframe con su propio apex/jQuery; en una pagina normal, en la
# ventana de la pagina.
def en_dialogo(code):
    return ('(function(){var f=document.querySelector("iframe");'
            'if(!f||!f.contentWindow||!f.contentDocument) return "SIN DIALOGO";'
            'var w=f.contentWindow,d=f.contentDocument,apex=w.apex,jq=w.apex.jQuery;'
            'return (function(apex,jq,d){%s})(apex,jq,d);})()' % code)


def suelto(code):
    return '(function(){var apex=window.apex,jq=apex.jQuery;%s})()' % code


def hay_dialogo(nav, campo):
    return nav.esperar('(function(){var f=document.querySelector("iframe");'
                       'return !!(f&&f.contentDocument&&f.contentDocument.getElementById("%s"));})()'
                       % campo, 60)


def boton(nav, texto):
    """Pulsa un boton/enlace por su texto visible o su data-otel-label."""
    return nav.clic('(function(){var b=[...document.querySelectorAll("button,a")].find(function(x){'
                    'return (x.getAttribute("data-otel-label")||"").indexOf("%s")>=0 '
                    '|| x.innerText.trim()==="%s";});'
                    'if(!b) return "SIN BOTON"; b.scrollIntoView({block:"center"});'
                    'var r=b.getBoundingClientRect();'
                    'return JSON.stringify({x:r.left+r.width/2,y:r.top+r.height/2});})()'
                    % (texto, texto))


def pon(nav, item, valor, dialogo):
    """Pone el valor en el item y dispara change como el usuario (o el LOV)."""
    code = 'apex.item("%s").setValue("%s"); jq("#%s").trigger("change");' % (item, valor, item)
    nav.js(en_dialogo(code) if dialogo else suelto(code))


def estado(nav, item, dialogo):
    """(valor, lleva_la_clase, hay_contenedor) del item."""
    # Ojo: dentro del dialogo el `document` de esta funcion es el de la pagina
    # padre (el codigo se evalua en la ventana de arriba), asi que hay que usar
    # el `d` que pasa en_dialogo.
    doc = "d" if dialogo else "document"
    code = ('var e=%s.getElementById("%s"),c=e?e.closest(".t-Form-fieldContainer"):null;'
            'return JSON.stringify([String(apex.item("%s").getValue()||""),'
            '!!(c&&c.classList.contains("js-show-label")),'
            'c?"CON":"SIN"]);' % (doc, item, item))
    r = nav.js(en_dialogo(code) if dialogo else suelto(code))
    try:
        v, lbl, hay = json.loads(r)
        return v, lbl, hay
    except Exception:
        return ("?", False, str(r))


def revisa(nav, dialogo):
    code = "return %s;" % (REVISA % ("d" if dialogo else "document"))
    r = nav.js(en_dialogo(code) if dialogo else suelto(code))
    if r is None:
        return ["SIN RESPUESTA DEL DOM"]
    if isinstance(r, str):
        return [r]
    return r or []


def ata(nav, dialogo):
    """Cierra el dialogo sin guardar."""
    code = ('var b=[...d.querySelectorAll("button")].find(function(x){'
            'return /Salir|Cancelar|Cerrar/i.test(x.innerText);});if(b){b.click();}')
    nav.js(en_dialogo(code))
    time.sleep(8)


# --- datos de la prueba ------------------------------------------------------
c = credenciales()
con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CS)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")
cur.execute("delete from syn_login_log where upper(usuario_intentado) = 'DIAG.FLOTA'")
cur.execute("begin delete from usuario_empresa where usuario_id in "
            "(select usuario_id from usuario where upper(username)='DIAG.FLOTA'); commit; "
            "delete from usuario where upper(username)='DIAG.FLOTA'; commit; end;")
cur.execute("""insert into usuario (username, email, password_hash, estado, id_empresa, rol_id,
                                    debe_cambiar_clave, reintentos_fallidos)
               values ('diag.flota', 'diag.flota@synpex.local', sypex_hash_password('Diag#2026'),
                       'ACTIVO', 1, (select id_rol from syn_roles where codigo_rol = 'ADMIN'), 'N', 0)""")
con.commit()
cur.execute("select min(id_proveedor) from proveedores where id_empresa = 1 and estado = 'ACTIVO'")
PROV = cur.fetchone()[0]
print("  proveedor de la prueba:", PROV)

nav = Nav()
try:
    nav.js('window.location.href="%s/f?p=100:9999"' % BASE)
    nav.esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(1)
    nav.js('(function(){apex.item("P9999_USERNAME").setValue(%s);'
           'apex.item("P9999_PASSWORD").setValue(%s);'
           'var b=[...document.querySelectorAll("button")].find(x=>/sign in|iniciar|entrar/i.test(x.innerText));'
           'if(b){b.click();}})()' % (json.dumps(USUARIO), json.dumps(CLAVE)))
    time.sleep(9)
    ses = nav.js('(function(){try{return apex.env.APP_SESSION || "";}catch(e){return "";}})()')
    if not ses:
        import re as _re
        m = _re.search(r"session=(\d+)", nav.js("window.location.href") or "")
        ses = m.group(1) if m else ""
    print("  sesion:", ses)

    # =============== D1-D3  pagina 9 (factura nueva) =========================
    nav.js('window.location.href="%s/f?p=100:8:%s"' % (BASE, ses))
    nav.esperar('!!document.getElementById("P8_ID_FACTURAS")', 60)
    time.sleep(4)
    comprobar("D1 el boton «Nueva factura» abre el dialogo de la 9",
              boton(nav, "Nueva factura") and hay_dialogo(nav, "P9_TIPO_DOCUMENTO"))
    time.sleep(4)
    v0, lbl0, hay0 = estado(nav, "P9_TIPO_CAMBIO", True)
    print("    antes: P9_TIPO_CAMBIO=%r etiqueta=%s" % (v0, "CON" if lbl0 else "SIN"))
    comprobar("D1 la tasa nace vacia y sin la clase de etiqueta",
              v0 == "" and lbl0 is False and hay0 == "CON", (v0, lbl0, hay0))
    pon(nav, "P9_COD_MONEDA", "USD", True)
    llego = nav.esperar(en_dialogo('return !!(apex.item("P9_TIPO_CAMBIO").getValue())'), 45)
    time.sleep(2)
    v1, lbl1, hay1 = estado(nav, "P9_TIPO_CAMBIO", True)
    print("    despues: P9_TIPO_CAMBIO=%r etiqueta=%s" % (v1, "CON" if lbl1 else "SIN"))
    comprobar("D2 la accion escribe la tasa de la factura", bool(llego) and v1 != "", v1)
    comprobar("D2 la etiqueta de la tasa ya no tapa la cifra", lbl1 is True, (v1, lbl1, hay1))
    faltan = revisa(nav, True)
    comprobar("D3 en la 9 no queda ningun campo con valor sin etiqueta", len(faltan) == 0, faltan)
    print("  captura:", nav.captura(os.path.join(SALIDA, "20261121_flota_9.png")))
    ata(nav, True)

    # =============== D4-D5  pagina 7 (presupuesto nuevo) =====================
    nav.js('window.location.href="%s/f?p=100:5:%s"' % (BASE, ses))
    nav.esperar('!!document.getElementById("P5_ID_PRESUPUESTO")', 60)
    time.sleep(5)
    comprobar("D4 el boton «Nuevo Presupuesto» abre el dialogo de la 7",
              boton(nav, "Nuevo Presupuesto") and hay_dialogo(nav, "P7_TIPO_CAMBIO"))
    time.sleep(4)
    v0, lbl0, _ = estado(nav, "P7_TIPO_CAMBIO", True)
    print("    antes: P7_TIPO_CAMBIO=%r etiqueta=%s" % (v0, "CON" if lbl0 else "SIN"))
    pon(nav, "P7_COD_MONEDA", "USD", True)
    llego7 = nav.esperar(en_dialogo('return !!(apex.item("P7_TIPO_CAMBIO").getValue())'), 45)
    time.sleep(2)
    v1, lbl1, hay1 = estado(nav, "P7_TIPO_CAMBIO", True)
    print("    despues: P7_TIPO_CAMBIO=%r etiqueta=%s" % (v1, "CON" if lbl1 else "SIN"))
    comprobar("D4 la accion escribe la tasa del presupuesto",
              bool(llego7) and v1 not in ("", "1"), v1)
    comprobar("D4 la etiqueta de la tasa ya no tapa la cifra", lbl1 is True, (v1, lbl1, hay1))
    faltan7 = revisa(nav, True)
    comprobar("D5 en la 7 no queda ningun campo con valor sin etiqueta", len(faltan7) == 0, faltan7)
    print("  captura:", nav.captura(os.path.join(SALIDA, "20261121_flota_7.png")))
    ata(nav, True)

    # =============== D6-D9  pagina 28 (compra nueva) =========================
    nav.js('window.location.href="%s/f?p=100:27:%s"' % (BASE, ses))
    nav.esperar('!!document.querySelector("table")', 60)
    time.sleep(6)
    comprobar("D6 el boton «Nueva compra» abre la 28",
              boton(nav, "Nueva compra") and
              nav.esperar('!!document.getElementById("P28_ID_PROVEEDOR")', 60))
    time.sleep(4)
    v0, lbl0, hay0 = estado(nav, "P28_PORCENTAJE_RETENCION", False)
    print("    antes: P28_PORCENTAJE_RETENCION=%r etiqueta=%s" % (v0, "CON" if lbl0 else "SIN"))
    comprobar("D6 el % de retencion nace vacio y sin la clase de etiqueta",
              v0 == "" and lbl0 is False and hay0 == "CON", (v0, lbl0, hay0))
    pon(nav, "P28_ID_PROVEEDOR", PROV, False)
    llego28 = nav.esperar('!!(apex.item("P28_PORCENTAJE_RETENCION").getValue())', 45)
    time.sleep(2)
    v1, lbl1, hay1 = estado(nav, "P28_PORCENTAJE_RETENCION", False)
    print("    despues: P28_PORCENTAJE_RETENCION=%r etiqueta=%s" % (v1, "CON" if lbl1 else "SIN"))
    comprobar("D7 la accion propone el % de retencion del proveedor",
              bool(llego28) and v1 != "", v1)
    comprobar("D7 la etiqueta del % de retencion ya no tapa la cifra", lbl1 is True, (v1, lbl1, hay1))
    pon(nav, "P28_COD_MONEDA", "USD", False)
    llego28b = nav.esperar('!!(apex.item("P28_TIPO_CAMBIO").getValue())', 45)
    time.sleep(2)
    v2, lbl2, hay2 = estado(nav, "P28_TIPO_CAMBIO", False)
    print("    despues: P28_TIPO_CAMBIO=%r etiqueta=%s" % (v2, "CON" if lbl2 else "SIN"))
    comprobar("D8 la accion escribe la tasa de la compra",
              bool(llego28b) and v2 not in ("", "1"), v2)
    comprobar("D8 la etiqueta de la tasa ya no tapa la cifra", lbl2 is True, (v2, lbl2, hay2))
    faltan28 = revisa(nav, False)
    comprobar("D9 en la 28 no queda ningun campo con valor sin etiqueta", len(faltan28) == 0, faltan28)
    print("  captura:", nav.captura(os.path.join(SALIDA, "20261121_flota_28.png")))
finally:
    # La 28 se queda con el formulario tocado y el navegador se cierra sin
    # navegar: asi no salta el aviso de cambios sin guardar. No se guardo nada.
    nav.cerrar()
    try:
        cur.execute("begin delete from usuario_empresa where usuario_id in "
                    "(select usuario_id from usuario where upper(username)='DIAG.FLOTA'); commit; "
                    "delete from usuario where upper(username)='DIAG.FLOTA'; commit; end;")
        cur.execute("delete from syn_login_log where upper(usuario_intentado) = 'DIAG.FLOTA'")
        con.commit()
    except Exception as ex:
        print("  limpieza:", ex)
    con.close()

print()
print("RESULTADO: FALLAS=%d" % len(fallas))
for f in fallas:
    print("  - " + f)
sys.exit(1 if fallas else 0)
