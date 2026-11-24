#!/usr/bin/env python3
"""Pagina 19 con un usuario de DOS empresas: el formulario de «Empresa» tiene que
poder enviarse aunque los selectores de empresa de las pestanas fiscales y del
logo esten vacios.

El fallo que reproduce: P19F_ID_EMPRESA y P19L_ID_EMPRESA eran `p_is_required` con
un defecto `having count(*) = 1`, o sea NULL para quien tiene dos empresas. APEX
valida los obligatorios de TODAS las regiones renderizadas (tambien las de las
pestanas ocultas), asi que el submit de «Guardar empresa» moria con «Empresa debe
tener algun valor» senalando un campo que no se ve.

Se comprueba lo barato y sin escribir nada: con la empresa en blanco, «Guardar
empresa» responde con la validacion propia de la app («El nombre de la empresa es
obligatorio»), que solo se alcanza si el POST salio.

Uso:  python deploy/diagnostico/20261111_pagina19_multiempresa.py
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

USUARIO, CLAVE = "diag.pestanas2", "Diag#2026"
fallas = 0


def num(valor):
    """fn_clean_num del lado de Python: '' o None valen 0."""
    try:
        return float(valor)
    except (TypeError, ValueError):
        return 0


def comprueba(ok, texto, detalle=""):
    global fallas
    print("  [%s] %s%s" % ("OK   " if ok else "FALLA", texto,
                           "" if not detalle else " (%s)" % detalle))
    if not ok:
        fallas += 1


c = credenciales()
con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")

# Dos empresas para el usuario: 1 y 2 (ambas existen en una base recien instalada).
cur.execute("begin delete from usuario_empresa where usuario_id in "
            "(select usuario_id from usuario where upper(username)=upper(:u)); commit; "
            "delete from usuario where upper(username)=upper(:u); commit; end;", u=USUARIO)
cur.execute("""insert into usuario (username,email,password_hash,estado,id_empresa,rol_id,
                                     debe_cambiar_clave,reintentos_fallidos)
               values (:u,:e,sypex_hash_password(:p),'ACTIVO',1,
                       (select id_rol from syn_roles where codigo_rol='ADMIN'),'N',0)""",
            u=USUARIO, e=USUARIO + "@synpex.local", p=CLAVE)
cur.execute("""insert into usuario_empresa (usuario_id, id_empresa)
               select usuario_id, 2 from usuario where upper(username) = upper(:u)
                and not exists (select 1 from usuario_empresa ue
                                 where ue.usuario_id = usuario.usuario_id
                                   and ue.id_empresa = 2)""", u=USUARIO)
con.commit()
cur.execute("select count(*) from v_empresas_usuario where upper(username) = upper(:u)", u=USUARIO)
print("  empresas del usuario de prueba:", cur.fetchone()[0])

proc = subprocess.Popen([EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
                         "--remote-debugging-port=9297",
                         "--user-data-dir=%s" % os.path.join(tempfile.gettempdir(),
                                                             "opencode", "edge-p19m"),
                         "about:blank"],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def objetivo():
    for _ in range(40):
        try:
            lista = json.loads(urllib.request.urlopen(
                "http://127.0.0.1:9297/json/list", timeout=2).read())
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


for m in ("Page.enable", "Runtime.enable"):
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
    if not esperar('document.readyState === "complete" && !!document.getElementById("P19_NOMBRE_EMPRESA")'):
        sys.exit("la pagina 19 no pinto el formulario de empresa")
    time.sleep(2)

    comprueba(str(js('apex.item("P19_NOMBRE_EMPRESA").getValue()') or "") == "",
              "con dos empresas el formulario de Empresa abre en blanco (no se elige por la cuenta)")

    # Las pestanas fiscal y del logo ya no tienen su propio combo (2026-11-22):
    # trabajan sobre la empresa que se edita o la activa de la barra, y con varias
    # empresas y ninguna elegida resuelven la menor del usuario. Antes, con el
    # `having count(*) = 1`, se quedaban vacias y parecia que no habia datos.
    comprueba(num(js('apex.item("P19F_ID_EMPRESA").getValue()')) > 0,
              "la pestana fiscal resuelve una empresa (no queda vacia)",
              js('apex.item("P19F_ID_EMPRESA").getValue()'))
    comprueba(js('document.getElementById("P19F_ID_EMPRESA").type === "hidden"'),
              "y ya no hay un combo de empresa dentro de la pestana")
    nombre_f = str(js("""(function(){var e=document.getElementById('P19F_EMPRESA_NOMBRE');
                          return e ? String(e.innerText || e.value || '').trim() : 'SIN ITEM';})()""") or "")
    comprueba(nombre_f not in ("", "- sin empresa -", "SIN ITEM"),
              "la pestana fiscal dice de que empresa es", nombre_f)
    comprueba(str(js('apex.item("P19L_ID_EMPRESA").getValue()')) ==
              str(js('apex.item("P19F_ID_EMPRESA").getValue()')),
              "las dos pestanas trabajan sobre la misma empresa")

    comprueba(js("document.querySelector('[data-otel-label=\"BTN_GUARDAR_FISCAL\"]') !== null"),
              "los botones fiscales estan siempre (sin empresa avisan al guardar)")

    js('[...document.querySelectorAll("button")].find(function(b){'
       'return b.getAttribute("data-otel-label") === "BTN_GUARDAR_EMPRESA"; }).click()')
    ok = esperar('document.body.innerText.indexOf("nombre de la empresa es obligatorio") >= 0', 45)
    comprueba(ok, "«Guardar empresa» llega al proceso aunque la pestana fiscal tenga empresa",
              (js("document.body.innerText") or "")[:200].replace("\n", " / "))

    # La pestana del logo: misma empresa y sus botones a la vista.
    js("""(function(){var a=document.querySelector('.a-RDS-link[href="#R43000000000000434"]');
             if(a){a.click();}})()""")
    time.sleep(2)
    comprueba(js("document.querySelector('[data-otel-label=\"BTN_SUBIR_LOGO\"]') !== null"),
              "los botones del logo estan siempre")
    comprueba(js("document.querySelector('[data-otel-label=\"BTN_QUITAR_LOGO\"]') !== null"),
              "tambien esta «Quitar logo»")
    nombre_l = str(js("""(function(){var e=document.getElementById('P19L_EMPRESA_NOMBRE');
                          return e ? String(e.innerText || e.value || '').trim() : 'SIN ITEM';})()""") or "")
    comprueba(nombre_l == nombre_f, "la pestana del logo dice la misma empresa", nombre_l)
finally:
    proc.terminate()
    cur.execute("begin delete from usuario_empresa where usuario_id in "
                "(select usuario_id from usuario where upper(username)=upper(:u)); commit; "
                "delete from usuario where upper(username)=upper(:u); commit; end;", u=USUARIO)
    con.commit()
    con.close()

print("\nRESULTADO: FALLAS=%d" % fallas)
sys.exit(1 if fallas else 0)
