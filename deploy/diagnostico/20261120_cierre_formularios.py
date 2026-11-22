"""Cierre de formularios (2026-11-20): capturas y comprobaciones de las pestanas
fiscales de la pagina 19 y del dialogo de Proveedor (23).

  F1  la pestana «Datos fiscales» pinta los tres bloques (Informacion fiscal,
      Contacto, Autorizaciones SENIAT)
  F2  la direccion fiscal es un area de texto de tres lineas a ancho completo
  F3  la pestana «Datos de la imprenta» pinta la linea de resumen con el nombre,
      el RIF, el telefono y el correo de la propia empresa
  F4  la imprenta tiene sus dos bloques (Identificacion, Contacto)
  P1  el dialogo de Proveedor abre con las parejas de campos en la misma fila
      (RIF|Tipo, Pais|Razon social, Correo|Telefono, Retiene|%, Concepto|SPE,
      Dias|Estado) y la direccion a ancho completo
  P2  la cabecera de seccion bajo de 80 a ~56 px (30 %), el relleno de tarjeta a
      13 px (20 %) y hay 12 px entre secciones (25 %)
  P3  el dialogo ocupa menos del 85 % de una ventana de 900 px y lo que queda por
      debajo es un scroll corto (menos de dos filas de campos)

Deja capturas en deploy/resultados/20261120_cierre_{fiscal,imprenta,p23,p23_900}.png
(y las variantes _500 de las tres). Crea y borra su propio usuario.

Uso:  python deploy/diagnostico/20261120_cierre_formularios.py
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

USUARIO, CLAVE = "diag.cierre", "Diag#2026"
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
cur.execute("""select imprenta_nombre, imprenta_rif, imprenta_telefono, imprenta_email
                 from empresa_fiscal where id_empresa = 1""")
IMP = cur.fetchone()
print("  imprenta en la base: %r" % (IMP,))

proc = subprocess.Popen([EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
                         "--remote-debugging-port=9298", "--window-size=1440,1000",
                         "--user-data-dir=%s" % os.path.join(tempfile.gettempdir(),
                                                             "opencode", "edge-cierre"),
                         "about:blank"],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def obj():
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


def medidas(ancho, alto):
    cmd("Emulation.setDeviceMetricsOverride", width=ancho, height=alto,
        deviceScaleFactor=1, mobile=False)
    time.sleep(1.2)


def captura(nombre, ancho, alto, completo=True):
    """Captura la pagina a ese ancho. `completo` incluye lo que queda por debajo."""
    if completo:
        alto_real = js("Math.max(%d, document.documentElement.scrollHeight)" % alto) or alto
        r = cmd("Page.captureScreenshot", format="png", captureBeyondViewport=True,
                clip={"x": 0, "y": 0, "width": ancho, "height": alto_real, "scale": 1})
    else:
        r = cmd("Page.captureScreenshot", format="png")
    ruta = os.path.join(SALIDA, nombre)
    with open(ruta, "wb") as f:
        f.write(base64.b64decode(r["data"]))
    print("  captura: %s (%d bytes)" % (nombre, os.path.getsize(ruta)))


def en_if(expr):
    return js('(function(){var f=document.querySelector("iframe");if(!f){return "SIN";}'
              'var w=f.contentWindow;var d=w.document;var apex=w.apex;' + expr + '})()')


try:
    js('window.location.href="%s/f?p=100:9999"' % BASE)
    esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(1)
    js('(function(){apex.item("P9999_USERNAME").setValue(%s);apex.item("P9999_PASSWORD").setValue(%s);'
       'var b=[...document.querySelectorAll("button")].find(x=>/sign in|iniciar|entrar/i.test(x.innerText));if(b){b.click();}})()'
       % (json.dumps(USUARIO), json.dumps(CLAVE)))
    time.sleep(8)
    ses = re.search(r"session=(\d+)", js("window.location.href") or "").group(1)
    print("  sesion %s" % ses)

    # ---------------- pagina 19, pestana «Datos fiscales» ----------------
    medidas(1440, 1000)
    js('window.location.href="%s/f?p=100:19:%s"' % (BASE, ses))
    if not esperar('document.readyState === "complete" && !!document.getElementById("P19F_TELEFONO")'):
        print("  MAL la pagina 19 no pinto la pestana fiscal")
        raise SystemExit(1)
    time.sleep(2.5)

    subs = js("""(function(){
      var r=document.getElementById('R43000000000000410');
      if(!r){return 'SIN REGION';}
      return [...r.querySelectorAll('.spx-sub')].map(function(x){return x.innerText;}).join(' | ');
    })()""")
    comprueba(subs == "INFORMACI\u00d3N FISCAL | CONTACTO | AUTORIZACIONES SENIAT",
              "F1 los tres bloques de la pestana fiscal", subs)

    caja_dir = js("""(function(){
      var e=document.getElementById('P19F_DIRECCION_FISCAL');
      if(!e){return 'SIN';}
      var r=e.getBoundingClientRect(), c=e.closest('.col').getBoundingClientRect();
      return JSON.stringify({etiqueta:e.tagName, alto:Math.round(r.height),
                             ancho:Math.round(r.width), ancho_col:Math.round(c.width)});
    })()""")
    try:
        d = json.loads(caja_dir)
    except Exception:
        d = {}
    comprueba(d.get("etiqueta") == "TEXTAREA" and (d.get("alto") or 0) >= 55
              and (d.get("ancho") or 0) >= (d.get("ancho_col") or 0) - 4,
              "F2 la direccion fiscal es un area de texto alta y a ancho completo", caja_dir)

    captura("20261120_cierre_fiscal.png", 1440, 1000)
    medidas(500, 1000)
    time.sleep(1.2)
    captura("20261120_cierre_fiscal_500.png", 500, 1000)

    # ---------------- pestana «Datos de la imprenta» ----------------
    medidas(1440, 1000)
    time.sleep(1)
    js("""(function(){var a=[...document.querySelectorAll('.a-RDS-link')]
             .find(function(x){return /Datos de la imprenta/i.test(x.innerText);});
             if(a){a.click();}})()""")
    time.sleep(2.5)
    prev = js("(function(){var p=document.querySelector('#R43000000000000411 .spx-preview');"
              "return p ? p.innerText : 'SIN';})()") or ""
    print("  resumen imprenta: %r" % prev)
    datos_imp = [x for x in IMP if x]
    comprueba(prev.startswith("Imprenta configurada:") and datos_imp
              and all(x in prev for x in datos_imp),
              "F3 la linea de resumen trae nombre, RIF, telefono y correo",
              "la base tiene %r" % (IMP,))
    subs2 = js("""(function(){
      var r=document.getElementById('R43000000000000411');
      return [...r.querySelectorAll('.spx-sub')].map(function(x){return x.innerText;}).join(' | ');
    })()""")
    comprueba(subs2 == "IDENTIFICACI\u00d3N | CONTACTO",
              "F4 la imprenta tiene sus dos bloques", subs2)
    captura("20261120_cierre_imprenta.png", 1440, 1000)
    medidas(500, 1000)
    time.sleep(1.2)
    captura("20261120_cierre_imprenta_500.png", 500, 1000)

    # ---------------- pagina 23: dialogo de Proveedor ----------------
    medidas(1440, 900)
    js('window.location.href="%s/f?p=100:22:%s"' % (BASE, ses))
    esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(4)
    js('(function(){var b=[...document.querySelectorAll("button,a")].find(function(x){'
       'return (x.getAttribute("data-otel-label")||"")==="BTN_NUEVO_PROVEEDOR";});if(b){b.click();}})()')
    if not esperar('!!document.querySelector("iframe")'):
        print("  MAL el dialogo de proveedor no abrio")
        raise SystemExit(1)
    time.sleep(3)
    # El % de retencion esta condicionado a «Retiene IVA = Si»: se pone para poder
    # medir la pareja «Retiene IVA | % de retencion».
    en_if('apex.item("P23_RETENER_IVA").setValue("S");return "OK";')
    time.sleep(2)

    m = en_if("""
      var regs=[...d.querySelectorAll('.t-Region')];
      var cab=regs[0].querySelector('.t-Region-header');
      var cuerpo=regs[0].querySelector('.t-Region-body');
      var g=w.getComputedStyle(regs[0]);
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
      var fondo=0, scroller=null;
      regs.forEach(function(r){ fondo = Math.max(fondo, Math.round(r.getBoundingClientRect().bottom)); });
      [...d.querySelectorAll('*')].forEach(function(e){
        if(e.scrollHeight > e.clientHeight + 8 &&
           ['auto','scroll'].indexOf(w.getComputedStyle(e).overflowY) >= 0){ scroller=e; }
      });
      var ifr=document.querySelector('iframe');
      return JSON.stringify({
        cabecera: Math.round(cab.getBoundingClientRect().height),
        relleno: w.getComputedStyle(cuerpo).paddingTop,
        margen: g.marginBottom,
        filas: pares,
        fondo: fondo,
        scroll: scroller ? scroller.scrollHeight - scroller.clientHeight : -1,
        iframe: Math.round(ifr.getBoundingClientRect().height),
        ancho_iframe: Math.round(ifr.getBoundingClientRect().width)
      });
    """)
    print("  medidas 23: %s" % m)
    try:
        mm = json.loads(m)
    except Exception:
        mm = {}
    filas = mm.get("filas") or []
    comprueba("P23_RIF+P23_TIPO_RIF" in filas, "P1 RIF y Tipo de RIF en la misma fila", filas)
    comprueba("P23_COD_PAIS+P23_RAZON_SOCIAL" in filas,
              "P1 Pais y Razon social en la misma fila", filas)
    comprueba("P23_EMAIL+P23_TELEFONO" in filas,
              "P1 Correo y Telefono en la misma fila", filas)
    comprueba("P23_DIRECCION" in filas, "P1 la direccion va sola a ancho completo", filas)
    comprueba("P23_RETENER_IVA+P23_PORCENTAJE_RETENCION" in filas,
              "P1 Retiene IVA y % de retencion en la misma fila", filas)
    comprueba("P23_ID_CONCEPTO_ISLR+P23_ES_SPE" in filas,
              "P1 Concepto de ISLR y SPE en la misma fila", filas)
    comprueba("P23_DIAS_CREDITO+P23_ESTADO" in filas,
              "P1 Dias de credito y Estado en la misma fila (seccion fusionada)", filas)

    cab = mm.get("cabecera") or 0
    comprueba(50 <= cab <= 62, "P2 la cabecera de seccion baja a ~56 px (de 80)", cab)
    comprueba(mm.get("relleno") == "9px", "P2 el relleno de la tarjeta baja a 9 px (de 16)",
              mm.get("relleno"))
    comprueba(mm.get("margen") == "9px", "P2 hay 9 px entre secciones (de 16)",
              mm.get("margen"))

    alto_if = mm.get("iframe") or 0
    comprueba(0 < alto_if <= 765, "P3 el dialogo ocupa menos del 85 % de 900 px", alto_if)
    resto = (mm.get("fondo") or 0) - alto_if
    # Desde el 2026-11-20 el formulario entra entero: no queda nada por debajo.
    comprueba(resto <= 2, "P3 el formulario entra sin scroll en 900 px", resto)
    comprueba((mm.get("scroll") or 0) <= 0, "P3 no hay contenedor con scroll",
              mm.get("scroll"))

    captura("20261120_cierre_p23_900.png", 1440, 900, completo=False)
    captura("20261120_cierre_p23.png", 1440, 900)
    medidas(500, 900)
    time.sleep(1.5)
    captura("20261120_cierre_p23_500.png", 500, 900, completo=False)
finally:
    proc.terminate()
    cur.execute("begin delete from usuario_empresa where usuario_id in "
                "(select usuario_id from usuario where upper(username)=upper(:u)); commit; "
                "delete from usuario where upper(username)=upper(:u); commit; end;", u=USUARIO)
    con.commit()
    con.close()

print("\nRESULTADO: FALLAS=%d" % fallas)
sys.exit(1 if fallas else 0)
