#!/usr/bin/env python3
"""Pagina 19 «Administracion»: la pestana «Datos fiscales» (Paso A del plan de
pestanas) tiene que cargar la fila de EMPRESA_FISCAL de la empresa del usuario,
guardarla desde la propia pestana y hacerlo tambien desde «Datos de la imprenta».

Se conduce con Edge headless por CDP (login real, clic real). Deja la fila de
EMPRESA_FISCAL de la empresa 1 como estaba (restaura en 'finally').

Uso:  python deploy/diagnostico/20261111_pagina19_datos_fiscales.py
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
TEL_PRUEBA = "0212-5550000"
TEL_IMP_PRUEBA = "0212-5551111"
fallas = 0
omitidos = []


def comprueba(ok, texto, detalle=""):
    global fallas
    print("  [%s] %s%s" % ("OK   " if ok else "FALLA", texto,
                           "" if not detalle else " (%s)" % detalle))
    if not ok:
        fallas += 1


def omite(texto, motivo):
    """Caso que depende de un dato opcional que pone el cliente.

    No es falla (la pantalla esta bien aunque el dato no exista) pero se dice
    en voz alta y se resume al final: nada pasa en silencio.
    """
    print("  [OMITIDO] %s -- %s" % (texto, motivo))
    omitidos.append((texto, motivo))


c = credenciales()
con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")

COLUMNAS = ["direccion_fiscal", "telefono", "email", "nro_providencia", "prov_fecha",
            "control_desde", "control_hasta", "imprenta_nombre", "imprenta_rif",
            "imprenta_direccion", "imprenta_telefono", "imprenta_email",
            "tipo_emision", "nro_registro_maquina"]
cur.execute("select %s from empresa_fiscal where id_empresa = 1" % ", ".join(COLUMNAS))
original = cur.fetchone()
prov_original = original[3]
imp_original = original[7]

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
                         "--remote-debugging-port=9293",
                         "--user-data-dir=%s" % os.path.join(tempfile.gettempdir(),
                                                             "opencode", "edge-p19f"),
                         "about:blank"],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def obj():
    for _ in range(40):
        try:
            lista = json.loads(urllib.request.urlopen(
                "http://127.0.0.1:9293/json/list", timeout=2).read())
            paginas = [t for t in lista if t.get("type") == "page"]
            if paginas:
                return paginas[0]
        except Exception:
            pass
        time.sleep(0.5)


ws = websocket.create_connection(obj()["webSocketDebuggerUrl"], timeout=60)
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


def valor(item):
    return js("apex.item('%s').getValue()" % item)


def esperar_bd(consulta, esperado, s=25):
    """El submit de APEX es una navegacion: el mensaje de la pantalla anterior
    sigue en el DOM hasta que llega la nueva. La verdad es la base."""
    f = time.time() + s
    while time.time() < f:
        cur.execute(consulta)
        if cur.fetchone()[0] == esperado:
            return True
        time.sleep(1)
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
        print("  MAL login fallido")
        raise SystemExit(1)

    js('window.location.href="%s/f?p=100:19:%s"' % (BASE, ses.group(1)))
    if not esperar('document.readyState === "complete" && !!document.getElementById("P19F_NRO_PROVIDENCIA")'):
        print("  MAL la pagina 19 no pinto la pestana de datos fiscales")
        raise SystemExit(1)
    time.sleep(2)

    # 1) Las pestanas existen en el selector de regiones.
    rds = js("(document.getElementById('43000000000000380_RDS')||{}).innerText || ''")
    comprueba("Datos fiscales" in (rds or ""), "el selector tiene la pestana «Datos fiscales»", rds)
    comprueba("Datos de la imprenta" in (rds or ""),
              "el selector tiene la pestana «Datos de la imprenta»")
    comprueba("Empresa" in (rds or ""), "«Empresa» tambien es pestana")

    # 2) La fila de EMPRESA_FISCAL se cargo en los items. La providencia y el
    #    nombre de la imprenta son datos OPCIONALES que teclea el cliente: si no
    #    estan, se omite la comparacion (no es un fallo de la pantalla) pero se
    #    exige que el campo salga vacio y no con un texto inventado.
    if prov_original is None:
        omite("carga la providencia de la empresa 1",
              "la empresa 1 no tiene providencia configurada (dato del cliente)")
        comprueba((valor("P19F_NRO_PROVIDENCIA") or "") == "",
                  "sin providencia el campo sale vacio, sin texto inventado",
                  repr(valor("P19F_NRO_PROVIDENCIA")))
    else:
        comprueba(valor("P19F_NRO_PROVIDENCIA") == prov_original,
                  "carga la providencia de la empresa 1", repr(valor("P19F_NRO_PROVIDENCIA")))

    if imp_original is None:
        omite("carga el nombre de la imprenta",
              "la empresa 1 no tiene imprenta configurada (dato del cliente)")
        comprueba((valor("P19F_IMPRENTA_NOMBRE") or "") == "",
                  "sin imprenta el campo sale vacio", repr(valor("P19F_IMPRENTA_NOMBRE")))
    else:
        comprueba(valor("P19F_IMPRENTA_NOMBRE") == imp_original,
                  "carga el nombre de la imprenta", repr(valor("P19F_IMPRENTA_NOMBRE")))

    comprueba(str(valor("P19F_ID_EMPRESA")) == "1",
              "la empresa por defecto es la del usuario", repr(valor("P19F_ID_EMPRESA")))

    # 3) Cambiar de pestana oculta la otra region (solo en la pagina recien cargada:
    #    justo despues de un submit el widget de tabs aun no esta enganchado y un
    #    clic en el enlace se va a la landing de ORDS; medido el 2026-11-16).
    js("""(function(){var a=[...document.querySelectorAll('.a-RDS-link')]
             .find(function(x){return /Datos de la imprenta/i.test(x.innerText);});
             if(a){a.click();}})()""")
    time.sleep(2)
    comprueba(js("document.getElementById('P19F_IMPRENTA_TELEFONO').offsetParent !== null"),
              "la pestana de la imprenta muestra sus campos")
    comprueba(js("document.getElementById('P19F_TELEFONO').offsetParent === null"),
              "la pestana fiscal queda oculta")

    # Se recarga para volver al estado limpio antes de guardar.
    js("location.reload()")
    esperar('document.readyState === "complete" && !!document.getElementById("P19F_TELEFONO")')
    time.sleep(2)

    # 3b) Rango de control (2026-11-25): uno que no sirve para numerar no se guarda y
    #     se explica por que (fn_rango_control_error).
    js('apex.item("P19F_CONTROL_DESDE").setValue("000001");'
       'apex.item("P19F_CONTROL_HASTA").setValue("0000010000");')
    js("document.getElementById('B43000000000000427').click()")
    ok = esperar('document.body.innerText.indexOf("misma cantidad de digitos") >= 0')
    comprueba(ok, "un rango con distinta cantidad de digitos no se guarda y lo explica")
    js("location.reload()")
    esperar('document.readyState === "complete" && !!document.getElementById("P19F_TELEFONO")')
    time.sleep(2)

    # 4) Guardar desde la pestana «Datos fiscales» (boton por id: los dos botones
    #    comparten texto y solo cambia la region que los pinta). Con un rango valido:
    #    el del cliente puede estar mal y entonces no dejaria guardar (se restaura al final).
    js('apex.item("P19F_CONTROL_DESDE").setValue("00-000001");'
       'apex.item("P19F_CONTROL_HASTA").setValue("00-010000");')
    js('apex.item("P19F_TELEFONO").setValue(%s)' % json.dumps(TEL_PRUEBA))
    js("document.getElementById('B43000000000000427').click()")
    ok = esperar('document.body.innerText.indexOf("Datos fiscales guardados") >= 0')
    comprueba(ok, "salio «Datos fiscales guardados»")
    comprueba(esperar_bd("select telefono from empresa_fiscal where id_empresa = 1", TEL_PRUEBA),
              "el telefono quedo guardado", repr(TEL_PRUEBA))

    # 5) Guardar desde la pestana «Datos de la imprenta».
    time.sleep(2)
    js('apex.item("P19F_IMPRENTA_TELEFONO").setValue(%s)' % json.dumps(TEL_IMP_PRUEBA))
    js("document.getElementById('B43000000000000428').click()")
    comprueba(esperar_bd("select imprenta_telefono from empresa_fiscal where id_empresa = 1",
                         TEL_IMP_PRUEBA),
              "el telefono de la imprenta quedo guardado")
    # El MERGE escribe las 14 columnas: desde la pestana de la imprenta no puede
    # pisar lo que se guardo en la fiscal.
    cur.execute("select telefono from empresa_fiscal where id_empresa = 1")
    comprueba(cur.fetchone()[0] == TEL_PRUEBA,
              "guardar la imprenta no pisa el telefono fiscal", repr(TEL_PRUEBA))

    # 6) El RIF de la imprenta se guarda en MAYUSCULAS (2026-11-22): se teclea en
    #    minusculas y la base tiene que quedar en mayusculas.
    time.sleep(2)
    js('apex.item("P19F_IMPRENTA_RIF").setValue("j-12345678-9")')
    js("document.getElementById('B43000000000000428').click()")
    ok = esperar_bd("select imprenta_rif from empresa_fiscal where id_empresa = 1",
                    "J-12345678-9")
    cur.execute("select imprenta_rif from empresa_fiscal where id_empresa = 1")
    queda = cur.fetchone()[0]
    comprueba(ok, "el RIF de la imprenta se guarda en mayusculas", repr(queda))
finally:
    proc.terminate()
    cur.execute("""update empresa_fiscal set direccion_fiscal=:0, telefono=:1, email=:2,
                          nro_providencia=:3, prov_fecha=:4, control_desde=:5, control_hasta=:6,
                          imprenta_nombre=:7, imprenta_rif=:8, imprenta_direccion=:9,
                          imprenta_telefono=:10, imprenta_email=:11, tipo_emision=:12,
                          nro_registro_maquina=:13
                     where id_empresa = 1""",
                **{str(i): v for i, v in enumerate(original)})
    cur.execute("begin delete from usuario_empresa where usuario_id in "
                "(select usuario_id from usuario where upper(username)=upper(:u)); commit; "
                "delete from usuario where upper(username)=upper(:u); commit; end;", u=USUARIO)
    con.commit()
    cur.execute("select telefono, imprenta_telefono from empresa_fiscal where id_empresa = 1")
    restaurado = cur.fetchone()
    con.close()
    print("  restaurar: telefono=%r imprenta=%r" % restaurado)
    if restaurado != (original[1], original[10]):
        print("  AVISO: no se pudo restaurar la fila")

print("\nRESULTADO: FALLAS=%d OMITIDOS=%d" % (fallas, len(omitidos)))
if omitidos:
    print("  Casos omitidos (no son fallas: dependen de datos del cliente):")
    for texto, motivo in omitidos:
        print("   * %s: %s" % (texto, motivo))
sys.exit(1 if fallas else 0)
