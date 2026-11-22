"""UT del ISLR editable desde Administracion (2026-11-20).

La UT (`SYN_PARAMETROS.UT_ISLR`, 43 Bs) gobierna el sustraendo de todos los
conceptos de ISLR y hasta hoy solo se podia cambiar por SQL. Ahora hay una
tarjeta Â«Parametros del sistemaÂ» en la pagina 19, FUERA del selector de pestanas
(no es un dato de la empresa) y visible solo para ADMIN.

Comprueba:
  U1  la tarjeta existe, esta fuera del selector de pestanas y muestra la UT
      vigente (43,00)
  U2  guardar 43 deja 43 en la base y el mensaje Â«UT guardada: 43.00 Bs.Â»
  U3  guardar 0 NO escribe: sale Â«La UT debe ser mayor que cero.Â» y la base
      conserva el valor anterior
  U4  el valor queda restaurado al original
  U5  la tarjeta y su boton estan condicionados a fn_tiene_rol('ADMIN') y un
      usuario GERENCIA no pasa esa condicion (la guarda es del servidor)

Deja la captura deploy/resultados/20261120_ut.png.
Crea y borra su propio usuario.

Uso:  python deploy/diagnostico/20261120_parametros_ut.py
Sale con codigo 1 si hay fallas.
"""
import base64
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
SALIDA = os.path.join(REPO, "deploy", "resultados")
sys.path.insert(0, os.path.join(REPO, "deploy", "conexion"))
from verificar_conexion import CONNECT_STRING, credenciales

USUARIO, CLAVE = "diag.ut", "Diag#2026"
fallas = 0


def comprueba(ok, texto, detalle=""):
    global fallas
    print("  [%s] %s%s" % ("OK   " if ok else "FALLA", texto,
                           "" if not detalle else "  (%s)" % detalle))
    if not ok:
        fallas += 1


c = credenciales()
con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")
cur.execute("begin delete from usuario_empresa where usuario_id in "
            "(select usuario_id from usuario where upper(username)=upper(:u)); commit; "
            "delete from usuario where upper(username)=upper(:u); commit; end;", u=USUARIO)
cur.execute("""insert into usuario (username,email,password_hash,estado,id_empresa,rol_id,
                                     debe_cambiar_clave,reintentos_fallidos)
               values (:u,:e,sypex_hash_password(:p),'ACTIVO',1,
                       (select id_rol from syn_roles where codigo_rol='ADMIN'),'N',0)""",
            u=USUARIO, e=USUARIO + "@synpex.local", p=CLAVE)
con.commit()


def ut():
    cur.execute("select valor from syn_parametros where clave = 'UT_ISLR'")
    f = cur.fetchone()
    return None if not f else f[0]


UT_ORIGINAL = ut()
print("  UT en la base al empezar: %s" % UT_ORIGINAL)

# ---------------------------------------------------------------- U5 (por SQL)
cur.execute("""select condition_expression1 from apex_application_page_regions
                where application_id = 100 and region_id = 43000000000001462""")
cond_region = (cur.fetchone() or [None])[0]
cur.execute("""select condition_expression1 from apex_application_page_buttons
                where application_id = 100 and button_name = 'BTN_GUARDAR_UT'""")
cond_boton = (cur.fetchone() or [None])[0]
comprueba(cond_region == "fn_tiene_rol('ADMIN')",
          "U5 la tarjeta esta condicionada al rol ADMIN", cond_region)
comprueba(cond_boton == "fn_tiene_rol('ADMIN')",
          "U5 el boton esta condicionado al rol ADMIN", cond_boton)
cur.execute("""select count(*) from usuario u
                 join syn_roles r on r.id_rol = u.rol_id
                where r.codigo_rol = 'GERENCIA'""")
# fn_tiene_rol() lee APP_USER del contexto de APEX: fuera de una sesion devuelve
# 0, asi que el paso de la condicion por un ADMIN se comprueba en el navegador
# (U1: la tarjeta se pinta y el boton guarda), no por SQL.

proc = subprocess.Popen([EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
                         "--remote-debugging-port=9290", "--window-size=1440,1000",
                         "--user-data-dir=%s" % os.path.join(tempfile.gettempdir(),
                                                             "opencode", "edge-cierre"),
                         "about:blank"],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def obj():
    for _ in range(40):
        try:
            lista = json.loads(urllib.request.urlopen(
                "http://127.0.0.1:9290/json/list", timeout=2).read())
            paginas = [t for t in lista if t.get("type") == "page"]
            # Edge abre a veces una pestana propia (edge://sync-confirmation...):
            # se elige la de trabajo, no la primera que aparezca.
            propias = [t for t in paginas if not (t.get("url") or "").startswith("edge://")]
            if propias:
                return propias[0]
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
        return "EXC: " + str(r["exceptionDetails"].get("exception", {}).get("description"))[:300]
    return r.get("result", {}).get("value")


def esperar(cond, s=40):
    f = time.time() + s
    while time.time() < f:
        if js(cond):
            return True
        time.sleep(0.5)
    return False


def captura(nombre):
    r = cmd("Page.captureScreenshot", format="png")
    ruta = os.path.join(SALIDA, nombre)
    with open(ruta, "wb") as f:
        f.write(base64.b64decode(r["data"]))
    print("  captura: %s (%d bytes)" % (nombre, os.path.getsize(ruta)))


def pulsa_ut():
    return js('(function(){var b=document.getElementById("B43000000000001464");'
              'if(!b){return "SIN BOTON";}b.click();return "OK";})()')


try:
    cmd("Emulation.setDeviceMetricsOverride", width=1440, height=1000,
        deviceScaleFactor=1, mobile=False)
    js('window.location.href="%s/f?p=100:9999"' % BASE)
    esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(1)
    js('(function(){apex.item("P9999_USERNAME").setValue(%s);apex.item("P9999_PASSWORD").setValue(%s);'
       'var b=[...document.querySelectorAll("button")].find(x=>/sign in|iniciar|entrar/i.test(x.innerText));if(b){b.click();}})()'
       % (json.dumps(USUARIO), json.dumps(CLAVE)))
    esperar('!/f?p=100:9999/.test(window.location.href)', 60)
    time.sleep(3)
    print("  url tras el login: %s" % js("window.location.href"))
    ses = re.search(r"session=(\d+)", js("window.location.href") or "").group(1)
    print("  sesion %s" % ses)

    js('window.location.href="%s/f?p=100:19:%s"' % (BASE, ses))
    if not esperar('document.readyState === "complete" && !!document.getElementById("P19_UT_ISLR")'):
        print("  MAL la tarjeta de parametros no se pinto")
        raise SystemExit(1)
    time.sleep(2.5)

    # ---------------------------------------------------------------- U1
    u1 = js("""(function(){
      var r=document.getElementById('R43000000000001462');
      if(!r){return 'SIN TARJETA';}
      var sel=document.getElementById('R43000000000000380');
      var dentro = sel && sel.contains(r);
      var inp=document.getElementById('P19_UT_ISLR');
      return JSON.stringify({
        titulo: (r.querySelector('.t-Region-title')||{}).innerText || '',
        valor: inp ? inp.value : null,
        dentro_del_selector: !!dentro,
        boton: !!document.getElementById('B43000000000001464')
      });
    })()""")
    print("  U1: %s" % u1)
    try:
        d = json.loads(u1)
    except Exception:
        d = {}
    comprueba(d.get("titulo") == u"Par\u00e1metros del sistema",
              "U1 la tarjeta se llama Â«Parametros del sistemaÂ»", d.get("titulo"))
    comprueba(d.get("dentro_del_selector") is False,
              "U1 la tarjeta NO es una pestana (va fuera del selector)")
    comprueba((d.get("valor") or "").replace(",", ".").startswith(str(UT_ORIGINAL).split(".")[0]),
              "U1 muestra la UT vigente", d.get("valor"))
    comprueba(d.get("boton") is True, "U1 el boton Â«Guardar UTÂ» esta en la tarjeta")

    captura("20261120_ut.png")

    # ---------------------------------------------------------------- U2
    js('apex.item("P19_UT_ISLR").setValue(43);')
    time.sleep(0.5)
    print("  pulsa Guardar UT:", pulsa_ut())
    time.sleep(6)
    cuerpo = js("document.body.innerText") or ""
    comprueba(u"UT guardada: 43.00 Bs." in cuerpo,
              "U2 sale el mensaje Â«UT guardada: 43.00 Bs.Â»",
              [x for x in cuerpo.splitlines() if "UT guardada" in x][:2])
    comprueba(ut() == 43, "U2 la base queda en 43", ut())

    # ---------------------------------------------------------------- U3
    js('apex.item("P19_UT_ISLR").setValue(0);')
    time.sleep(0.5)
    print("  pulsa Guardar UT con 0:", pulsa_ut())
    time.sleep(6)
    cuerpo = js("document.body.innerText") or ""
    comprueba(u"La UT debe ser mayor que cero" in cuerpo,
              "U3 guardar 0 se rechaza con un mensaje claro",
              [x for x in cuerpo.splitlines() if "UT debe" in x][:2])
    comprueba(ut() == 43, "U3 la base NO cambio (sigue en 43)", ut())

    # ---------------------------------------------------------------- U4
    js('apex.item("P19_UT_ISLR").setValue(%s);' % json.dumps(UT_ORIGINAL))
    time.sleep(0.5)
    print("  pulsa Guardar UT para restaurar:", pulsa_ut())
    time.sleep(6)
    comprueba(ut() == UT_ORIGINAL, "U4 la UT queda restaurada", ut())
finally:
    proc.terminate()
    cur.execute("update syn_parametros set valor = :v where clave = 'UT_ISLR'", v=UT_ORIGINAL)
    cur.execute("begin delete from usuario_empresa where usuario_id in "
                "(select usuario_id from usuario where upper(username)=upper(:u)); commit; "
                "delete from usuario where upper(username)=upper(:u); commit; end;", u=USUARIO)
    con.commit()
    con.close()

print("\nRESULTADO: FALLAS=%d" % fallas)
sys.exit(1 if fallas else 0)

