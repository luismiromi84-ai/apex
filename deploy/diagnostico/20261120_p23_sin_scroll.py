"""Pagina 23 «Proveedor» sin scroll (2026-11-20).

El dueno pidio que el formulario completo entre en una ventana de 1440x900 sin
barra de desplazamiento. Para eso se fusiono «Condiciones comerciales» dentro de
«Configuracion fiscal y comercial» (cuatro cabeceras pasan a tres) y se aprieto
el alto de las tarjetas.

Comprueba:
  P1  el dialogo tiene TRES cabeceras de seccion (Datos fiscales, Contacto,
      Configuracion fiscal y comercial) y ya no existe «Condiciones comerciales»
  P2  los seis campos de la seccion fusionada siguen ahi, en parejas, dentro de
      la misma region: Retiene IVA | %, Concepto de ISLR | SPE, Dias | Estado
  P3  el contenido del dialogo NO desborda: el scroll del iframe es 0 y el
      formulario completo cabe en la ventana de 1440x900
  P4  todos los items del formulario siguen presentes (no se perdio ninguno)

Deja la captura deploy/resultados/20261120_p23_sin_scroll.png a 1440x900.
Crea y borra su propio usuario.

Uso:  python deploy/diagnostico/20261120_p23_sin_scroll.py
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

USUARIO, CLAVE = "diag.p23scroll", "Diag#2026"
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

proc = subprocess.Popen([EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
                         "--remote-debugging-port=9297", "--window-size=1440,900",
                         "--user-data-dir=%s" % os.path.join(tempfile.gettempdir(),
                                                             "opencode", "edge-p23scroll"),
                         "about:blank"],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def obj():
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


def en_if(expr):
    return js('(function(){var f=document.querySelector("iframe");if(!f){return "SIN";}'
              'var w=f.contentWindow;var d=w.document;var apex=w.apex;' + expr + '})()')


try:
    cmd("Emulation.setDeviceMetricsOverride", width=1440, height=900,
        deviceScaleFactor=1, mobile=False)
    js('window.location.href="%s/f?p=100:9999"' % BASE)
    esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(1)
    js('(function(){apex.item("P9999_USERNAME").setValue(%s);apex.item("P9999_PASSWORD").setValue(%s);'
       'var b=[...document.querySelectorAll("button")].find(x=>/sign in|iniciar|entrar/i.test(x.innerText));if(b){b.click();}})()'
       % (json.dumps(USUARIO), json.dumps(CLAVE)))
    time.sleep(8)
    ses = re.search(r"session=(\d+)", js("window.location.href") or "").group(1)
    print("  sesion %s" % ses)

    js('window.location.href="%s/f?p=100:22:%s"' % (BASE, ses))
    esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(4)
    js('(function(){var b=[...document.querySelectorAll("button,a")].find(function(x){'
       'return (x.getAttribute("data-otel-label")||"")==="BTN_NUEVO_PROVEEDOR";});if(b){b.click();}})()')
    if not esperar('!!document.querySelector("iframe")'):
        print("  MAL el dialogo de proveedor no abrio")
        raise SystemExit(1)
    time.sleep(3)
    # El % de retencion solo se pinta con «Retiene IVA = Si»; con «No» la fila
    # queda mas corta y la medida no seria la del caso real.
    en_if('apex.item("P23_RETENER_IVA").setValue("S");return "OK";')
    time.sleep(2)

    m = en_if("""
      var regs=[...d.querySelectorAll('.t-Region')];
      var cabeceras=regs.map(function(r){
        var c=r.querySelector('.t-Region-header');
        if (!c || c.getBoundingClientRect().height === 0) { return ''; }
        return c.innerText.replace(/\\s+/g,' ').trim();
      }).filter(function(x){ return x; });
      var filas={};
      regs.forEach(function(r){
        [...r.querySelectorAll('.col')].forEach(function(c){
          var it=c.querySelector('[id$="_CONTAINER"]');
          if(!it) return;
          if(c.getBoundingClientRect().height === 0) return;
          var k=Math.round(c.getBoundingClientRect().top);
          (filas[k]=filas[k]||[]).push(it.getAttribute('data-otel-label'));
        });
      });
      var pares=Object.keys(filas).sort(function(a,b){return a-b;}).map(function(k){
        return filas[k].join('+');
      });
      var fondo=0;
      regs.forEach(function(r){ fondo = Math.max(fondo, Math.round(r.getBoundingClientRect().bottom)); });
      var scroller=null, peor=0;
      [...d.querySelectorAll('*')].forEach(function(e){
        if(e.scrollHeight > e.clientHeight + 4 &&
           ['auto','scroll'].indexOf(w.getComputedStyle(e).overflowY) >= 0){
          var d2 = e.scrollHeight - e.clientHeight;
          if (d2 > peor) { peor = d2; scroller = e; }
        }
      });
      var doc = d.documentElement, body = d.body;
      var ifr=document.querySelector('iframe');
      return JSON.stringify({
        cabeceras: cabeceras,
        filas: pares,
        items: regs.reduce(function(a,r){
          return a.concat([...r.querySelectorAll('[id$="_CONTAINER"]')]
            .map(function(x){return x.getAttribute('data-otel-label');}));}, []),
        fondo: fondo,
        scroll_peor: peor,
        scroll_doc: Math.max(doc.scrollHeight, body.scrollHeight)
                    - Math.min(doc.clientHeight, body.clientHeight),
        iframe: Math.round(ifr.getBoundingClientRect().height),
        ancho_iframe: Math.round(ifr.getBoundingClientRect().width)
      });
    """)
    print("  medidas 23: %s" % m)
    try:
        mm = json.loads(m)
    except Exception:
        mm = {}
    cabeceras = mm.get("cabeceras") or []
    filas = mm.get("filas") or []
    items = mm.get("items") or []

    # «Acciones» no es una seccion del formulario (es la barra de botones, sin
    # cabecera a la vista): se miran solo las cuatro secciones que existian.
    secciones = [x for x in cabeceras
                 if x in ("Datos fiscales", "Contacto",
                          u"Configuraci\u00f3n fiscal y comercial",
                          "Condiciones comerciales")]
    comprueba(len(secciones) == 3, "P1 quedan tres cabeceras de seccion", cabeceras)
    comprueba(not any("Condiciones comerciales" in x for x in cabeceras),
              "P1 «Condiciones comerciales» ya no es una seccion aparte", cabeceras)
    comprueba(any("Configuraci" in x and "comercial" in x for x in cabeceras),
              "P1 la seccion fusionada se llama «Configuracion fiscal y comercial»", cabeceras)

    comprueba("P23_RETENER_IVA+P23_PORCENTAJE_RETENCION" in filas,
              "P2 Retiene IVA y % en la misma fila", filas)
    comprueba("P23_ID_CONCEPTO_ISLR+P23_ES_SPE" in filas,
              "P2 Concepto de ISLR y SPE en la misma fila", filas)
    comprueba("P23_DIAS_CREDITO+P23_ESTADO" in filas,
              "P2 Dias de credito y Estado en la misma fila", filas)

    esperados = ["P23_RAZON_SOCIAL", "P23_TIPO_RIF", "P23_RIF", "P23_COD_PAIS",
                 "P23_EMAIL", "P23_TELEFONO", "P23_DIRECCION", "P23_RETENER_IVA",
                 "P23_PORCENTAJE_RETENCION", "P23_ID_CONCEPTO_ISLR", "P23_ES_SPE",
                 "P23_DIAS_CREDITO", "P23_ESTADO"]
    faltan = [i for i in esperados if i not in items]
    comprueba(not faltan, "P4 siguen los trece campos del formulario", faltan)

    comprueba((mm.get("scroll_peor") or 0) <= 2,
              "P3 el contenido del dialogo no tiene scroll", mm.get("scroll_peor"))
    comprueba((mm.get("scroll_doc") or 0) <= 2,
              "P3 el documento del iframe no desborda", mm.get("scroll_doc"))
    comprueba((mm.get("fondo") or 0) <= (mm.get("iframe") or 0) + 2,
              "P3 el formulario completo cabe en el alto del dialogo",
              "contenido %s / iframe %s" % (mm.get("fondo"), mm.get("iframe")))

    captura("20261120_p23_sin_scroll.png")
finally:
    proc.terminate()
    cur.execute("begin delete from usuario_empresa where usuario_id in "
                "(select usuario_id from usuario where upper(username)=upper(:u)); commit; "
                "delete from usuario where upper(username)=upper(:u); commit; end;", u=USUARIO)
    con.commit()
    con.close()

print("\nRESULTADO: FALLAS=%d" % fallas)
sys.exit(1 if fallas else 0)
