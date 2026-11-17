#!/usr/bin/env python3
"""
Retencion de IVA del cliente, de punta a punta en la pantalla (2026-11-17).

Con navegador real (Edge headless por CDP) y un usuario temporal:

  T1  la pagina 21 (Cliente) ABRE (estaba en HTTP 400 por la LOV sin prefijo
      STATIC2) y guarda ES_AGENTE_RETENCION y PORCENTAJE_RETENCION
      (antes el proceso los ignoraba: todo cliente quedaba en 'N' / 75)
  T2  al elegir ese cliente en una factura nueva, la pagina 9 trae su % de
      retencion (accion dinamica CARGAR_RETENCION_CLIENTE)

El cliente y el usuario de prueba se borran al final.

Uso:
    python deploy/diagnostico/20261117_retencion_iva_pagina.py
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

USUARIO, CLAVE = "diag.retiva", "Diag#2026"
RIF = "12345678-9"
RAZON = "Cliente retencion (verificacion)"

fallas = []


def comprobar(nombre, condicion, detalle=""):
    print(("  OK  " if condicion else "  MAL ") + nombre + (" " + str(detalle) if detalle else ""))
    if not condicion:
        fallas.append(nombre)


class Nav:
    def __init__(self, puerto=9286):
        self.proc = subprocess.Popen(
            [EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
             f"--remote-debugging-port={puerto}",
             f"--user-data-dir={os.path.join(tempfile.gettempdir(), 'opencode', 'edge-retiva')}",
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


def espera_iframe(nav, campo, seg=40):
    return nav.esperar('(function(){var f=document.querySelector("iframe");'
                       'return !!(f&&f.contentWindow&&f.contentDocument&&'
                       'f.contentDocument.getElementById("%s"));})()' % campo, seg)


def en_dialogo(nav, expr):
    """Ejecuta `expr` dentro del iframe. `apex` es el de DENTRO del dialogo: el
    de la ventana padre no ve los items de la pagina modal."""
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


conn = oracledb.connect(user=credenciales()["DB_USER"], password=credenciales()["DB_PASSWORD"], dsn=CS)
cur = conn.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")


def limpia():
    cur.execute("delete from clientes where razon_social = :r", r=RAZON)
    cur.execute("delete from syn_login_log where upper(usuario_intentado) = 'DIAG.RETIVA'")
    cur.execute("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario "
                "where upper(username) = 'DIAG.RETIVA'); commit; "
                "delete from usuario where upper(username) = 'DIAG.RETIVA'; commit; end;")


limpia()
cur.execute("""insert into usuario (username, email, password_hash, estado, id_empresa, rol_id,
                                    debe_cambiar_clave, reintentos_fallidos)
               values ('diag.retiva', 'diag.retiva@synpex.local', sypex_hash_password('Diag#2026'),
                       'ACTIVO', 1, (select id_rol from syn_roles where codigo_rol = 'ADMIN'), 'N', 0)""")
conn.commit()

cliente_id = None
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

    # ---------------------------------------------------------------- T1
    nav.js('window.location.href="%s/f?p=100:20:%s"' % (BASE, ses))
    nav.esperar('document.readyState === "complete" && !!window.apex', 40)
    time.sleep(6)
    lista_texto = nav.js('document.body.innerText') or ""
    comprobar("T1 la lista de clientes (20) consulta bien",
              "falta la palabra clave" not in lista_texto.lower()
              and "ora-" not in lista_texto.lower(),
              "(" + [l for l in lista_texto.splitlines() if "clave" in l.lower() or "ora-" in l.lower()][:1].__str__() + ")")
    un_cliente = cur.execute("""select razon_social from clientes
                                 where id_empresa = 1 and estado = 'ACTIVO'
                                 order by razon_social fetch first 1 rows only""").fetchone()[0]
    comprobar("T1 la lista muestra los clientes de la empresa",
              un_cliente[:18].upper() in lista_texto.upper(), f"({un_cliente[:30]})")
    nav.clic('(function(){var b=[...document.querySelectorAll("button")].find(function(x){'
             'return /Nuevo cliente/i.test(x.innerText);}); if(!b) return null;'
             'var r=b.getBoundingClientRect();'
             'return JSON.stringify({x:r.left+r.width/2,y:r.top+r.height/2});})()')
    abierto = espera_iframe(nav, "P21_RAZON_SOCIAL")
    comprobar("T1 el dialogo de cliente (21) abre", abierto)
    if abierto:
        nav.esperar('(function(){var w=document.querySelector("iframe").contentWindow;'
                    'var e=w.document.getElementById("P21_ID_EMPRESA");'
                    'return !!(e && e.options.length > 1);})()', 20)
        texto = nav.js('(function(){var w=document.querySelector("iframe").contentWindow;'
                       'return w.document.body.innerText||"";})()') or ""
        comprobar("T1 la pagina 21 no devuelve error de servidor",
                  "Bad Request" not in texto and "ORA-" not in texto,
                  "(" + texto.strip().replace("\n", " ")[:80] + ")")
        comprobar("T1 el campo Retiene IVA ofrece Si/No",
                  "Retiene IVA" in texto and "Sí" in texto and "No" in texto)
        en_dialogo(nav, 'apex.item("P21_ID_EMPRESA").setValue("1");')
        time.sleep(1)
        en_dialogo(nav, 'apex.item("P21_TIPO_RIF").setValue("J");')
        en_dialogo(nav, 'apex.item("P21_RIF").setValue(%s);' % json.dumps(RIF))
        en_dialogo(nav, 'apex.item("P21_RAZON_SOCIAL").setValue(%s);' % json.dumps(RAZON))
        en_dialogo(nav, 'apex.item("P21_COD_PAIS").setValue("VE");')
        en_dialogo(nav, 'apex.item("P21_ESTADO").setValue("ACTIVO");')
        en_dialogo(nav, 'apex.item("P21_ES_AGENTE_RETENCION").setValue("S");')
        en_dialogo(nav, 'apex.item("P21_PORCENTAJE_RETENCION").setValue(80);')
        time.sleep(1)
        nav.captura(os.path.join(REPO, "deploy", "resultados", "20261117_retencion_p21.png"))
        clic_en_dialogo(nav, "Guardar")
        time.sleep(9)

        fila = cur.execute("""select id_cliente, es_agente_retencion, porcentaje_retencion
                                from clientes where razon_social = :r""", r=RAZON).fetchone()
        if fila is None:
            comprobar("T1 el cliente se guarda", False, "(no se creo)")
        else:
            cliente_id, agente, pct = fila
            comprobar("T1 guarda ES_AGENTE_RETENCION = S", agente == "S", f"({agente})")
            comprobar("T1 guarda el porcentaje 80", float(pct) == 80, f"({pct})")

    # ---------------------------------------------------------------- T2
    if cliente_id:
        nav.js('window.location.href="%s/f?p=100:8:%s"' % (BASE, ses))
        nav.esperar('document.readyState === "complete" && !!window.apex', 40)
        time.sleep(4)
        nav.clic('(function(){var b=[...document.querySelectorAll("button,a")].find(function(x){'
                 'return /Nueva Factura/i.test(x.innerText);}); if(!b) return null;'
                 'var r=b.getBoundingClientRect();'
                 'return JSON.stringify({x:r.left+r.width/2,y:r.top+r.height/2});})()')
        abierto = nav.esperar('(function(){var f=document.querySelector("iframe");'
                              'return !!(f&&f.contentWindow&&f.contentDocument&&'
                              'f.contentDocument.getElementById("P9_ID_CLIENTE"));})()', 60)
        comprobar("T2 el dialogo de la factura (9) abre", abierto)
        if abierto:
            en_dialogo(nav, 'apex.item("P9_ID_EMPRESA").setValue("1");')
            time.sleep(3)
            en_dialogo(nav, 'apex.item("P9_ID_CLIENTE").setValue(%d);' % cliente_id)
            time.sleep(5)
            pct_fac = en_dialogo(nav, 'return apex.item("P9_PORCENTAJE_RETENCION").getValue();')
            comprobar("T2 al elegir el cliente se carga su 80 %",
                      str(pct_fac).strip() in ("80", "80.0"), f"({pct_fac})")
            nav.captura(os.path.join(REPO, "deploy", "resultados", "20261117_retencion_p9.png"))
finally:
    nav.cerrar()
    limpia()
    conn.commit()
    conn.close()

print()
print("RESULTADO: FALLAS=" + str(len(fallas)))
for f in fallas:
    print("  - " + f)
sys.exit(1 if fallas else 0)
