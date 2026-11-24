#!/usr/bin/env python3
"""
Dos acabados del 2026-11-23, con navegador real (Edge headless por CDP):

  V1  en Articulos (40) los chips de TIPO y ESTADO van en la MISMA fila
  V2  Conceptos de ISLR (34) tiene pestanas (lista y formulario) y el
      formulario se abre en su pestana al pulsar «Editar»
  V3  la 34 ya no tiene la region «Acciones» y los botones viven en el formulario

Uso:  python deploy/diagnostico/20261123_chips_pestanas_capturas.py
Sale con codigo 1 si algo falla.
"""
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.request

import websocket

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(RAIZ, "deploy", "conexion"))
import oracledb  # noqa: E402
from verificar_conexion import CONNECT_STRING as CS, credenciales  # noqa: E402

BASE = ("https://gfd7e2575d251ae-sypexsql.adb.mx-monterrey-1.oraclecloudapps.com/ords")
EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
USUARIO, CLAVE, PUERTO = "diag.acabados", "Diag#2026", 9283

fallas = []


def comprobar(nombre, condicion, detalle=""):
    print(("  OK  " if condicion else "  MAL ") + nombre + (" " + str(detalle) if detalle else ""))
    if not condicion:
        fallas.append(nombre)


conn = oracledb.connect(user=credenciales()["DB_USER"],
                        password=credenciales()["DB_PASSWORD"], dsn=CS)
cur = conn.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")


def borrar(usuario):
    cur.execute("""begin
                     for r in (select usuario_id from usuario where upper(username) = :u) loop
                         delete from usuario_empresa where usuario_id = r.usuario_id;
                         commit;
                         delete from usuario where usuario_id = r.usuario_id;
                         commit;
                     end loop;
                   end;""", u=usuario.upper())
    conn.commit()


borrar(USUARIO)
cur.execute("""insert into usuario (username,email,password_hash,estado,id_empresa,rol_id,
                                    debe_cambiar_clave,reintentos_fallidos)
               values (:u, :u||'@synpex.local', sypex_hash_password(:c), 'ACTIVO', 1,
                       (select id_rol from syn_roles where codigo_rol = 'ADMIN'), 'N', 0)""",
            u=USUARIO, c=CLAVE)
conn.commit()

proc = subprocess.Popen([EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
                         "--remote-debugging-port=%d" % PUERTO, "--window-size=1440,900",
                         "--user-data-dir=" + os.path.join(tempfile.gettempdir(), "opencode", "edge-acabados"),
                         "about:blank"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def objetivo():
    for _ in range(40):
        try:
            lista = json.loads(urllib.request.urlopen(
                "http://127.0.0.1:%d/json/list" % PUERTO, timeout=2).read())
            pag = [t for t in lista if t.get("type") == "page"]
            if pag:
                return pag[0]
        except Exception:
            pass
        time.sleep(0.5)
    raise SystemExit("no se pudo abrir el navegador")


ws = websocket.create_connection(objetivo()["webSocketDebuggerUrl"], timeout=60)
ws.settimeout(60)
n = [0]


def cmd(m, **p):
    n[0] += 1
    ws.send(json.dumps({"id": n[0], "method": m, "params": p}))
    while True:
        r = json.loads(ws.recv())
        if r.get("id") == n[0]:
            return r.get("result", {})


for m in ("Page.enable", "Runtime.enable"):
    cmd(m)


def js(e):
    r = cmd("Runtime.evaluate", expression=e, returnByValue=True, awaitPromise=True)
    if "exceptionDetails" in r:
        return "EXC: " + str(r["exceptionDetails"].get("exception", {}).get("description"))[:250]
    return r.get("result", {}).get("value")


def esperar(c_, s=60):
    f = time.time() + s
    while time.time() < f:
        v = js(c_)
        if v and not (isinstance(v, str) and v.startswith("EXC:")):
            return True
        time.sleep(0.5)
    return False


def captura(nombre):
    time.sleep(1)
    img = cmd("Page.captureScreenshot", format="png").get("data")
    if img:
        import base64
        destino = os.path.join(RAIZ, "deploy", "resultados", nombre)
        open(destino, "wb").write(base64.b64decode(img))
        print("  captura:", destino)


try:
    js('window.location.href="%s/f?p=100:9999"' % BASE)
    esperar('document.readyState === "complete" && document.getElementById("P9999_USERNAME")', 45)
    js('(function(){apex.item("P9999_USERNAME").setValue(%s);apex.item("P9999_PASSWORD").setValue(%s);'
       'var b=[...document.querySelectorAll("button")].find(x=>/sign in|iniciar|entrar/i.test(x.innerText));'
       'if(b){b.click();}})()' % (json.dumps(USUARIO), json.dumps(CLAVE)))
    esperar('!!window.apex && /session=\\d+/.test(location.href)', 70)
    ses = re.search(r"session=(\d+)", js("window.location.href") or "")
    comprobar("login", bool(ses))
    if not ses:
        raise SystemExit(1)

    # ------------------------------------------------------------------ V1
    js('window.location.href="%s/f?p=100:40:%s"' % (BASE, ses.group(1)))
    esperar('document.readyState === "complete" && document.querySelectorAll(".spx-filtro").length >= 6', 60)
    time.sleep(2)
    tops = js('[...document.querySelectorAll(".spx-filtro-lbl")]'
              '.map(function(e){return Math.round(e.getBoundingClientRect().top);})') or []
    comprobar("V1 hay dos rotulos (Tipo y Estado)", len(tops) == 2, tops)
    comprobar("V1 los dos grupos van en la misma fila",
              len(tops) == 2 and abs(tops[0] - tops[1]) <= 2, tops)
    filas = js('document.querySelectorAll(".spx-filtros").length')
    comprobar("V1 una sola franja de chips", filas == 1, filas)
    estilos = js('[...document.querySelectorAll(".spx-filtro-lbl")].map(function(e){'
                 'var s=getComputedStyle(e);'
                 'return [s.fontSize, s.fontWeight, s.letterSpacing, s.textTransform].join("|");})') or []
    comprobar("V1 los dos rotulos tienen el mismo estilo",
              len(estilos) == 2 and estilos[0] == estilos[1], estilos)
    captura("20261123_chips_una_fila.png")

    # ------------------------------------------------------------------ V2 y V3
    js('window.location.href="%s/f?p=100:34:%s"' % (BASE, ses.group(1)))
    esperar('document.readyState === "complete" && !!window.apex', 60)
    time.sleep(3)
    tabs = js('[...document.querySelectorAll(".a-RDS-link, .a-Tabs-link")]'
              '.map(function(a){return a.textContent.trim();})') or []
    comprobar("V2 las pestanas de la 34", "Conceptos de ISLR" in tabs and "Concepto" in tabs, tabs)
    comprobar("V3 la region Acciones ya no existe", not js('!!document.getElementById("R43000000000001485")'))
    captura("20261123_p34_pestanas.png")

    # Al entrar, APEX abre el selector en «Mostrar todo» (igual que Administración);
    # lo que importa es que la lista este visible y las dos pestanas existan.
    visible_lista = js('(function(){var r=document.getElementById("R43000000000001471");'
                       'return !!r && r.offsetParent !== null;})()')
    comprobar("V2 al entrar se ve la lista", visible_lista is True, visible_lista)

    # «Editar» de una fila abre la pestana del formulario (el enlace es una URL
    # amigable con p34_id_concepto=). Se espera a que la navegacion arranque.
    antes = js('window.location.href')
    clic = js('(function(){'
              'var a=[...document.querySelectorAll("a")].find(function(x){'
              'return (x.getAttribute("href")||"").toLowerCase().indexOf("p34_id_concepto=")>=0;});'
              'if(!a){return "NO LINK";}a.click();return "OK";})()')
    comprobar("V2 hay enlace Editar en la fila", clic == "OK", clic)
    navego = False
    for _ in range(25):
        time.sleep(1)
        ahora = js('window.location.href')
        if ahora and ahora != antes:
            navego = True
            break
    comprobar("V2 el enlace Editar navega", navego)
    esperar('(function(){try{var v=apex.item("P34_CODIGO").getValue();return !!v;}catch(e){return false;}})()', 60)
    visible_form = js('(function(){var r=document.getElementById("R43000000000001483");'
                      'return !!r && r.offsetParent !== null;})()')
    cod = js('(function(){try{return apex.item("P34_CODIGO").getValue();}catch(e){return null;}})()')
    comprobar("V2 «Editar» abre el formulario en su pestana", visible_form is True, visible_form)
    comprobar("V2 y el formulario trae el concepto pulsado", bool(cod), cod)
    captura("20261123_p34_formulario.png")

finally:
    try:
        ws.close()
    except Exception:
        pass
    proc.terminate()
    borrar(USUARIO)
    conn.close()

print("RESULTADO: FALLAS=%d" % len(fallas))
if fallas:
    print("fallos:", fallas)
sys.exit(1 if fallas else 0)
