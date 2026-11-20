#!/usr/bin/env python3
"""
Verifica en navegador real que el comprobante de retencion del cliente se puede
registrar DESPUES de emitir la factura (2026-11-20).

Por que existe: en Venezuela el cliente entrega el comprobante dias despues de
recibir la factura, cuando ya esta TIMBRADA y fn_factura_editable la cierra. El
campo se podia teclear pero no habia forma de guardarlo: el boton Guardar no se
pinta en un documento cerrado. La via nueva es el boton «Guardar comprobante»
de la region «Acciones» (pagina 9), que llama a
pkg_facturacion.prc_registrar_comprobante_retencion sin tocar el documento.

Casos:
  C1  el dialogo de una factura TIMBRADA abre y el campo del comprobante esta
      editable (no de solo lectura)
  C2  el boton «Guardar comprobante» se pinta
  C3  el boton Guardar (edicion del documento) NO se pinta: el documento sigue
      cerrado
  C4  al teclear el numero y pulsar el boton sale «Comprobante registrado.»
  C5  el numero queda en la base y la factura sigue TIMBRADA, con los mismos
      importes y el mismo IVA retenido

La factura de prueba la crea y la borra el propio script (con su folio y su
control restaurados), asi que no toca documentos reales.

Uso:
    python deploy/diagnostico/20261120_comprobante_retencion_navegador.py
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

USUARIO, CLAVE = "diag.comprobante", "Diag#2026"
NRO = "20261100000042"

fallas = []


def comprobar(nombre, condicion, detalle=""):
    print(("  OK  " if condicion else "  MAL ") + nombre + (" " + str(detalle) if detalle else ""))
    if not condicion:
        fallas.append(nombre)


class Nav:
    def __init__(self, puerto=9285):
        self.proc = subprocess.Popen(
            [EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
             f"--remote-debugging-port={puerto}",
             f"--user-data-dir={os.path.join(tempfile.gettempdir(), 'opencode', 'edge-comprobante')}",
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
        datos = r.get("data")
        if datos:
            with open(ruta, "wb") as fh:
                fh.write(base64.b64decode(datos))
            return True
        return False


EN_IFRAME = ('(function(){var f=document.querySelector("iframe");'
             'if(!f||!f.contentDocument) return null; var d=f.contentDocument; '
             'return (%s);})()')


def js_dialogo(nav, expr):
    return nav.js(EN_IFRAME % expr)


def texto_dialogo(nav):
    return js_dialogo(nav, 'd.body ? (d.body.innerText||"") : ""') or ""


conn = oracledb.connect(user=credenciales()["DB_USER"], password=credenciales()["DB_PASSWORD"], dsn=CS)
cur = conn.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")

# --- usuario temporal ------------------------------------------------------
cur.execute("delete from syn_login_log where upper(usuario_intentado) = 'DIAG.COMPROBANTE'")
cur.execute("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario "
            "where upper(username) = 'DIAG.COMPROBANTE'); commit; "
            "delete from usuario where upper(username) = 'DIAG.COMPROBANTE'; commit; end;")
cur.execute("""insert into usuario (username, email, password_hash, estado, id_empresa, rol_id,
                                    debe_cambiar_clave, reintentos_fallidos)
               values ('diag.comprobante', 'diag.comprobante@synpex.local',
                       sypex_hash_password('Diag#2026'), 'ACTIVO', 1,
                       (select id_rol from syn_roles where codigo_rol = 'ADMIN'), 'N', 0)""")
conn.commit()

# --- contadores y factura de prueba ---------------------------------------
cur.execute("select tipo, ultimo from folio_contador where id_empresa = 1 and tipo in ('FAC', 'CONTROL')")
contadores = dict(cur.fetchall())

cur.execute("""select min(id_cliente) from clientes
                where id_empresa = 1 and nvl(estado, 'ACTIVO') = 'ACTIVO'""")
cliente = cur.fetchone()[0]
if cliente is None:
    sys.exit("No hay clientes activos en la empresa 1")

v_id = cur.var(oracledb.NUMBER)
cur.execute("""begin
                   pkg_facturacion.prc_guardar_factura(
                       p_id_factura => :id, p_id_empresa => 1, p_folio_factura => 'T-COMP',
                       p_id_cliente => :cli, p_id_presupuesto => null,
                       p_rfc_emisor => null, p_rfc_receptor => null, p_uuid_fiscal => null,
                       p_uso_cfdi => null, p_forma_pago => null, p_metodo_pago => null,
                       p_condicion_pago => null, p_fecha_emision => '01/11/2026',
                       p_fecha_vencimiento => null, p_estado => 'PENDIENTE',
                       p_subtotal => 0, p_monto_impuesto => 0, p_monto_total => 0,
                       p_observaciones => 'prueba navegador', p_cod_moneda => 'VES',
                       p_tipo_cambio => 1, p_usuario => 'VERIF',
                       p_tipo_documento => 'FAC', p_porcentaje_retencion => 75,
                       p_nro_comprobante_retencion => null);
               end;""", id=v_id, cli=cliente)
factura = int(v_id.getvalue())

cur.execute("""update facturas set subtotal = 1000, monto_impuesto = 160, monto_total = 1160,
                      retencion_iva_bs = 100
                where id_factura = :i""", i=factura)
cur.execute("begin pkg_facturacion.prc_procesar_factura(:i, 'VERIF'); end;", i=factura)
conn.commit()

cur.execute("""select folio_factura, estado, nro_comprobante_retencion, retencion_iva_bs, monto_total
                 from facturas where id_factura = :i""", i=factura)
folio, estado0, comp0, ret0, tot0 = cur.fetchone()
print(f"factura de prueba: {factura} ({folio}) {estado0} retencion {ret0} total {tot0} comprobante {comp0}")

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

    # La lista ordena por id_factura DESC, asi que la factura de prueba es la
    # primera fila: el primer «Editar» la abre.
    nav.js('window.location.href="%s/f?p=100:8:%s"' % (BASE, ses))
    nav.esperar('!!document.getElementById("P8_ID_FACTURAS")', 40)
    time.sleep(4)
    nav.js('(function(){var as=[...document.querySelectorAll("td a")].filter(function(a){'
           'return /Editar/.test(a.innerText);});'
           'if(!as.length) return null; as[0].scrollIntoView({block:"center"}); as[0].click();})()')
    abierto = nav.esperar(EN_IFRAME % '!!d.getElementById("P9_NRO_COMPROBANTE_RETENCION")', 45)
    comprobar("C1 el dialogo de la factura TIMBRADA abre", abierto)

    id_dialogo = js_dialogo(nav, 'd.getElementById("P9_ID_FACTURA") ? d.getElementById("P9_ID_FACTURA").value : null')
    comprobar("C1 el dialogo es el de la factura de prueba", str(id_dialogo) == str(factura), id_dialogo)

    solo_lectura = js_dialogo(
        nav,
        'JSON.stringify((function(){var e=d.getElementById("P9_NRO_COMPROBANTE_RETENCION");'
        'return {ro:e.readOnly===true||e.getAttribute("aria-readonly")==="true"'
        '||e.classList.contains("apex-item-text-readonly"),'
        'cls:e.className};})())')
    datos = json.loads(solo_lectura) if solo_lectura and solo_lectura.startswith("{") else {}
    comprobar("C1 el campo del comprobante esta editable", datos.get("ro") is False, datos)

    hay_boton = js_dialogo(
        nav,
        '[...d.querySelectorAll("button")].some(function(b){return /Guardar comprobante/i.test(b.innerText||"");})')
    comprobar("C2 el boton «Guardar comprobante» se pinta", hay_boton is True)

    hay_guardar = js_dialogo(
        nav,
        '[...d.querySelectorAll("button")].some(function(b){return /^Guardar$/i.test((b.innerText||"").trim());})')
    comprobar("C3 el boton Guardar del documento NO se pinta (sigue cerrado)", hay_guardar is False, hay_guardar)

    nav.captura(os.path.join(REPO, "deploy", "resultados", "20261120_comprobante_antes.png"))

    valores = js_dialogo(
        nav,
        'JSON.stringify(["P9_TIPO_CAMBIO","P9_COD_MONEDA","P9_FECHA_EMISION","P9_ESTADO"]'
        '.map(function(n){var e=d.getElementById(n);return n+"="+(e?e.value:"(sin item)");}))')
    print("    valores del dialogo:", valores)

    # Teclear el numero y pulsar el boton. OJO: `apex` hay que tomarlo del
    # contentWindow del iframe; el apex del padre no ve los items del modal y
    # setValue falla en silencio (trampa medida el 2026-11-17).
    nav.js('(function(){var f=document.querySelector("iframe");var w=f.contentWindow;var d=w.document;'
           'w.apex.item("P9_NRO_COMPROBANTE_RETENCION").setValue(%s);'
           'var b=[...d.querySelectorAll("button")].find(function(x){'
           'return /Guardar comprobante/i.test(x.innerText||"");});'
           'if(b){b.click();} return !!b;})()' % json.dumps(NRO))
    salio = nav.esperar(EN_IFRAME % '/Comprobante registrado/i.test(d.body.innerText||"")', 45)
    comprobar("C4 al pulsar el boton sale «Comprobante registrado.»", salio,
              (texto_dialogo(nav) or "").strip().replace("\n", " ")[:120])
    nav.captura(os.path.join(REPO, "deploy", "resultados", "20261120_comprobante_despues.png"))

    valor = js_dialogo(nav, 'd.getElementById("P9_NRO_COMPROBANTE_RETENCION") ? '
                            'd.getElementById("P9_NRO_COMPROBANTE_RETENCION").value : null')
    comprobar("C4 el campo muestra el numero guardado", str(valor) == NRO, valor)
finally:
    nav.cerrar()

cur.execute("""select estado, nro_comprobante_retencion, retencion_iva_bs, monto_total
                 from facturas where id_factura = :i""", i=factura)
estado1, comp1, ret1, tot1 = cur.fetchone()
print(f"en la base: {estado1} comprobante {comp1} retencion {ret1} total {tot1}")
comprobar("C5 el numero quedo en la base", (comp1 or "").strip() == NRO, comp1)
comprobar("C5 la factura sigue TIMBRADA", estado1 == "TIMBRADA", estado1)
comprobar("C5 los importes no se movieron", float(ret1) == float(ret0) and float(tot1) == float(tot0),
          f"{ret1}/{tot1} vs {ret0}/{tot0}")

# --- limpieza --------------------------------------------------------------
cur.execute("delete from facturas where id_factura = :i", i=factura)
for tipo, ultimo in contadores.items():
    cur.execute("update folio_contador set ultimo = :u where id_empresa = 1 and tipo = :t",
                u=ultimo, t=tipo)
cur.execute("delete from syn_login_log where upper(usuario_intentado) = 'DIAG.COMPROBANTE'")
cur.execute("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario "
            "where upper(username) = 'DIAG.COMPROBANTE'); commit; "
            "delete from usuario where upper(username) = 'DIAG.COMPROBANTE'; commit; end;")
conn.commit()
conn.close()

print()
print("RESULTADO: FALLAS=" + str(len(fallas)))
for f in fallas:
    print("  - " + f)
sys.exit(1 if fallas else 0)
