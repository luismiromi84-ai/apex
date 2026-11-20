#!/usr/bin/env python3
# =============================================================================
# 20261110_multiempresa_navegador.py
#
# Verificacion en NAVEGADOR REAL (Edge headless por CDP) de la pagina 19
# «Administracion» con el listado de empresas del usuario y el alta que asocia
# al creador.
#
# Que mide:
#   1. Un usuario temporal ADMIN con DOS empresas abre la pagina 19: el
#      listado «Mis empresas» muestra las DOS filas.
#   2. Pulsar «Editar» en la segunda fila abre el formulario con ESA empresa
#      (no la primera).
#   3. «Nueva empresa» deja el formulario en blanco.
#   4. Escribir «Empresa de prueba NN» y guardar: la empresa se crea, el par
#      queda en USUARIO_EMPRESA para el usuario y la empresa sale en el
#      listado.
#   5. Un usuario temporal ADMIN con UNA empresa: el listado muestra UNA fila y
#      el formulario la trae por defecto (regresion).
#
# Al final borra TODO: los usuarios temporales, la empresa centinela, la
# empresa de prueba y sus pares. Las empresas reales (1 y 2) no se
# tocan. (Antes eran 1, 2, 3, 4 y 5; la poda del 2026-11-19 borro las dotech 3,
# 4 y 5, y este script fallaba con ORA-02291 en FK_UE_EMPRESA.)
#
# RANGO RESERVADO (regla del plan): TODOS los datos de prueba usan ids
# 900000+. Concretamente:
#   - los dos usuarios temporales se insertan con 'usuario_id' EXPLICITO
#     (900901 y 900902), no con la identity;
#   - la empresa centinela se crea con 'id_empresa' = 900910;
#   - la empresa que crea el ALTA la asigna el proceso con
#     'select nvl(max(id_empresa),0)+1 from empresas', o sea que con la
#     centinela presente toma 900911: tambien dentro del rango reservado.
#     (Medido el 2026-11-10: con la centinela 900910, el proceso real
#     «Guardar empresa» asigna 900911.)
# MEDIDO: 'USUARIO.USUARIO_ID' y 'EMPRESAS.ID_EMPRESA' son identity BY DEFAULT,
# asi que un 'insert' con el id explicito entra (probado y revertido).
#
# De donde sale el arnes CDP: deploy/diagnostico/20261109_pagina19_nueva_empresa.py
#
# Uso (desde la raiz del repo):
#   python deploy/diagnostico/20261110_multiempresa_navegador.py
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
USUARIO_A = "DIAG_MULTI_A"   # dos empresas
USUARIO_B = "DIAG_MULTI_B"   # una empresa
NOMBRE_PRUEBA = "EMPRESA PRUEBA MULTI"

# RANGO RESERVADO 900000+ (regla del plan): nada de esto puede tocar el rango
# real de ids.
# Los ids 900001..900005 y 900010 ya los usa la verificacion SQL
# (20261110_multiempresa_verificacion.sql), asi que este script usa ids
# PROPIOS: una corrida no pisa a la otra.
ID_USUARIO_A = 900901
ID_USUARIO_B = 900902
ID_EMPRESA_CENTINELA = 900910   # hace que el alta tome 900911
ID_EMPRESA_ALTA = 900911        # el id que tomara el alta; se comprueba
NOMBRE_CENTINELA = "DIAG CENTINELA 900910"
CAPTURA = os.path.join(REPO, "deploy", "resultados", "20261110_pagina19_listado.png")

fallas = 0


def falla(msg):
    global fallas
    fallas += 1
    print("  MAL " + msg)


# ---------------------------------------------------------------------------
# Base de datos: usuarios temporales, pares y empresa de prueba.
# ---------------------------------------------------------------------------
c = credenciales()
con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")


def sql(texto, **params):
    cur.execute(texto, params or None)


def borrar_todo():
    """Borra TODOS los datos de prueba (rango 900000+)."""
    # Los pares primero (FK a USUARIO y a EMPRESAS).
    sql("""delete from usuario_empresa
             where usuario_id in (:a, :b)
                or id_empresa in (:c, :x)""",
        a=ID_USUARIO_A, b=ID_USUARIO_B, c=ID_EMPRESA_CENTINELA, x=ID_EMPRESA_ALTA)
    con.commit()
    # Las empresas de prueba (la centinela y la que creo el alta).
    sql("""delete from empresas
             where id_empresa in (:c, :x)
                or nombre_empresa = :n""",
        c=ID_EMPRESA_CENTINELA, x=ID_EMPRESA_ALTA, n=NOMBRE_PRUEBA)
    con.commit()
    # Los usuarios temporales.
    sql("delete from usuario where usuario_id in (:a, :b)",
        a=ID_USUARIO_A, b=ID_USUARIO_B)
    con.commit()


def preparar():
    """Deja la base como la necesita la prueba, TODO en el rango 900000+.

    Los usuarios se insertan con 'usuario_id' EXPLICITO (la identity es BY
    DEFAULT, asi que entra). La centinela 900910 hace que el proceso de alta
    calcule 'max(id_empresa)+1' = 900911, tambien dentro del rango reservado.
    """
    borrar_todo()

    # La centinela: sin hijos, solo para que el alto tome un id de prueba.
    sql("""insert into empresas (id_empresa, nombre_empresa, cod_pais,
                                   tipo_ident_fiscal, estado, fecha_creacion)
           values (:i, :n, 'VE', 'RIF', 'ACTIVO', systimestamp)""",
        i=ID_EMPRESA_CENTINELA, n=NOMBRE_CENTINELA)
    con.commit()

    for uid, nombre, correo in ((ID_USUARIO_A, USUARIO_A, "diag.multi.a@synpex.local"),
                                (ID_USUARIO_B, USUARIO_B, "diag.multi.b@synpex.local")):
        sql("""insert into usuario (usuario_id, username, email, password_hash, estado,
                                      id_empresa, rol_id, debe_cambiar_clave, reintentos_fallidos)
               values (:i, :u, :e, sypex_hash_password(:p), 'ACTIVO', 1,
                       (select min(id_rol) from syn_roles where codigo_rol='ADMIN'), 'N', 0)""",
            i=uid, u=nombre, e=correo, p=CLAVE)
        con.commit()

    # El usuario A tiene pares en las empresas 1 y 2 (las dos reales que quedan);
    # el B, solo en la 1.
    sql("""insert into usuario_empresa (usuario_id, id_empresa)
           select :u, :e from dual where not exists
           (select 1 from usuario_empresa where usuario_id = :u and id_empresa = :e)""",
        u=ID_USUARIO_A, e=1)
    con.commit()
    sql("""insert into usuario_empresa (usuario_id, id_empresa)
           select :u, :e from dual where not exists
           (select 1 from usuario_empresa where usuario_id = :u and id_empresa = :e)""",
        u=ID_USUARIO_A, e=2)
    con.commit()
    sql("""insert into usuario_empresa (usuario_id, id_empresa)
           select :u, :e from dual where not exists
           (select 1 from usuario_empresa where usuario_id = :u and id_empresa = :e)""",
        u=ID_USUARIO_B, e=1)
    con.commit()

    sql("select u.usuario_id, ue.id_empresa from usuario_empresa ue "
        "join usuario u on u.usuario_id = ue.usuario_id "
        "where u.usuario_id in (:a, :b) order by 1,2",
        a=ID_USUARIO_A, b=ID_USUARIO_B)
    print("  pares de prueba:", cur.fetchall())

# ---------------------------------------------------------------------------
# Edge headless por CDP.
# ---------------------------------------------------------------------------
proc = subprocess.Popen(
    [EDGE, "--headless=new", "--disable-gpu", "--no-first-run", "--remote-debugging-port=9293",
     "--user-data-dir=" + os.path.join(tempfile.gettempdir(), "opencode", "edge-p19multi"),
     "--window-size=1440,1000", "about:blank"],
    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def objetivo():
    for _ in range(40):
        try:
            l = json.loads(urllib.request.urlopen("http://127.0.0.1:9293/json/list", timeout=2).read())
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


def esperar(cond, s=45):
    f = time.time() + s
    while time.time() < f:
        if js(cond):
            return True
        time.sleep(0.5)
    return False


def clic(texto):
    return js("(function(){var b=[...document.querySelectorAll('button')]"
              ".find(function(x){return /%s/i.test(x.innerText);});"
              "if(b){b.click();return 'clic';}return 'NO';})()" % texto)


def filas_listado():
    """Devuelve la lista de nombres de empresa que pinta el listado.

    OJO: el marcado del IR de APEX 26.1 pone la fila de ENCABEZADOS
    ('<tr><th ...>') como hija directa de '<table class="a-IRR-table">', sin
    '<thead>' ni '<tbody>': si se pide 'tbody tr' sale tambien la cabecera y
    'cells[1]' devuelve el titulo de la columna ('Empresa') en vez del nombre
    de la empresa. La fila de datos es la unica que tiene celdas '<td>'.
    """
    return js("(function(){var t=document.getElementById('R43000000000000396_worksheet_region');"
              "if(!t) return null;"
              "var rs=[...t.querySelectorAll('table.a-IRR-table tr')]"
              ".filter(function(r){return r.querySelector('td');});"
              "return rs.map(function(r){return r.cells[1] ? r.cells[1].innerText.trim() : '';});})()")


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


try:
    # La preparacion va DENTRO del try: si falla el arranque (por ejemplo, que
    # Edge no abra), el finally borra igual lo que se haya creado.
    preparar()

    # -----------------------------------------------------------------------
    # 1) Usuario de DOS empresas.
    # -----------------------------------------------------------------------
    print("\n== usuario con DOS empresas ==")
    ses = entrar(USUARIO_A)
    js('window.location.href="%s/f?p=100:19:%s"' % (BASE, ses))
    if not esperar('document.readyState === "complete" && !!document.getElementById("R43000000000000396_worksheet_region")'):
        falla("la pagina 19 no pinto el listado «Mis empresas»; texto: " + texto()[:200])
        raise SystemExit(1)
    time.sleep(2)

    filas = filas_listado()
    print("  filas del listado:", filas)
    if not filas or len(filas) != 2:
        falla("el listado mostro %r filas (se esperaban 2)" % (filas,))

    # El formulario NO debe elegir solo (el usuario tiene dos empresas).
    nom_ini = js('apex.item("P19_NOMBRE_EMPRESA").getValue()')
    print("  nombre en el formulario al abrir: %r" % nom_ini)
    if nom_ini:
        falla("el formulario se abrio con %r: con dos empresas no se elige por la cuenta" % nom_ini)

    # -----------------------------------------------------------------------
    # 2) «Editar» en la segunda fila: el formulario trae ESA empresa.
    # -----------------------------------------------------------------------
    print("\n== «Editar» en la segunda fila ==")
    enlaces = js("(function(){var t=document.getElementById('R43000000000000396_worksheet_region');"
                 "if(!t) return null;"
                 "var rs=[...t.querySelectorAll('table.a-IRR-table tr')]"
                 ".filter(function(r){return r.querySelector('td');});"
                 "if(rs.length<2) return 'NO';"
                 "var a=rs[1].querySelector('td a');"
                 "if(!a) return 'NO';"
                 "a.click(); return 'clic';})()")
    if enlaces != "clic":
        falla("no se pudo pulsar «Editar» en la segunda fila (%r)" % enlaces)
    else:
        if not esperar('document.readyState === "complete" && !!document.getElementById("P19_NOMBRE_EMPRESA")', 60):
            falla("tras «Editar» no cargo el formulario; texto: " + texto()[:200])
        else:
            time.sleep(2)
            id_sel = js('apex.item("P19_ID_EMPRESA").getValue()')
            nom_sel = js('apex.item("P19_NOMBRE_EMPRESA").getValue()')
            print("  formulario tras «Editar»: id=%r nombre=%r" % (id_sel, nom_sel))
            if not nom_sel:
                falla("«Editar» no cargo la empresa en el formulario")
            else:
                # La empresa cargada tiene que ser la de la fila pulsada.
                sql("select nombre_empresa from empresas where id_empresa = :i", i=int(id_sel))
                real = cur.fetchone()
                print("  la fila pulsada era %r; el formulario trae %r" % (filas[1], real[0] if real else None))
                if not real or real[0] != filas[1]:
                    falla("«Editar» cargo %r en vez de %r" % (real[0] if real else None, filas[1]))

    # -----------------------------------------------------------------------
    # 3) El alta: al entrar de nuevo el formulario esta en blanco. El boton
    #    «Nueva empresa» se elimino el 2026-11-16 (el formulario ya nace vacio).
    # -----------------------------------------------------------------------
    print("\n== formulario en blanco (con «Nueva empresa») ==")
    if js("document.querySelector('[data-otel-label=\"BTN_CREAR_EMPRESA\"]') === null"):
        falla("no esta el boton «Nueva empresa»")
    js('window.location.href="%s/f?p=100:19:%s"' % (BASE, ses))
    if not esperar('document.readyState === "complete" && !!document.getElementById("P19_NOMBRE_EMPRESA")', 60):
        falla("no recargo la pagina 19")
    time.sleep(2)
    id_vacio = js('apex.item("P19_ID_EMPRESA").getValue()')
    nom_vacio = js('apex.item("P19_NOMBRE_EMPRESA").getValue()')
    print("  al entrar de nuevo: id=%r nombre=%r" % (id_vacio, nom_vacio))
    if id_vacio:
        falla("el id no se limpio: con id, «Guardar empresa» ACTUALIZA en vez de dar de alta")
    if nom_vacio:
        falla("el formulario no quedo en blanco")

    # -----------------------------------------------------------------------
    # 4) Alta real: la empresa se crea, el par queda y sale en el listado.
    # -----------------------------------------------------------------------
    print("\n== alta real ==")
    js('apex.item("P19_NOMBRE_EMPRESA").setValue(%s)' % json.dumps(NOMBRE_PRUEBA))
    # La empresa exige un RIF/RFC con la forma del pais desde el 2026-11-17/18
    # (fn_rif_empresa_valido); sin el, el alta responde «El RIF/RFC de la empresa
    # no tiene la forma del pais» y este caso mide el alta y el par, no el RIF.
    js('apex.item("P19_COD_PAIS").setValue("VE")')
    js('apex.item("P19_RFC").setValue("J-12345678-9")')
    if clic("Guardar empresa") != "clic":
        falla("no encontre el boton «Guardar empresa»")
    elif not esperar('document.body.innerText.indexOf("Empresa creada") >= 0', 60):
        falla("no dijo «Empresa creada»; texto: " + texto()[:250])
    time.sleep(2)
    sql("select id_empresa from empresas where nombre_empresa = :n", n=NOMBRE_PRUEBA)
    fila = cur.fetchone()
    if fila and fila[0] < 900000:
        falla("la empresa de prueba tombo el id %d, que esta FUERA del rango "
              "reservado 900000+" % fila[0])
    if fila and fila[0] != ID_EMPRESA_ALTA:
        falla("la empresa de prueba tomo el id %d (se esperaba %d, el siguiente "
              "al de la centinela %d)" % (fila[0], ID_EMPRESA_ALTA, ID_EMPRESA_CENTINELA))
    if not fila:
        falla("no se creo la empresa de prueba")
    else:
        print("  OK  empresa de prueba creada con id", fila[0])
        sql("""select count(*) from usuario_empresa ue
                join usuario u on u.usuario_id = ue.usuario_id
               where upper(u.username) = :u and ue.id_empresa = :e""",
            u=USUARIO_A, e=fila[0])
        n_par = cur.fetchone()[0]
        print("  par en USUARIO_EMPRESA para el creador:", n_par)
        if n_par != 1:
            falla("el alta no asocio la empresa nueva al usuario que la creo (pares=%d)" % n_par)

        # Y la empresa nueva tiene que salir en el listado.
        if not esperar('document.readyState === "complete"', 60):
            pass
        js('apex.region("admin-mis-empresas").refresh()')
        time.sleep(3)
        filas2 = filas_listado()
        print("  filas del listado tras el alta:", filas2)
        if not filas2 or NOMBRE_PRUEBA not in filas2:
            falla("la empresa nueva no sale en el listado (%r)" % (filas2,))

    # Captura del listado con la empresa nueva.
    try:
        os.makedirs(os.path.dirname(CAPTURA), exist_ok=True)
        datos = cmd("Page.captureScreenshot", format="png", captureBeyondViewport=True)
        with open(CAPTURA, "wb") as f:
            f.write(base64.b64decode(datos["data"]))
        print("  captura guardada en", CAPTURA)
    except Exception as ex:
        print("  AVISO: no se pudo guardar la captura: %s" % str(ex)[:120])

    # -----------------------------------------------------------------------
    # 5) Usuario de UNA empresa: el listado muestra una y el formulario tambien
    #    nace EN BLANCO (alta). Desde el 2026-11-16 no se elige la empresa por la
    #    cuenta: la carga el «Editar» del listado.
    # -----------------------------------------------------------------------
    print("\n== usuario con UNA empresa ==")
    ses = entrar(USUARIO_B)
    js('window.location.href="%s/f?p=100:19:%s"' % (BASE, ses))
    if not esperar('document.readyState === "complete" && !!document.getElementById("R43000000000000396_worksheet_region")', 60):
        falla("la pagina 19 no pinto el listado para el usuario de una empresa; texto: " + texto()[:200])
    else:
        time.sleep(2)
        filas3 = filas_listado()
        print("  filas del listado:", filas3)
        if not filas3 or len(filas3) != 1:
            falla("el listado mostro %r filas para un usuario de 1 empresa (se esperaba 1)" % (filas3,))
        nom_uno = js('apex.item("P19_NOMBRE_EMPRESA").getValue()')
        print("  nombre en el formulario al abrir: %r" % nom_uno)
        if nom_uno:
            falla("con una sola empresa el formulario tambien debe nacer en blanco")
finally:
    proc.terminate()
    borrar_todo()
    # Comprobacion: no queda ninguna fila de prueba (rango reservado).
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
