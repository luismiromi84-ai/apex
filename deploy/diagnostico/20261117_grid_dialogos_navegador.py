#!/usr/bin/env python3
"""
Verifica en navegador real que los dialogos con rejilla reciente abren bien:

  G1  pagina 9 (factura) abre con los tres campos de retencion visibles
  G2  la pagina 9 no muestra el error WWV_FLOW_GRID_LAYOUT
  G3  pagina 4 (editar usuario) abre con sus campos (aviso del mismo problema:
      P4_ID_EMPRESA ocupa 12 columnas y P4_ROL_ID continuaba en la 13)

Por que existe: el 2026-11-17 la pagina 9 devolvia HTTP 400 con
  "Component P9_RETENCION_IVA_BS cannot be rendered ... Column 13 ... Column Span 3"
porque P9_PORCENTAJE_RETENCION continuaba la primera fila (ya llena con
Tipo Documento + N Factura + N Control 6 UUID). Los dialogos no se pueden
comprobar por HTTP (piden p_dialog_cs), asi que se abre el navegador.

Uso:
    python deploy/diagnostico/20261117_grid_dialogos_navegador.py
Requiere: websocket-client y Edge instalado.
"""
import json
import os
import re
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
sys.path.insert(0, os.path.join(REPO, "deploy", "conexion"))
from verificar_conexion import CONNECT_STRING as CS, credenciales  # noqa: E402

USUARIO, CLAVE = "diag.rejilla", "Diag#2026"

fallas = []


def comprobar(nombre, condicion, detalle=""):
    print(("  OK  " if condicion else "  MAL ") + nombre + (" " + str(detalle) if detalle else ""))
    if not condicion:
        fallas.append(nombre)


class Nav:
    def __init__(self, puerto=9275):
        self.proc = subprocess.Popen(
            [EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
             f"--remote-debugging-port={puerto}",
             f"--user-data-dir={os.path.join(tempfile.gettempdir(), 'opencode', 'edge-grid')}",
             "about:blank"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
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
        r = self.cmd("Runtime.evaluate", expression=expr, returnByValue=True, awaitPromise=True)
        if "exceptionDetails" in r:
            return "EXC: " + str(r["exceptionDetails"].get("exception", {}).get("description"))[:200]
        return r.get("result", {}).get("value")

    def esperar(self, cond, seg=30):
        fin = time.time() + seg
        while time.time() < fin:
            if self.js(cond):
                return True
            time.sleep(0.5)
        return False

    def clic(self, expr_boton):
        r = self.js(expr_boton)
        if not r or r == "null":
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
        datos = r.get("data")
        if datos:
            with open(ruta, "wb") as fh:
                fh.write(base64.b64decode(datos))
            return True
        return False


def abre_dialogo(nav, campo, expresion_boton, seg=40):
    """Pulsa el boton y espera a que el iframe del dialogo tenga `campo`."""
    cond = ('(function(){var f=document.querySelector("iframe");'
            'return !!(f&&f.contentWindow&&f.contentDocument&&'
            'f.contentDocument.getElementById("%s"));})()' % campo)
    return nav.clic(expresion_boton) and nav.esperar(cond, seg)


def abre_dialogo_js(nav, campo, expresion_boton, seg=40):
    """Igual que abre_dialogo, pero dispara `el.click()`.

    Hace falta cuando el enlace es un icono sin texto y queda fuera del area
    visible: mandar el raton a sus coordenadas no pulsa nada.
    """
    cond = ('(function(){var f=document.querySelector("iframe");'
            'return !!(f&&f.contentWindow&&f.contentDocument&&'
            'f.contentDocument.getElementById("%s"));})()' % campo)
    nav.js(expresion_boton)
    return nav.esperar(cond, seg)


def texto_dialogo(nav):
    t = nav.js('(function(){var f=document.querySelector("iframe");'
               'return f&&f.contentDocument ? (f.contentDocument.body.innerText||"") : "";})()')
    return t or ""


def hay_item(nav, campo):
    return bool(nav.js('(function(){var f=document.querySelector("iframe");'
                       'return !!(f&&f.contentDocument&&f.contentDocument.getElementById("%s"));})()'
                       % campo))


conn = oracledb.connect(user=credenciales()["DB_USER"], password=credenciales()["DB_PASSWORD"], dsn=CS)
cur = conn.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")

cur.execute("delete from syn_login_log where upper(usuario_intentado) = 'DIAG.REJILLA'")
cur.execute("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario "
            "where upper(username) = 'DIAG.REJILLA'); commit; "
            "delete from usuario where upper(username) = 'DIAG.REJILLA'; commit; end;")
cur.execute("""insert into usuario (username, email, password_hash, estado, id_empresa, rol_id,
                                    debe_cambiar_clave, reintentos_fallidos)
               values ('diag.rejilla', 'diag.rejilla@synpex.local', sypex_hash_password('Diag#2026'),
                       'ACTIVO', 1, (select id_rol from syn_roles where codigo_rol = 'ADMIN'), 'N', 0)""")
conn.commit()

nav = Nav()
try:
    nav.js('window.location.href="%s/f?p=100:9999"' % BASE)
    nav.esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(1)
    nav.js('(function(){apex.item("P9999_USERNAME").setValue(%s);apex.item("P9999_PASSWORD").setValue(%s);'
           'var b=[...document.querySelectorAll("button")].find(x=>/sign in|iniciar|entrar/i.test(x.innerText));'
           'if(b){b.click();}})()' % (json.dumps(USUARIO), json.dumps(CLAVE)))
    time.sleep(7)
    m = re.search(r"session=(\d+)", nav.js("window.location.href") or "")
    if not m:
        comprobar("login", False, (nav.js("document.body.innerText") or "")[:160])
        raise SystemExit(1)
    ses = m.group(1)

    # --- G1/G2: dialogo de la factura (pagina 9) desde la lista (8)
    nav.js('window.location.href="%s/f?p=100:8:%s"' % (BASE, ses))
    nav.esperar('!!document.getElementById("P8_ID_FACTURAS")', 40)
    time.sleep(4)
    abierto = abre_dialogo(nav, "P9_TIPO_DOCUMENTO",
                           '(function(){var as=[...document.querySelectorAll("td a")].filter(function(a){'
                           'return /Editar/.test(a.innerText);});'
                           'if(!as.length) return null;'
                           # La fila de indicadores empuja la lista hacia abajo: sin
                           # esto, en una ventana baja el clic por coordenadas cae
                           # fuera de la pantalla y el dialogo no se abre.
                           'as[0].scrollIntoView({block:"center"});'
                           'var r=as[0].getBoundingClientRect();'
                           'return JSON.stringify({x:r.left+r.width/2,y:r.top+r.height/2});})()')
    comprobar("G1 el dialogo de la factura (9) abre", abierto)
    texto = texto_dialogo(nav)
    comprobar("G2 la 9 no muestra el error de rejilla",
              "grid settings" not in texto.lower() and "column 13" not in texto.lower(),
              "(" + texto.strip().replace("\n", " ")[:90] + ")")
    for campo in ("P9_PORCENTAJE_RETENCION", "P9_RETENCION_IVA_BS", "P9_NRO_COMPROBANTE_RETENCION"):
        comprobar(f"G1 el campo {campo} se pinta", hay_item(nav, campo))
    nav.captura(os.path.join(REPO, "deploy", "resultados", "20261117_rejilla_p9.png"))

    # --- G3: dialogo de editar usuario (pagina 4) desde la lista (3)
    nav.js('window.location.href="%s/f?p=100:3:%s"' % (BASE, ses))
    nav.esperar('!!document.getElementById("R43000000000000092") || document.readyState==="complete"', 40)
    time.sleep(5)
    abierto4 = abre_dialogo_js(nav, "P4_USERNAME",
                               '(function(){var a=document.querySelector(\'td a[href*="a-dialog-open"]\');'
                               'if(a){a.click();}})()')
    comprobar("G3 el dialogo de editar usuario (4) abre", abierto4)
    texto4 = texto_dialogo(nav)
    comprobar("G3 la 4 no muestra el error de rejilla",
              "grid settings" not in texto4.lower() and "column 13" not in texto4.lower(),
              "(" + texto4.strip().replace("\n", " ")[:90] + ")")
    nav.captura(os.path.join(REPO, "deploy", "resultados", "20261117_rejilla_p4.png"))
finally:
    nav.cerrar()
    cur.execute("delete from syn_login_log where upper(usuario_intentado) = 'DIAG.REJILLA'")
    cur.execute("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario "
                "where upper(username) = 'DIAG.REJILLA'); commit; "
                "delete from usuario where upper(username) = 'DIAG.REJILLA'; commit; end;")
    conn.commit()
    conn.close()

print()
print("RESULTADO: FALLAS=" + str(len(fallas)))
for f in fallas:
    print("  - " + f)
sys.exit(1 if fallas else 0)
