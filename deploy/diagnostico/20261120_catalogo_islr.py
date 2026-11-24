"""Catalogo de conceptos de ISLR: pagina 34 (2026-11-20).

Pantalla de mantenimiento del catalogo del SENIAT (`ISLR_CONCEPTOS`), que hasta
hoy solo se podia tocar por SQL. Lista + formulario en la misma pagina, guarda de
rol ADMIN,GERENCIA,CONTABILIDAD.

Comprueba, con navegador real:
  C1  la pagina abre con el informe, el formulario, la nota y los tres botones
  C2  crear un concepto lo guarda en la base y deja el formulario en esa fila
  C3  editar la tarifa del mismo concepto la actualiza
  C3b el enlace «Editar» de la lista carga ese concepto en el formulario
  C4  un codigo repetido se rechaza con «Ya existe un concepto con el codigo …»
      y no toca la fila existente
  C5  desactivar el concepto lo deja ACTIVO='N' y la lista pinta la insignia
  C6  la fila de prueba se borra y el catalogo vuelve a su numero de conceptos

Deja la captura deploy/resultados/20261120_catalogo_islr.png.
Crea y borra su propio usuario y su propio concepto.

Uso:  python deploy/diagnostico/20261120_catalogo_islr.py
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

USUARIO, CLAVE = "diag.islr", "Diag#2026"
CODIGO = "T99"
fallas = 0


def comprueba(ok, texto, detalle=""):
    global fallas
    print("  [%s] %s%s" % ("OK   " if ok else "FALLA", texto,
                           "" if not detalle else "  (%s)" % (detalle,)))
    if not ok:
        fallas += 1


c = credenciales()
con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")
cur.execute("delete from islr_conceptos where codigo = :c", c=CODIGO)
cur.execute("begin delete from usuario_empresa where usuario_id in "
            "(select usuario_id from usuario where upper(username)=upper(:u)); commit; "
            "delete from usuario where upper(username)=upper(:u); commit; end;", u=USUARIO)
cur.execute("""insert into usuario (username,email,password_hash,estado,id_empresa,rol_id,
                                     debe_cambiar_clave,reintentos_fallidos)
               values (:u,:e,sypex_hash_password(:p),'ACTIVO',1,
                       (select id_rol from syn_roles where codigo_rol='ADMIN'),'N',0)""",
            u=USUARIO, e=USUARIO + "@synpex.local", p=CLAVE)
con.commit()
cur.execute("select count(*) from islr_conceptos")
CONCEPTOS = cur.fetchone()[0]
print("  conceptos en el catalogo al empezar: %d" % CONCEPTOS)


def fila():
    cur.execute("""select id_concepto, descripcion, actividad, base_pct, tarifa,
                          sustraendo_ut, activo
                     from islr_conceptos where codigo = :c""", c=CODIGO)
    return cur.fetchone()


proc = subprocess.Popen([EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
                         "--remote-debugging-port=9295", "--window-size=1440,1000",
                         "--user-data-dir=%s" % os.path.join(tempfile.gettempdir(),
                                                             "opencode", "edge-islr"),
                         "about:blank"],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def obj():
    for _ in range(40):
        try:
            lista = json.loads(urllib.request.urlopen(
                "http://127.0.0.1:9295/json/list", timeout=2).read())
            paginas = [t for t in lista if t.get("type") == "page"]
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
    """Espera a que la condicion devuelva true. Mientras la pagina carga, js()
    devuelve la cadena 'EXC: ...' (apex todavia no existe) y eso es truthy: por
    eso se exige el booleano."""
    f = time.time() + s
    while time.time() < f:
        if js(cond) is True:
            return True
        time.sleep(0.5)
    return False


def listo():
    """La pagina 34 esta cargada y con apex disponible."""
    return esperar('document.readyState === "complete" '
                   '&& typeof apex !== "undefined" '
                   '&& !!document.getElementById("P34_CODIGO")', 60)


def captura(nombre):
    """Captura la pagina entera: la lista y, debajo, el formulario y la nota."""
    alto = js("Math.max(1000, document.documentElement.scrollHeight)") or 1000
    r = cmd("Page.captureScreenshot", format="png", captureBeyondViewport=True,
            clip={"x": 0, "y": 0, "width": 1440, "height": alto, "scale": 1})
    ruta = os.path.join(SALIDA, nombre)
    with open(ruta, "wb") as f:
        f.write(base64.b64decode(r["data"]))
    print("  captura: %s (%d bytes)" % (nombre, os.path.getsize(ruta)))


def pon(item, valor):
    return js('apex.item("%s").setValue(%s);' % (item, json.dumps(valor)))


def guarda():
    return js('(function(){var b=document.getElementById("B43000000000001494");'
              'if(!b){return "SIN BOTON";}b.click();return "OK";})()')


def nuevo():
    return js('(function(){var b=document.getElementById("B43000000000001495");'
              'if(!b){return "SIN BOTON";}b.click();return "OK";})()')


def editar(idn):
    """Pulsa el enlace «Editar» de la fila cuyo enlace lleva ese concepto."""
    antes = js('window.location.href')
    expr = """(function(){
      var id = %s;
      var enlaces = [...document.querySelectorAll('a')].filter(function(x){
        return (x.getAttribute('href') || '').toLowerCase().indexOf('p34_id_concepto=') >= 0;
      });
      // Coincidencia exacta: 'p34_id_concepto=2' tambien esta dentro de '=282'.
      var re = new RegExp('[?&]p34_id_concepto=' + id + '(?:&|$)');
      var a = enlaces.find(function(x){
        return re.test((x.getAttribute('href') || '').toLowerCase());
      });
      if (!a) { return 'SIN ENLACE (' + enlaces.length + ' enlaces)'; }
      a.click();
      return 'OK';
    })()""" % json.dumps(str(idn))
    r = js(expr)
    if r != 'OK':
        time.sleep(1)
        return r
    # Se comprueba que la navegacion arranco: en una pagina recien enviada el
    # primer clic puede caer antes de que el navegador vuelva a estar activo.
    for _ in range(20):
        time.sleep(1)
        ahora = js('window.location.href')
        if ahora and ahora != antes:
            return 'OK'
    print("        (la URL no cambio: %s)" % antes)
    return 'SIN NAVEGAR'


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
    ses = re.search(r"session=(\d+)", js("window.location.href") or "").group(1)
    print("  sesion %s" % ses)

    # ---------------------------------------------------------------- C1
    js('window.location.href="%s/f?p=100:34:%s"' % (BASE, ses))
    if not esperar('document.readyState === "complete" && !!document.getElementById("P34_CODIGO")'):
        print("  MAL la pagina 34 no pinto el formulario")
        raise SystemExit(1)
    time.sleep(2.5)
    c1 = js("""(function(){
      var lista=document.getElementById('R43000000000001471');
      var nota=document.getElementById('R43000000000001484');
      var filas=lista ? lista.querySelectorAll('.a-IRR-table tbody tr').length : 0;
      return JSON.stringify({
        lista: !!lista,
        filas: filas,
        nota: nota ? nota.innerText.replace(/\\s+/g,' ').trim() : '',
        botones: ['B43000000000001494','B43000000000001495','B43000000000001496']
                   .map(function(b){ return !!document.getElementById(b); }),
        titulo: (document.querySelector('.t-Body-title') || {}).innerText || ''
      });
    })()""")
    print("  C1: %s" % c1)
    try:
        d = json.loads(c1)
    except Exception:
        d = {}
    comprueba(d.get("lista") is True, "C1 el informe de conceptos se pinta")
    comprueba((d.get("filas") or 0) >= 10,
              "C1 el informe trae el catalogo", "%s filas" % d.get("filas"))
    comprueba(u"tarifa plana" in (d.get("nota") or "")
              and u"Tarifa N\u00b0 2" in (d.get("nota") or ""),
              "C1 la nota del SENIAT esta en pantalla", d.get("nota"))
    comprueba(d.get("botones") == [True, True, True],
              "C1 estan Guardar, Nuevo concepto y Volver", d.get("botones"))
    captura("20261120_catalogo_islr.png")

    # ---------------------------------------------------------------- C1b
    # Chips de filtro rapido (2026-11-22): Todos / Activos / Inactivos.
    chips = js("(function(){return JSON.stringify([...document.querySelectorAll('.spx-filtro')]"
               ".map(function(a){return a.getAttribute('data-filtro');}));})()")
    print("  chips:", chips)
    try:
        cch = json.loads(chips)
    except Exception:
        cch = []
    comprueba(cch == ["TODOS", "ACTIVOS", "INACTIVOS"], "C1b estan los tres chips", chips)

    js("(function(){var a=[...document.querySelectorAll('.spx-filtro')]"
       ".find(function(x){return x.getAttribute('data-filtro')==='INACTIVOS';});a.click();})()")
    ok = esperar("""(function(){var b=[...document.querySelectorAll('#R43000000000001471 .status-badge')]
        .map(function(x){return x.innerText.trim();});
        return b.length > 0 && b.every(function(x){return x === 'INACTIVO';});})()""", 60)
    comprueba(ok, "C1b el chip Inactivos deja solo los inactivos",
              js('apex.item("P34_FILTRO").getValue()'))

    js("(function(){var a=[...document.querySelectorAll('.spx-filtro')]"
       ".find(function(x){return x.getAttribute('data-filtro')==='TODOS';});a.click();})()")
    ok = esperar("""(function(){var b=[...document.querySelectorAll('#R43000000000001471 .status-badge')]
        .map(function(x){return x.innerText.trim();});
        return b.length >= 10 && b.indexOf('ACTIVO') >= 0;})()""", 60)
    comprueba(ok, "C1b y el chip Todos repone la lista",
              js('apex.item("P34_FILTRO").getValue()'))

    # ---------------------------------------------------------------- C2
    pon("P34_CODIGO", CODIGO)
    pon("P34_DESCRIPCION", "CONCEPTO DE PRUEBA")
    pon("P34_ACTIVIDAD", "ACTIVIDAD DE PRUEBA")
    pon("P34_BASE_PCT", 100)
    pon("P34_TARIFA", 5)
    pon("P34_SUSTRAENDO_UT", 1.5)
    pon("P34_ACTIVO", "S")
    time.sleep(0.6)
    print("  C2 pulsa Guardar:", guarda())
    # El aviso tiene que salir UNA sola vez (el proceso lo publicaba a mano y ademas
    # por atributo) y cerrarse solo a los 5 s (2026-11-22).
    ok = esperar('document.body.innerText.indexOf("Concepto guardado") >= 0', 45)
    cuerpo = js("document.body.innerText") or ""
    comprueba(ok and cuerpo.count(u"Concepto guardado") == 1,
              "C2 sale «Concepto guardado» una sola vez",
              [x for x in cuerpo.splitlines() if "Concepto guardado" in x][:3])
    f = fila()
    print("  fila creada: %s" % (f,))
    comprueba(f is not None and f[6] == "S" and float(f[4]) == 5.0,
              "C2 la fila quedo en la base con tarifa 5 y activa")
    idn = f[0] if f else None
    comprueba(str(js('apex.item("P34_ID_CONCEPTO").getValue()') or "") == str(idn),
              "C2 el formulario se queda en la fila creada",
              js('apex.item("P34_ID_CONCEPTO").getValue()'))

    # C2b: el aviso se cierra solo a los 5 s (antes habia que recargar para quitarlo).
    time.sleep(8)
    comprueba(u"Concepto guardado" not in (js("document.body.innerText") or ""),
              "C2b el aviso se cierra solo, sin recargar")

    # ---------------------------------------------------------------- C3
    pon("P34_TARIFA", 7)
    time.sleep(0.6)
    print("  C3 pulsa Guardar:", guarda())
    time.sleep(7)
    f = fila()
    comprueba(f is not None and float(f[4]) == 7.0,
              "C3 editar la tarifa la guarda (5 -> 7)", f and f[4])

    # ---------------------------------------------------------------- C3b
    cur.execute("select id_concepto, codigo from islr_conceptos where codigo = '002'")
    dos = cur.fetchone()
    print("  C3b pulsa Editar del concepto %s:" % (dos,), editar(dos[0]))
    # Esta ADB tarda 12-15 s por peticion: se espera al valor, no un tiempo fijo.
    listo()
    llego = esperar('String(apex.item("P34_CODIGO").getValue()) === "002"', 60)
    cargado = js('apex.item("P34_CODIGO").getValue()')
    comprueba(llego, "C3b el enlace «Editar» carga ese concepto", cargado)
    comprueba(str(js('apex.item("P34_ID_CONCEPTO").getValue()')) == str(dos[0]),
              "C3b el formulario trae su id",
              js('apex.item("P34_ID_CONCEPTO").getValue()'))

    # ---------------------------------------------------------------- C4
    print("  C4 pulsa Nuevo concepto:", nuevo())
    listo()
    vacio = esperar('(function(){try{var v=apex.item("P34_ID_CONCEPTO").getValue();'
                    'return v === null || v === "" || v === undefined;}'
                    'catch(e){return false;}})()', 60)
    comprueba(vacio and js('apex.item("P34_CODIGO").getValue()') in (None, ""),
              "C4 «Nuevo concepto» deja el formulario en blanco",
              (vacio, js('apex.item("P34_CODIGO").getValue()')))
    pon("P34_CODIGO", CODIGO)
    pon("P34_DESCRIPCION", "OTRO CONCEPTO CON EL MISMO CODIGO")
    pon("P34_ACTIVIDAD", "ACTIVIDAD")
    pon("P34_BASE_PCT", 100)
    pon("P34_TARIFA", 3)
    pon("P34_SUSTRAENDO_UT", 0)
    time.sleep(0.6)
    print("  C4 pulsa Guardar con codigo repetido:", guarda())
    time.sleep(7)
    cuerpo = js("document.body.innerText") or ""
    comprueba(u"Ya existe un concepto con el codigo %s" % CODIGO in cuerpo,
              "C4 el codigo repetido se rechaza con -20047",
              [x for x in cuerpo.splitlines() if "Ya existe" in x][:2])
    f = fila()
    comprueba(f is not None and float(f[4]) == 7.0 and f[1] == "CONCEPTO DE PRUEBA",
              "C4 la fila existente no se toco", f and (f[1], f[4]))

    # ---------------------------------------------------------------- C5
    print("  C5 pulsa Editar del concepto de prueba:", editar(idn))
    listo()
    llego = esperar('String(apex.item("P34_ID_CONCEPTO").getValue()) === %s'
                    % json.dumps(str(idn)), 60)
    comprueba(llego and str(js('apex.item("P34_CODIGO").getValue()')) == CODIGO,
              "C5 abre el concepto de prueba",
              (js('apex.item("P34_ID_CONCEPTO").getValue()'),
               js('apex.item("P34_CODIGO").getValue()')))
    pon("P34_ACTIVO", "N")
    time.sleep(0.6)
    print("  C5 pulsa Guardar para desactivar:", guarda())
    time.sleep(7)
    f = fila()
    comprueba(f is not None and f[6] == "N", "C5 el concepto queda inactivo", f and f[6])
    insignias = js("""(function(){
      var r=document.getElementById('R43000000000001471');
      if(!r){return 'SIN';}
      return [...r.querySelectorAll('.status-badge')].map(function(x){return x.innerText.trim();})
             .join(',');
    })()""")
    print("  insignias de la lista: %s" % insignias)
    comprueba("INACTIVO" in (insignias or ""),
              "C5 la lista pinta la insignia INACTIVO", insignias)
finally:
    proc.terminate()
    cur.execute("delete from islr_conceptos where codigo = :c", c=CODIGO)
    cur.execute("begin delete from usuario_empresa where usuario_id in "
                "(select usuario_id from usuario where upper(username)=upper(:u)); commit; "
                "delete from usuario where upper(username)=upper(:u); commit; end;", u=USUARIO)
    con.commit()
    cur.execute("select count(*) from islr_conceptos")
    quedan = cur.fetchone()[0]
    comprueba(quedan == CONCEPTOS, "C6 el catalogo queda como estaba", quedan)
    con.close()

print("\nRESULTADO: FALLAS=%d" % fallas)
sys.exit(1 if fallas else 0)
