"""Pagina 19 «Administracion > Empresa»: «Nueva empresa» tiene que DEJAR EL FORMULARIO
EN BLANCO (id vacio) y «Guardar empresa» tiene que dar de ALTA cuando el id esta vacio.

El fallo que se reproduce: al pulsar «Nueva empresa» sale el mensaje «Formulario en
blanco...» pero los campos siguen con la empresa del usuario, porque el proceso
«Carga la empresa del usuario» (BEFORE_HEADER) vuelve a rellenarlos en el render
posterior al submit. Con el id relleno, «Guardar empresa» no inserta: actualiza la
empresa del usuario.

Se conduce con Edge headless por CDP (login real, clic real). Deja la empresa 1 como
estaba y borra la empresa de prueba que cree.
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

USUARIO, CLAVE = "diag.diseno", "Diag#2026"
PRUEBA = "EMPRESA PRUEBA P19"
fallas = 0

c = credenciales()
con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")

cur.execute("""select nombre_empresa, cod_pais, tipo_ident_fiscal, rfc, estado
                 from empresas where id_empresa = 1""")
original = cur.fetchone()

cur.execute("delete from usuario where upper(username)='DIAG.DISENO'")
cur.execute("""insert into usuario (username,email,password_hash,estado,id_empresa,rol_id,debe_cambiar_clave,reintentos_fallidos)
 values ('diag.diseno','diag.diseno@synpex.local',sypex_hash_password('Diag#2026'),'ACTIVO',1,
 (select id_rol from syn_roles where codigo_rol='ADMIN'),'N',0)""")
con.commit()

proc = subprocess.Popen([EDGE, "--headless=new", "--disable-gpu", "--no-first-run", "--remote-debugging-port=9292",
                         f"--user-data-dir={os.path.join(tempfile.gettempdir(),'opencode','edge-p19n')}", "about:blank"],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def obj():
    for _ in range(40):
        try:
            l = json.loads(urllib.request.urlopen("http://127.0.0.1:9292/json/list", timeout=2).read())
            p = [t for t in l if t.get("type") == "page"]
            if p:
                return p[0]
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


def esperar(c_, s=40):
    f = time.time() + s
    while time.time() < f:
        if js(c_):
            return True
        time.sleep(0.5)
    return False


def clic(texto):
    return js("(function(){var b=[...document.querySelectorAll('button')]"
              ".find(function(x){return /%s/i.test(x.innerText);});"
              "if(b){b.click();return 'clic';}return 'NO';})()" % texto)


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
    if not esperar('document.readyState === "complete" && !!document.getElementById("P19_NOMBRE_EMPRESA")'):
        print("  MAL la pagina 19 no pinto el formulario")
        raise SystemExit(1)
    time.sleep(2)
    print("  carga inicial: id=%r nombre=%r" % (js('apex.item("P19_ID_EMPRESA").getValue()'),
                                                js('apex.item("P19_NOMBRE_EMPRESA").getValue()')))

    print("  pulsando «Nueva empresa»...")
    if clic("Nueva empresa") != "clic":
        fallas += 1
        print("  MAL no encontre el boton «Nueva empresa»")
    elif not esperar('document.body.innerText.indexOf("Formulario en blanco") >= 0', 45):
        fallas += 1
        print("  MAL no salio el mensaje «Formulario en blanco»")
    time.sleep(2)
    id_txt = js('apex.item("P19_ID_EMPRESA").getValue()')
    nom = js('apex.item("P19_NOMBRE_EMPRESA").getValue()')
    print("  tras «Nueva empresa»: id=%r nombre=%r" % (id_txt, nom))
    if id_txt:
        fallas += 1
        print("  MAL el id no se limpio: con id, Guardar ACTUALIZA en vez de dar de alta")
    if nom:
        fallas += 1
        print("  MAL el formulario no quedo en blanco")

    # Alta real: con el formulario en blanco, escribir el nombre y guardar.
    print("  alta: escribiendo %r y pulsando «Guardar empresa»..." % PRUEBA)
    js('apex.item("P19_NOMBRE_EMPRESA").setValue(%s)' % json.dumps(PRUEBA))
    if clic("Guardar empresa") != "clic":
        fallas += 1
        print("  MAL no encontre el boton «Guardar empresa»")
    elif not esperar('document.body.innerText.indexOf("Empresa creada") >= 0', 45):
        fallas += 1
        print("  MAL no dijo «Empresa creada»; texto:",
              (js("document.body.innerText") or "")[:300].replace("\n", " / "))
    cur.execute("select id_empresa from empresas where nombre_empresa = :n", n=PRUEBA)
    fila = cur.fetchone()
    cur.execute("select nombre_empresa from empresas where id_empresa = 1")
    actual = cur.fetchone()[0]
    if fila and fila[0] != 1:
        print("  OK  creo la empresa de prueba con id", fila[0])
        # El render posterior al alta tiene que dejar el formulario en la empresa nueva
        # (si lo recargara, el id volveria a 1 y el siguiente Guardar la pisaria).
        time.sleep(1)
        id_post = js('apex.item("P19_ID_EMPRESA").getValue()')
        nom_post = js('apex.item("P19_NOMBRE_EMPRESA").getValue()')
        print("  tras el alta: id=%r nombre=%r" % (id_post, nom_post))
        if str(id_post) != str(fila[0]) or nom_post != PRUEBA:
            fallas += 1
            print("  MAL el formulario no se quedo en la empresa recien creada")
        # Y guardar con el nombre vacio tiene que avisar, no escribir nada.
        js('apex.item("P19_NOMBRE_EMPRESA").setValue("")')
        clic("Guardar empresa")
        if esperar('document.body.innerText.indexOf("nombre de la empresa es obligatorio") >= 0', 45):
            print("  OK  guardar en blanco avisa «El nombre de la empresa es obligatorio»")
        else:
            fallas += 1
            print("  MAL guardar en blanco no aviso; texto:",
                  (js("document.body.innerText") or "")[:300].replace("\n", " / "))
    else:
        fallas += 1
        print("  MAL no creo una empresa nueva (la fila encontrada es la del usuario)")
    if actual != original[0]:
        fallas += 1
        print("  MAL renombro la empresa del usuario 1 a %r" % actual)
    else:
        print("  OK  la empresa del usuario (1) sigue siendo %r" % actual)
finally:
    proc.terminate()
    # Restaurar primero: si el fallo renombro la empresa 1, hay que deshacerlo antes
    # de intentar borrar (la 1 tiene hijos en FOLIO_CONTADOR y no se puede borrar).
    cur.execute("""update empresas set nombre_empresa=:n, cod_pais=:p, tipo_ident_fiscal=:t,
                          rfc=:r, estado=:e where id_empresa = 1""",
                n=original[0], p=original[1], t=original[2], r=original[3], e=original[4])
    cur.execute("delete from empresas where nombre_empresa = :n", n=PRUEBA)
    cur.execute("delete from usuario where upper(username)='DIAG.DISENO'")
    con.commit()
    con.close()

print("RESULTADO: FALLAS=%d" % fallas)
sys.exit(1 if fallas else 0)
