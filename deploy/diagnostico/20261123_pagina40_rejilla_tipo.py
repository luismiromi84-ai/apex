# -*- coding: utf-8 -*-
"""Verifica en navegador real la pagina 40: grid, Nuevo y codigo por tipo."""
import json, os, re, subprocess, sys, tempfile, time, urllib.request

sys.path.insert(0, r"C:\Users\luism\OneDrive\Documents\Apex_luis\deploy\conexion")
import websocket
import oracledb
from verificar_conexion import CONNECT_STRING as CS, credenciales

BASE = ("https://gfd7e2575d251ae-sypexsql.adb.mx-monterrey-1.oraclecloudapps.com/ords")
EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
USUARIO = "diag.p40"
CLAVE = "Diag#2026"
PUERTO = 9294

fallas = []


def comprobar(nombre, ok, detalle=""):
    print(("  OK  " if ok else "  MAL ") + nombre + (("  -> " + str(detalle)) if detalle else ""))
    if not ok:
        fallas.append(nombre)


conn = oracledb.connect(user=credenciales()["DB_USER"], password=credenciales()["DB_PASSWORD"], dsn=CS)
cur = conn.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")


def borrar():
    cur.execute("""begin
                     for r in (select usuario_id from usuario where upper(username) = :u) loop
                         delete from usuario_empresa where usuario_id = r.usuario_id;
                         commit;
                         delete from usuario where usuario_id = r.usuario_id;
                         commit;
                     end loop;
                   end;""", u=USUARIO.upper())
    conn.commit()


borrar()
cur.execute("""insert into usuario (username, email, password_hash, estado, id_empresa, rol_id,
                                    debe_cambiar_clave, reintentos_fallidos)
               values (:u, :u || '@synpex.local', sypex_hash_password(:c), 'ACTIVO', 1,
                       (select id_rol from syn_roles where codigo_rol = 'ADMIN'), 'N', 0)""",
            u=USUARIO, c=CLAVE)
conn.commit()

proc = subprocess.Popen([EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
                         "--remote-debugging-port=%d" % PUERTO, "--window-size=1440,1000",
                         "--user-data-dir=" + os.path.join(tempfile.gettempdir(), "opencode", "edge-p40"),
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
    raise SystemExit("no hay navegador")


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
        return "EXC: " + str(r["exceptionDetails"].get("exception", {}).get("description"))[:300]
    return r.get("result", {}).get("value")


def esperar(c, s=60):
    f = time.time() + s
    while time.time() < f:
        v = js(c)
        if v and not (isinstance(v, str) and v.startswith("EXC:")):
            return True
        time.sleep(0.5)
    return False


def valor(it):
    return js('apex.item("%s").getValue()' % it)


def caja(it):
    """devuelve {left, top, width} del campo, para comprobar la rejilla."""
    return js('(function(){var e=document.getElementById("%s");'
              'var c=e.closest(".col")||e;var r=c.getBoundingClientRect();'
              'return {l:Math.round(r.left),t:Math.round(r.top),w:Math.round(r.width)};})()' % it)


try:
    js('window.location.href="%s/f?p=100:9999"' % BASE)
    esperar('document.readyState === "complete" && document.getElementById("P9999_USERNAME")', 40)
    js('(function(){apex.item("P9999_USERNAME").setValue(%s);apex.item("P9999_PASSWORD").setValue(%s);'
       'var b=[...document.querySelectorAll("button")].find(x=>/sign in|iniciar|entrar/i.test(x.innerText));'
       'if(b){b.click();}})()' % (json.dumps(USUARIO), json.dumps(CLAVE)))
    esperar('!!window.apex && document.readyState === "complete" && /session=\\d+/.test(location.href)', 60)
    ses = re.search(r"session=(\d+)", js("window.location.href") or "")
    if not ses:
        raise SystemExit("sin sesion")
    comprobar("P0 login", True)

    js('window.location.href="%s/f?p=100:40:%s"' % (BASE, ses.group(1)))
    esperar('document.readyState === "complete" && !!window.apex', 60)
    time.sleep(3)

    # ---------------------------------------------------------------- rejilla
    nombre = caja("P40_NOMBRE")
    iva = caja("P40_IMPUESTO_APLICABLE")
    estado = caja("P40_ESTADO")
    tipo = caja("P40_TIPO")
    precio = caja("P40_PRECIO_SUGERIDO")
    print("  cajas:", dict(nombre=nombre, iva=iva, estado=estado, tipo=tipo, precio=precio))
    comprobar("P1 el IVA va en la fila de Tipo/Precio",
              bool(iva) and bool(tipo) and iva["t"] == tipo["t"] == precio["t"], (tipo, precio, iva))
    comprobar("P1 el IVA cae debajo del Nombre (mitad derecha)",
              bool(iva) and bool(nombre) and iva["l"] == nombre["l"], (nombre, iva))
    comprobar("P1 el Estado va al lado del IVA, sin hueco",
              bool(estado) and bool(iva) and estado["t"] == iva["t"] and estado["l"] > iva["l"], (iva, estado))
    comprobar("P1 la fila 2 suma 12 columnas",
              bool(estado) and abs((estado["l"] + estado["w"]) - (nombre["l"] + nombre["w"])) <= 2,
              (estado["l"] + estado["w"], nombre["l"] + nombre["w"]))

    # ---------------------------------------------------------------- Nuevo limpia
    js('(function(){var a=[...document.querySelectorAll(".spx-filtro")]'
       '.find(function(x){return x.textContent.trim()==="Productos";});if(a){a.click();}})()')
    time.sleep(8)
    js('(function(){var a=document.querySelector("#R43000000000001800 .a-IRR-table tbody tr td a");'
       'if(a){a.click();}})()')
    esperar('document.readyState === "complete" && apex.item("P40_ID_ARTICULO").getValue() != ""', 60)
    time.sleep(3)
    comprobar("P2 abre un Producto", valor("P40_TIPO") == "PRODUCTO", valor("P40_TIPO"))

    js('(function(){var b=[...document.querySelectorAll("button")]'
       '.find(x=>x.textContent.trim().indexOf("Nuevo art") >= 0);if(b){b.click();}})()')
    esperar('document.readyState === "complete" && apex.item("P40_ID_ARTICULO").getValue() === ""', 60)
    time.sleep(3)
    # 2026-11-24 (dueno): el tipo nace vacio y no se propone codigo hasta elegirlo.
    comprobar("P2 Nuevo deja el tipo vacio (lo limpia)", (valor("P40_TIPO") or "") == "", valor("P40_TIPO"))
    comprobar("P2 Nuevo limpia el nombre", (valor("P40_NOMBRE") or "") == "", valor("P40_NOMBRE"))
    comprobar("P2 Nuevo deja el estado en Activo", valor("P40_ESTADO") == "ACTIVO", valor("P40_ESTADO"))
    comprobar("P2 sin tipo no se propone codigo", (valor("P40_CODIGO") or "") == "", valor("P40_CODIGO"))

    # ---------------------------------------------------------------- el codigo sigue al tipo
    js('(function(){var el=document.getElementById("P40_TIPO");'
       'el.value="PRODUCTO";el.dispatchEvent(new Event("change",{bubbles:true}));})()')
    time.sleep(10)
    comprobar("P3 al cambiar a Producto el codigo pasa a PROD-",
              str(valor("P40_CODIGO")).startswith("PROD-"), valor("P40_CODIGO"))
    comprobar("P3 el tipo quedo en Producto", valor("P40_TIPO") == "PRODUCTO", valor("P40_TIPO"))

    js('(function(){var el=document.getElementById("P40_TIPO");'
       'el.value="SERVICIO";el.dispatchEvent(new Event("change",{bubbles:true}));})()')
    time.sleep(10)
    comprobar("P3 al volver a Servicio el codigo pasa a SERV-",
              str(valor("P40_CODIGO")).startswith("SERV-"), valor("P40_CODIGO"))

    # ---------------------------------------------------------------- editar no se pisa
    js('window.location.href="%s/f?p=100:40:%s"' % (BASE, ses.group(1)))
    esperar('document.readyState === "complete" && !!window.apex', 60)
    time.sleep(3)
    js('(function(){var a=document.querySelector("#R43000000000001800 .a-IRR-table tbody tr td a");'
       'if(a){a.click();}})()')
    esperar('document.readyState === "complete" && apex.item("P40_ID_ARTICULO").getValue() != ""', 60)
    time.sleep(3)
    id0 = valor("P40_ID_ARTICULO")
    cod0 = valor("P40_CODIGO")
    js('apex.item("P40_NOMBRE").setValue("NOMBRE TECLEADO")')
    js('(function(){var el=document.getElementById("P40_TIPO");'
       'el.value=(el.value==="PRODUCTO"?"SERVICIO":"PRODUCTO");'
       'el.dispatchEvent(new Event("change",{bubbles:true}));})()')
    time.sleep(10)
    comprobar("P4 al cambiar el tipo en una edicion no se pierde lo tecleado",
              valor("P40_NOMBRE") == "NOMBRE TECLEADO", valor("P40_NOMBRE"))
    comprobar("P4 el codigo del articulo editado no cambia", valor("P40_CODIGO") == cod0, (cod0, valor("P40_CODIGO")))
    comprobar("P4 sigue siendo el mismo articulo", valor("P40_ID_ARTICULO") == id0, valor("P40_ID_ARTICULO"))
finally:
    proc.terminate()
    try:
        borrar()
    except Exception as e:
        print("limpieza", e)
    conn.close()

print("RESULTADO: FALLAS=%d" % len(fallas))
if fallas:
    print("fallas:", fallas)
sys.exit(1 if fallas else 0)
