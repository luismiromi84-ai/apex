#!/usr/bin/env python3
"""
Comprueba en navegador real que la rejilla del dialogo de la factura (pagina 9)
llena las 12 columnas, en los dos estados del documento.

Por que existe: el dueño reporto el 2026-11-18 que el formulario "seguia
teniendo espacio" a la derecha. Medido: la fila Fecha Emision + Presupuesto +
RIF Emisor terminaba en 521 de 680 px (3 columnas vacias) porque Presupuesto y
Factura origen comparten casilla y el que queda oculto (display:none) dejaba su
hueco; y Cobrado + Saldo solo ocupaban media fila (6 de 12 columnas).

El arreglo: Cobrado y Saldo pasan a `p_colspan=>6` y el item visible del par
Presupuesto/Factura origen recibe la clase `spx-origen-ancho` (6 columnas) desde
el JS `spxVer`, con la rejilla de base intacta para que el peor caso del
servidor siga sumando 12 (si no, APEX devuelve HTTP 400).

Comprobaciones:
  Q1  el dialogo de la factura abre
  Q2  no aparece el error de rejilla de APEX
  Q3  en una factura normal, ninguna fila deja hueco a la derecha
  Q4  Cobrado y Saldo ocupan media fila cada uno
  Q5  en una factura normal se ve Presupuesto (ancho) y no Factura origen
  Q6  con tipo NC se ve Factura origen (ancho) y no Presupuesto
  Q7  con tipo NC tampoco queda hueco

Uso:
    python deploy/diagnostico/20261118_pagina9_rejilla.py
Requiere: websocket-client, oracledb y Edge instalado.
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
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(REPO, "deploy", "conexion"))
from verificar_conexion import CONNECT_STRING as CS, credenciales  # noqa: E402

USUARIO, CLAVE = "diag.rejilla", "Diag#2026"
TOLERANCIA = 5      # px
MEDIA_FILA = 300    # px; 6 de 12 columnas del cuerpo (~320)

fallas = []


def comprobar(nombre, condicion, detalle=""):
    print(("  OK  " if condicion else "  MAL ") + nombre + (" " + str(detalle) if detalle else ""))
    if not condicion:
        fallas.append(nombre)


class Nav:
    def __init__(self, puerto=9280):
        self.proc = subprocess.Popen(
            [EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
             "--window-size=1440,1100",
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
            return "EXC: " + str(r["exceptionDetails"].get("exception", {}).get("description"))[:300]
        return r.get("result", {}).get("value")

    def esperar(self, cond, seg=40):
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

    def captura(self, ruta):
        import base64
        r = self.cmd("Page.captureScreenshot", format="png")
        datos = r.get("data")
        if datos:
            with open(ruta, "wb") as fh:
                fh.write(base64.b64decode(datos))
            return True
        return False

    def cerrar(self):
        try:
            self.proc.terminate()
        except Exception:
            pass


MEDIDAS = """(function(){
  var f=document.querySelector("iframe");
  if(!f||!f.contentDocument) return "sin iframe";
  var d=f.contentDocument, filas=[];
  var ancho = 0;
  d.querySelectorAll(".t-Form-fieldContainer").forEach(function(c){
     var b=c.getBoundingClientRect();
     if (b.width === 0) { return; }
     var col=c.closest(".col");
     filas.push({id:(c.getAttribute("id")||"").replace("_CONTAINER",""),
                 x:Math.round(b.left), w:Math.round(b.width), y:Math.round(b.top),
                 oculto: col ? (d.defaultView.getComputedStyle(col).display === "none") : false});
  });
  /* Referencia: el borde derecho del item mas ancho (Observaciones ocupa las 12
     columnas siempre), no el .row, que lleva margenes negativos del gutter. */
  filas.forEach(function(it){ ancho = Math.max(ancho, it.x + it.w); });
  return JSON.stringify({ancho:ancho, items:filas});
})()"""

PON_TIPO = """(function(t){
  var f=document.querySelector("iframe"), d=f.contentDocument, w=f.contentWindow;
  (function(apex, jq){
    apex.item("P9_TIPO_DOCUMENTO").setValue(t);
    jq("#P9_TIPO_DOCUMENTO").trigger("change");
  })(w.apex, w.apex.jQuery);
  return "ok";
})("""

TEXTO = ('(function(){var f=document.querySelector("iframe");'
         'return f&&f.contentDocument ? (f.contentDocument.body.innerText||"") : "";})()')


def filas(datos):
    """Agrupa las medidas por fila (mismo `y`) y devuelve [(y, fin, ancho, hueco)]."""
    salida, y, fin = [], None, 0
    for it in datos["items"]:
        if y is not None and it["y"] != y:
            salida.append((y, fin, datos["ancho"], fin < datos["ancho"] - TOLERANCIA))
            fin = 0
        y = it["y"]
        fin = max(fin, it["x"] + it["w"])
    if y is not None:
        salida.append((y, fin, datos["ancho"], fin < datos["ancho"] - TOLERANCIA))
    return salida


def por_id(datos, nombre):
    for it in datos["items"]:
        if it["id"] == nombre:
            return it
    return None


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
    time.sleep(8)
    m = re.search(r"session=(\d+)", nav.js("window.location.href") or "")
    comprobar("Q1 login con el usuario de diagnostico", bool(m),
              (nav.js("document.body.innerText") or "")[:80] if not m else "")
    if not m:
        raise SystemExit(1)
    ses = m.group(1)

    nav.js('window.location.href="%s/f?p=100:8:%s"' % (BASE, ses))
    nav.esperar('!!document.getElementById("P8_ID_FACTURAS")', 40)
    time.sleep(4)
    nav.clic('(function(){var as=[...document.querySelectorAll("td a")].filter(function(a){'
             'return /Editar/.test(a.innerText);});'
             'if(!as.length) return null; var r=as[0].getBoundingClientRect();'
             'return JSON.stringify({x:r.left+r.width/2,y:r.top+r.height/2});})()')
    abierto = nav.esperar('(function(){var f=document.querySelector("iframe");'
                          'return !!(f&&f.contentDocument&&'
                          'f.contentDocument.getElementById("P9_TIPO_DOCUMENTO"));})()', 40)
    comprobar("Q1 el dialogo de la factura (9) abre", abierto)
    time.sleep(2)
    texto = nav.js(TEXTO) or ""
    comprobar("Q2 la 9 no muestra el error de rejilla",
              "grid settings" not in texto.lower() and "column 13" not in texto.lower(),
              "(" + texto.strip().replace("\n", " ")[:80] + ")")

    # --- estado normal (FAC)
    fac = json.loads(nav.js(MEDIDAS))
    print(f"\n  cuerpo del formulario: {fac['ancho']} px")
    for y, fin, ancho, hueco in filas(fac):
        print(f"    fila y={y:>4} termina en {fin} de {ancho}" + ("   << HUECO" if hueco else ""))
    comprobar("Q3 en FAC ninguna fila deja hueco", not any(f[3] for f in filas(fac)),
              [f"{f[1]}/{f[2]}" for f in filas(fac) if f[3]])
    cobrado = por_id(fac, "P9_COBRADO")
    saldo = por_id(fac, "P9_SALDO")
    comprobar("Q4 Cobrado y Saldo ocupan media fila cada uno",
              bool(cobrado) and bool(saldo) and cobrado["w"] >= MEDIA_FILA and saldo["w"] >= MEDIA_FILA,
              f"({cobrado['w'] if cobrado else '?'} / {saldo['w'] if saldo else '?'} px)")
    pres = por_id(fac, "P9_ID_PRESUPUESTO")
    orig = por_id(fac, "P9_ID_FACTURA_ORIGEN")
    comprobar("Q5 en FAC se ve Presupuesto ancho y no Factura origen",
              bool(pres) and pres["w"] >= MEDIA_FILA and not orig,
              f"(presupuesto {pres['w'] if pres else '?'} px)")
    nav.captura(os.path.join(REPO, "deploy", "resultados", "20261118_pagina9_rejilla_fac.png"))

    # --- estado nota de credito (NC)
    nav.js(PON_TIPO + json.dumps("NC") + ")")
    time.sleep(6)
    nc = json.loads(nav.js(MEDIDAS))
    print("\n  con Tipo Documento = NC:")
    for y, fin, ancho, hueco in filas(nc):
        print(f"    fila y={y:>4} termina en {fin} de {ancho}" + ("   << HUECO" if hueco else ""))
    orig = por_id(nc, "P9_ID_FACTURA_ORIGEN")
    pres = por_id(nc, "P9_ID_PRESUPUESTO")
    comprobar("Q6 en NC se ve Factura origen ancho y no Presupuesto",
              bool(orig) and orig["w"] >= MEDIA_FILA and not pres,
              f"(factura origen {orig['w'] if orig else '?'} px)")
    comprobar("Q7 en NC ninguna fila deja hueco", not any(f[3] for f in filas(nc)),
              [f"{f[1]}/{f[2]}" for f in filas(nc) if f[3]])
    nav.captura(os.path.join(REPO, "deploy", "resultados", "20261118_pagina9_rejilla_nc.png"))
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
