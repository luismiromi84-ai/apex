#!/usr/bin/env python3
# =============================================================================
# 20261121_impresos_capturas.py
#
# El logo en todos los impresos y el recibo en papel, con navegador real:
#
#   P31  el comprobante de retencion (31) se abre desde la compra (28) y pinta el
#        logo de la empresa (la imagen carga: naturalWidth > 0)
#   P30  el libro en modo imprimir/PDF (30) pinta el logo y NO abre el dialogo de
#        impresion (aqui window.print esta intervenido para poder capturar)
#   P35  el recibo impreso (35) se abre con la URL que arma apex_page.get_url en
#        el dialogo del recibo (25), y trae logo, numero, cliente y los cuatro
#        importes
#
# Capturas (deploy/resultados/):
#   20261121_impresos_31.png · 20261121_impresos_30.png · 20261121_impresos_35.png
#
# Uso: python deploy/diagnostico/20261121_impresos_capturas.py
# Crea y borra su propio usuario temporal. No escribe nada de negocio.
# =============================================================================
import base64
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request

import oracledb
import websocket

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
BASE = "https://gfd7e2575d251ae-sypexsql.adb.mx-monterrey-1.oraclecloudapps.com/ords"
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(REPO, "deploy", "conexion"))
from verificar_conexion import CONNECT_STRING as CS, credenciales  # noqa: E402

USUARIO, CLAVE = "diag.imp", "Diag#2026"
SALIDA = os.path.join(REPO, "deploy", "resultados")
PUERTO = 9298

fallas = []


def comprobar(nombre, ok, detalle=""):
    print(("  OK  " if ok else "  MAL ") + nombre + ("" if ok else "  " + str(detalle)[:300]))
    if not ok:
        fallas.append(nombre)


def omitir(nombre, motivo):
    print("  OMIT " + nombre + "  " + motivo)


class Nav:
    def __init__(self):
        self.proc = subprocess.Popen(
            [EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
             "--window-size=1440,1000", f"--remote-debugging-port={PUERTO}",
             "--user-data-dir=" + os.path.join(tempfile.gettempdir(), "opencode", "edge-imp21"),
             "about:blank"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        objetivo = None
        for _ in range(40):
            try:
                lista = json.loads(urllib.request.urlopen(
                    f"http://127.0.0.1:{PUERTO}/json/list", timeout=2).read())
                pag = [t for t in lista if t.get("type") == "page"]
                if pag:
                    objetivo = pag[0]
                    break
            except Exception:
                pass
            time.sleep(0.5)
        self.ws = websocket.create_connection(objetivo["webSocketDebuggerUrl"], timeout=60)
        self.ws.settimeout(60)
        self.n = 0
        self.cmd("Page.enable")
        self.cmd("Runtime.enable")
        # window.print() lo dispara solo la 30 (y el boton de la 31/35). En headless
        # no hay dialogo, pero se interviene para que la captura no dependa de eso.
        self.cmd("Page.addScriptToEvaluateOnNewDocument",
                 source="window.print=function(){window.__impreso=(window.__impreso||0)+1;};")

    def cmd(self, method, **params):
        self.n += 1
        self.ws.send(json.dumps({"id": self.n, "method": method, "params": params}))
        while True:
            r = json.loads(self.ws.recv())
            if r.get("method") == "Page.javascriptDialogOpening":
                self.n += 1
                self.ws.send(json.dumps({"id": self.n, "method": "Page.handleJavaScriptDialog",
                                         "params": {"accept": True}}))
                continue
            if r.get("id") == self.n:
                return r.get("result", {})

    def js(self, expr):
        r = self.cmd("Runtime.evaluate", expression=expr, returnByValue=True, awaitPromise=True)
        if "exceptionDetails" in r:
            return "EXC: " + str(r["exceptionDetails"].get("exception", {}).get("description"))[:300]
        return r.get("result", {}).get("value")

    def esperar(self, cond, seg=45):
        fin = time.time() + seg
        while time.time() < fin:
            if self.js(cond):
                return True
            time.sleep(0.5)
        return False

    def captura(self, ruta):
        r = self.cmd("Page.captureScreenshot", format="png")
        datos = r.get("data")
        if not datos:
            return False
        with open(ruta, "wb") as fh:
            fh.write(base64.b64decode(datos))
        return True

    def cerrar(self):
        try:
            self.proc.terminate()
        except Exception:
            pass


# El logo del documento: la etiqueta <img> que pinta pkg_empresa_logo.
LOGO = """(function(){var i=document.querySelector('img[alt="Logo de la empresa"]');
  if(!i){return 0;} return i.naturalWidth || 0;})()"""

EN_DIALOGO = """(function(){var f=document.querySelector("iframe");
  if(!f){return "SIN DIALOGO";}
  var w=f.contentWindow;var d=w.document;var apex=w.apex;%s})()"""

conn = oracledb.connect(user=credenciales()["DB_USER"], password=credenciales()["DB_PASSWORD"], dsn=CS)
cur = conn.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")
cur.execute("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario "
            "where upper(username) = 'DIAG.IMP'); commit; "
            "delete from usuario where upper(username) = 'DIAG.IMP'; commit; end;")
cur.execute("""insert into usuario (username, email, password_hash, estado, id_empresa, rol_id,
                                    debe_cambiar_clave, reintentos_fallidos)
               values (:u, :e, sypex_hash_password(:c), 'ACTIVO', 1,
                       (select id_rol from syn_roles where codigo_rol = 'ADMIN'), 'N', 0)""",
            u=USUARIO, e=USUARIO + "@synpex.local", c=CLAVE)
conn.commit()

# Una compra REGISTRADA con comprobante de IVA, de una empresa con logo.
cur.execute("""select c.id_compra
                 from compras c
                where c.estado = 'REGISTRADA'
                  and exists (select 1 from retenciones r
                               where r.id_compra = c.id_compra and r.tipo = 'IVA'
                                 and nvl(r.estado, 'EMITIDO') <> 'ANULADO')
                  and exists (select 1 from empresa_logo l where l.id_empresa = c.id_empresa)
                order by c.id_compra desc fetch first 1 rows only""")
fila = cur.fetchone()
COMPRA = fila[0] if fila else None
# Un recibo EMITIDO (ACTIVO) con logo: es la vista normal del papel. Se guarda
# tambien uno anulado para comprobar la banda roja.
cur.execute("""select r.id_recibo
                 from recibos r
                where r.estado = 'ACTIVO'
                  and exists (select 1 from empresa_logo l where l.id_empresa = r.id_empresa)
                order by r.id_recibo desc fetch first 1 rows only""")
fila = cur.fetchone()
RECIBO = fila[0] if fila else None
if RECIBO is None:
    cur.execute("""select r.id_recibo from recibos r
                    where exists (select 1 from empresa_logo l where l.id_empresa = r.id_empresa)
                    order by r.id_recibo desc fetch first 1 rows only""")
    fila = cur.fetchone()
    RECIBO = fila[0] if fila else None
    ANULADO = None
else:
    cur.execute("""select r.id_recibo from recibos r
                    where r.estado = 'ANULADO'
                      and exists (select 1 from empresa_logo l where l.id_empresa = r.id_empresa)
                    order by r.id_recibo desc fetch first 1 rows only""")
    fila = cur.fetchone()
    ANULADO = fila[0] if fila else None

nav = Nav()
try:
    nav.js('window.location.href="%s/f?p=100:9999"' % BASE)
    nav.esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(1)
    nav.js('(function(){apex.item("P9999_USERNAME").setValue(%s);apex.item("P9999_PASSWORD").setValue(%s);'
           'var b=[...document.querySelectorAll("button")].find(x=>/sign in|iniciar|entrar/i.test(x.innerText));'
           'if(b){b.click();}})()' % (json.dumps(USUARIO), json.dumps(CLAVE)))
    time.sleep(9)
    m = re.search(r"session=(\d+)", nav.js("window.location.href") or "")
    if not m:
        raise SystemExit("no se pudo entrar: " + str(nav.js("document.body.innerText"))[:200])
    ses = m.group(1)

    # ------------------------------------------------- Comprobante de retencion (31)
    print("Comprobante de retencion (31)")
    if COMPRA is None:
        omitir("P31", "(no hay compra REGISTRADA con comprobante de IVA)")
    else:
        nav.js('window.location.href="%s/f?p=100:27:%s"' % (BASE, ses))
        nav.esperar('document.readyState === "complete" && !!window.apex', 60)
        time.sleep(6)
        abierto = nav.js('(function(){var a=[...document.querySelectorAll("a")].find(function(x){'
                         'return (x.getAttribute("href")||"").indexOf("p28_id_compra%%3D%d")>=0'
                         '||(x.getAttribute("href")||"").indexOf("p28_id_compra=%d")>=0;});'
                         'if(a){a.click();return "CLIC";}return "NO";})()' % (COMPRA, COMPRA))
        time.sleep(9)
        comprobar("P31 la compra se abre desde la lista", abierto == "CLIC", abierto)
        clic = nav.js('(function(){var b=[...document.querySelectorAll("button,a")].find(function(x){'
                      'return (x.getAttribute("data-otel-label")||"")==="BTN_IMPRIMIR_RETENCION";});'
                      'if(!b)return "NO";b.click();return "CLIC";})()')
        time.sleep(10)
        texto = (nav.js("document.body.innerText") or "").upper()
        comprobar("P31 el comprobante se imprime",
                  clic == "CLIC" and "COMPROBANTE DE RETENCI" in texto and "I.V.A." in texto,
                  (clic, texto[:120]))
        ancho = nav.js(LOGO)
        comprobar("P31 el comprobante pinta el logo de la empresa", (ancho or 0) > 0, ancho)
        comprobar("P31 el boton Imprimir no sale en el papel",
                  nav.js('!!document.querySelector("button.u-no-print")') is True)
        nav.js("window.scrollTo(0,0)")
        time.sleep(1)
        comprobar("P31 captura", nav.captura(os.path.join(SALIDA, "20261121_impresos_31.png")))

    # ------------------------------------------------- Libro imprimible (30)
    print("Libro en modo imprimir/PDF (30)")
    nav.js('window.location.href="%s/f?p=100:30:%s"' % (BASE, ses))
    nav.esperar('document.readyState === "complete" && !!window.apex', 60)
    time.sleep(10)
    texto = (nav.js("document.body.innerText") or "").upper()
    comprobar("P30 el libro sale con su membrete",
              "LIBRO DE COMPRAS Y VENTAS" in texto, texto[:150])
    ancho = nav.js(LOGO)
    comprobar("P30 el libro imprimible pinta el logo", (ancho or 0) > 0, ancho)
    comprobar("P30 la pagina en papel esconde el cromo de APEX",
              nav.js('(function(){var s=[...document.querySelectorAll("style")].map(function(e){return e.textContent;}).join(" ");'
                     'return s.indexOf("@page")>=0;})()') is True)
    nav.js("window.scrollTo(0,0)")
    time.sleep(1)
    comprobar("P30 captura", nav.captura(os.path.join(SALIDA, "20261121_impresos_30.png")))

    # ------------------------------------------------- Recibo impreso (35)
    print("Recibo impreso (35)")
    if RECIBO is None:
        omitir("P35", "(no hay recibos)")
    else:
        pruebas = [(RECIBO, "20261121_impresos_35.png", False)]
        if ANULADO is not None:
            pruebas.append((ANULADO, "20261121_impresos_35_anulado.png", True))
        for cual, archivo, anulado in pruebas:
            cola = " (anulado)" if anulado else ""
            nav.js('window.location.href="%s/f?p=100:24:%s"' % (BASE, ses))
            nav.esperar('document.readyState === "complete" && !!document.querySelector("table.a-IRR-table")', 60)
            time.sleep(6)
            abierto = nav.js('(function(){var a=document.querySelector(\'a[href*="p25_id_recibo%%3D%d"]\')'
                             '||document.querySelector(\'a[href*="p25_id_recibo=%d"]\');'
                             'if(a){a.click();return "CLIC";}return "NO";})()' % (cual, cual))
            time.sleep(10)
            comprobar("P35 el recibo se abre desde la lista" + cola, abierto == "CLIC", abierto)
            boton = nav.js(EN_DIALOGO % 'var b=d.getElementById("B43000000000001547");'
                                         'return b?b.innerText.trim():"NO";')
            comprobar("P35 el dialogo tiene el boton Imprimir recibo" + cola,
                      boton == "Imprimir recibo", boton)
            url = nav.js(EN_DIALOGO % 'var i=d.getElementById("P25_URL_IMPRESO");'
                                       'return i?(i.value||""):"NO";')
            # Dentro de un dialogo, apex_page.get_url devuelve la URL envuelta en el
            # cierre del modal (#action$a-dialog-close?target=<url>&isModal=true): el
            # boton cierra el dialogo y abre la 35 en la ventana padre. El destino
            # sigue siendo la 35 con su checksum; se saca de target= para capturar.
            plano = urllib.parse.unquote(url if isinstance(url, str) else "")
            m = re.search(r"[?&]target=([^&]+)", url if isinstance(url, str) else "")
            destino = urllib.parse.unquote(m.group(1)) if m else (url if isinstance(url, str) else "")
            comprobar("P35 la URL del impreso la arma APEX (lleva checksum)" + cola,
                      "p35_id_recibo" in plano.lower() and "cs=" in plano.lower(), plano[-120:])
            comprobar("P35 la URL lleva el id del recibo" + cola,
                      ("p35_id_recibo=%d" % cual) in plano.lower(), plano[-120:])
            if "p35_id_recibo" not in destino.lower():
                comprobar("P35 abrir el impreso" + cola, False, destino)
                continue
            if destino.startswith("/"):
                destino = "https://gfd7e2575d251ae-sypexsql.adb.mx-monterrey-1.oraclecloudapps.com" + destino
            nav.js('window.location.href=%s' % json.dumps(destino))
            nav.esperar('document.readyState === "complete" && !!window.apex', 60)
            time.sleep(8)
            texto = (nav.js("document.body.innerText") or "").upper()
            comprobar("P35 el recibo sale con su titulo" + cola, "RECIBO DE COBRO" in texto, texto[:150])
            comprobar("P35 el recibo trae su numero" + cola, str(cual) in texto, texto[:200])
            comprobar("P35 el recibo trae los cuatro importes" + cola,
                      all(c in texto for c in ("MONTO COBRADO", "IGTF", "RETENCI", "NETO")),
                      texto[:200])
            ancho = nav.js(LOGO)
            comprobar("P35 el recibo pinta el logo" + cola, (ancho or 0) > 0, ancho)
            comprobar("P35 el recibo tiene el boton Imprimir" + cola,
                      nav.js('!!document.querySelector("button.u-no-print")') is True)
            if anulado:
                comprobar("P35 un recibo anulado lleva la banda roja",
                          nav.js('!!document.querySelector(".rc-anulado")') is True)
            else:
                comprobar("P35 un recibo vigente NO lleva la banda roja",
                          nav.js('!!document.querySelector(".rc-anulado")') is False)
            nav.js("window.scrollTo(0,0)")
            time.sleep(1)
            comprobar("P35 captura" + cola, nav.captura(os.path.join(SALIDA, archivo)))
finally:
    nav.cerrar()
    try:
        cur.execute("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario "
                    "where upper(username) = 'DIAG.IMP'); commit; "
                    "delete from usuario where upper(username) = 'DIAG.IMP'; commit; end;")
        conn.commit()
    except Exception as ex:
        print("limpieza:", ex)

print()
print("RESULTADO: FALLAS=%d" % len(fallas))
for f in fallas:
    print("  - " + f)
sys.exit(1 if fallas else 0)
