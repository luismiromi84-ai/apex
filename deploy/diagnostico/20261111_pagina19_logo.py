#!/usr/bin/env python3
"""Pagina 19 «Administracion > Logo de empresa» (Paso B del plan de pestanas).

Comprueba con navegador real (Edge headless por CDP) que:
  - la 19 trae la pestana «Logo corporativo» (desde el 2026-11-20 «Logo actual»
    y «Subir logo» son una sola pestana),
  - el logo de la empresa se pinta en la pagina (data URI),
  - el archivo elegido en el input se sube y queda en EMPRESA_LOGO.
Restaura el logo que hubiera antes (lo vuelve a guardar con el paquete, o lo
borra si no habia).

Uso:  python deploy/diagnostico/20261111_pagina19_logo.py
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
EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
BASE = "https://gfd7e2575d251ae-sypexsql.adb.mx-monterrey-1.oraclecloudapps.com/ords"
REPO = r"C:\Users\luism\OneDrive\Documents\Apex_luis"
sys.path.insert(0, os.path.join(REPO, "deploy", "conexion"))
import oracledb
from verificar_conexion import CONNECT_STRING, credenciales

USUARIO, CLAVE = "diag.pestanas", "Diag#2026"
ARCHIVO = os.path.join(REPO, "libreria", "variantes", "lockup_600.png")
fallas = 0


def comprueba(ok, texto, detalle=""):
    global fallas
    print("  [%s] %s%s" % ("OK   " if ok else "FALLA", texto,
                           "" if not detalle else " (%s)" % detalle))
    if not ok:
        fallas += 1


if not os.path.exists(ARCHIVO):
    sys.exit("no existe " + ARCHIVO)

c = credenciales()
con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")

cur.execute("select nombre_archivo, mime_type, imagen, fecha_carga, subido_por "
            "from empresa_logo where id_empresa = 1")
fila = cur.fetchone()
if fila:
    original = (fila[0], fila[1], fila[2].read(), fila[3], fila[4])
    print("  logo original: %s (%s, %d bytes)" % (fila[0], fila[1], len(original[2])))
else:
    original = None
    print("  la empresa 1 no tenia logo")

cur.execute("begin delete from usuario_empresa where usuario_id in "
            "(select usuario_id from usuario where upper(username)=upper(:u)); commit; "
            "delete from usuario where upper(username)=upper(:u); commit; end;", u=USUARIO)
cur.execute("""insert into usuario (username,email,password_hash,estado,id_empresa,rol_id,
                                     debe_cambiar_clave,reintentos_fallidos)
               values (:u,:e,sypex_hash_password(:p),'ACTIVO',1,
                       (select id_rol from syn_roles where codigo_rol='ADMIN'),'N',0)""",
            u=USUARIO, e=USUARIO + "@synpex.local", p=CLAVE)
con.commit()

proc = subprocess.Popen([EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
                         "--remote-debugging-port=9296",
                         "--user-data-dir=%s" % os.path.join(tempfile.gettempdir(),
                                                             "opencode", "edge-p19l"),
                         "about:blank"],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def objetivo():
    for _ in range(40):
        try:
            lista = json.loads(urllib.request.urlopen(
                "http://127.0.0.1:9296/json/list", timeout=2).read())
            paginas = [t for t in lista if t.get("type") == "page"]
            if paginas:
                return paginas[0]
        except Exception:
            pass
        time.sleep(0.5)


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


for m in ("Page.enable", "Runtime.enable", "DOM.enable"):
    cmd(m)


def js(e):
    r = cmd("Runtime.evaluate", expression=e, returnByValue=True, awaitPromise=True)
    if "exceptionDetails" in r:
        return "EXC: " + str(r["exceptionDetails"].get("exception", {}).get("description"))[:200]
    return r.get("result", {}).get("value")


def esperar(cond, s=40):
    f = time.time() + s
    while time.time() < f:
        if js(cond):
            return True
        time.sleep(0.5)
    return False


try:
    js('window.location.href="%s/f?p=100:9999"' % BASE)
    esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(1)
    js('(function(){apex.item("P9999_USERNAME").setValue(%s);apex.item("P9999_PASSWORD").setValue(%s);'
       'var b=[...document.querySelectorAll("button")].find(x=>/sign in|iniciar|entrar/i.test(x.innerText));if(b){b.click();}})()'
       % (json.dumps(USUARIO), json.dumps(CLAVE)))
    time.sleep(7)
    ses = re.search(r"session=(\d+)", js("window.location.href") or "")
    if not ses:
        sys.exit("login fallido")

    js('window.location.href="%s/f?p=100:19:%s"' % (BASE, ses.group(1)))
    if not esperar('document.readyState === "complete" && !!document.getElementById("spx-logo-file")'):
        sys.exit("la pagina 19 no pinto la pestana del logo")
    time.sleep(2)

    rds = js("(document.getElementById('43000000000000380_RDS')||{}).innerText || ''")
    comprueba("Logo corporativo" in (rds or ""), "el selector tiene la pestana «Logo corporativo»")
    comprueba("Subir logo" not in (rds or ""),
              "«Subir logo» ya no es una pestana aparte (vive dentro de la del logo)")
    comprueba((js("document.body.innerHTML") or "").count("data:image") >= 1,
              "la pagina pinta el logo de la empresa como data URI")

    # Subir un archivo real por el input y pulsar el boton.
    doc = cmd("DOM.getDocument", depth=-1)
    nodo = cmd("DOM.querySelector", nodeId=doc["root"]["nodeId"], selector="#spx-logo-file")
    cmd("DOM.setFileInputFiles", files=[ARCHIVO], nodeId=nodo["nodeId"])
    js('apex.item("P19L_ID_EMPRESA").setValue("1")')
    js('[...document.querySelectorAll("button")].find(function(b){'
       ' return /Subir logo/i.test(b.innerText) && b.offsetParent !== null; }).click()')
    ok = esperar('document.body.innerText.indexOf("Logo guardado") >= 0', 60)
    comprueba(ok, "la pagina dice «Logo guardado»",
              (js("document.body.innerText") or "")[:160].replace("\n", " / "))

    cur.execute("select tamano, nombre_archivo, mime_type from empresa_logo where id_empresa = 1")
    nueva = cur.fetchone()
    comprueba(nueva is not None and nueva[0] > 0, "EMPRESA_LOGO tiene la imagen", str(nueva))
    comprueba(nueva is not None and nueva[2] in ("image/png", "image/jpeg"),
              "el mime guardado es PNG o JPEG", str(nueva[2] if nueva else None))
    comprueba(nueva is not None and nueva[1] == os.path.basename(ARCHIVO),
              "guarda el nombre del archivo", str(nueva[1] if nueva else None))
finally:
    proc.terminate()
    if original:
        cur.setinputsizes(b=oracledb.DB_TYPE_BLOB)
        cur.execute("""update empresa_logo
                          set imagen = :b, nombre_archivo = :n, mime_type = :m,
                              tamano = :t, fecha_carga = :f, subido_por = :u
                        where id_empresa = 1""",
                    b=original[2], n=original[0], m=original[1], t=len(original[2]),
                    f=original[3], u=original[4])
    else:
        cur.execute("delete from empresa_logo where id_empresa = 1")
    cur.execute("begin delete from usuario_empresa where usuario_id in "
                "(select usuario_id from usuario where upper(username)=upper(:u)); commit; "
                "delete from usuario where upper(username)=upper(:u); commit; end;", u=USUARIO)
    con.commit()
    cur.execute("select tamano from empresa_logo where id_empresa = 1")
    resta = cur.fetchone()
    con.close()
    print("  restaurado: %s" % (str(resta) if resta else "sin logo"))

print("\nRESULTADO: FALLAS=%d" % fallas)
sys.exit(1 if fallas else 0)
