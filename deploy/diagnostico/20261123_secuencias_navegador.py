#!/usr/bin/env python3
"""
Pestana «Secuencias» de Administracion (19). 2026-11-23.

Comprueba, con navegador real (Edge headless por CDP):
  N1  la pestana «Secuencias» sale para un ADMIN
  N2  la lista trae las diez series con su «siguiente» ya formateado
  N3  fijar PROD en 50 deja el contador en 50 y el siguiente en PROD-00051
  N4  el aviso de confirmacion aparece antes de fijar (serie fiscal o no)
  N5  un usuario CONSULTA no ve la pestana

Uso:  python deploy/diagnostico/20261123_secuencias_navegador.py
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
ADMIN, CLAVE, PUERTO = "diag.secuencias", "Diag#2026", 9284
CONSULTA = "diag.secver"

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


def crear(usuario, rol):
    borrar(usuario)
    cur.execute("""insert into usuario (username,email,password_hash,estado,id_empresa,rol_id,
                                        debe_cambiar_clave,reintentos_fallidos)
                   values (:u, :u||'@synpex.local', sypex_hash_password(:c), 'ACTIVO', 1,
                           (select id_rol from syn_roles where codigo_rol = :r), 'N', 0)""",
                u=usuario, c=CLAVE, r=rol)
    conn.commit()


crear(ADMIN, "ADMIN")
crear(CONSULTA, "CONSULTA")

# valor previo de PROD, para dejarlo como estaba
cur.execute("select nvl(max(ultimo), 0) from folio_contador where id_empresa = 1 and tipo = 'PROD'")
PROD_ANTES = cur.fetchone()[0]

proc = subprocess.Popen([EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
                         "--remote-debugging-port=%d" % PUERTO, "--window-size=1440,900",
                         "--user-data-dir=" + os.path.join(tempfile.gettempdir(), "opencode", "edge-secuencias"),
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


def entrar(usuario, clave):
    js('window.location.href="%s/f?p=100:9999"' % BASE)
    esperar('document.readyState === "complete" && document.getElementById("P9999_USERNAME")', 45)
    js('(function(){apex.item("P9999_USERNAME").setValue(%s);apex.item("P9999_PASSWORD").setValue(%s);'
       'var b=[...document.querySelectorAll("button")].find(x=>/sign in|iniciar|entrar/i.test(x.innerText));'
       'if(b){b.click();}})()' % (json.dumps(usuario), json.dumps(clave)))
    esperar('!!window.apex && /session=\\d+/.test(location.href)', 70)
    m = re.search(r"session=(\d+)", js("window.location.href") or "")
    return m.group(1) if m else None


def abrir_pestana_secuencias(sesion):
    js('window.location.href="%s/f?p=100:19:%s"' % (BASE, sesion))
    esperar('document.readyState === "complete" && !!window.apex', 60)
    time.sleep(3)
    # el selector de regiones se pulsa en una carga limpia (si no, se va a ORDS)
    js('(function(){var a=[...document.querySelectorAll(".a-RDS-link, a")]'
       '.find(function(x){return x.textContent.trim()==="Secuencias";});'
       'if(a){a.click();}return true;})()')
    time.sleep(3)
    return esperar('!!document.getElementById("P19S_SERIE")', 30)


try:
    ses = entrar(ADMIN, CLAVE)
    comprobar("N0 login ADMIN", bool(ses), ses and len(ses))
    if not ses:
        raise SystemExit(1)

    comprobar("N1 la pestana Secuencias abre", abrir_pestana_secuencias(ses))

    texto = js('(function(){var r=document.getElementById("R43000000000001900");'
               'return r ? r.innerText : "";})()') or ""
    lineas = [l.strip() for l in texto.splitlines() if l.strip()]
    series = ["PRESUPUESTO", "FAC", "NC", "ND", "CONTROL", "FAC_PROV", "CONTROL_PROV",
              "ARTICULO", "PROD", "SERV"]
    faltan = [s for s in series if not any(l.startswith(s) or l.startswith(s + " ") for l in lineas)]
    comprobar("N2 la lista trae las diez series", not faltan, faltan or len(lineas))
    comprobar("N2 el siguiente sale formateado por serie",
              bool(re.search(r"F-\d+", texto)) and bool(re.search(r"PROD-\d{5}", texto))
              and bool(re.search(r"1\d{7}", texto)), texto[:160].replace("\n", " | "))

    # ---------------------------------------------------------------- N4 + N3
    js('apex.item("P19S_SERIE").setValue("PROD"); '
       'apex.item("P19S_ULTIMO").setValue(50); 1')
    js('(function(){var b=[...document.querySelectorAll("button,a")]'
       '.find(function(x){return /fijar el siguiente/i.test(x.textContent);});'
       'if(b){b.click();}return true;})()')
    confirmado = esperar('!!document.querySelector(".ui-dialog")', 25)
    comprobar("N4 sale el aviso de confirmacion", confirmado)
    aceptado = js('(function(){var d=document.querySelector(".ui-dialog");'
                  'if(!d){return "NO";}'
                  'var b=[...d.querySelectorAll("button")].find(function(x){'
                  'return /fijar el siguiente/i.test(x.textContent) && !/cancelar/i.test(x.textContent);});'
                  'if(!b){return "SIN BOTON";}b.click();return "OK";})()')
    comprobar("N4 el aviso se puede aceptar", aceptado == "OK", aceptado)
    esperar('(function(){var t=document.body.innerText;return /fijada en 50/i.test(t);})()', 60)

    cur.execute("select nvl(ultimo, -1) from folio_contador where id_empresa = 1 and tipo = 'PROD'")
    comprobar("N3 el contador queda en 50", cur.fetchone()[0] == 50)
    cur.execute("begin :v := fn_siguiente_folio(1, 'PROD'); end;",
                v=cur.var(str))
    # (el var no se reutiliza: se pide con una consulta simple)
    cur.execute("select fn_siguiente_folio(1, 'PROD') from dual")
    comprobar("N3 el siguiente es PROD-00051", cur.fetchone()[0] == "PROD-00051")

    js('window.location.href="%s/f?p=100:19:%s"' % (BASE, ses))
    esperar('document.readyState === "complete" && !!window.apex', 60)
    time.sleep(2)
    cmd("Page.captureScreenshot", format="png")
    img = cmd("Page.captureScreenshot", format="png").get("data")
    if img:
        import base64
        destino = os.path.join(RAIZ, "deploy", "resultados", "20261123_secuencias.png")
        open(destino, "wb").write(base64.b64decode(img))
        print("  captura:", destino)

    # ---------------------------------------------------------------- N5
    ses2 = entrar(CONSULTA, CLAVE)
    comprobar("N5 login CONSULTA", bool(ses2))
    js('window.location.href="%s/f?p=100:19:%s"' % (BASE, ses2))
    esperar('document.readyState === "complete" && !!window.apex', 60)
    time.sleep(3)
    pestanas = js('[...document.querySelectorAll(".a-RDS-link, a")]'
                  '.map(function(x){return x.textContent.trim();})') or []
    comprobar("N5 CONSULTA no ve la pestana", "Secuencias" not in pestanas,
              [p for p in pestanas if p in ("Secuencias", "Empresa", "Mis empresas")])

finally:
    try:
        ws.close()
    except Exception:
        pass
    proc.terminate()
    if PROD_ANTES == 0:
        cur.execute("delete from folio_contador where id_empresa = 1 and tipo = 'PROD'")
    else:
        cur.execute("update folio_contador set ultimo = :n where id_empresa = 1 and tipo = 'PROD'",
                    n=PROD_ANTES)
    conn.commit()
    borrar(ADMIN)
    borrar(CONSULTA)
    conn.close()

print("RESULTADO: FALLAS=%d" % len(fallas))
if fallas:
    print("fallos:", fallas)
sys.exit(1 if fallas else 0)
