#!/usr/bin/env python3
"""
Clientes (20 y 21) con el acabado nuevo, en navegador real (2026-11-20).

Comprueba lo que solo se ve pintado:

  C1  la fila de indicadores sale con sus cuatro tarjetas y sus numeros
  C2  el chip «Retienen IVA» filtra la lista (3 de 5 en la empresa 1)
  C3  el chip «Todos» la deja completa (5) y el chip queda marcado
  C4  cada fila trae avatar, el nombre enlazado, correo mailto: y telefono tel:
  C5  el NOMBRE abre la ficha del cliente (pagina 32) y el icono «Editar» sigue
      abriendo el dialogo de la 21 (2026-11-20: antes el nombre abria el dialogo)
  C6  el dialogo de proveedor (23) abre con los flags guardados y, al guardar
      sin tocarlos, no los cambia
  C7  lo mismo en la 22/23 con el proveedor de prueba
  C8  un CLIENTE NUEVO nace sin retener IVA, sin SPE y con el % en 75
      (2026-11-20: sin defecto, la lista abria en «Si» y el cliente nacia
      marcado como agente y como SPE, y eso cambia el IVA y el IGTF)
  C9  un PROVEEDOR NUEVO tambien, y el % de retencion se esconde con «No»
  C10 capturas a 1440 y 500 px y del dialogo

Uso:
    python deploy/diagnostico/20261120_clientes_premium.py
Requiere websocket-client y Edge instalado.
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
sys.path.insert(0, os.path.join(REPO, "deploy", "conexion"))
from verificar_conexion import CONNECT_STRING as CS, credenciales  # noqa: E402

USUARIO, CLAVE = "diag.clientes20", "Diag#2026"
RES = os.path.join(REPO, "deploy", "resultados")

# Fichas de prueba para C6/C7: las dos con los flags en 'N', para comprobar que
# abrir y guardar sin tocar nada NO los convierte en 'S'.
NOMBRE_CLI = "Cliente carga sin retencion (verificacion)"
RIF_CLI = "J-91000001-1"
NOMBRE_PROV = "Proveedor carga sin retencion (verificacion)"
RIF_PROV = "J-91000002-2"
PCT_CLI = 30      # distinto de 75: asi se ve si el % se carga o se queda en el defecto
PCT_PROV = 50

fallas = []


def comprobar(nombre, condicion, detalle=""):
    print(("  OK  " if condicion else "  MAL ") + nombre + ((" " + str(detalle)) if detalle else ""))
    if not condicion:
        fallas.append(nombre)


class Nav:
    def __init__(self, puerto=9291):
        self.proc = subprocess.Popen(
            [EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
             "--remote-debugging-port=%d" % puerto,
             "--user-data-dir=" + os.path.join(tempfile.gettempdir(), "opencode", "edge-clientes20"),
             "--window-size=1440,900", "about:blank"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
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
        self.ws = websocket.create_connection(objetivo["webSocketDebuggerUrl"], timeout=90)
        self.n = 0
        for m in ("Page.enable", "Runtime.enable"):
            self.cmd(m)

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
            return "EXC: " + str(r["exceptionDetails"].get("exception", {}).get("description"))[:200]
        return r.get("result", {}).get("value")

    def esperar(self, cond, seg=40):
        fin = time.time() + seg
        while time.time() < fin:
            if self.js(cond):
                return True
            time.sleep(0.5)
        return False

    def captura(self, ruta):
        r = self.cmd("Page.captureScreenshot", format="png")
        if r.get("data"):
            with open(ruta, "wb") as fh:
                fh.write(base64.b64decode(r["data"]))
            return True
        return False

    def clic(self, expresion):
        r = self.js(expresion)
        if not r or r == "null":
            return False
        d = json.loads(r)
        for t in ("mousePressed", "mouseReleased"):
            self.cmd("Input.dispatchMouseEvent", type=t, x=d["x"], y=d["y"],
                     button="left", clickCount=1)
        return True

    def cerrar(self):
        try:
            self.proc.terminate()
        except Exception:
            pass


# Una fila de datos = un enlace de nombre. Contar <tr> incluye la fila de la
# cabecera fija del informe, que no lleva celdas de datos.
FILAS = ('document.querySelectorAll("#R43000000000000501 a.spx-nombre-link").length')
TEXTO = 'document.body.innerText'

conn = oracledb.connect(user=credenciales()["DB_USER"], password=credenciales()["DB_PASSWORD"], dsn=CS)
cur = conn.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")


def limpia():
    cur.execute("delete from clientes where razon_social = :r", r=NOMBRE_CLI)
    cur.execute("delete from proveedores where razon_social = :r", r=NOMBRE_PROV)
    cur.execute("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario "
                "where upper(username)=upper(:u)); commit; end;", u=USUARIO)
    cur.execute("delete from usuario where upper(username)=upper(:u)", u=USUARIO)
    cur.execute("delete from syn_login_log where upper(usuario_intentado)=upper(:u)", u=USUARIO)
    conn.commit()


limpia()
cur.execute("""insert into usuario (username, email, password_hash, estado, id_empresa, rol_id,
                                    debe_cambiar_clave, reintentos_fallidos)
               values (:u, 'diag.clientes20@synpex.local', sypex_hash_password('Diag#2026'),
                       'ACTIVO', 1, (select id_rol from syn_roles where codigo_rol='ADMIN'), 'N', 0)""",
            u=USUARIO)
conn.commit()

# Los numeros que tienen que salir en los indicadores.
cur.execute("""select count(*),
                      count(case when estado='ACTIVO' then 1 end),
                      count(case when estado='INACTIVO' then 1 end),
                      count(case when nvl(es_agente_retencion,'N')='S' then 1 end)
                 from clientes where id_empresa = 1""")
esperado = cur.fetchone()
print("  indicadores esperados (clientes/activos/inactivos/retienen):", esperado)

nav = Nav()
try:
    nav.js('window.location.href="%s/f?p=100:9999"' % BASE)
    nav.esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(1)
    nav.js('(function(){apex.item("P9999_USERNAME").setValue(%s);apex.item("P9999_PASSWORD").setValue(%s);'
           'var b=[...document.querySelectorAll("button")].find(x=>/sign in|iniciar|entrar/i.test(x.innerText));'
           'if(b){b.click();}})()' % (json.dumps(USUARIO), json.dumps(CLAVE)))
    time.sleep(7)
    m = re.search(r"session=(\d+)", nav.js("window.location.href") or "")
    if not m:
        comprobar("login", False, (nav.js(TEXTO) or "")[:160])
        raise SystemExit(1)
    ses = m.group(1)

    # ---------------------------------------------------------------- C1
    nav.js('window.location.href="%s/f?p=100:20:%s"' % (BASE, ses))
    nav.esperar('document.readyState === "complete" && !!window.apex')
    nav.esperar('!!document.querySelector(".spx-kpis")', 30)
    time.sleep(2)

    kpis = nav.js('(function(){var t=[];document.querySelectorAll(".spx-card").forEach(function(c){'
                  't.push(c.querySelector(".spx-card-lbl").innerText.trim()+"="+'
                  'c.querySelector(".spx-card-val").innerText.trim());});return t.join(" | ");})()')
    print("  tarjetas:", kpis)
    comprobar("C1 salen las cuatro tarjetas", (kpis or "").count("=") == 4, kpis)
    # La etiqueta se pinta en mayusculas por CSS: se compara asi.
    kpi_txt = (kpis or "").upper()
    comprobar("C1 los numeros son los de la base",
              ("CLIENTES=%d" % esperado[0]) in kpi_txt
              and ("ACTIVOS=%d" % esperado[1]) in kpi_txt
              and ("INACTIVOS=%d" % esperado[2]) in kpi_txt
              and ("RETIENEN IVA=%d" % esperado[3]) in kpi_txt, kpis)

    filas_todas = nav.js(FILAS)
    comprobar("C1 la lista trae los clientes de la empresa", filas_todas == esperado[0], filas_todas)

    # ---------------------------------------------------------------- C2
    nav.clic('(function(){var a=[...document.querySelectorAll(".spx-filtro")].find(function(x){'
             'return x.getAttribute("data-filtro")==="RETIENE";});if(!a){return null;}'
             'var r=a.getBoundingClientRect();'
             'return JSON.stringify({x:r.left+r.width/2,y:r.top+r.height/2});})()')
    ok = nav.esperar('%s === %d' % (FILAS, esperado[3]), 30)
    activo = nav.js('(function(){var a=[...document.querySelectorAll(".spx-filtro")].find(function(x){'
                    'return x.getAttribute("data-filtro")==="RETIENE";});'
                    'return a ? a.className : "sin chip";})()')
    comprobar("C2 el chip «Retienen IVA» filtra la lista", ok, nav.js(FILAS))
    comprobar("C2 el chip queda marcado", "is-active" in (activo or ""), activo)

    # ---------------------------------------------------------------- C3
    nav.clic('(function(){var a=[...document.querySelectorAll(".spx-filtro")].find(function(x){'
             'return x.getAttribute("data-filtro")==="TODOS";});if(!a){return null;}'
             'var r=a.getBoundingClientRect();'
             'return JSON.stringify({x:r.left+r.width/2,y:r.top+r.height/2});})()')
    ok = nav.esperar('%s === %d' % (FILAS, esperado[0]), 30)
    comprobar("C3 el chip «Todos» devuelve la lista completa", ok, nav.js(FILAS))

    # ---------------------------------------------------------------- C4
    nav.js('window.scrollTo(0,0)')
    time.sleep(1)
    nav.captura(os.path.join(RES, "20261120_clientes_1440.png"))
    fila = nav.js('(function(){var a=document.querySelector("#R43000000000000501 a.spx-nombre-link");'
                  'if(!a){return null;}var tr=a.closest("tr");'
                  'var av=tr.querySelector(".spx-avatar");'
                  'var m=tr.querySelector("a.spx-mail");'
                  'var t=tr.querySelector("a.spx-tel");'
                  'var e=tr.querySelector("a.spx-editar");'
                  'return JSON.stringify({nombre:!!a, avatar:av?av.className:"", mail:m?m.getAttribute("href"):"",'
                  ' tel:t?t.getAttribute("href"):"", editar:e?e.className:""});})()')
    print("  primera fila:", fila)
    d = json.loads(fila) if fila and fila.startswith("{") else {}
    comprobar("C4 el nombre es un enlace", bool(d.get("nombre")))
    comprobar("C4 la fila trae avatar", "spx-avatar" in (d.get("avatar") or ""), d.get("avatar"))
    comprobar("C4 el correo es mailto:", (d.get("mail") or "").startswith("mailto:"), d.get("mail"))
    comprobar("C4 el telefono es tel:", (d.get("tel") or "").startswith("tel:"), d.get("tel"))
    comprobar("C4 «Editar» es un icono compacto", "spx-editar" in (d.get("editar") or ""), d.get("editar"))

    # ---------------------------------------------------------------- C6 (500 px)
    nav.cmd("Emulation.setDeviceMetricsOverride", width=500, height=900,
            deviceScaleFactor=1, mobile=False)
    time.sleep(3)
    nav.captura(os.path.join(RES, "20261120_clientes_500.png"))
    nav.cmd("Emulation.clearDeviceMetricsOverride")
    time.sleep(1)

    # ---------------------------------------------------------------- C5
    # 2026-11-20: el NOMBRE ya no abre el dialogo de edicion: lleva a la FICHA del
    # cliente (pagina 32). El dialogo se sigue abriendo con el icono «Editar».
    nav.clic('(function(){var a=document.querySelector("#R43000000000000501 a.spx-nombre-link");'
             'if(!a){return null;}var r=a.getBoundingClientRect();'
             'return JSON.stringify({x:r.left+r.width/2,y:r.top+r.height/2});})()')
    llego = nav.esperar('document.readyState === "complete" && !!document.querySelector(".spx-ficha")', 45)
    comprobar("C5 el nombre abre la ficha del cliente (32)", llego)
    if llego:
        time.sleep(2)
        ficha = nav.js('(function(){var f=document.querySelector(".spx-ficha");'
                       'return f?(f.innerText||"").replace(/\\s+/g," "):"";})()')
        print("  ficha:", (ficha or "")[:120])
        comprobar("C5 la ficha trae nombre, RIF y estado",
                  bool(ficha) and "J-" in ficha and ("ACTIVO" in ficha or "INACTIVO" in ficha), ficha)
        comprobar("C5 la ficha trae los cuatro indicadores",
                  nav.js('document.querySelectorAll(".spx-card").length') == 4)
        nav.captura(os.path.join(RES, "20261120_clientes_p32.png"))

    # C5b: el icono «Editar» de la fila sigue abriendo el dialogo de la 21.
    nav.js('window.location.href="%s/f?p=100:20:%s"' % (BASE, ses))
    nav.esperar('document.readyState === "complete" && !!window.apex')
    nav.esperar('!!document.querySelector("#R43000000000000501 a.spx-editar")', 40)
    time.sleep(3)
    nav.js('(function(){var a=document.querySelector("#R43000000000000501 a.spx-editar");'
           'if(a){a.click();return "ok";}return "sin enlace";})()')
    abierto = nav.esperar('(function(){var f=document.querySelector("iframe");'
                          'return !!(f&&f.contentWindow&&f.contentDocument&&'
                          'f.contentDocument.getElementById("P21_RAZON_SOCIAL"));})()', 45)
    comprobar("C5b el icono «Editar» sigue abriendo el dialogo de cliente", abierto)
    if abierto:
        time.sleep(3)
        comprobar("C5b el formulario de la 21 sigue completo",
                  bool(nav.js('(function(){var d=document.querySelector("iframe").contentDocument;'
                              'return !!d.getElementById("P21_RIF");})()')))
        nav.captura(os.path.join(RES, "20261120_clientes_p21.png"))

    # ------------------------------------------------- C6/C7: la carga no cambia nada
    # Las dos fichas de prueba nacen con los flags en 'N' y un % distinto del
    # defecto: si el proceso de carga no los pone, el navegador manda 'Si' al
    # guardar y el porcentaje se queda en el defecto.
    cur.execute("""insert into clientes (id_empresa, rif, razon_social, tipo_persona, cod_pais,
                                         estado, es_agente_retencion, porcentaje_retencion, es_spe)
                   values (1, :rif, :nom, 'J', 'VE', 'ACTIVO', 'N', :pct, 'N')""",
                rif=RIF_CLI, nom=NOMBRE_CLI, pct=PCT_CLI)
    cur.execute("""insert into proveedores (id_empresa, rif, razon_social, tipo_persona, cod_pais,
                                            estado, retener_iva, porcentaje_retencion, es_spe, dias_credito)
                   values (1, :rif, :nom, 'J', 'VE', 'ACTIVO', 'N', :pct, 'N', 0)""",
                rif=RIF_PROV, nom=NOMBRE_PROV, pct=PCT_PROV)
    conn.commit()

    def abrir_ficha(pagina, nombre, campo, link):
        nav.js('window.location.href="%s/f?p=100:%d:%s"' % (BASE, pagina, ses))
        nav.esperar('document.readyState === "complete" && !!window.apex')
        time.sleep(4)
        nav.js('(function(){var n=%s;'
               'var tr=[...document.querySelectorAll("tr")].find(function(t){'
               'return (t.innerText||"").indexOf(n)>=0;});'
               'if(!tr){return "sin fila";}'
               'var a=tr.querySelector(\'%s\');'
               'if(a){a.click();return "ok";}return "sin enlace";})()' % (json.dumps(nombre), link))
        return nav.esperar('(function(){var f=document.querySelector("iframe");'
                           'return !!(f&&f.contentWindow&&f&&f.contentDocument&&'
                           'f.contentDocument.getElementById("%s"));})()' % campo, 45)

    def en_if(expr):
        return nav.js('(function(){var w=document.querySelector("iframe").contentWindow;'
                      'return (function(apex){' + expr + '})(w.apex);})()')

    def abrir_nuevo(pagina, boton, campo):
        """Abre el dialogo con el boton de alta de la lista (sin fila elegida)."""
        nav.js('window.location.href="%s/f?p=100:%d:%s"' % (BASE, pagina, ses))
        nav.esperar('document.readyState === "complete" && !!window.apex')
        time.sleep(4)
        nav.js('(function(){var b=[...document.querySelectorAll("button,a")].find(function(x){'
               'return (x.getAttribute("data-otel-label")||"")===%s;});'
               'if(b){b.click();return "ok";}return "sin boton";})()' % json.dumps(boton))
        return nav.esperar('(function(){var f=document.querySelector("iframe");'
                           'return !!(f&&f.contentWindow&&f.contentDocument&&'
                           'f.contentDocument.getElementById("%s"));})()' % campo, 45)

    # C6: cliente. Se abre con el icono «Editar» (el nombre lleva a la ficha, 32).
    abierto = abrir_ficha(20, NOMBRE_CLI, "P21_RAZON_SOCIAL", 'a.spx-editar')
    comprobar("C6 el cliente de prueba abre su dialogo", abierto)
    if abierto:
        time.sleep(3)
        agente = en_if('return String(apex.item("P21_ES_AGENTE_RETENCION").getValue());')
        spe = en_if('return String(apex.item("P21_ES_SPE").getValue());')
        pct = en_if('return String(apex.item("P21_PORCENTAJE_RETENCION").getValue());')
        print("  C6 items al abrir: agente=%r spe=%r pct=%r" % (agente, spe, pct))
        comprobar("C6 el cliente abre con «Retiene IVA» en No", agente == "N", agente)
        comprobar("C6 el cliente abre con SPE en No", spe == "N", spe)
        comprobar("C6 el cliente abre con su % real", str(pct).strip() in ("30", "30.0"), pct)
        # Guardar SIN tocar nada
        nav.js('(function(){var d=document.querySelector("iframe").contentDocument;'
               'var b=d.querySelector(\'[data-otel-label="BTN_GUARDAR_CLIENTE"]\');'
               'if(b){b.click();return "ok";}return "sin boton";})()')
        time.sleep(10)
        fila = cur.execute("""select es_agente_retencion, porcentaje_retencion, es_spe
                                 from clientes where razon_social = :r""", r=NOMBRE_CLI).fetchone()
        print("  C6 en la base tras guardar:", fila)
        comprobar("C6 guardar sin tocar nada lo deja sin retener IVA",
                  fila is not None and fila[0] == "N", fila)
        comprobar("C6 guardar sin tocar nada lo deja sin SPE",
                  fila is not None and fila[2] == "N", fila)
        comprobar("C6 guardar sin tocar nada conserva el %",
                  fila is not None and float(fila[1]) == PCT_CLI, fila)

    # C7: proveedor (misma comprobacion; la 23 ya cargaba los tres campos)
    abierto = abrir_ficha(22, NOMBRE_PROV, "P23_RAZON_SOCIAL", 'a[href*="p23_id_proveedor"]')
    comprobar("C7 el proveedor de prueba abre su dialogo", abierto)
    if abierto:
        time.sleep(3)
        ret = en_if('return String(apex.item("P23_RETENER_IVA").getValue());')
        spe = en_if('return String(apex.item("P23_ES_SPE").getValue());')
        pct = en_if('return String(apex.item("P23_PORCENTAJE_RETENCION").getValue());')
        print("  C7 items al abrir: retiene=%r spe=%r pct=%r" % (ret, spe, pct))
        comprobar("C7 el proveedor abre con «Retiene IVA» en No", ret == "N", ret)
        comprobar("C7 el proveedor abre con SPE en No", spe == "N", spe)
        comprobar("C7 el proveedor abre con su % real", str(pct).strip() in ("50", "50.0"), pct)
        nav.js('(function(){var d=document.querySelector("iframe").contentDocument;'
               'var b=d.querySelector(\'[data-otel-label="BTN_GUARDAR_PROVEEDOR"]\');'
               'if(b){b.click();return "ok";}return "sin boton";})()')
        time.sleep(10)
        fila = cur.execute("""select retener_iva, porcentaje_retencion, es_spe
                                 from proveedores where razon_social = :r""", r=NOMBRE_PROV).fetchone()
        print("  C7 en la base tras guardar:", fila)
        comprobar("C7 guardar sin tocar nada lo deja sin retener IVA",
                  fila is not None and fila[0] == "N", fila)
        comprobar("C7 guardar sin tocar nada lo deja sin SPE",
                  fila is not None and fila[2] == "N", fila)
        comprobar("C7 guardar sin tocar nada conserva el %",
                  fila is not None and float(fila[1]) == PCT_PROV, fila)

    # C8: un CLIENTE NUEVO nace sin retener IVA y sin SPE. Sin defecto en el item,
    # la lista de seleccion abre en su primera opcion («Si») y el alta queda
    # marcada como agente de retencion y como SPE: eso cambia el IVA retenido y
    # el IGTF de un cliente recien creado.
    abierto = abrir_nuevo(20, "BTN_NUEVO_CLIENTE", "P21_RAZON_SOCIAL")
    comprobar("C8 «Nuevo cliente» abre el dialogo", abierto)
    if abierto:
        time.sleep(3)
        agente = en_if('return String(apex.item("P21_ES_AGENTE_RETENCION").getValue());')
        spe = en_if('return String(apex.item("P21_ES_SPE").getValue());')
        pct = en_if('return String(apex.item("P21_PORCENTAJE_RETENCION").getValue());')
        print("  C8 items del cliente nuevo: agente=%r spe=%r pct=%r" % (agente, spe, pct))
        comprobar("C8 el cliente nuevo nace sin retener IVA", agente == "N", agente)
        comprobar("C8 el cliente nuevo nace sin SPE", spe == "N", spe)
        comprobar("C8 el cliente nuevo trae el % de la norma (75)",
                  str(pct).strip() in ("75", "75.0"), pct)

    # C9: un PROVEEDOR NUEVO, igual. Ademas, con «Retiene IVA = No» el porcentaje
    # no se usa y la accion dinamica esconde su contenedor.
    abierto = abrir_nuevo(22, "BTN_NUEVO_PROVEEDOR", "P23_RAZON_SOCIAL")
    comprobar("C9 «Nuevo proveedor» abre el dialogo", abierto)
    if abierto:
        time.sleep(3)
        ret = en_if('return String(apex.item("P23_RETENER_IVA").getValue());')
        spe = en_if('return String(apex.item("P23_ES_SPE").getValue());')
        pct = en_if('return String(apex.item("P23_PORCENTAJE_RETENCION").getValue());')
        print("  C9 items del proveedor nuevo: retiene=%r spe=%r pct=%r" % (ret, spe, pct))
        comprobar("C9 el proveedor nuevo nace sin retener IVA", ret == "N", ret)
        comprobar("C9 el proveedor nuevo nace sin SPE", spe == "N", spe)
        comprobar("C9 el proveedor nuevo trae el % de la norma (75)",
                  str(pct).strip() in ("75", "75.0"), pct)

        def display_pct():
            return nav.js('(function(){var w=document.querySelector("iframe").contentWindow;'
                          'var el=w.document.getElementById("P23_PORCENTAJE_RETENCION");'
                          'if(!el){return "sin item";}'
                          'var col=el.closest(".col")||el.parentElement;'
                          'return col?col.style.display:"sin col";})()')

        oculto = display_pct()
        comprobar("C9 con «No» el % de retencion esta oculto", oculto == "none", oculto)
        en_if('apex.item("P23_RETENER_IVA").setValue("S");return "OK";')
        time.sleep(4)
        visible = display_pct()
        comprobar("C9 al pasar a «Si» el % vuelve a verse", visible in ("", None), visible)
        nav.captura(os.path.join(RES, "20261120_clientes_p23.png"))
finally:
    nav.cerrar()
    limpia()
    conn.close()

print()
print("RESULTADO: FALLAS=" + str(len(fallas)))
for f in fallas:
    print("  - " + f)
sys.exit(1 if fallas else 0)
