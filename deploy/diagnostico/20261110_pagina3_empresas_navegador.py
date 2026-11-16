#!/usr/bin/env python3
# =============================================================================
# 20261110_pagina3_empresas_navegador.py
#
# Verificacion en NAVEGADOR REAL (Edge headless por CDP) de la columna
# «Empresas» de la pagina 3 «Gestion de Usuarios».
#
# Que mide:
#   1. Un usuario temporal ADMIN con DOS empresas abre la pagina 3: la
#      columna «Empresas» pinta las DOS empresas COMPARTIDAS, separadas por
#      ', ' y ordenadas por nombre.
#   2. Un usuario que ademas tiene una empresa AJENA al administrador: esa
#      tercera NO aparece en la columna «Empresas» (decision 13.6 del spec:
#      no se enseña el nombre de la empresa de otro cliente).
#   3. Un usuario temporal ADMIN con UNA empresa: la columna pinta UNA
#      (regresion: un usuario de una sola empresa no debe perder nada).
#
# POR QUE ESTE SCRIPT (y no solo el SQL):
#   La consulta guardada de la region tiene DOS apariciones de ':APP_USER'
#   (el filtro F5 y el subselect de la columna EMPRESAS). El SQL dinamico
#   mide bien el texto guardado, pero no comprueba que APEX resuelva los dos
#   binds al RENDERIZAR el informe. Eso solo se ve en el navegador.
#
# RANGO RESERVADO (regla del plan): TODOS los datos de prueba usan ids
# 900000+. Este script usa ids PROPIOS (900920+) para no pisar a la
# verificacion SQL (que usa 900001..900042).
#
# De donde sale el arnes CDP: deploy/diagnostico/20261110_multiempresa_navegador.py
#
# Uso (desde la raiz del repo):
#   python deploy/diagnostico/20261110_pagina3_empresas_navegador.py
#
# Salida: RESULTADO: FALLAS=n (sale con codigo 1 si hay fallas).
# =============================================================================

import base64
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

CLAVE = "Diag#2026"

# --- Datos de prueba (rango 900000+) ---------------------------------------
ID_USUARIO_A = 900920   # administrador con DOS empresas (900921, 900922)
ID_USUARIO_B = 900923   # usuario con DOS: una compartida + una AJENA (900923)
ID_USUARIO_C = 900924   # administrador con UNA empresa (900921)
ID_EMP_A = 900921       # compartida
ID_EMP_B = 900922       # compartida
ID_EMP_X = 900923       # AJENA (solo del usuario B)

USUARIO_A = "DIAG_P3_ADM"
USUARIO_B = "DIAG_P3_USR"
USUARIO_C = "DIAG_P3_UNI"

NOM_A = "DIAG P3 ALFA"
NOM_B = "DIAG P3 BETA"
NOM_X = "DIAG P3 GAMMA"

CAPTURA = os.path.join(REPO, "deploy", "resultados", "20261110_pagina3_empresas.png")

fallas = 0


def falla(msg):
    global fallas
    fallas += 1
    print("  MAL " + msg)


def ok(msg):
    print("  OK  " + msg)


# ---------------------------------------------------------------------------
# Base de datos: usuarios temporales, empresas de prueba y pares.
# ---------------------------------------------------------------------------
c = credenciales()
con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")


def sql(texto, **params):
    cur.execute(texto, params or None)


def borrar_todo():
    """Borra TODOS los datos de prueba (rango 900000+).

    MEDIDO (2026-11-11): los DELETE con 'in (:a, :b, :c)' sobre
    USUARIO_EMPRESA y EMPRESAS los manda el servidor en PARALELO, y en esta
    base el error de la FK sale enmascarado como ORA-12801 ('error signaled in
    parallel query server') con un ORA-02292 ('child record found') que es
    FALSO: no hay ninguna fila hija. Borra fila por fila, que va en serie y
    no da el falso error.

    OJO EL ORDEN: 'USUARIO.ID_EMPRESA' tiene su propia FK a EMPRESAS
    (FK_USUARIO_EMPRESA), aparte de la de USUARIO_EMPRESA. Por eso los
    USUARIOS se borran ANTES que las EMPRESAS: si no, la empresa no se puede
    borrar porque el usuario la tiene en su columna.
    """
    for uid in (ID_USUARIO_A, ID_USUARIO_B, ID_USUARIO_C):
        sql("delete from usuario_empresa where usuario_id = :u", u=uid)
        con.commit()
    for eid in (ID_EMP_A, ID_EMP_B, ID_EMP_X):
        sql("delete from usuario_empresa where id_empresa = :e", e=eid)
        con.commit()
    for uid in (ID_USUARIO_A, ID_USUARIO_B, ID_USUARIO_C):
        sql("delete from usuario where usuario_id = :u", u=uid)
        con.commit()
    for eid in (ID_EMP_A, ID_EMP_B, ID_EMP_X):
        sql("delete from empresas where id_empresa = :e", e=eid)
        con.commit()


def preparar():
    """Deja la base como la necesita la prueba, TODO en el rango 900000+."""
    borrar_todo()

    for i, n in ((ID_EMP_A, NOM_A), (ID_EMP_B, NOM_B), (ID_EMP_X, NOM_X)):
        sql("""insert into empresas (id_empresa, nombre_empresa, cod_pais,
                                       tipo_ident_fiscal, estado, fecha_creacion)
               values (:i, :n, 'VE', 'RIF', 'ACTIVO', systimestamp)""", i=i, n=n)
        con.commit()

    for uid, nombre in ((ID_USUARIO_A, USUARIO_A),
                        (ID_USUARIO_B, USUARIO_B),
                        (ID_USUARIO_C, USUARIO_C)):
        sql("""insert into usuario (usuario_id, username, email, password_hash, estado,
                                      id_empresa, rol_id, debe_cambiar_clave, reintentos_fallidos)
               values (:i, :u, :e, sypex_hash_password(:p), 'ACTIVO', :emp,
                       (select min(id_rol) from syn_roles where codigo_rol='ADMIN'), 'N', 0)""",
            i=uid, u=nombre, e=nombre.lower() + "@synpex.local", p=CLAVE, emp=ID_EMP_A)
        con.commit()

    # El administrador A: empresas ALFA y BETA (las dos compartidas).
    sql("""insert into usuario_empresa (usuario_id, id_empresa)
           select :u, :e from dual where not exists
           (select 1 from usuario_empresa where usuario_id = :u and id_empresa = :e)""",
        u=ID_USUARIO_A, e=ID_EMP_A)
    con.commit()
    sql("""insert into usuario_empresa (usuario_id, id_empresa)
           select :u, :e from dual where not exists
           (select 1 from usuario_empresa where usuario_id = :u and id_empresa = :e)""",
        u=ID_USUARIO_A, e=ID_EMP_B)
    con.commit()

    # El usuario B: ALFA (compartida) y GAMMA (AJENA al administrador).
    sql("""insert into usuario_empresa (usuario_id, id_empresa)
           select :u, :e from dual where not exists
           (select 1 from usuario_empresa where usuario_id = :u and id_empresa = :e)""",
        u=ID_USUARIO_B, e=ID_EMP_A)
    con.commit()
    sql("""insert into usuario_empresa (usuario_id, id_empresa)
           select :u, :e from dual where not exists
           (select 1 from usuario_empresa where usuario_id = :u and id_empresa = :e)""",
        u=ID_USUARIO_B, e=ID_EMP_X)
    con.commit()

    # El administrador C: solo ALFA (regresion, una sola empresa).
    sql("""insert into usuario_empresa (usuario_id, id_empresa)
           select :u, :e from dual where not exists
           (select 1 from usuario_empresa where usuario_id = :u and id_empresa = :e)""",
        u=ID_USUARIO_C, e=ID_EMP_A)
    con.commit()

    sql("select u.username, ue.id_empresa from usuario_empresa ue "
        "join usuario u on u.usuario_id = ue.usuario_id "
        "where u.usuario_id in (:a, :b, :c) order by 1,2",
        a=ID_USUARIO_A, b=ID_USUARIO_B, c=ID_USUARIO_C)
    print("  pares de prueba:", cur.fetchall())


# ---------------------------------------------------------------------------
# Edge headless por CDP.
# ---------------------------------------------------------------------------
proc = subprocess.Popen(
    [EDGE, "--headless=new", "--disable-gpu", "--no-first-run", "--remote-debugging-port=9294",
     "--user-data-dir=" + os.path.join(tempfile.gettempdir(), "opencode", "edge-p3emp"),
     "--window-size=1440,1000", "about:blank"],
    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def objetivo():
    for _ in range(40):
        try:
            l = json.loads(urllib.request.urlopen("http://127.0.0.1:9294/json/list", timeout=2).read())
            p = [t for t in l if t.get("type") == "page"]
            if p:
                return p[0]
        except Exception:
            pass
        time.sleep(0.5)
    raise SystemExit("no se pudo abrir Edge")


ws = websocket.create_connection(objetivo()["webSocketDebuggerUrl"], timeout=90)
ws.settimeout(90)
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


def esperar(cond, s=60):
    f = time.time() + s
    while time.time() < f:
        if js(cond):
            return True
        time.sleep(0.5)
    return False


def texto():
    return js("document.body.innerText") or ""


def entrar(usuario):
    js('window.location.href="%s/f?p=100:9999"' % BASE)
    esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(1)
    js('(function(){apex.item("P9999_USERNAME").setValue(%s);apex.item("P9999_PASSWORD").setValue(%s);'
       'var b=[...document.querySelectorAll("button")].find(x=>/sign in|iniciar|entrar/i.test(x.innerText));'
       'if(b){b.click();}})()' % (json.dumps(usuario), json.dumps(CLAVE)))
    time.sleep(7)
    ses = re.search(r"session=(\d+)", js("window.location.href") or "")
    if not ses:
        raise SystemExit("  MAL login fallido para " + usuario)
    return ses.group(1)


# ---------------------------------------------------------------------------
# Lectura de la tabla del IR.
#
# OJO (medido el 2026-11-11): el marcado del IR de APEX 26.1 pone la fila de
# ENCABEZADOS ('<tr><th ...>') como hija directa de '<table class="a-IRR-table">',
# sin '<thead>' ni '<tbody>': si se pide 'tbody tr' sale tambien la cabecera.
# La fila de datos es la unica que tiene celdas '<td>'. Ademas la celda 0 es
# la del enlace «Editar» (la columna USUARIO_ID, oculta con el icono), la 1
# es USERNAME, la 2 EMAIL, la 3 EMPRESA, la 4 ROL y la 5 EMPRESAS.
# ---------------------------------------------------------------------------
JS_TABLA = (
    "(function(){var t=document.getElementById('R10564941614198500_worksheet_region');"
    "if(!t) return null;"
    "var rs=[...t.querySelectorAll('table.a-IRR-table tr')]"
    ".filter(function(r){return r.querySelector('td');});"
    "return rs.map(function(r){return [...r.cells].map(function(c){return c.innerText.trim();});});})()"
)

JS_EMPRESAS = (
    "(function(){var t=document.getElementById('R10564941614198500_worksheet_region');"
    "if(!t) return null;"
    "var rs=[...t.querySelectorAll('table.a-IRR-table tr')]"
    ".filter(function(r){return r.querySelector('td');});"
    "var out={};"
    "rs.forEach(function(r){var u=r.cells[1]?r.cells[1].innerText.trim():'';"
    "  var e=r.cells[5]?r.cells[5].innerText.trim():'';out[u]=e;});"
    "return out;})()"
)

JS_ENCABEZADOS = (
    "(function(){var t=document.getElementById('R10564941614198500_worksheet_region');"
    "if(!t) return null;"
    "var tr=t.querySelector('table.a-IRR-table tr');"
    "if(!tr) return null;"
    "return [...tr.children].map(function(c){return c.innerText.trim();});})()"
)


def abrir_pagina3(ses):
    js('window.location.href="%s/f?p=100:3:%s"' % (BASE, ses))
    return esperar('document.readyState === "complete" && '
                   '!!document.getElementById("R10564941614198500_worksheet_region")')


def empresas_por_usuario():
    v = js(JS_EMPRESAS)
    return v if isinstance(v, dict) else {}


try:
    preparar()

    # -----------------------------------------------------------------------
    # 1) Administrador con DOS empresas.
    # -----------------------------------------------------------------------
    print("\n== administrador con DOS empresas ==")
    ses = entrar(USUARIO_A)
    if not abrir_pagina3(ses):
        falla("la pagina 3 no pinto la region; texto: " + texto()[:300])
        raise SystemExit(1)
    time.sleep(2)

    enc = js(JS_ENCABEZADOS)
    print("  encabezados:", enc)
    if not isinstance(enc, list) or "Empresas" not in enc:
        falla("la columna «Empresas» no sale en el informe: %r" % (enc,))

    tabla = js(JS_TABLA)
    print("  filas:", tabla)

    por_usuario = empresas_por_usuario()
    print("  columna Empresas:", por_usuario)

    # El usuario B tiene ALFA (compartida) y GAMMA (AJENA): solo ALFA.
    v = por_usuario.get(USUARIO_B)
    if v is None:
        falla("el usuario %s no sale en la lista" % USUARIO_B)
    else:
        if NOM_A not in v:
            falla("EMPRESAS de %s no trae la empresa compartida %r (trae %r)"
                  % (USUARIO_B, NOM_A, v))
        else:
            ok("%s trae la empresa compartida %r" % (USUARIO_B, NOM_A))
        if NOM_X in v:
            falla("EMPRESAS de %s trae la empresa AJENA %r (trae %r): no se puede "
                  "enseñar la empresa de otro cliente" % (USUARIO_B, NOM_X, v))
        else:
            ok("%s NO trae la empresa ajena %r" % (USUARIO_B, NOM_X))

    # El propio administrador ve sus DOS empresas, ordenadas por nombre.
    v = por_usuario.get(USUARIO_A)
    if v is None:
        falla("el administrador %s no sale en su propia lista" % USUARIO_A)
    elif v != "%s, %s" % (NOM_A, NOM_B):
        falla("EMPRESAS del administrador = %r (se esperaba %r)"
              % (v, "%s, %s" % (NOM_A, NOM_B)))
    else:
        ok("el administrador ve sus dos empresas: %r" % v)

    # El administrador C (una empresa) ve UNA.
    v = por_usuario.get(USUARIO_C)
    if v is None:
        falla("el usuario %s no sale en la lista" % USUARIO_C)
    elif v != NOM_A:
        falla("EMPRESAS de %s = %r (se esperaba %r)" % (USUARIO_C, v, NOM_A))
    else:
        ok("%s (una sola empresa) trae %r" % (USUARIO_C, v))

    try:
        os.makedirs(os.path.dirname(CAPTURA), exist_ok=True)
        datos = cmd("Page.captureScreenshot", format="png", captureBeyondViewport=True)
        with open(CAPTURA, "wb") as f:
            f.write(base64.b64decode(datos["data"]))
        print("  captura guardada en", CAPTURA)
    except Exception as ex:
        print("  AVISO: no se pudo guardar la captura: %s" % str(ex)[:120])

    # -----------------------------------------------------------------------
    # 2) El usuario B como administrador: solo ve su propia ALFA (la GAMMA es
    #    suya, asi que debe verla) y la del admin NO puede ser ajena.
    # -----------------------------------------------------------------------
    print("\n== el usuario B entra como administrador ==")
    ses = entrar(USUARIO_B)
    if not abrir_pagina3(ses):
        falla("la pagina 3 no pinto la region para %s; texto: " % USUARIO_B + texto()[:300])
    else:
        time.sleep(2)
        por_usuario = empresas_por_usuario()
        print("  columna Empresas:", por_usuario)
        v = por_usuario.get(USUARIO_B)
        if v is None:
            falla("el usuario %s no sale en su propia lista" % USUARIO_B)
        elif NOM_X not in v or NOM_A not in v:
            falla("EMPRESAS de %s = %r (se esperaban %r y %r)"
                  % (USUARIO_B, v, NOM_A, NOM_X))
        else:
            ok("%s (admin de ALFA y GAMMA) ve %r" % (USUARIO_B, v))
        # El administrador A solo tiene ALFA y BETA: BETA es ajena para B.
        v = por_usuario.get(USUARIO_A)
        if v is not None and NOM_B in v:
            falla("EMPRESAS de %s trae %r, que es ajena a %s (trae %r)"
                  % (USUARIO_A, NOM_B, USUARIO_B, v))
        else:
            ok("a %s no le sale %r (empresa ajena)" % (USUARIO_A, NOM_B))
finally:
    proc.terminate()
    borrar_todo()
    for etiqueta, consulta in (
            ("usuario", "select count(*) from usuario where usuario_id >= 900000"),
            ("usuario_empresa", "select count(*) from usuario_empresa where usuario_id >= 900000"),
            ("empresas", "select count(*) from empresas where id_empresa >= 900000")):
        sql(consulta)
        n = cur.fetchone()[0]
        print("  filas de prueba que quedan en %s: %d" % (etiqueta, n))
        if n:
            falla("quedan %d filas de prueba en %s (rango 900000+)" % (n, etiqueta))
    con.close()

print("\nRESULTADO: FALLAS=%d" % fallas)
sys.exit(1 if fallas else 0)
