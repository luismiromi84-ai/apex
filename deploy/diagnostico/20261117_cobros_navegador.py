#!/usr/bin/env python3
"""
Cobros de punta a punta en el navegador (2026-11-17).

  P1  la lista de cobros (24) abre y no da error de servidor
  P2  «Registrar cobro» abre el dialogo (25) con la LOV de facturas
  P3  al elegir la factura se llenan moneda y tasa y el IGTF queda en 0 (VES)
  P4  al cambiar la moneda a USD el IGTF se calcula y el neto = monto + IGTF
  P5  al guardar, el recibo queda y la factura pasa a PAGADA
  P6  la lista ya muestra el cobro con su neto

Deja la base como estaba (borra el recibo y la factura de prueba).

Uso:  python deploy/diagnostico/20261117_cobros_navegador.py
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

USUARIO, CLAVE = "diag.cobros", "Diag#2026"
FOLIO = "COB-ZZ-1"

fallas = []

def num(valor):
    """Los importes ya salen con mascara: quita separadores antes de comparar."""
    if valor is None:
        return 0.0
    texto = str(valor).strip().replace(" ", "")
    # 2026-11-25: la coma es decimal si va la ultima (1.234,56 o 919,8227: formato VE);
    # si no, es de miles (1,234.56: formato MX).
    if "," in texto and ("." not in texto or texto.rfind(",") > texto.rfind(".")):
        texto = texto.replace(".", "").replace(",", ".")
    else:
        texto = texto.replace(",", "")
    try:
        return float(texto)
    except ValueError:
        return 0.0




def comprobar(nombre, condicion, detalle=""):
    print(("  OK  " if condicion else "  MAL ") + nombre + (" " + str(detalle) if detalle else ""))
    if not condicion:
        fallas.append(nombre)


class Nav:
    def __init__(self, puerto=9290):
        self.proc = subprocess.Popen(
            [EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
             f"--remote-debugging-port={puerto}",
             f"--user-data-dir={os.path.join(tempfile.gettempdir(), 'opencode', 'edge-cobros')}",
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
        r = self.cmd("Runtime.evaluate", expression=expr, returnByValue=True, awaitPromise=True)
        if "exceptionDetails" in r:
            return "EXC: " + str(r["exceptionDetails"].get("exception", {}).get("description"))[:250]
        return r.get("result", {}).get("value")

    def esperar(self, cond, seg=30):
        fin = time.time() + seg
        while time.time() < fin:
            if self.js(cond):
                return True
            time.sleep(0.5)
        return False

    def clic(self, expresion):
        r = self.js(expresion)
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
        if r.get("data"):
            with open(ruta, "wb") as fh:
                fh.write(base64.b64decode(r["data"]))


def en_dialogo(nav, expr):
    return nav.js('(function(){var w=document.querySelector("iframe").contentWindow;'
                  'return (function(apex){' + expr + '})(w.apex);})()')


def clic_en_dialogo(nav, texto):
    r = nav.js('(function(){var f=document.querySelector("iframe"); var d=f.contentDocument;'
               'var b=[...d.querySelectorAll("button")].find(function(x){'
               'return /%s/i.test(x.innerText);}); if(!b) return null;'
               'var fb=f.getBoundingClientRect(), r=b.getBoundingClientRect();'
               'return JSON.stringify({x:fb.left+r.left+r.width/2, y:fb.top+r.top+r.height/2});})()'
               % texto)
    if not r or r == "null":
        return False
    d = json.loads(r)
    nav.cmd("Input.dispatchMouseEvent", type="mousePressed", x=d["x"], y=d["y"],
            button="left", clickCount=1)
    nav.cmd("Input.dispatchMouseEvent", type="mouseReleased", x=d["x"], y=d["y"],
            button="left", clickCount=1)
    return True


conn = oracledb.connect(user=credenciales()["DB_USER"],
                        password=credenciales()["DB_PASSWORD"], dsn=CS)
cur = conn.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")

# Estado original de la marca SPE de la empresa 1: la prueba necesita 'S' para que el
# IGTF se cause y al terminar tiene que devolver lo que hubiera (config del dueno).
ES_SPE_ORIGINAL = cur.execute(
    "select nvl(es_spe, 'N') from empresas where id_empresa = 1").fetchone()[0]


def limpia():
    # ORA-12860 si se borran el hijo y el padre en la misma transaccion: commit entre los dos.
    cur.execute("delete from recibos where id_factura in (select id_factura from facturas where folio_factura = :f)",
                f=FOLIO)
    conn.commit()
    cur.execute("delete from facturas where folio_factura = :f", f=FOLIO)
    conn.commit()
    # NO se toca EMPRESAS.ES_SPE: es configuracion del dueno (marca si la empresa es
    # Sujeto Pasivo Especial y por tanto si el IGTF se causa). Esta funcion se llama
    # tambien en el finally y dejaba la empresa 1 en 'N', o sea que la suite apagaba
    # el IGTF en produccion. El valor original se restaura en el finally.
    cur.execute("""update clientes set es_spe = 'N'
                    where id_cliente = (select id_cliente from facturas where folio_factura = :f)""",
                f=FOLIO)
    cur.execute("delete from syn_login_log where upper(usuario_intentado) = 'DIAG.COBROS'")
    cur.execute("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario "
                "where upper(username) = 'DIAG.COBROS'); commit; "
                "delete from usuario where upper(username) = 'DIAG.COBROS'; commit; end;")


limpia()
cur.execute("""insert into usuario (username, email, password_hash, estado, id_empresa, rol_id,
                                    debe_cambiar_clave, reintentos_fallidos)
               values ('diag.cobros', 'diag.cobros@synpex.local', sypex_hash_password('Diag#2026'),
                       'ACTIVO', 1, (select id_rol from syn_roles where codigo_rol = 'ADMIN'), 'N', 0)""")
cur.execute("""insert into facturas (id_empresa, id_cliente, tipo_documento, folio_factura,
                                    cod_moneda, tipo_cambio, fecha_emision, subtotal,
                                    monto_impuesto, monto_total, estado, creado_por)
               values (1, (select min(id_cliente) from clientes where id_empresa = 1),
                       'FAC', :f, 'VES', 1, sysdate - 2, 116, 0, 116, 'TIMBRADA', 'test')""",
            f=FOLIO)
cur.execute("update empresas set es_spe = 'S' where id_empresa = 1")
cur.execute("""update clientes set es_spe = 'S'
                where id_cliente = (select id_cliente from facturas where folio_factura = :f)""",
            f=FOLIO)
conn.commit()

fac = cur.execute("select id_factura from facturas where folio_factura = :f", f=FOLIO).fetchone()[0]
print(f"  factura de prueba: {fac} (116 VES, TIMBRADA, empresa SPE)")

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

    # P1: la lista
    nav.js('window.location.href="%s/f?p=100:24:%s"' % (BASE, ses))
    nav.esperar('document.readyState === "complete" && !!window.apex', 40)
    time.sleep(5)
    texto = nav.js("document.body.innerText") or ""
    comprobar("P1 la lista de cobros abre", "ORA-" not in texto and "Bad Request" not in texto,
              "(" + texto.strip().replace("\n", " ")[:70] + ")")
    comprobar("P1 trae los filtros y el boton",
              "Filtros" in texto and "Registrar cobro" in texto,
              "(" + texto.strip().replace("\n", " ")[-90:] + ")")

    # P2: el dialogo
    nav.clic('(function(){var b=[...document.querySelectorAll("button,a")].find(function(x){'
             'return /Registrar cobro/i.test(x.innerText);}); if(!b) return null;'
             'var r=b.getBoundingClientRect();'
             'return JSON.stringify({x:r.left+r.width/2,y:r.top+r.height/2});})()')
    abierto = nav.esperar('(function(){var f=document.querySelector("iframe");'
                          'return !!(f&&f.contentWindow&&f.contentDocument&&'
                          'f.contentDocument.getElementById("P25_ID_FACTURA"));})()', 60)
    comprobar("P2 el dialogo de cobro (25) abre", abierto)
    if not abierto:
        raise SystemExit(1)

    # P3: elegir la factura -> moneda y tasa, IGTF 0 (VES)
    en_dialogo(nav, 'apex.item("P25_ID_FACTURA").setValue("%d");' % fac)
    time.sleep(5)
    moneda = en_dialogo(nav, 'return apex.item("P25_COD_MONEDA").getValue();')
    tasa = en_dialogo(nav, 'return apex.item("P25_TIPO_CAMBIO").getValue();')
    comprobar("P3 la moneda se llena con la de la factura", str(moneda) == "VES", f"({moneda})")
    comprobar("P3 la tasa queda en 1", abs(num(tasa) - 1) < 0.001, f"({tasa})")

    en_dialogo(nav, 'apex.item("P25_MONTO").setValue(116);')
    time.sleep(4)
    igtf = en_dialogo(nav, 'return apex.item("P25_IGTF").getValue();')
    comprobar("P3 en bolivares el IGTF es 0", abs(num(igtf)) < 0.001, f"({igtf})")

    nav.captura(os.path.join(REPO, "deploy", "resultados", "20261117_cobros_25_ves.png"))

    # P4: en divisas el IGTF se calcula
    # primero el monto y despues la moneda: la ultima accion ve los dos valores
    en_dialogo(nav, 'apex.item("P25_MONTO").setValue(1);')
    time.sleep(2)
    en_dialogo(nav, 'apex.item("P25_COD_MONEDA").setValue("USD");')
    time.sleep(6)
    igtf_usd = num(en_dialogo(nav, 'return apex.item("P25_IGTF").getValue();'))
    neto_usd = en_dialogo(nav, 'return apex.item("P25_NETO").getValue();')
    comprobar("P4 en divisas el IGTF es el 3 % del monto", abs(igtf_usd - 0.03) < 0.011, f"({igtf_usd})")
    comprobar("P4 el neto suma el IGTF", abs(num(neto_usd) - (1 + igtf_usd)) < 0.02, f"({neto_usd})")
    nav.captura(os.path.join(REPO, "deploy", "resultados", "20261117_cobros_25_usd.png"))

    # P4b: el caso que reporto el dueno (factura USD, retencion en Bs):
    # 200 USD con 18.910,80 Bs retenidos -> neto 185,35 USD y el IGTF 6.
    # La tasa NO se fija a mano: al pasar a USD la accion la trae de la tabla para
    # la fecha del cobro, asi que la esperada se lee de la pantalla.
    en_dialogo(nav, 'apex.item("P25_COD_MONEDA").setValue("USD");')
    time.sleep(3)
    en_dialogo(nav, 'apex.item("P25_MONTO").setValue(200);')
    time.sleep(4)
    en_dialogo(nav, 'apex.item("P25_RETENCION").setValue(18910.8);')
    time.sleep(5)
    tasa_u = num(en_dialogo(nav, 'return apex.item("P25_TIPO_CAMBIO").getValue();'))
    neto = num(en_dialogo(nav, 'return apex.item("P25_NETO").getValue();'))
    neto_bs = num(en_dialogo(nav, 'return apex.item("P25_NETO_BS").getValue();'))
    igtf_u = num(en_dialogo(nav, 'return apex.item("P25_IGTF").getValue();'))
    print("  P4b tasa leida: %s" % tasa_u)
    comprobar("P4b el neto no resta bolivares de dolares",
              abs(neto - (200 - 18910.8 / tasa_u + 6)) < 0.05, f"({neto})")
    comprobar("P4b el IGTF es el 3 % del abono en divisas", abs(igtf_u - 6) < 0.05, f"({igtf_u})")
    comprobar("P4b el neto en bolivares cuadra",
              abs(neto_bs - (200 * tasa_u - 18910.8 + 6 * tasa_u)) < 1, f"({neto_bs})")
    nav.captura(os.path.join(REPO, "deploy", "resultados", "20261117_cobros_escenario_usd.png"))

    # P5: se cobra en bolivares el total. Se limpia la retencion y el IGTF de la
    # prueba anterior (una retencion en Bs mayor que el IVA se rechaza a proposito).
    en_dialogo(nav, 'apex.item("P25_RETENCION").setValue("");')
    time.sleep(2)
    en_dialogo(nav, 'apex.item("P25_COD_MONEDA").setValue("VES");')
    time.sleep(3)
    en_dialogo(nav, 'apex.item("P25_MONTO").setValue(1);')
    time.sleep(3)
    en_dialogo(nav, 'apex.item("P25_MONTO").setValue(116);')
    time.sleep(5)

    def cobrar():
        clic_en_dialogo(nav, "Guardar")
        time.sleep(9)
        fila = cur.execute("""select r.id_recibo, r.monto_cobrado, r.monto_neto, f.estado
                                from recibos r join facturas f on f.id_factura = r.id_factura
                               where f.folio_factura = :f and r.estado = 'ACTIVO'""",
                           f=FOLIO).fetchone()
        try:
            dicho = en_dialogo(nav, 'return document.body.innerText;') or ""
        except Exception:
            dicho = nav.js("document.body.innerText") or ""
        errores = [l for l in dicho.splitlines()
                   if "error" in l.lower() or "aviso" in l.lower() or "confirmaci" in l.lower()]
        if errores or fila is None:
            print("  pantalla tras guardar:", (" | ".join(errores) or dicho[:200]))
        return fila, dicho

    fila, dicho = cobrar()
    # ORDS corta las rafagas de peticiones con 429 («Too Many Requests»): si paso,
    # se espera y se reintenta UNA vez, que es lo que hace una persona.
    if fila is None and "Too Many Requests" in dicho:
        print("  (429 de ORDS: se espera y se reintenta)")
        time.sleep(15)
        fila, dicho = cobrar()
    comprobar("P5 el cobro se guarda", fila is not None)


    if fila:
        comprobar("P5 la factura queda PAGADA", fila[3] == "PAGADA", f"({fila[3]})")
        comprobar("P5 el monto es el de la factura", abs(float(fila[1]) - 116) < 0.01, f"({fila[1]})")

    # P6: la lista lo muestra
    nav.js('window.location.href="%s/f?p=100:24:%s"' % (BASE, ses))
    time.sleep(6)
    texto = nav.js("document.body.innerText") or ""
    comprobar("P6 la lista muestra el cobro", FOLIO in texto or "116" in texto)

    # P7: el cobro se abre desde la columna «Abrir» del Interactive Report.
    texto = nav.js('document.body.innerText') or ''
    comprobar('P7 la lista trae la columna Abrir', 'Abrir' in texto,
              f"({[l for l in texto.splitlines() if 'Abrir' in l][:1]})")
    enlace = nav.js('(function(){var a=document.querySelector(\'a[href*="p25_id_recibo"]\');'
                    'return a ? a.getAttribute("href") : "SIN ENLACE";})()')
    comprobar('P7 la columna Abrir enlaza a la 25',
              'p25_id_recibo' in str(enlace).lower(), f"({enlace})")

finally:
    nav.cerrar()
    limpia()
    cur.execute("update empresas set es_spe = :v where id_empresa = 1", v=ES_SPE_ORIGINAL)
    conn.commit()
    conn.close()

print()
print("RESULTADO: FALLAS=" + str(len(fallas)))
for f in fallas:
    print("  - " + f)
sys.exit(1 if fallas else 0)
