#!/usr/bin/env python3
"""
Ficha del cliente (pagina 32), en navegador real (2026-11-20).

La 32 es la pantalla nueva: se llega desde el NOMBRE del cliente en la lista
(20) y muestra su cabecera, cuatro indicadores y sus documentos. El «Editar»
de la lista sigue abriendo el dialogo (21).

Comprueba:

  F1  el nombre del cliente de la lista (20) lleva a la ficha (32) y no al dialogo
  F2  la cabecera trae el nombre, el RIF, la empresa y la insignia de estado
  F3  el icono distingue juridica (edificio) de natural (persona)
  F4  el telefono es un enlace tel: y el correo un mailto:, y sale la direccion
  F5  salen las cuatro tarjetas con sus rotulos
  F6  los cuatro numeros son los de la base (misma cuenta que la region)
  F7  el informe trae los documentos del cliente y solo los suyos
  F8  el saldo de la fila es fn_saldo_factura y el estado la insignia
  F9  el «Ver» lleva a la 9 en modo consulta (P9_MODO_VER=S) con su checksum
  F10 los botones «Editar cliente» y «Volver» estan
  F11 un cliente de OTRA empresa responde -20003
  F12 capturas a 1440 y 500 px

Uso:
    python deploy/diagnostico/20261120_cliente_ficha.py
Requiere websocket-client y Edge instalado.
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

USUARIO, CLAVE = "diag.ficha32", "Diag#2026"
RES = os.path.join(REPO, "deploy", "resultados")

fallas = []


def comprobar(nombre, condicion, detalle=""):
    print(("  OK  " if condicion else "  MAL ") + nombre + ((" " + str(detalle)) if detalle else ""))
    if not condicion:
        fallas.append(nombre)


class Nav:
    def __init__(self, puerto=9293):
        self.proc = subprocess.Popen(
            [EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
             "--remote-debugging-port=%d" % puerto,
             "--user-data-dir=" + os.path.join(tempfile.gettempdir(), "opencode", "edge-ficha32"),
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
    cur.execute("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario "
                "where upper(username)=upper(:u)); commit; end;", u=USUARIO)
    cur.execute("delete from usuario where upper(username)=upper(:u)", u=USUARIO)
    cur.execute("delete from syn_login_log where upper(usuario_intentado)=upper(:u)", u=USUARIO)
    conn.commit()


# El cliente de la empresa 1 con mas documentos: asi la ficha tiene lista, saldos
# y notas de credito que mirar.
cur.execute("""select c.id_cliente, c.razon_social, c.rif, c.telefono, c.email, c.direccion, c.tipo_persona,
                      c.estado, e.nombre_empresa
                 from clientes c
                 join empresas e on e.id_empresa = c.id_empresa
                where c.id_empresa = 1
                order by (select count(*) from facturas f
                           where f.id_cliente = c.id_cliente and f.id_empresa = c.id_empresa) desc,
                         c.id_cliente
                fetch first 1 rows only""")
CLI = cur.fetchone()
ID_CLI, NOMBRE, RIF, TEL, EMAIL, DIREC, TIPO, ESTADO, EMPRESA = CLI
print("  cliente de prueba:", ID_CLI, NOMBRE, "| empresa", EMPRESA, "| tipo", TIPO)

# Un cliente de OTRA empresa (la 2), para la guarda de -20003.
cur.execute("""select c.id_cliente, c.razon_social from clientes c
                where c.id_empresa = 2 and not exists (select 1 from usuario_empresa ue
                                                        join usuario u on u.usuario_id = ue.usuario_id
                                                       where upper(u.username) = upper(:u)
                                                         and ue.id_empresa = 2)
                order by c.id_cliente fetch first 1 rows only""", u=USUARIO)
AJENO = cur.fetchone()
print("  cliente ajeno:", AJENO)

# Los cuatro indicadores, con la MISMA cuenta que la region de la pagina.
cur.execute("""select count(case when tipo_documento = 'FAC' and nvl(estado, '#') <> 'ANULADA' then 1 end),
                      nvl(sum(case when tipo_documento = 'FAC' and estado in ('TIMBRADA', 'PARCIAL')
                                   then fn_saldo_factura(id_factura) * nvl(tipo_cambio, 1) end), 0),
                      nvl(sum(case when tipo_documento = 'FAC' and estado in ('TIMBRADA', 'PARCIAL')
                                    and fecha_vencimiento < trunc(sysdate)
                                   then fn_saldo_factura(id_factura) * nvl(tipo_cambio, 1) end), 0),
                      count(case when tipo_documento = 'NC' and nvl(estado, '#') <> 'ANULADA' then 1 end)
                 from facturas where id_cliente = :c and id_empresa = 1""", c=ID_CLI)
KPI = cur.fetchone()
print("  indicadores esperados (facturas/por cobrar/vencido/nc):", KPI)

# Los documentos de la ficha: todos los del cliente en su empresa.
cur.execute("""select f.folio_factura, f.tipo_documento,
                      case when f.tipo_documento = 'FAC' then fn_saldo_factura(f.id_factura) end,
                      fn_estado_factura(f.estado, (select e.cod_pais from empresas e
                                                    where e.id_empresa = f.id_empresa)),
                      f.id_factura
                 from facturas f
                where f.id_cliente = :c and f.id_empresa = 1
                order by f.fecha_emision desc, f.id_factura desc""", c=ID_CLI)
DOCS = cur.fetchall()
print("  documentos del cliente:", len(DOCS))


def miles(v):
    return "{:,.2f}".format(float(v))


limpia()
cur.execute("""insert into usuario (username, email, password_hash, estado, id_empresa, rol_id,
                                    debe_cambiar_clave, reintentos_fallidos)
               values (:u, 'diag.ficha32@synpex.local', sypex_hash_password('Diag#2026'),
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

    # ---------------------------------------------------------------- F1
    nav.js('window.location.href="%s/f?p=100:20:%s"' % (BASE, ses))
    nav.esperar('document.readyState === "complete" && !!window.apex')
    nav.esperar('!!document.querySelector("#R43000000000000501 a.spx-nombre-link")', 40)
    time.sleep(2)
    nav.clic('(function(){var a=[...document.querySelectorAll("#R43000000000000501 a.spx-nombre-link")]'
             '.find(function(x){return (x.innerText||"").indexOf(%s)>=0;});if(!a){return null;}'
             'var r=a.getBoundingClientRect();'
             'return JSON.stringify({x:r.left+r.width/2,y:r.top+r.height/2});})()' % json.dumps(NOMBRE))
    llego = nav.esperar('document.readyState === "complete" && !!document.querySelector(".spx-ficha")', 45)
    url = nav.js("window.location.href") or ""
    print("  url:", url[:130])
    comprobar("F1 el nombre lleva a la ficha del cliente (32)", llego
              and ("cliente-ficha" in url.lower() or ":32:" in url), url[:100])
    comprobar("F1 la ficha NO abre el dialogo de edicion",
              not nav.js('!!document.querySelector("iframe")'))

    time.sleep(2)
    # ---------------------------------------------------------------- F2
    ficha = nav.js('(function(){var f=document.querySelector(".spx-ficha");'
                   'return f?(f.innerText||"").replace(/\\s+/g," ").trim():"";})()') or ""
    print("  cabecera:", ficha[:170])
    comprobar("F2 la cabecera trae el nombre", NOMBRE[:22] in ficha, ficha[:60])
    comprobar("F2 la cabecera trae el RIF", RIF in ficha, RIF)
    comprobar("F2 la cabecera trae la empresa", EMPRESA in ficha, EMPRESA)
    comprobar("F2 la cabecera trae la insignia de estado",
              nav.js('(function(){var b=document.querySelector(".spx-ficha .status-badge");'
                     'return b?b.className+"|"+b.innerText.trim():"";})()') ==
              "status-badge status-%s|%s" % (ESTADO, ESTADO),
              nav.js('(function(){var b=document.querySelector(".spx-ficha .status-badge");'
                     'return b?b.className:"";})()'))

    # ---------------------------------------------------------------- F3
    icono = nav.js('(function(){var e=document.querySelector(".spx-ficha-icono");'
                   'if(!e){return "sin icono";}'
                   'var t=(e.textContent||"").trim();return t?t.codePointAt(0):"vacio";})()')
    esperado_icono = 127970 if TIPO == "J" else 128100
    comprobar("F3 el icono es el de %s" % ("juridica (edificio)" if TIPO == "J" else "natural (persona)"),
              icono == esperado_icono, icono)

    # ---------------------------------------------------------------- F4
    contacto = nav.js('(function(){var f=document.querySelector(".spx-ficha");if(!f){return "{}";}'
                      'var t=f.querySelector("a.spx-tel"), m=f.querySelector("a.spx-mail");'
                      'return JSON.stringify({tel:t?t.getAttribute("href"):"",'
                      ' mail:m?m.getAttribute("href"):"", texto:(f.innerText||"")});})()')
    d = json.loads(contacto) if contacto and contacto.startswith("{") else {}
    comprobar("F4 el telefono es un enlace tel:", (d.get("tel") or "").startswith("tel:"), d.get("tel"))
    comprobar("F4 el correo es un mailto:", (d.get("mail") or "").startswith("mailto:"), d.get("mail"))
    if DIREC:
        comprobar("F4 sale la direccion", DIREC[:18] in (d.get("texto") or ""), DIREC[:30])

    # ---------------------------------------------------------------- F5
    kpis = nav.js('(function(){var t=[];document.querySelectorAll(".spx-card").forEach(function(c){'
                  't.push(c.querySelector(".spx-card-lbl").innerText.trim()+"="+'
                  'c.querySelector(".spx-card-val").innerText.trim());});return t.join(" | ");})()')
    print("  tarjetas:", kpis)
    comprobar("F5 salen las cuatro tarjetas", (kpis or "").count("=") == 4, kpis)
    k = (kpis or "").upper()
    comprobar("F5 los rotulos son los pedidos",
              "FACTURAS=" in k and "POR COBRAR (BS)=" in k and "VENCIDO (BS)=" in k
              and "NOTAS DE CR" in k, kpis)

    # ---------------------------------------------------------------- F6
    comprobar("F6 «Facturas» es el de la base", ("FACTURAS=%d" % KPI[0]) in k, kpis)
    comprobar("F6 «Por cobrar (Bs)» es el de la base", ("POR COBRAR (BS)=%s" % miles(KPI[1])) in k, kpis)
    comprobar("F6 «Vencido (Bs)» es el de la base", ("VENCIDO (BS)=%s" % miles(KPI[2])) in k, kpis)
    comprobar("F6 «Notas de credito» es el de la base", ("NOTAS DE CR" in k and "=%d" % KPI[3] in k), kpis)

    # ---------------------------------------------------------------- F7
    filas = nav.js('document.querySelectorAll("#R43000000000001362 a[href*=p9_id_factura]").length')
    comprobar("F7 el informe trae los documentos del cliente", filas == len(DOCS), "%s de %s" % (filas, len(DOCS)))
    texto = nav.js('(function(){var r=document.getElementById("R43000000000001362");'
                   'return r?(r.innerText||"").replace(/\\s+/g," "):"";})()') or ""
    comprobar("F7 el informe no mezcla documentos de otro cliente",
              all(folio in texto for folio, _, _, _, _ in DOCS), texto[:100])

    # ---------------------------------------------------------------- F8
    # La fila del primer documento con saldo tiene que decir su saldo y su estado.
    con_saldo = [x for x in DOCS if x[2] is not None]
    if con_saldo:
        folio, tipo, saldo, estado, _ = con_saldo[0]
        comprobar("F8 la fila %s muestra su saldo (%s)" % (folio, miles(saldo)),
                  miles(saldo) in texto, texto[:120])
        comprobar("F8 la fila %s muestra el estado %s" % (folio, estado),
                  estado in texto, estado)
    comprobar("F8 el estado se pinta como insignia",
              nav.js('document.querySelectorAll("#R43000000000001362 .status-badge").length') == len(DOCS),
              nav.js('document.querySelectorAll("#R43000000000001362 .status-badge").length'))

    # ---------------------------------------------------------------- F9
    ver = nav.js('(function(){var a=document.querySelector("#R43000000000001362 a[href*=p9_id_factura]");'
                 'if(!a){return "sin enlace";}'
                 'return decodeURIComponent(a.getAttribute("href"));})()') or ""
    print("  enlace Ver:", ver[:150])
    comprobar("F9 el «Ver» abre la 9 en consulta", "p9_id_factura=" in ver and "p9_modo_ver=s" in ver.lower(), ver[:120])
    comprobar("F9 el enlace lleva checksum", "cs=" in ver, ver[-40:])

    # ---------------------------------------------------------------- F10
    botones = nav.js('(function(){var t=[];document.querySelectorAll("button").forEach(function(b){'
                     't.push((b.getAttribute("data-otel-label")||b.innerText||"").trim());});'
                     'return t.join(" | ");})()') or ""
    print("  botones:", botones[:120])
    comprobar("F10 esta «Editar cliente»", "BTN_EDITAR_CLIENTE" in botones or "Editar cliente" in botones, botones[:80])
    comprobar("F10 esta «Volver»", "BTN_VOLVER" in botones or "Volver" in botones, botones[:80])

    # ---------------------------------------------------------------- F12
    nav.js('window.scrollTo(0,0)')
    time.sleep(1)
    nav.captura(os.path.join(RES, "20261120_cliente_ficha_1440.png"))
    nav.cmd("Emulation.setDeviceMetricsOverride", width=500, height=900,
            deviceScaleFactor=1, mobile=False)
    time.sleep(3)
    nav.js('window.scrollTo(0,0)')
    time.sleep(1)
    nav.captura(os.path.join(RES, "20261120_cliente_ficha_500.png"))
    nav.cmd("Emulation.clearDeviceMetricsOverride")
    time.sleep(1)

    # ---------------------------------------------------------------- F11
    # Un cliente de otra empresa: se cambia el item oculto y se envia la pagina
    # (el item no esta protegido, es un dato de pantalla). El proceso de la ficha
    # tiene que cortar con -20003.
    if AJENO:
        nav.js('apex.item("P32_ID_CLIENTE").setValue(%s); apex.submit({request:"DIAG"});' % json.dumps(str(AJENO[0])))
        time.sleep(8)
        cuerpo = nav.js('document.body.innerText') or ""
        comprobar("F11 un cliente de otra empresa responde -20003",
                  ("ORA-20003" in cuerpo) or ("No tiene permisos sobre este cliente" in cuerpo),
                  cuerpo.strip().replace("\n", " ")[:130])
        comprobar("F11 y no pinta la ficha del cliente ajeno",
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
