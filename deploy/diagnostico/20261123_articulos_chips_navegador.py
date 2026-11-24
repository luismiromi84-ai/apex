#!/usr/bin/env python3
"""
Articulos y Servicios (40): chips de filtro y codigo interno automatico.
2026-11-23.

Comprueba, con navegador real (Edge headless por CDP):
  C1  la pagina abre con las dos filas de chips y sin la tarjeta «Filtros»
  C2  «Productos» deja solo articulos de tipo PRODUCTO y «Servicios» solo SERVICIO
  C3  «Activos» / «Inactivos» filtran por estado
  C4  Productos + Activos a la vez: las dos condiciones se conservan
  C5  en cada fila hay exactamente un chip activo (no se pisan entre filas)
  C6  al abrir «Nuevo articulo» el codigo interno y el de barras salen
      propuestos (PROD-/SERV- + 5 digitos, 8 digitos) y el interno no se teclea

Uso:  python deploy/diagnostico/20261123_articulos_chips_navegador.py
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

RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(RAIZ, "deploy", "conexion"))
import oracledb  # noqa: E402
from verificar_conexion import CONNECT_STRING as CS, credenciales  # noqa: E402

BASE = ("https://gfd7e2575d251ae-sypexsql.adb.mx-monterrey-1.oraclecloudapps.com/ords")
EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
USUARIO = "diag.artchips"
CLAVE = "Diag#2026"
PUERTO = 9287

fallas = []


def comprobar(nombre, condicion, detalle=""):
    print(("  OK  " if condicion else "  MAL ") + nombre + (" " + str(detalle) if detalle else ""))
    if not condicion:
        fallas.append(nombre)


# ------------------------------------------------------------------ usuario
conn = oracledb.connect(user=credenciales()["DB_USER"],
                        password=credenciales()["DB_PASSWORD"], dsn=CS)
cur = conn.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")


def borrar_usuario():
    cur.execute("""begin
                     for r in (select usuario_id from usuario where upper(username) = :u) loop
                         delete from usuario_empresa where usuario_id = r.usuario_id;
                         commit;
                         delete from usuario where usuario_id = r.usuario_id;
                         commit;
                     end loop;
                   end;""", u=USUARIO.upper())
    conn.commit()


borrar_usuario()
cur.execute("""insert into usuario (username, email, password_hash, estado, id_empresa,
                                    rol_id, debe_cambiar_clave, reintentos_fallidos)
               values (:u, :u || '@synpex.local', sypex_hash_password(:c), 'ACTIVO', 1,
                       (select id_rol from syn_roles where codigo_rol = 'ADMIN'), 'N', 0)""",
            u=USUARIO, c=CLAVE)
conn.commit()

# ------------------------------------------------------------------ navegador
proc = subprocess.Popen([EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
                         "--remote-debugging-port=%d" % PUERTO, "--window-size=1440,900",
                         "--user-data-dir=" + os.path.join(tempfile.gettempdir(), "opencode", "edge-artchips"),
                         "about:blank"],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def objetivo():
    for _ in range(40):
        try:
            lista = json.loads(urllib.request.urlopen(
                "http://127.0.0.1:%d/json/list" % PUERTO, timeout=2).read())
            pag = [t for t in lista if t.get("type") == "page"]
            if pag:
                return pag[0]
        except Exception:
            pass
        time.sleep(0.5)
    raise SystemExit("no se pudo abrir el navegador")


ws = websocket.create_connection(objetivo()["webSocketDebuggerUrl"], timeout=60)
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


def esperar(c_, s=45):
    f = time.time() + s
    while time.time() < f:
        v = js(c_)
        if v and not (isinstance(v, str) and v.startswith("EXC:")):
            return True
        time.sleep(0.5)
    return False


FILAS = ('[...document.querySelectorAll("#R43000000000001800 .a-IRR-table tbody tr")]'
         '.map(function(t){return t.innerText.replace(/\\s+/g," ").trim();})'
         '.filter(function(x){return x.indexOf("Editar") === 0 && x.indexOf("Precio sugerido") < 0;})')


def filas():
    v = js(FILAS)
    return v if isinstance(v, list) else []


def chip(texto, item=None, valor=None, s=25):
    """Pulsa un chip y espera a que su item tome el valor (reintenta si el DA
    todavia no estaba enganchado: al abrir la pagina tarda un momento)."""
    expr = ('(function(){var a=[...document.querySelectorAll(".spx-filtro")]'
            '.find(function(x){return x.textContent.trim()==="%s";});'
            'if(!a){return "NO";}a.click();return "OK";})()' % texto)
    f = time.time() + s
    while time.time() < f:
        r = js(expr)
        if r == "NO":
            time.sleep(0.5)
            continue
        if item is None:
            return True
        time.sleep(1)
        if (js('apex.item("%s").getValue()' % item) or "") == valor:
            return True
        time.sleep(1)
    return False


try:
    js('window.location.href="%s/f?p=100:9999"' % BASE)
    esperar('document.readyState === "complete" && document.getElementById("P9999_USERNAME")', 40)
    js('(function(){apex.item("P9999_USERNAME").setValue(%s);apex.item("P9999_PASSWORD").setValue(%s);'
       'var b=[...document.querySelectorAll("button")].find(x=>/sign in|iniciar|entrar/i.test(x.innerText));'
       'if(b){b.click();}})()' % (json.dumps(USUARIO), json.dumps(CLAVE)))
    esperar('!!window.apex && document.readyState === "complete" && /session=\\d+/.test(location.href)', 60)
    ses = re.search(r"session=(\d+)", js("window.location.href") or "")
    comprobar("C0 login", bool(ses), js("window.location.href"))
    if not ses:
        raise SystemExit(1)

    js('window.location.href="%s/f?p=100:40:%s"' % (BASE, ses.group(1)))
    esperar('document.readyState === "complete" && document.querySelectorAll(".spx-filtro").length > 0', 60)
    time.sleep(2)

    # ---------------------------------------------------------------- C1
    chips = js('[...document.querySelectorAll(".spx-filtro")]'
               '.map(function(a){return a.textContent.trim();})') or []
    filas_chips = js('document.querySelectorAll(".spx-filtros").length')
    comprobar("C1 seis chips", len(chips) == 6, chips)
    comprobar("C1 una sola franja de chips (tipo y estado en la misma fila)",
              (filas_chips or 0) == 1, filas_chips)
    comprobar("C1 no queda la tarjeta Filtros",
              not js('!!document.getElementById("R43000000000001840")'))

    todas = filas()
    comprobar("C1 la lista trae articulos", len(todas) > 0, len(todas))

    def espera_filas(cond, s=70):
        """Espera a que la lista refrescada cumpla la condicion (el ADB tarda)."""
        f = time.time() + s
        r = filas()
        while time.time() < f:
            r = filas()
            if r is not None and cond(r):
                return r
            time.sleep(1)
        return r

    # ---------------------------------------------------------------- C2
    chip("Productos", "P40_F_TIPO", "PRODUCTO")
    esperar('apex.item("P40_F_TIPO").getValue() === "PRODUCTO"', 30)
    prod = espera_filas(lambda r: len(r) > 0 and all("PRODUCTO" in f for f in r))
    comprobar("C2 Productos filtra por tipo",
              len(prod) > 0 and all("PRODUCTO" in f for f in prod), prod)
    comprobar("C2 Productos deja menos filas que Todos", len(prod) < len(todas),
              "%d de %d" % (len(prod), len(todas)))

    chip("Servicios", "P40_F_TIPO", "SERVICIO")
    esperar('apex.item("P40_F_TIPO").getValue() === "SERVICIO"', 30)
    serv = espera_filas(lambda r: len(r) > 0 and all("SERVICIO" in f for f in r))
    comprobar("C2 Servicios filtra por tipo",
              len(serv) > 0 and all("SERVICIO" in f for f in serv), serv)

    # ---------------------------------------------------------------- C3 (estado)
    # No hay articulos inactivos: el filtro se demuestra dejando la lista vacia.
    chip("Inactivos", "P40_F_ESTADO", "INACTIVO")
    esperar('apex.item("P40_F_ESTADO").getValue() === "INACTIVO"', 30)
    inac = espera_filas(lambda r: len(r) == 0)
    comprobar("C3 Inactivos deja la lista vacia (no hay inactivos)", len(inac) == 0, inac)

    chip("Activos", "P40_F_ESTADO", "ACTIVO")
    esperar('apex.item("P40_F_ESTADO").getValue() === "ACTIVO"', 30)
    act = espera_filas(lambda r: len(r) > 0 and all("ACTIVO" in f for f in r))
    comprobar("C3 Activos vuelve a traer los articulos",
              len(act) > 0 and all("ACTIVO" in f for f in act), len(act))

    # ---------------------------------------------------------------- C4 (combinacion)
    chip("Productos", "P40_F_TIPO", "PRODUCTO")
    esperar('apex.item("P40_F_TIPO").getValue() === "PRODUCTO"', 30)
    comb = espera_filas(lambda r: len(r) > 0 and all("PRODUCTO" in f for f in r))
    comprobar("C4 Productos + Activos conserva las dos condiciones",
              js('apex.item("P40_F_TIPO").getValue()') == "PRODUCTO"
              and js('apex.item("P40_F_ESTADO").getValue()') == "ACTIVO",
              "%s / %s" % (js('apex.item("P40_F_TIPO").getValue()'),
                           js('apex.item("P40_F_ESTADO").getValue()')))
    comprobar("C4 la lista sigue filtrada por producto y activo",
              len(comb) > 0 and all("PRODUCTO" in f and "ACTIVO" in f for f in comb), comb)

    # ---------------------------------------------------------------- C5
    activos = js('(function(){var r={};document.querySelectorAll(".spx-filtro.is-active")'
                 '.forEach(function(a){var it=a.getAttribute("data-item");r[it]=(r[it]||0)+1;});'
                 'return r;})()') or {}
    comprobar("C5 un solo chip activo por fila",
              all(v == 1 for v in activos.values()) and len(activos) == 2, activos)

    # vuelve a Todos para dejar la pagina neutra
    chip("Todos")

    # ---------------------------------------------------------------- C6
    js('window.location.href="%s/f?p=100:40:%s"' % (BASE, ses.group(1)))
    esperar('document.readyState === "complete" && !!window.apex', 60)
    time.sleep(2)
    boton = ('(function(){var b=[...document.querySelectorAll("button,a")]'
             '.find(function(x){return /nuevo art/i.test(x.textContent);});'
             'if(!b){return "NO";}b.click();return "OK";})()')
    comprobar("C6 hay boton Nuevo articulo", js(boton) == "OK")
    esperar('(function(){var v=apex.item("P40_CODIGO").getValue();return !!v && /^(PROD|SERV)-[0-9]{5}$/.test(v);})()', 40)
    cod = js('apex.item("P40_CODIGO").getValue()')
    bar = js('apex.item("P40_CODIGO_BARRAS").getValue()')
    comprobar("C6 el codigo interno se propone solo",
              bool(re.match(r"^(PROD|SERV)-[0-9]{5}$", cod or "")), cod)
    comprobar("C6 el codigo de barras se propone solo",
              bool(re.match(r"^[0-9]{8}$", bar or "")), bar)
    comprobar("C6 el codigo interno es de solo lectura",
              js('(function(){var e=document.getElementById("P40_CODIGO");'
                 'return !!(e && (e.readOnly || e.getAttribute("aria-readonly")==="true" ||'
                 ' e.classList.contains("apex-item-text-readonly")));})()'))

    # ---------------------------------------------------------------- C7 (guardar de verdad)
    # OJO (2026-11-23): cambiar el TIPO ahora envia la pagina (el codigo interno se
    # repropone en el servidor, porque una accion dinamica no puede escribir un
    # item de solo lectura). Por eso primero se teclea y despues se cambia el tipo.
    js('(function(){'
       'function pon(i,v){try{apex.item(i).setValue(v);}catch(e){}}'
       'pon("P40_NOMBRE","PRUEBA CHIPS");'
       'pon("P40_PRECIO_SUGERIDO",10);'
       'pon("P40_IMPUESTO_APLICABLE",16);'
       'return true;})()')
    js('(function(){var el=document.getElementById("P40_TIPO");'
       'el.value="SERVICIO";el.dispatchEvent(new Event("change",{bubbles:true}));})()')
    time.sleep(6)
    esperar('document.readyState === "complete" && apex.item("P40_NOMBRE").getValue() === "PRUEBA CHIPS"', 45)
    js('(function(){'
       'var b=document.querySelector("[data-otel-label=\\"BTN_GUARDAR_ARTICULO\\"]")'
       '  || [...document.querySelectorAll("button,a")].find(function(x){return /^guardar$/i.test(x.textContent.trim());});'
       'if(b){b.click();}return true;})()')
    guardado = esperar("""(function(){
        var t = document.body.innerText;
        return /PRUEBA CHIPS/i.test(t) && !/Se ha producido/i.test(t);
    })()""", 90)
    if not guardado:
        print("        aviso en pantalla:", (js('(document.body.innerText||"").slice(0,400)') or "").replace("\n", " | "))
    cur.execute("""select codigo, codigo_barras from producto_servicio
                    where id_empresa = 1 and nombre = 'PRUEBA CHIPS'""")
    fila = cur.fetchone()
    comprobar("C7 el articulo se guarda y la base le pone el codigo",
              bool(fila) and bool(re.match(r"^SERV-[0-9]{5}$", fila[0] or ""))
              and bool(re.match(r"^[0-9]{8}$", fila[1] or "")), fila)
    cur.execute("delete from producto_servicio where id_empresa = 1 and nombre = 'PRUEBA CHIPS'")
    conn.commit()

    js('(function(){var b=[...document.querySelectorAll("button,a")]'
       '.find(function(x){return /cancelar/i.test(x.textContent);});if(b){b.click();}return true;})()')
    time.sleep(1)
    js('window.print = function(){};')
    cmd("Page.captureScreenshot", format="png")
    img = cmd("Page.captureScreenshot", format="png").get("data")
    if img:
        import base64
        destino = os.path.join(RAIZ, "deploy", "resultados", "20261123_articulos_chips.png")
        open(destino, "wb").write(base64.b64decode(img))
        print("  captura:", destino)

finally:
    try:
        ws.close()
    except Exception:
        pass
    proc.terminate()
    # El articulo de prueba se borra, pero su codigo ya consumio el contador:
    # se deja cada serie del catalogo en su maximo real (2026-11-23).
    for tipo in ("ARTICULO", "PROD", "SERV"):
        cur.execute("""update folio_contador set ultimo = fn_maximo_real(1, :t)
                        where id_empresa = 1 and tipo = :t""", t=tipo)
    conn.commit()
    borrar_usuario()
    conn.close()

print("RESULTADO: FALLAS=%d" % len(fallas))
if fallas:
    print("fallos:", fallas)
sys.exit(1 if fallas else 0)
