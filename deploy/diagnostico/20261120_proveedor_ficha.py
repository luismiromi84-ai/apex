#!/usr/bin/env python3
"""
Ficha del proveedor (pagina 33), en navegador real (2026-11-20).

La 33 es el espejo de la ficha del cliente (32) para el lado de las compras: se
llega desde el NOMBRE del proveedor en la lista (22) y muestra su cabecera,
cuatro indicadores, sus compras y los enlaces a editar y volver. El «Editar» de
la lista sigue abriendo el dialogo (23).

Comprueba:

  P1  el nombre del proveedor de la lista (22) lleva a la ficha (33) y no al dialogo
  P2  la cabecera trae el nombre, el RIF, la empresa y la insignia de estado
  P3  el icono distingue juridica (edificio) de natural (persona)
  P4  el telefono es un enlace tel:, el correo un mailto: y sale la direccion
  P5  salen las cuatro tarjetas con sus rotulos
  P6  los cuatro numeros son los de la base (misma cuenta que la region)
  P7  el informe trae las compras del proveedor y solo las suyas
  P8  la fila trae su N. de control y el estado como insignia
  P9  el «Ver compra» lleva a la 28 con su checksum
  P10 los botones «Editar proveedor» y «Volver» estan
  P11 un proveedor de OTRA empresa responde -20003
  P12 capturas a 1440 y 500 px

Uso:
    python deploy/diagnostico/20261120_proveedor_ficha.py
Requiere websocket-client y Edge instalado. Crea y borra su usuario y un
proveedor ajeno de prueba; no toca ningun dato del cliente.
"""
import base64
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

USUARIO, CLAVE = "diag.ficha33", "Diag#2026"
AJENO_NOMBRE = "Proveedor Ajeno ZZ"
RES = os.path.join(REPO, "deploy", "resultados")

fallas = []


def comprobar(nombre, condicion, detalle=""):
    print(("  OK  " if condicion else "  MAL ") + nombre + ((" " + str(detalle)) if detalle else ""))
    if not condicion:
        fallas.append(nombre)


class Nav:
    def __init__(self, puerto=9294):
        self.proc = subprocess.Popen(
            [EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
             "--remote-debugging-port=%d" % puerto,
             "--user-data-dir=" + os.path.join(tempfile.gettempdir(), "opencode", "edge-ficha33"),
             "--window-size=1440,900", "about:blank"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        objetivo = None
        for _ in range(40):
            try:
                lista = json.loads(urllib.request.urlopen(
                    "http://127.0.0.1:%d/json/list" % puerto, timeout=2).read())
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

    def esperar(self, cond, seg=40):
        fin = time.time() + seg
        while time.time() < fin:
            if self.js(cond):
                return True
            time.sleep(0.5)
        return False

    def captura(self, ruta):
        r = self.cmd("Page.captureScreenshot", format="png")
        if r.get("data"):
            with open(ruta, "wb") as fh:
                fh.write(base64.b64decode(r["data"]))
            return True
        return False

    def clic(self, expresion):
        r = self.js(expresion)
        if not r or r == "null":
            return False
        d = json.loads(r)
        for t in ("mousePressed", "mouseReleased"):
            self.cmd("Input.dispatchMouseEvent", type=t, x=d["x"], y=d["y"],
                     button="left", clickCount=1)
        return True

    def cerrar(self):
        try:
            self.proc.terminate()
        except Exception:
            pass


conn = oracledb.connect(user=credenciales()["DB_USER"], password=credenciales()["DB_PASSWORD"], dsn=CS)
cur = conn.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")


def limpia():
    cur.execute("delete from proveedores where razon_social = :n", n=AJENO_NOMBRE)
    cur.execute("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario "
                "where upper(username)=upper(:u)); commit; end;", u=USUARIO)
    cur.execute("delete from usuario where upper(username)=upper(:u)", u=USUARIO)
    cur.execute("delete from syn_login_log where upper(usuario_intentado)=upper(:u)", u=USUARIO)
    conn.commit()


# El proveedor de la empresa 1 con mas compras: asi la ficha tiene lista que mirar.
cur.execute("""select p.id_proveedor, p.razon_social, p.rif, p.telefono, p.email, p.direccion,
                      p.tipo_persona, p.estado, e.nombre_empresa
                 from proveedores p
                 join empresas e on e.id_empresa = p.id_empresa
                where p.id_empresa = 1
                order by (select count(*) from compras c
                           where c.id_proveedor = p.id_proveedor and c.id_empresa = p.id_empresa) desc,
                         p.id_proveedor
                fetch first 1 rows only""")
PROV = cur.fetchone()
ID_PROV, NOMBRE, RIF, TEL, EMAIL, DIREC, TIPO, ESTADO, EMPRESA = PROV
print("  proveedor de prueba:", ID_PROV, NOMBRE, "| empresa", EMPRESA, "| tipo", TIPO)

# Los cuatro indicadores, con la MISMA cuenta que la region de la pagina.
cur.execute("""select count(case when co.tipo_documento = 'FAC' and nvl(co.estado, '#') <> 'ANULADA'
                                 then 1 end),
                      nvl(sum(case when co.tipo_documento = 'FAC' and nvl(co.estado, '#') <> 'ANULADA'
                                   then co.monto_total * nvl(co.tipo_cambio, 1) end), 0),
                      nvl(sum(case when co.tipo_documento = 'FAC' and nvl(co.estado, '#') <> 'ANULADA'
                                   then co.retencion_iva_bs end), 0)
                 from compras co where co.id_proveedor = :p and co.id_empresa = 1""", p=ID_PROV)
KPI = cur.fetchone()
cur.execute("""select count(*) from retenciones r
                where r.id_proveedor = :p and r.id_empresa = 1 and r.estado = 'EMITIDO'""", p=ID_PROV)
KPI = tuple(KPI) + (cur.fetchone()[0],)
# Quinta tarjeta: lo que se le debe hoy (en bolivares, con la tasa de cada documento).
cur.execute("""select nvl(sum(fn_saldo_compra(co.id_compra) * nvl(co.tipo_cambio, 1)), 0),
                      count(case when fn_saldo_compra(co.id_compra) > 0.01 then 1 end)
                 from compras co
                where co.id_proveedor = :p and co.id_empresa = 1
                  and co.tipo_documento = 'FAC'
                  and co.estado in ('REGISTRADA', 'PARCIAL')""", p=ID_PROV)
KPI = tuple(KPI) + cur.fetchone()
print("  indicadores esperados (compras/total bs/retencion bs/comprobantes/por pagar/n):", KPI)

# Sus pagos (la region nueva de la ficha).
cur.execute("""select count(*), nvl(max(nvl(referencia, '-')), '-')
                 from pagos where id_proveedor = :p and id_empresa = 1""", p=ID_PROV)
PAGOS = cur.fetchone()
cur.execute("""select to_char(monto, 'FM999G999G999G990D00') from (
                 select monto, fecha_pago, id_pago from pagos
                  where id_proveedor = :p and id_empresa = 1
                  order by fecha_pago desc, id_pago desc) where rownum = 1""", p=ID_PROV)
fila_pago = cur.fetchone()
PAGOS = PAGOS + (fila_pago[0] if fila_pago else None,)
print("  pagos del proveedor:", PAGOS)

# Sus compras: todas (la nota de credito tambien sale en la lista).
cur.execute("""select co.folio_factura, co.tipo_documento, co.nro_control, co.cod_moneda,
                      co.monto_total, co.retencion_iva_bs,
                      fn_estado_compra(co.estado), co.estado
                 from compras co
                where co.id_proveedor = :p and co.id_empresa = 1
                order by co.fecha_emision desc, co.id_compra desc""", p=ID_PROV)
COMPRAS = cur.fetchall()
print("  compras del proveedor:", len(COMPRAS))

# Los numeros de control de las compras de OTROS proveedores: no deben salir.
cur.execute("""select nro_control from compras
                where id_empresa = 1 and id_proveedor <> :p and nro_control is not null""", p=ID_PROV)
AJENOS = [r[0] for r in cur.fetchall() if r[0]]

# Un proveedor de OTRA empresa (la 2), para la guarda de -20003. Se crea y se
# borra: la empresa 2 no tiene proveedores y no se tocan datos del cliente.
cur.execute("select count(*) from proveedores where id_empresa = 2")
if cur.fetchone()[0] == 0:
    cur.execute("""insert into proveedores (id_empresa, rif, razon_social, tipo_persona, estado,
                                            retener_iva, porcentaje_retencion, es_spe, dias_credito)
                   values (2, 'J-99999999-1', :n, 'J', 'ACTIVO', 'N', 0, 'N', 0)""", n=AJENO_NOMBRE)
    conn.commit()
cur.execute("""select id_proveedor, razon_social from proveedores
                where id_empresa = 2 order by id_proveedor fetch first 1 rows only""")
AJENO = cur.fetchone()
print("  proveedor ajeno:", AJENO)


def miles(v):
    # 2026-11-23: formato venezolano, ver la nota de 20261120_cliente_ficha.py.
    t = "{:,.2f}".format(float(v))
    return t.replace(",", "X").replace(".", ",").replace("X", ".")


limpia()
cur.execute("""insert into usuario (username, email, password_hash, estado, id_empresa, rol_id,
                                    debe_cambiar_clave, reintentos_fallidos)
               values (:u, 'diag.ficha33@synpex.local', sypex_hash_password('Diag#2026'),
                       'ACTIVO', 1, (select id_rol from syn_roles where codigo_rol='ADMIN'), 'N', 0)""",
            u=USUARIO)
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
        comprobar("login", False, (nav.js('document.body.innerText') or "")[:160])
        raise SystemExit(1)
    ses = m.group(1)

    # ---------------------------------------------------------------- P1
    nav.js('window.location.href="%s/f?p=100:22:%s"' % (BASE, ses))
    nav.esperar('document.readyState === "complete" && !!window.apex')
    nav.esperar('!!document.querySelector("#R43000000000000600 a.spx-nombre-link")', 40)
    time.sleep(2)
    nav.clic('(function(){var a=[...document.querySelectorAll("#R43000000000000600 a.spx-nombre-link")]'
             '.find(function(x){return (x.innerText||"").indexOf(%s)>=0;});if(!a){return null;}'
             'var r=a.getBoundingClientRect();'
             'return JSON.stringify({x:r.left+r.width/2,y:r.top+r.height/2});})()' % json.dumps(NOMBRE))
    llego = nav.esperar('document.readyState === "complete" && !!document.querySelector(".spx-ficha")', 45)
    url = nav.js("window.location.href") or ""
    print("  url:", url[:130])
    comprobar("P1 el nombre lleva a la ficha del proveedor (33)", llego
              and ("proveedor-ficha" in url.lower() or ":33:" in url), url[:100])
    comprobar("P1 la ficha NO abre el dialogo de edicion",
              not nav.js('!!document.querySelector("iframe")'))

    time.sleep(2)
    # ---------------------------------------------------------------- P2
    ficha = nav.js('(function(){var f=document.querySelector(".spx-ficha");'
                   'return f?(f.innerText||"").replace(/\\s+/g," ").trim():"";})()') or ""
    print("  cabecera:", ficha[:170])
    comprobar("P2 la cabecera trae el nombre", NOMBRE[:22] in ficha, ficha[:60])
    comprobar("P2 la cabecera trae el RIF", RIF in ficha, RIF)
    comprobar("P2 la cabecera trae la empresa", EMPRESA in ficha, EMPRESA)
    comprobar("P2 la cabecera trae la insignia de estado",
              nav.js('(function(){var b=document.querySelector(".spx-ficha .status-badge");'
                     'return b?b.className+"|"+b.innerText.trim():"";})()') ==
              "status-badge status-%s|%s" % (ESTADO, ESTADO),
              nav.js('(function(){var b=document.querySelector(".spx-ficha .status-badge");'
                     'return b?b.className:"";})()'))

    # ---------------------------------------------------------------- P3
    icono = nav.js('(function(){var e=document.querySelector(".spx-ficha-icono");'
                   'if(!e){return "sin icono";}'
                   'var t=(e.textContent||"").trim();return t?t.codePointAt(0):"vacio";})()')
    esperado_icono = 127970 if TIPO == "J" else 128100
    comprobar("P3 el icono es el de %s" % ("juridica (edificio)" if TIPO == "J" else "natural (persona)"),
              icono == esperado_icono, icono)

    # ---------------------------------------------------------------- P4
    contacto = nav.js('(function(){var f=document.querySelector(".spx-ficha");if(!f){return "{}";}'
                      'var t=f.querySelector("a.spx-tel"), m=f.querySelector("a.spx-mail");'
                      'return JSON.stringify({tel:t?t.getAttribute("href"):"",'
                      ' mail:m?m.getAttribute("href"):"", texto:(f.innerText||"")});})()')
    d = json.loads(contacto) if contacto and contacto.startswith("{") else {}
    comprobar("P4 el telefono es un enlace tel:", (d.get("tel") or "").startswith("tel:"), d.get("tel"))
    comprobar("P4 el correo es un mailto:", (d.get("mail") or "").startswith("mailto:"), d.get("mail"))
    if DIREC:
        comprobar("P4 sale la direccion", DIREC[:18] in (d.get("texto") or ""), DIREC[:30])

    # ---------------------------------------------------------------- P5
    kpis = nav.js('(function(){var t=[];document.querySelectorAll(".spx-card").forEach(function(c){'
                  't.push(c.querySelector(".spx-card-lbl").innerText.trim()+"="+'
                  'c.querySelector(".spx-card-val").innerText.trim());});return t.join(" | ");})()')
    print("  tarjetas:", kpis)
    comprobar("P5 salen las cinco tarjetas", (kpis or "").count("=") == 5, kpis)
    k = (kpis or "").upper()
    comprobar("P5 los rotulos son los pedidos",
              "COMPRAS=" in k and "TOTAL COMPRAS (BS)=" in k and "RETENCI" in k and "(BS)=" in k
              and "COMPROBANTES=" in k and "POR PAGAR (BS)=" in k, kpis)

    # ---------------------------------------------------------------- P6
    # «—» cuando no hay nada; con compras, el numero.
    def valor(rotulo):
        mm = re.search(re.escape(rotulo) + r"=([^|]+)", k)
        return (mm.group(1).strip() if mm else "")

    comprobar("P6 «Compras» es el de la base",
              valor("COMPRAS") == (str(KPI[0]) if KPI[0] else "\u2014"), kpis)
    comprobar("P6 «Total compras (Bs)» es el de la base",
              valor("TOTAL COMPRAS (BS)") == (miles(KPI[1]) if KPI[0] else "\u2014"), kpis)
    comprobar("P6 «Retencion IVA (Bs)» es el de la base",
              valor("RETENCI\u00d3N IVA (BS)") == (miles(KPI[2]) if KPI[0] else "\u2014"), kpis)
    comprobar("P6 «Comprobantes» es el de la base",
              valor("COMPROBANTES") == (str(KPI[3]) if KPI[3] else "\u2014"), kpis)
    comprobar("P6 «Por pagar (Bs)» es el de la base",
              valor("POR PAGAR (BS)") == (miles(KPI[4]) if KPI[5] else "\u2014"),
              (valor("POR PAGAR (BS)"), KPI[4], KPI[5]))

    # ---------------------------------------------------------------- P8
    # La region nueva con sus pagos (si no tiene, lo dice).
    pagos_txt = nav.js('(function(){var r=document.getElementById("R43000000000001690");'
                       'return r?(r.innerText||"").replace(/\\s+/g," "):"SIN REGION";})()') or ""
    pagos_fil = nav.js('document.querySelectorAll("#R43000000000001690 tr").length')
    print("  pagos en pantalla: %s filas | %s" % (pagos_fil, pagos_txt[:120]))
    if PAGOS[0] > 0:
        comprobar("P8 la ficha lista los pagos del proveedor",
                  "no tiene pagos" not in pagos_txt.lower()
                  and PAGOS[2] is not None and PAGOS[2] in pagos_txt,
                  (PAGOS[2], pagos_txt[:120]))
    else:
        comprobar("P8 sin pagos la region lo dice",
                  "no tiene pagos" in pagos_txt.lower(), pagos_txt[:120])

    # ---------------------------------------------------------------- P7
    filas = nav.js('document.querySelectorAll("#R43000000000001382 a[href*=p28_id_compra]").length')
    comprobar("P7 el informe trae las compras del proveedor", filas == len(COMPRAS),
              "%s de %s" % (filas, len(COMPRAS)))
    texto = nav.js('(function(){var r=document.getElementById("R43000000000001382");'
                   'return r?(r.innerText||"").replace(/\\s+/g," "):"";})()') or ""
    comprobar("P7 el informe trae las compras de este proveedor",
              all((f[2] or "") in texto for f in COMPRAS), texto[:120])
    comprobar("P7 el informe no mezcla compras de otro proveedor",
              not any(c in texto for c in AJENOS), [c for c in AJENOS if c in texto])

    # ---------------------------------------------------------------- P8
    if COMPRAS:
        folio, tipo, control, moneda, total, ret, estado_txt, _ = COMPRAS[0]
        comprobar("P8 la fila %s muestra su N. de control (%s)" % (folio, control),
                  (control or "") in texto, texto[:120])
        comprobar("P8 la fila %s muestra el estado %s" % (folio, estado_txt),
                  estado_txt in texto, estado_txt)
    comprobar("P8 el estado se pinta como insignia",
              nav.js('document.querySelectorAll("#R43000000000001382 .status-badge").length') == len(COMPRAS),
              nav.js('document.querySelectorAll("#R43000000000001382 .status-badge").length'))

    # ---------------------------------------------------------------- P9
    ver = nav.js('(function(){var a=document.querySelector("#R43000000000001382 a[href*=p28_id_compra]");'
                 'if(!a){return "sin enlace";}'
                 'return decodeURIComponent(a.getAttribute("href"));})()') or ""
    print("  enlace Ver compra:", ver[:150])
    comprobar("P9 el «Ver compra» abre la 28", "p28_id_compra=" in ver, ver[:120])
    comprobar("P9 el enlace lleva checksum", "cs=" in ver, ver[-40:])

    # ---------------------------------------------------------------- P10
    botones = nav.js('(function(){var t=[];document.querySelectorAll("button").forEach(function(b){'
                     't.push((b.getAttribute("data-otel-label")||b.innerText||"").trim());});'
                     'return t.join(" | ");})()') or ""
    print("  botones:", botones[:120])
    comprobar("P10 esta «Editar proveedor»",
              "BTN_EDITAR_PROVEEDOR" in botones or "Editar proveedor" in botones, botones[:80])
    comprobar("P10 esta «Volver»", "BTN_VOLVER" in botones or "Volver" in botones, botones[:80])

    # ---------------------------------------------------------------- P12
    nav.js('window.scrollTo(0,0)')
    time.sleep(1)
    nav.captura(os.path.join(RES, "20261120_proveedor_ficha_1440.png"))
    nav.cmd("Emulation.setDeviceMetricsOverride", width=500, height=900,
            deviceScaleFactor=1, mobile=False)
    time.sleep(3)
    nav.js('window.scrollTo(0,0)')
    time.sleep(1)
    nav.captura(os.path.join(RES, "20261120_proveedor_ficha_500.png"))
    nav.cmd("Emulation.clearDeviceMetricsOverride")
    time.sleep(1)

    # ---------------------------------------------------------------- P11
    # Un proveedor de otra empresa: se cambia el item oculto y se envia la pagina
    # (el item no esta protegido, es un dato de pantalla). El proceso de la ficha
    # tiene que cortar con -20003.
    if AJENO:
        nav.js('apex.item("P33_ID_PROVEEDOR").setValue(%s); apex.submit({request:"DIAG"});' % json.dumps(str(AJENO[0])))
        time.sleep(8)
        cuerpo = nav.js('document.body.innerText') or ""
        comprobar("P11 un proveedor de otra empresa responde -20003",
                  ("ORA-20003" in cuerpo) or ("No tiene permisos sobre este proveedor" in cuerpo),
                  cuerpo.strip().replace("\n", " ")[:130])
        comprobar("P11 y no pinta la ficha del proveedor ajeno",
                  AJENO[1][:18] not in cuerpo, cuerpo[:60])
finally:
    nav.cerrar()
    limpia()
    conn.close()

print()
print("RESULTADO: FALLAS=" + str(len(fallas)))
for f in fallas:
    print("  - " + f)
sys.exit(1 if fallas else 0)
