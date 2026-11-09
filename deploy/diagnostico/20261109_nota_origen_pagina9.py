"""
Verificacion de la pagina 9: elegir la factura que acredita (2026-11-09).

Con navegador real (Edge headless por CDP) y un usuario temporal. Comprueba:
  C1  al elegir la factura origen se llena la cabecera (empresa, cliente, moneda,
      tasa, RIF del receptor) y las observaciones citan la factura
  C2  aparece la region de lineas solo con NC y factura origen elegida
  C3  marcar una linea y pulsar "Traer marcadas" deja la nota con esa linea y su
      total (crea la nota de verdad y la borra al final, devolviendo el contador)
  C4  con lineas dentro, la region y el boton desaparecen y la factura origen
      queda en solo lectura
  C5  en una factura FAC no aparece nada de esto

Uso:
    python deploy/diagnostico/20261109_nota_origen_pagina9.py
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
BASE = ("https://gfd7e2575d251ae-sypexsql.adb.mx-monterrey-1.oraclecloudapps.com/ords")
REPO = r"C:\Users\luism\OneDrive\Documents\Apex_luis"
sys.path.insert(0, os.path.join(REPO, "deploy", "conexion"))
from verificar_conexion import CONNECT_STRING as CS, credenciales  # noqa: E402

USUARIO, CLAVE = "diag.diseno", "Diag#2026"

fallas = []


def comprobar(nombre, condicion, detalle=""):
    print(("  OK  " if condicion else "  MAL ") + nombre + (" " + str(detalle) if detalle else ""))
    if not condicion:
        fallas.append(nombre)


class Nav:
    def __init__(self, puerto=9270):
        self.proc = subprocess.Popen(
            [EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
             f"--remote-debugging-port={puerto}",
             f"--user-data-dir={os.path.join(tempfile.gettempdir(), 'opencode', 'edge-p9')}",
             "about:blank"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        objetivo = None
        for _ in range(40):
            try:
                lista = json.loads(urllib.request.urlopen(f"http://127.0.0.1:{puerto}/json/list",
                                                          timeout=2).read())
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


IFRAME_OK = ('(function(){var f=document.querySelector("iframe");'
             'return !!(f&&f.contentWindow&&f.contentWindow.document&&'
             'f.contentWindow.document.getElementById("P9_TIPO_DOCUMENTO"));})()')


def abrir_dialogo(nav, expresion_boton):
    return nav.clic(expresion_boton) and nav.esperar(IFRAME_OK, 40)


def leer(nav, campo):
    return nav.js('(function(){var w=document.querySelector("iframe").contentWindow;'
                  'return w.apex.item("%s") ? w.apex.item("%s").getValue() : null;})()'
                  % (campo, campo))


def visible(nav, region_id):
    return nav.js('(function(){var f=document.querySelector("iframe");'
                  'if(!f||!f.contentWindow) return false;'
                  'var d=f.contentWindow.document;'
                  'var e=d.getElementById("%s") || d.getElementById("R43000000000000343")'
                  '      || d.getElementById("lineas-factura-origen");'
                  'return !!(e && e.offsetParent !== null && (e.innerText||"").indexOf("Cant") >= 0);})()'
                  % region_id)


conn = oracledb.connect(user=credenciales()["DB_USER"], password=credenciales()["DB_PASSWORD"], dsn=CS)
cur = conn.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")

# usuario temporal (se borra al final)
cur.execute("delete from syn_login_log where upper(usuario_intentado) = 'DIAG.DISENO'")
cur.execute("delete from usuario where upper(username) = 'DIAG.DISENO'")
cur.execute("""insert into usuario (username, email, password_hash, estado, id_empresa, rol_id,
                                     debe_cambiar_clave, reintentos_fallidos)
               values ('diag.diseno', 'diag.diseno@synpex.local', sypex_hash_password('Diag#2026'),
                       'ACTIVO', 1, (select id_rol from syn_roles where codigo_rol = 'ADMIN'), 'N', 0)""")
conn.commit()

origen, total_origen, lineas = cur.execute("""
    select f.id_factura, f.monto_total,
           (select count(*) from facturas_det d where d.id_factura = f.id_factura)
      from facturas f
     where f.id_empresa = 1 and f.tipo_documento = 'FAC' and f.estado <> 'ANULADA'
       and (select count(*) from facturas_det d where d.id_factura = f.id_factura) >= 1
     order by f.id_factura asc fetch first 1 rows only
""").fetchone()
primera_linea, total_linea = cur.execute("""
    select id_detalle, monto_total_linea from facturas_det
     where id_factura = :i order by num_linea fetch first 1 rows only
""", i=origen).fetchone()
print(f"  factura origen: {origen} ({lineas} lineas, total {total_origen})")

nav = Nav()
creada = None
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
        comprobar("login", False, nav.js("document.body.innerText")[:120])
        raise SystemExit(1)
    ses = m.group(1)

    # C5 primero: una factura FAC no enseña la region
    nav.js('window.location.href="%s/f?p=100:8:%s"' % (BASE, ses))
    nav.esperar('!!document.getElementById("P8_ID_FACTURAS")', 40)
    time.sleep(4)
    abrir_dialogo(nav, '(function(){var b=[...document.querySelectorAll("button,a")].find(function(x){'
                       'return /Nueva Factura/i.test(x.innerText);});var r=b.getBoundingClientRect();'
                       'return JSON.stringify({x:r.left+r.width/2,y:r.top+r.height/2});})()')
    time.sleep(3)
    nav.js('(function(){var w=document.querySelector("iframe").contentWindow;'
           'w.apex.item("P9_TIPO_DOCUMENTO").setValue("FAC");})()')
    time.sleep(2)
    comprobar("C5 en FAC no aparece la region de lineas",
              not visible(nav, "lineas-factura-origen"))

    # C1/C2: NC + factura origen
    nav.js('(function(){var w=document.querySelector("iframe").contentWindow;'
           'w.apex.item("P9_TIPO_DOCUMENTO").setValue("NC");})()')
    time.sleep(1)
    nav.js('(function(){var w=document.querySelector("iframe").contentWindow;'
           'w.apex.item("P9_ID_FACTURA_ORIGEN").setValue("%d");})()' % origen)
    time.sleep(6)

    empresa = leer(nav, "P9_ID_EMPRESA")
    cliente = leer(nav, "P9_ID_CLIENTE")
    moneda = leer(nav, "P9_COD_MONEDA")
    tasa = leer(nav, "P9_TIPO_CAMBIO")
    rfc = leer(nav, "P9_RFC_RECEPTOR")
    obs = leer(nav, "P9_OBSERVACIONES") or ""
    comprobar("C1 la cabecera se llena con la factura",
              str(empresa) == "1" and cliente not in (None, "") and moneda not in (None, "")
              and tasa not in (None, "") and rfc not in (None, ""),
              f"(emp={empresa} cli={cliente} mon={moneda} tasa={tasa} rfc={rfc})")
    comprobar("C1 las observaciones citan la factura", "de la factura" in obs.lower(),
              f"({obs[:60]})")
    comprobar("C2 la region de lineas aparece", visible(nav, "lineas-factura-origen"))

    # C3: marcar la primera linea y traerla
    nav.js('(function(){var w=document.querySelector("iframe").contentWindow,d=w.document;'
           'var c=d.querySelector(".js-linea-sel[data-id=\\"%d\\"]");'
           'if(c){c.checked=true;c.dispatchEvent(new w.Event("change",{bubbles:true}));}'
           'return c ? "ok" : "no encontrada";})()' % primera_linea)
    time.sleep(1)
    nav.clic('(function(){var f=document.querySelector("iframe"); var d=f.contentDocument;'
             'var b=[...d.querySelectorAll("button")].find(function(x){return /Traer marcadas/i.test(x.innerText);});'
             'if(!b) return null; var fb=f.getBoundingClientRect(), r=b.getBoundingClientRect();'
             'return JSON.stringify({x:fb.left+r.left+r.width/2, y:fb.top+r.top+r.height/2});})()')
    time.sleep(9)

    creada = cur.execute("""select max(id_factura) from facturas
                             where tipo_documento = 'NC' and id_factura_origen = :o
                               and creado_por = 'DIAG.DISENO'""", o=origen).fetchone()[0]
    if creada is None:
        comprobar("C3 la nota se crea con la linea marcada", False, "(no se creo la nota)")
    else:
        n_lin, tot, id_origen = cur.execute("""select count(*), nvl(sum(monto_total_linea),0),
                                                      min(id_detalle_origen)
                                                 from facturas_det where id_factura = :i""",
                                             i=creada).fetchone()
        tot_cab = cur.execute("select monto_total from facturas where id_factura = :i",
                              i=creada).fetchone()[0]
        comprobar("C3 la nota queda con 1 linea", n_lin == 1, f"({n_lin})")
        comprobar("C3 el total es el de la linea", abs(tot_cab - total_linea) < 0.01,
                  f"(nota {tot_cab} vs linea {total_linea})")
        comprobar("C3 la linea apunta a la original", id_origen == primera_linea, f"({id_origen})")

        # C4: con lineas, sin region y sin boton; factura origen en solo lectura
        nav.js('window.location.href="%s/f?p=100:8:%s"' % (BASE, ses))
        nav.esperar('!!document.getElementById("P8_ID_FACTURAS")', 40)
        time.sleep(4)
        abrir_dialogo(nav, '(function(){var as=[...document.querySelectorAll("td a")].filter(function(a){'
                           'return /Editar/.test(a.innerText);});'
                           'if(!as.length) return null; var r=as[0].getBoundingClientRect();'
                           'return JSON.stringify({x:r.left+r.width/2,y:r.top+r.height/2});})()')
        time.sleep(4)
        comprobar("C4 con lineas no aparece la region",
                  not visible(nav, "lineas-factura-origen"))
        comprobar("C4 con lineas no aparece el boton",
                  not bool(nav.js('(function(){var f=document.querySelector("iframe");'
                                  'return !!(f && [...f.contentDocument.querySelectorAll("button")]'
                                  '.find(function(x){return /Traer marcadas/i.test(x.innerText);}));})()')))
        solo_lectura = nav.js('(function(){var w=document.querySelector("iframe").contentWindow,'
                              'd=w.document,e=d.getElementById("P9_ID_FACTURA_ORIGEN");'
                              'return e ? (e.readOnly || e.getAttribute("readonly") !== null) : null;})()')
        comprobar("C4 la factura origen queda en solo lectura", bool(solo_lectura), f"({solo_lectura})")
finally:
    nav.cerrar()
    # limpieza: la nota de prueba y el usuario temporal
    if creada is not None:
        cur.execute("delete from facturas_det where id_factura = :i", i=creada)
        cur.execute("delete from facturas where id_factura = :i", i=creada)
        cur.execute("""update folio_contador set ultimo = 0
                        where tipo = 'NC'
                          and not exists (select 1 from facturas f
                                           where f.id_empresa = folio_contador.id_empresa
                                             and f.tipo_documento = 'NC')""")
    cur.execute("delete from syn_login_log where upper(usuario_intentado) = 'DIAG.DISENO'")
    cur.execute("delete from usuario where upper(username) = 'DIAG.DISENO'")
    conn.commit()
    conn.close()

print()
print("RESULTADO: FALLAS=" + str(len(fallas)))
for f in fallas:
    print("  - " + f)
sys.exit(1 if fallas else 0)
