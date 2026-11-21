#!/usr/bin/env python3
"""
Comprueba en navegador real que la factura NUEVA nace con la fecha de emision de
hoy y que al EDITAR una factura el fetch gana al defecto.

Por que existe: al crear una factura (pagina 9 sin P9_ID_FACTURA) el campo
`P9_FECHA_EMISION` nacia vacio y APEX no dejaba guardar («Fecha Emision debe
tener algun valor»). La prueba de la nota de credito tenia que teclearla a mano,
que es justo lo que le pasa al usuario.

El arreglo (mismo patron que la pagina 7): `p_item_default_type=>'SQL_QUERY'`
con `select sysdate from dual`. `P9_FECHA_VENCIMIENTO` se deja vacia a
proposito: depende de la condicion de pago y la pagina 7 tampoco la rellena al
crear (su regla solo corre al cambiar la fecha).

Comprobaciones:
  F1  el boton «Nueva Facturas» de la lista (8) abre la 9 en alta
  F2  en un alta la fecha de emision viene con la de hoy
  F3  al editar, la 9 muestra la fecha propia del documento (no la de hoy)
  F4  al editar, la fecha de vencimiento sigue siendo la del documento

Uso:
    python deploy/diagnostico/20261121_pagina9_fecha_default.py
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

USUARIO, CLAVE = "diag.fecha", "Diag#2026"
PUERTO = 9291  # propio: dos scripts no pueden compartir navegador

fallas = []


def comprobar(nombre, condicion, detalle=""):
    print(("  OK  " if condicion else "  MAL ") + nombre + (" " + str(detalle) if detalle else ""))
    if not condicion:
        fallas.append(nombre)


class Nav:
    def __init__(self, puerto=PUERTO):
        self.proc = subprocess.Popen(
            [EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
             "--window-size=1440,1100",
             f"--remote-debugging-port={puerto}",
             f"--user-data-dir={os.path.join(tempfile.gettempdir(), 'opencode', 'edge-fecha')}",
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


# Lee un item de la pagina 9, que siempre vive dentro del iframe del dialogo:
# el valor del item de APEX y el texto del input (que es lo que ve el usuario).
LEER_FECHA = ('(function(id){var w=document.querySelector("iframe").contentWindow,'
              'd=w.document, v=null, t=null;'
              'try{v=w.apex.item(id).getValue();}catch(e){v="EXC";}'
              'var el=d.getElementById(id);'
              'if(el){t=(el.value===undefined?null:el.value);}'
              'return JSON.stringify({valor:v, texto:t});})')

TEXTO = '(document.body ? (document.body.innerText||"") : "")'


conn = oracledb.connect(user=credenciales()["DB_USER"], password=credenciales()["DB_PASSWORD"], dsn=CS)
cur = conn.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")
cur.execute("delete from syn_login_log where upper(usuario_intentado) = 'DIAG.FECHA'")
cur.execute("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario "
            "where upper(username) = 'DIAG.FECHA'); commit; "
            "delete from usuario where upper(username) = 'DIAG.FECHA'; commit; end;")
cur.execute("""insert into usuario (username, email, password_hash, estado, id_empresa, rol_id,
                                    debe_cambiar_clave, reintentos_fallidos)
               values ('diag.fecha', 'diag.fecha@synpex.local', sypex_hash_password('Diag#2026'),
                       'ACTIVO', 1, (select id_rol from syn_roles where codigo_rol = 'ADMIN'), 'N', 0)""")
conn.commit()

# Factura de la empresa 1 cuya fecha NO sea hoy: si el fetch no ganara al
# defecto, la prueba lo veria como la fecha de hoy.
cur.execute("""select id_factura, folio_factura, to_char(fecha_emision,'DD/MM/YYYY'),
                      to_char(fecha_vencimiento,'DD/MM/YYYY')
                 from (select f.* from facturas f
                        where f.id_empresa = 1
                          and f.fecha_emision <> trunc(sysdate)
                        order by f.id_factura desc)
                where rownum = 1""")
fila = cur.fetchone()
if not fila:
    print("  MAL no hay ninguna factura con fecha distinta de hoy para probar la edicion")
    sys.exit(1)
id_fact, folio, fecha_doc, venc_doc = fila
print(f"  (factura de prueba: {folio} id={id_fact} emision={fecha_doc} vencimiento={venc_doc})")

cur.execute("select to_char(sysdate,'DD/MM/YYYY') from dual")
hoy = cur.fetchone()[0]
print(f"  (hoy segun la base: {hoy})")

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
    comprobar("F0 login con el usuario de diagnostico", bool(m),
              (nav.js("document.body.innerText") or "")[:80] if not m else "")
    if not m:
        raise SystemExit(1)
    ses = m.group(1)

    # ---- caso 1: factura NUEVA por el boton de la lista
    nav.js('window.location.href="%s/f?p=100:8:%s"' % (BASE, ses))
    nav.esperar('!!document.getElementById("P8_ID_FACTURAS")', 40)
    time.sleep(4)
    # El boton se pulsa con el.click(), no mandando el raton a sus coordenadas:
    # APEX engancha el REDIRECT_PAGE por su manejador, y si el boton queda fuera
    # de la ventana las coordenadas no aciertan (leccion del 2026-11-17).
    nav.js('(function(){var bs=[...document.querySelectorAll("button,a,[role=button]")]'
           '.filter(function(b){return /nueva factura/i.test(b.innerText||"");});'
           'if(!bs.length) return "no-encontrado"; bs[0].click(); return "pulsado";})()')
    abierto = nav.esperar('(function(){var f=document.querySelector("iframe");'
                          'return !!(f&&f.contentDocument&&'
                          'f.contentDocument.getElementById("P9_FECHA_EMISION"));})()', 40)
    texto = nav.js(TEXTO) or ""
    comprobar("F1 el boton «Nueva Facturas» abre la 9 en alta",
              abierto and "grid settings" not in texto.lower(),
              "" if abierto else texto.strip().replace("\n", " ")[:100])
    if abierto:
        time.sleep(3)
        idfact = nav.js('(function(){var w=document.querySelector("iframe").contentWindow;'
                        'try{return w.apex.item("P9_ID_FACTURA").getValue();}catch(e){return null;}})()')
        nueva = json.loads(nav.js(LEER_FECHA + '("P9_FECHA_EMISION")'))
        comprobar("F2 en un alta (sin id de factura) la fecha de emision viene con la de hoy",
                  (idfact in (None, "", "null")) and nueva["texto"] == hoy
                  and str(nueva["valor"]) == hoy,
                  f"(id={idfact} input={nueva['texto']} valor={nueva['valor']} hoy={hoy})")
        venc_raw = json.loads(nav.js(LEER_FECHA + '("P9_FECHA_VENCIMIENTO")'))
        comprobar("F5 en un alta el vencimiento nace vacio (no hay condicion de pago aun)",
                  str(venc_raw["valor"] or "") == "",
                  f"(valor={venc_raw['valor']!r})")
        nav.captura(os.path.join(REPO, "deploy", "resultados", "20261121_p9_fecha_nueva.png"))

    # ---- caso 2: factura EXISTENTE, por el «Editar» de la lista (dialogo)
    nav.js('window.location.href="%s/f?p=100:8:%s"' % (BASE, ses))
    nav.esperar('!!document.getElementById("P8_ID_FACTURAS")', 40)
    time.sleep(4)
    nav.clic('(function(){var as=[...document.querySelectorAll("td a")].filter(function(a){'
             'return /Editar/.test(a.innerText);});'
             'if(!as.length) return null; var r=as[0].getBoundingClientRect();'
             'return JSON.stringify({x:r.left+r.width/2,y:r.top+r.height/2});})()')
    abierto = nav.esperar('(function(){var f=document.querySelector("iframe");'
                          'return !!(f&&f.contentDocument&&'
                          'f.contentDocument.getElementById("P9_FECHA_EMISION"));})()', 40)
    comprobar("F1b el «Editar» de la lista abre la 9 con la factura", abierto)
    if abierto:
        time.sleep(3)
        edit = json.loads(nav.js(LEER_FECHA + '("P9_FECHA_EMISION")'))
        folio = nav.js('(function(){var w=document.querySelector("iframe").contentWindow;'
                       'try{return w.apex.item("P9_FOLIO_FACTURA").getValue();}catch(e){return null;}})()')
        # la fecha del documento que se abrio, leida de la base por el folio
        cur.execute("select to_char(fecha_emision,'DD/MM/YYYY'), "
                    "to_char(fecha_vencimiento,'DD/MM/YYYY') "
                    "from facturas where folio_factura = :f and id_empresa = 1", f=folio)
        real = cur.fetchone() or (None, None)
        comprobar("F3 al editar, la 9 muestra la fecha propia del documento (no la de hoy)",
                  edit["texto"] == real[0] and real[0] != hoy,
                  f"(folio={folio} input={edit['texto']} documento={real[0]} hoy={hoy})")
        venc = json.loads(nav.js(LEER_FECHA + '("P9_FECHA_VENCIMIENTO")'))
        venc_visible = venc["texto"] if venc["texto"] is not None else venc["valor"]
        comprobar("F4 al editar, el vencimiento sigue siendo el del documento",
                  venc_visible == real[1],
                  f"(input={venc_visible} documento={real[1]})")
        nav.captura(os.path.join(REPO, "deploy", "resultados", "20261121_p9_fecha_editar.png"))
finally:
    nav.cerrar()
    cur.execute("delete from syn_login_log where upper(usuario_intentado) = 'DIAG.FECHA'")
    cur.execute("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario "
                "where upper(username) = 'DIAG.FECHA'); commit; "
                "delete from usuario where upper(username) = 'DIAG.FECHA'; commit; end;")
    conn.commit()
    conn.close()

print()
print("RESULTADO: FALLAS=" + str(len(fallas)))
for f in fallas:
    print("  - " + f)
sys.exit(1 if fallas else 0)
