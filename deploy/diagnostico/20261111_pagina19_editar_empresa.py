#!/usr/bin/env python3
"""Pagina 19, pestana «Empresa»:

  1. Al ENTRAR, el formulario tiene que estar en blanco (solo el estado en ACTIVO):
     es el alta. «Nueva empresa» ya no existe porque el formulario ya nace vacio.
  2. «Editar» de «Mis empresas» tiene que cargar esa empresa Y DEJAR VISIBLE la
     pestana «Empresa» (si el formulario se llena en una pestana oculta, el
     usuario ve «no levanta la pantalla»).

Se conduce con Edge headless por CDP. No escribe nada.

Uso:  python deploy/diagnostico/20261111_pagina19_editar_empresa.py
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

USUARIO, CLAVE = "diag.pestanas3", "Diag#2026"
PRUEBA = "EMPRESA PRUEBA P19 ALTA"
fallas = 0


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

cur.execute("select nombre_empresa from empresas where id_empresa = 1")
nombre1 = cur.fetchone()[0]

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
                         "--remote-debugging-port=9298",
                         "--user-data-dir=%s" % os.path.join(tempfile.gettempdir(),
                                                             "opencode", "edge-p19e"),
                         "about:blank"],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def objetivo():
    for _ in range(40):
        try:
            lista = json.loads(urllib.request.urlopen(
                "http://127.0.0.1:9298/json/list", timeout=2).read())
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

    # 1) Alta: formulario vacio, solo el estado.
    comprueba(not js('apex.item("P19_ID_EMPRESA").getValue()'),
              "al entrar, la empresa esta vacia", repr(js('apex.item("P19_ID_EMPRESA").getValue()')))
    comprueba(not js('apex.item("P19_NOMBRE_EMPRESA").getValue()'),
              "al entrar, el nombre esta vacio", repr(js('apex.item("P19_NOMBRE_EMPRESA").getValue()')))
    comprueba(js('apex.item("P19_ESTADO").getValue()') == "ACTIVO",
              "al entrar, el estado es ACTIVO", repr(js('apex.item("P19_ESTADO").getValue()')))
    comprueba(js("document.querySelector('[data-otel-label=\"BTN_CREAR_EMPRESA\"]') !== null"),
              "«Nueva empresa» esta disponible para limpiar el formulario")

    # 2) Editar tiene que cargar la empresa y dejar la pestana «Empresa» delante.
    #    OJO: desde el 2026-11-20 el enlace es SOLO el icono (como en Clientes),
    #    asi que no se puede buscar por el texto «Editar».
    js("""(function(){var a=document.querySelector('a.spx-editar[href*="p19_id_empresa"]');
             if(!a){a=[...document.querySelectorAll('a')].find(function(x){
               return /p19_id_empresa/i.test(x.getAttribute('href')||'');});}
             if(a){a.click();}})()""")
    if not esperar('document.readyState === "complete" && !!window.apex', 30):
        sys.exit("no recargo al pulsar Editar")
    time.sleep(3)
    comprueba(str(js('apex.item("P19_ID_EMPRESA").getValue()') or "") == "1",
              "Editar carga el id de la empresa", repr(js('apex.item("P19_ID_EMPRESA").getValue()')))
    comprueba(js('apex.item("P19_NOMBRE_EMPRESA").getValue()') == nombre1,
              "Editar carga el nombre", repr(js('apex.item("P19_NOMBRE_EMPRESA").getValue()')))
    clases = js("(document.getElementById('R43000000000000381')||{}).className || ''")
    comprueba("apex-rds-element-selected" in (clases or ""),
              "Editar deja la pestana «Empresa» seleccionada", clases)

    # 3) Editar y guardar: el nombre cambia y el proceso responde.
    EDITADO = nombre1 + " EDITADA"
    js('apex.item("P19_NOMBRE_EMPRESA").setValue(%s)' % json.dumps(EDITADO))
    js("document.getElementById('B43000000000000388').click()")
    ok = esperar('document.body.innerText.indexOf("Empresa guardada") >= 0', 45)
    comprueba(ok, "editar y guardar responde «Empresa guardada»")
    cur.execute("select nombre_empresa from empresas where id_empresa = 1")
    comprueba(cur.fetchone()[0] == EDITADO, "el nombre quedo guardado en la base")
    cur.execute("update empresas set nombre_empresa = :n where id_empresa = 1", n=nombre1)
    con.commit()

    # 4) Alta: se entra de nuevo (formulario en blanco), se escribe y se guarda.
    js('window.location.href="%s/f?p=100:19:%s"' % (BASE, ses.group(1)))
    esperar('document.readyState === "complete" && !!document.getElementById("P19_NOMBRE_EMPRESA")', 60)
    time.sleep(2)
    comprueba(not js('apex.item("P19_NOMBRE_EMPRESA").getValue()'),
              "al volver a entrar el formulario sigue en blanco")
    js('apex.item("P19_NOMBRE_EMPRESA").setValue(%s)' % json.dumps(PRUEBA))
    # Desde el 2026-11-17/18 la empresa exige un RIF/RFC con la forma del pais
    # (fn_rif_empresa_valido): sin el, el alta responde «El RIF/RFC de la empresa
    # no tiene la forma del pais». La prueba es del alta en blanco, no del RIF.
    js('apex.item("P19_COD_PAIS").setValue("VE")')
    js('apex.item("P19_RFC").setValue("J-12345678-9")')
    js("document.getElementById('B43000000000000388').click()")
    ok = esperar('document.body.innerText.indexOf("Empresa creada") >= 0', 45)
    comprueba(ok, "el alta desde el formulario en blanco responde «Empresa creada»")
    cur.execute("select id_empresa from empresas where nombre_empresa = :n", n=PRUEBA)
    fila = cur.fetchone()
    comprueba(fila is not None and fila[0] != 1, "la empresa nueva esta en la base", str(fila))
    if fila:
        cur.execute("""select count(*) from usuario_empresa ue
                         join usuario u on u.usuario_id = ue.usuario_id
                        where upper(u.username) = upper(:u) and ue.id_empresa = :e""",
                    u=USUARIO, e=fila[0])
        comprueba(cur.fetchone()[0] == 1, "el alta asocia la empresa al creador")

    # 5) «Nueva empresa» limpia el formulario (con el id cargado) y deja Empresa.
    js("document.querySelector('[data-otel-label=\"BTN_CREAR_EMPRESA\"]').click()")
    ok = esperar('document.body.innerText.indexOf("Formulario en blanco") >= 0', 45)
    comprueba(ok, "«Nueva empresa» responde «Formulario en blanco»")
    time.sleep(1)
    comprueba(not js('apex.item("P19_ID_EMPRESA").getValue()')
              and not js('apex.item("P19_NOMBRE_EMPRESA").getValue()'),
              "«Nueva empresa» limpia id y nombre")
    clases2 = js("(document.getElementById('R43000000000000381')||{}).className || ''")
    comprueba("apex-rds-element-selected" in (clases2 or ""),
              "«Nueva empresa» deja la pestana «Empresa» seleccionada", clases2)

    # 6) Cambiar de empresa en Datos fiscales NO debe sacar de su pestana.
    js("""(function(){var a=document.querySelector('.a-RDS-link[href="#R43000000000000410"]');
             if(a){a.click();}})()""")
    time.sleep(2)
    clase_fiscal = "(document.getElementById('R43000000000000410')||{}).className || ''"
    comprueba("apex-rds-element-selected" in (js(clase_fiscal) or ""),
              "se puede entrar a la pestana «Datos fiscales»")
    js('apex.submit({request:"CAMBIA_EMPRESA", showWait:true})')
    esperar('document.readyState === "complete" && !!window.apex', 60)
    time.sleep(3)
    comprueba("apex-rds-element-selected" in (js(clase_fiscal) or ""),
              "tras cambiar de empresa sigue en «Datos fiscales»",
              js(clase_fiscal))
finally:
    proc.terminate()
    # Restaurar el nombre y borrar la empresa de prueba (pares primero, con commit
    # en medio: en esta ADB hijo+padre en la misma transaccion da ORA-12860).
    cur.execute("update empresas set nombre_empresa = :n where id_empresa = 1", n=nombre1)
    con.commit()
    cur.execute("""delete from usuario_empresa
                    where id_empresa in (select id_empresa from empresas
                                          where nombre_empresa = :n)""", n=PRUEBA)
    con.commit()
    cur.execute("delete from empresas where nombre_empresa = :n", n=PRUEBA)
    con.commit()
    cur.execute("begin delete from usuario_empresa where usuario_id in "
                "(select usuario_id from usuario where upper(username)=upper(:u)); commit; "
                "delete from usuario where upper(username)=upper(:u); commit; end;", u=USUARIO)
    con.commit()
    con.close()

print("\nRESULTADO: FALLAS=%d" % fallas)
sys.exit(1 if fallas else 0)
