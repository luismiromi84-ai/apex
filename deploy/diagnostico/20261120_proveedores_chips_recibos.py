#!/usr/bin/env python3
# =============================================================================
# 20261120_proveedores_chips_recibos.py
#
# Cierra dos remates del 2026-11-20, con navegador real:
#   C1  la pagina 22 (Proveedores) tiene los chips [Todos] [Activos]
#       [Retienen IVA] [SPE] [Inactivos], con el mismo aspecto que Clientes (20)
#   C2  el chip activo es el que dice el item P22_FILTRO al cargar
#   C3  al pulsar un chip cambia P22_FILTRO y el informe se filtra de verdad
#       (Todos trae las filas de la empresa; Inactivos no trae ninguna, porque
#       hoy no hay proveedores inactivos)
#   C4  el buscador del informe y el boton «Nuevo proveedor» siguen ahi
#   R1  el filtro de Estado de la pagina 24 (Recibos) dice «Emitidos» y no
#       «Activos», y el valor sigue siendo ACTIVO (la tabla no cambia)
#   R2  la lista de recibos sigue mostrando la insignia EMITIDO
#
# Capturas:
#   deploy/resultados/20261120_proveedores_chips.png
#   deploy/resultados/20261120_recibos_emitidos.png
#
# Uso:
#     python deploy/diagnostico/20261120_proveedores_chips_recibos.py
# Requiere: websocket-client, oracledb y Edge instalado.
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

import oracledb
import websocket

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
BASE = "https://gfd7e2575d251ae-sypexsql.adb.mx-monterrey-1.oraclecloudapps.com/ords"
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(REPO, "deploy", "conexion"))
from verificar_conexion import CONNECT_STRING as CS, credenciales  # noqa: E402

USUARIO, CLAVE = "diag.chips22", "Diag#2026"
SALIDA = os.path.join(REPO, "deploy", "resultados")
LISTA = "#R43000000000000600"
fallas = []


def comprobar(texto, ok, detalle=""):
    print(("  OK  " if ok else "  MAL ") + texto + ("" if ok else " " + str(detalle)))
    if not ok:
        fallas.append(texto)


class Nav:
    def __init__(self, puerto=9287):
        self.proc = subprocess.Popen(
            [EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
             "--window-size=1440,1000",
             "--remote-debugging-port=%d" % puerto,
             "--user-data-dir=" + os.path.join(tempfile.gettempdir(), "opencode", "edge-chips22"),
             "about:blank"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        objetivo = None
        for _ in range(40):
            try:
                lista = json.loads(urllib.request.urlopen(
                    "http://127.0.0.1:%d/json/list" % puerto, timeout=2).read())
                pag = [t for t in lista if t.get("type") == "page"]
                if pag:
                    objetivo = pag[0]
                    break
            except Exception:
                pass
            time.sleep(0.5)
        self.ws = websocket.create_connection(objetivo["webSocketDebuggerUrl"], timeout=60)
        self.n = 0
        self.cmd("Page.enable")
        self.cmd("Runtime.enable")

    def cmd(self, method, **params):
        self.n += 1
        self.ws.send(json.dumps({"id": self.n, "method": method, "params": params}))
        while True:
            r = json.loads(self.ws.recv())
            if r.get("id") == self.n:
                return r.get("result", {})

    def js(self, expr):
        r = self.cmd("Runtime.evaluate", expression=expr, returnByValue=True, awaitPromise=True)
        if "exceptionDetails" in r:
            return "EXC: " + str(r["exceptionDetails"].get("exception", {}).get("description"))[:300]
        return r.get("result", {}).get("value")

    def esperar(self, cond, seg=40):
        fin = time.time() + seg
        while time.time() < fin:
            if self.js(cond):
                return True
            time.sleep(0.5)
        return False

    def tamano(self, ancho, alto):
        self.cmd("Emulation.setDeviceMetricsOverride", width=ancho, height=alto,
                 deviceScaleFactor=1, mobile=False)

    def captura(self, ruta):
        r = self.cmd("Page.captureScreenshot", format="png")
        datos = r.get("data")
        if not datos:
            return False
        with open(ruta, "wb") as fh:
            fh.write(base64.b64decode(datos))
        return True

    def cerrar(self):
        try:
            self.proc.terminate()
        except Exception:
            pass


conn = oracledb.connect(user=credenciales()["DB_USER"], password=credenciales()["DB_PASSWORD"], dsn=CS)
cur = conn.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")
cur.execute("delete from syn_login_log where upper(usuario_intentado) = 'DIAG.CHIPS22'")
cur.execute("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario "
            "where upper(username) = 'DIAG.CHIPS22'); commit; "
            "delete from usuario where upper(username) = 'DIAG.CHIPS22'; commit; end;")
cur.execute("""insert into usuario (username, email, password_hash, estado, id_empresa, rol_id,
                                    debe_cambiar_clave, reintentos_fallidos)
               values ('diag.chips22', 'diag.chips22@synpex.local', sypex_hash_password('Diag#2026'),
                       'ACTIVO', 1, (select id_rol from syn_roles where codigo_rol = 'ADMIN'), 'N', 0)""")
conn.commit()

# Lo que tiene que traer cada chip, medido en la base.
cur.execute("""select count(*),
                      count(case when estado = 'ACTIVO' then 1 end),
                      count(case when estado = 'INACTIVO' then 1 end),
                      count(case when nvl(es_spe, 'N') = 'S' then 1 end),
                      count(case when nvl(retener_iva, 'S') = 'S' then 1 end)
                 from proveedores where id_empresa = 1""")
tot, act, ina, spe, ret = cur.fetchone()
print("  esperado en la base: todos=%d activos=%d inactivos=%d spe=%d retienen=%d"
      % (tot, act, ina, spe, ret))

nav = Nav()
try:
    nav.tamano(1440, 1000)
    nav.js('window.location.href="%s/f?p=100:9999"' % BASE)
    nav.esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(1)
    nav.js('(function(){apex.item("P9999_USERNAME").setValue(%s);apex.item("P9999_PASSWORD").setValue(%s);'
           'var b=[...document.querySelectorAll("button")].find(x=>/sign in|iniciar|entrar/i.test(x.innerText));'
           'if(b){b.click();}})()' % (json.dumps(USUARIO), json.dumps(CLAVE)))
    time.sleep(8)
    m = re.search(r"session=(\d+)", nav.js("window.location.href") or "")
    if not m:
        print("FALLO el login:", (nav.js("document.body.innerText") or "")[:200])
        raise SystemExit(1)
    ses = m.group(1)

    # ------------------------------------------------------------- pagina 22
    nav.js('window.location.href="%s/f?p=100:22:%s"' % (BASE, ses))
    nav.esperar('document.readyState === "complete" && typeof apex === "object"', 60)
    nav.esperar('!!document.querySelector(".spx-filtros")', 60)
    nav.esperar('document.querySelectorAll("%s a.spx-nombre-link").length > 0' % LISTA, 60)
    time.sleep(2)

    chips = nav.js('(function(){var t=[];document.querySelectorAll(".spx-filtro").forEach(function(a){'
                   't.push(a.getAttribute("data-filtro")+":"+a.innerText.trim());});return t.join(" | ");})()')
    print("  chips:", chips)
    for valor, texto in (("TODOS", "Todos"), ("ACTIVOS", "Activos"), ("RETIENE", "Retienen IVA"),
                         ("SPE", "SPE"), ("INACTIVOS", "Inactivos")):
        comprobar("C1 el chip «%s» esta" % texto,
                  ("%s:%s" % (valor, texto)) in (chips or ""), chips)
    comprobar("C1 son cinco chips", len((chips or "").split(" | ")) == 5, chips)

    estilo = nav.js('(function(){var a=document.querySelector(".spx-filtro");'
                    'var s=getComputedStyle(a);'
                    'return [s.borderRadius, s.paddingLeft, s.fontWeight].join("|");})()')
    print("  estilo del chip:", estilo)
    comprobar("C1 el chip tiene el estilo redondeado de Clientes",
              "999px" in (estilo or "") and "14px" in (estilo or ""), estilo)

    activo = nav.js('(function(){var a=document.querySelector(".spx-filtro.is-active");'
                    'return a?a.getAttribute("data-filtro"):"ninguno";})()')
    comprobar("C2 al cargar esta activo el chip de P22_FILTRO",
              activo == (nav.js('apex.item("P22_FILTRO").getValue()') or "TODOS"), activo)

    def filas():
        # Una fila del informe = un enlace con el nombre del proveedor (el informe
        # pinta ademas la cabecera fija, que duplica el <table>).
        return nav.js('(function(){return document.querySelectorAll('
                      '"%s a.spx-nombre-link").length;})()' % LISTA)

    def pulsar(valor, esperadas):
        # Se engancha un MutationObserver al informe: asi se espera a que el
        # refresco termine de verdad (dos lecturas seguidas sin cambios) y no a
        # que el conteo coincida por casualidad con el de antes.
        nav.js('(function(){window.__mut=0;'
               'var r=document.getElementById("R43000000000000600");'
               'if(window.__obs){window.__obs.disconnect();}'
               'window.__obs=new MutationObserver(function(){window.__mut++;});'
               'window.__obs.observe(r,{childList:true,subtree:true});return "ok";})()')
        nav.js('(function(){var a=document.querySelector(\'.spx-filtro[data-filtro="%s"]\');'
               'if(a){a.click();return "ok";}return "sin chip";})()' % valor)
        nav.esperar('(function(){return apex.item("P22_FILTRO").getValue() === "%s";})()' % valor, 20)
        nav.esperar('(function(){return window.__mut > 0;})()', 40)
        # estable: dos lecturas del contador separadas por un segundo
        anterior = -1
        for _ in range(60):
            actual = nav.js('window.__mut')
            if actual == anterior:
                break
            anterior = actual
            time.sleep(1)
        nav.esperar('(function(){return document.querySelectorAll("%s a.spx-nombre-link").length'
                    ' === %d;})()' % (LISTA, esperadas), 40)
        time.sleep(1)
        return nav.js('apex.item("P22_FILTRO").getValue()')

    print("  filas con Todos:", filas())
    comprobar("C3 el chip Todos trae las filas de la empresa", filas() == tot, (filas(), tot))

    valor = pulsar("INACTIVOS", ina)
    comprobar("C3 el chip Inactivos deja P22_FILTRO en INACTIVOS", valor == "INACTIVOS", valor)
    activo = nav.js('(function(){var a=document.querySelector(".spx-filtro.is-active");'
                    'return a?a.getAttribute("data-filtro"):"ninguno";})()')
    comprobar("C3 el chip activo se mueve al pulsado", activo == "INACTIVOS", activo)
    if ina == 0:
        vacio = nav.js('(function(){return (document.body.innerText||"").indexOf('
                       '"No hay proveedores para tu empresa") >= 0;})()')
        comprobar("C3 sin inactivos el informe sale vacio (no las 3 filas)",
                  filas() == 0 and vacio, (filas(), vacio))
    else:
        comprobar("C3 el chip Inactivos trae solo los inactivos", filas() == ina, (filas(), ina))

    pulsar("SPE", spe)
    comprobar("C3 el chip SPE trae solo los SPE", filas() == spe, (filas(), spe))

    pulsar("RETIENE", ret)
    comprobar("C3 el chip Retienen IVA trae solo los que retienen", filas() == ret, (filas(), ret))

    pulsar("TODOS", tot)
    comprobar("C3 al volver a Todos vuelven todas las filas", filas() == tot, (filas(), tot))

    buscador = nav.js('(function(){return !!document.querySelector("#P24_BUSCAR");})()')
    boton = nav.js('(function(){var b=document.querySelector(\'[data-otel-label="BTN_NUEVO_PROVEEDOR"]\');'
                   'return !!b;})()')
    comprobar("C4 el boton «Nuevo proveedor» sigue ahi", boton, boton)
    comprobar("C4 el informe conserva su buscador", nav.js(
        '(function(){return !!document.querySelector(".a-IRR-search-field");})()'), buscador)

    ok = nav.captura(os.path.join(SALIDA, "20261120_proveedores_chips.png"))
    comprobar("C5 captura de la pagina 22 a 1440", ok)

    # ------------------------------------------------------------- pagina 24
    nav.js('window.location.href="%s/f?p=100:24:%s"' % (BASE, ses))
    nav.esperar('!!document.getElementById("P24_ESTADO")', 40)
    time.sleep(4)

    opciones = nav.js('(function(){var s=document.getElementById("P24_ESTADO");var t=[];'
                      'for(var i=0;i<s.options.length;i++){t.push(s.options[i].value+"="+s.options[i].text);}'
                      'return t.join(" | ");})()')
    print("  opciones de Estado:", opciones)
    comprobar("R1 el filtro ofrece «Emitidos»", "=Emitidos" in (opciones or ""), opciones)
    comprobar("R1 ya no dice «Activos»", "Activos" not in (opciones or ""), opciones)
    comprobar("R1 el valor sigue siendo ACTIVO (la tabla no cambia)",
              "ACTIVO=Emitidos" in (opciones or ""), opciones)
    comprobar("R1 y el de anulados sigue", "ANULADO=Anulados" in (opciones or ""), opciones)

    insignias = nav.js('(function(){return document.querySelectorAll(".status-EMITIDO").length;})()')
    comprobar("R2 la lista sigue mostrando la insignia EMITIDO", (insignias or 0) >= 1, insignias)

    # Se elige «Emitidos» en el filtro: asi la captura ensena la etiqueta en el
    # combo cerrado y, de paso, se comprueba que filtra de verdad. (Hasta hoy no
    # filtraba: los cinco items se declaraban p_is_persistent=>'N' y su accion hace
    # apex.submit, asi que APEX descartaba el valor antes de renderizar.)
    cur.execute("select count(*) from recibos where id_empresa = 1 and estado = 'ACTIVO'")
    activos = cur.fetchone()[0]
    nav.js('(function(){var s=document.getElementById("P24_ESTADO");s.value="ACTIVO";'
           's.dispatchEvent(new Event("change",{bubbles:true}));return "ok";})()')
    time.sleep(12)
    nav.esperar('(function(){return apex.item("P24_ESTADO").getValue() === "ACTIVO";})()', 40)
    time.sleep(2)
    texto = nav.js('(function(){var s=document.getElementById("P24_ESTADO");'
                   'return s.options[s.selectedIndex].text;})()')
    comprobar("R4 al elegirlo el combo lee «Emitidos»", texto == "Emitidos", texto)

    def filas_estado(clase):
        return nav.js('(function(){var t=0;document.querySelectorAll('
                      '"#R43000000000000801 .a-IRR-table tbody tr").forEach(function(tr){'
                      'if(tr.querySelectorAll("td").length > 3 && tr.querySelector(".%s")){t++;}});'
                      'return t;})()' % clase)

    print("  filas emitidas en pantalla:", filas_estado("status-EMITIDO"), "en la base:", activos)
    comprobar("R4 el filtro deja solo los emitidos",
              filas_estado("status-EMITIDO") == activos and filas_estado("status-ANULADO") == 0,
              (filas_estado("status-EMITIDO"), activos, filas_estado("status-ANULADO")))

    # Y el buscador, que corria la misma suerte, ya filtra.
    nav.js('(function(){var s=document.getElementById("P24_BUSCAR");s.value="zzzz";'
           's.dispatchEvent(new Event("change",{bubbles:true}));return "ok";})()')
    time.sleep(12)
    vacio = nav.js('(function(){var t=0;document.querySelectorAll('
                   '"#R43000000000000801 .a-IRR-table tbody tr").forEach(function(tr){'
                   'if(tr.querySelectorAll("td").length > 3){t++;}});return t;})()')
    comprobar("R4 el buscador tambien filtra (ya no ignora lo tecleado)", vacio == 0, vacio)
    nav.js('(function(){var s=document.getElementById("P24_BUSCAR");s.value="";'
           's.dispatchEvent(new Event("change",{bubbles:true}));return "ok";})()')
    time.sleep(12)

    ok = nav.captura(os.path.join(SALIDA, "20261120_recibos_emitidos.png"))
    comprobar("R3 captura de la pagina 24 a 1440", ok)
finally:
    nav.cerrar()
    cur.execute("delete from syn_login_log where upper(usuario_intentado) = 'DIAG.CHIPS22'")
    cur.execute("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario "
                "where upper(username) = 'DIAG.CHIPS22'); commit; "
                "delete from usuario where upper(username) = 'DIAG.CHIPS22'; commit; end;")
    conn.commit()
    conn.close()

print()
print("RESULTADO: FALLAS=" + str(len(fallas)))
for f in fallas:
    print("  - " + f)
sys.exit(1 if fallas else 0)
