# -*- coding: utf-8 -*-
"""Pagina 6 «Detalle de Presupuesto»: el LOV del producto y el % del impuesto.

Comprueba en navegador real lo que reporto el dueno:
  N1 al abrir una linea NUEVA no sale ningun aviso de error y el % de IVA NO se
     queda en 16 (antes salia «No se ha podido convertir el valor de cadena que
     contiene '-' en un numero» y el % aparecia en 16).
  N2 si el item del producto lleva TEXTO (lo que hacia el Popup LOV al limpiarse)
     la pagina no revienta: no hay aviso y no se registra un error nuevo.
  N3 al elegir un articulo de verdad siguen viniendo descripcion, precio,
     impuesto y % — y los totales se calculan.
  N4 no se registro ningun error nuevo de la pagina 6 en SYN_ERROR_LOG.

    python deploy/diagnostico/20261124_p6_linea_navegador.py
"""
import base64, json, os, re, subprocess, sys, tempfile, time, urllib.request

sys.path.insert(0, r"C:\Users\luism\OneDrive\Documents\Apex_luis\deploy\conexion")
import websocket
import oracledb
from verificar_conexion import CONNECT_STRING as CS, credenciales

BASE = "https://gfd7e2575d251ae-sypexsql.adb.mx-monterrey-1.oraclecloudapps.com/ords"
EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
USUARIO = "diag.p6v"
CLAVE = "Diag#2026"
PUERTO = 9297

fallas = []


def comprobar(nombre, ok, detalle=""):
    print(("  OK  " if ok else "  MAL ") + nombre + (("  -> " + str(detalle)) if detalle else ""))
    if not ok:
        fallas.append(nombre)


conn = oracledb.connect(user=credenciales()["DB_USER"], password=credenciales()["DB_PASSWORD"], dsn=CS)
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


def max_error():
    cur.execute("select nvl(max(id_error), 0) from syn_error_log")
    return cur.fetchone()[0]


borrar_usuario()
cur.execute("""insert into usuario (username, email, password_hash, estado, id_empresa, rol_id,
                                    debe_cambiar_clave, reintentos_fallidos)
               values (:u, :u || '@synpex.local', sypex_hash_password(:c), 'ACTIVO', 1,
                       (select id_rol from syn_roles where codigo_rol = 'ADMIN'), 'N', 0)""",
            u=USUARIO, c=CLAVE)
conn.commit()

# articulo de la empresa 1 al 16 % para el camino bueno
cur.execute("""select id_producto_servicio, nombre, precio_sugerido, impuesto_aplicable
                 from (select * from producto_servicio
                        where id_empresa = 1 and nvl(estado,'ACTIVO') = 'ACTIVO'
                          and nvl(impuesto_aplicable, 0) = 16
                        order by id_producto_servicio)
                where rownum = 1""")
fila = cur.fetchone()
if not fila:
    raise SystemExit("no hay articulos al 16 % en la empresa 1")
ID_ART, NOMBRE_ART, PRECIO_ART, PCT_ART = fila
print("articulo de prueba:", fila)

err_antes = max_error()

proc = subprocess.Popen([EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
                         "--remote-debugging-port=%d" % PUERTO, "--window-size=1440,1000",
                         "--user-data-dir=" + os.path.join(tempfile.gettempdir(), "opencode", "edge-p6v"),
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


ws = websocket.create_connection(objetivo()["webSocketDebuggerUrl"], timeout=90)
ws.settimeout(90)
n = [0]

for m in ("Page.enable", "Runtime.enable"):
    cmd = None
    n[0] += 1
    ws.send(json.dumps({"id": n[0], "method": m, "params": {}}))
    while True:
        r = json.loads(ws.recv())
        if r.get("id") == n[0]:
            break


def cmd(m, **p):
    n[0] += 1
    ws.send(json.dumps({"id": n[0], "method": m, "params": p}))
    while True:
        r = json.loads(ws.recv())
        if r.get("id") == n[0]:
            return r.get("result", {})


def js(e):
    r = cmd("Runtime.evaluate", expression=e, returnByValue=True, awaitPromise=True)
    if "exceptionDetails" in r:
        d = r["exceptionDetails"]
        return "EXC: " + str(d.get("exception", {}).get("description") or d.get("text"))[:400]
    return r.get("result", {}).get("value")


def esperar(c, s=60):
    f = time.time() + s
    while time.time() < f:
        v = js(c)
        if v and not (isinstance(v, str) and v.startswith("EXC")):
            return True
        time.sleep(0.5)
    return False


DIALOGO = """(function(){
  var f = document.querySelector('iframe');
  if (!f || !f.contentDocument) return 'SIN DIALOGO';
  var w = f.contentWindow, d = f.contentDocument, apex = w.apex;
  %s
})()"""


def dlg(codigo):
    return DIALOGO % codigo


def num(txt):
    """Importe en el formato de la sesion: 1.234,56 (VE) o 1,234.56 (MX). 2026-11-25."""
    s = str(txt or "").strip().replace(" ", "")
    if not s:
        return 0.0
    if "," in s and ("." not in s or s.rfind(",") > s.rfind(".")):
        return float(s.replace(".", "").replace(",", "."))
    return float(s.replace(",", ""))


def valor(item):
    return js(dlg('return String(apex.item("%s").getValue());' % item))


def avisos():
    """Cualquier aviso de error visible: en el dialogo o en la pagina padre."""
    r = js(dlg("""
        var t = (d.body.innerText || '');
        var alerta = d.querySelector('.t-Alert--error, .a-Error, .ui-dialog-content');
        return (alerta ? alerta.innerText + ' || ' : '') + (t.indexOf('No se ha podido') >= 0 ? 'EN TEXTO' : '');
    """))
    p = js("""(function(){var a=document.querySelector('.t-Alert--error');
                 return a ? a.innerText.substring(0,200) : '';})()""")
    return (str(r or "") + " " + str(p or "")).strip()


try:
    js('window.location.href="%s/f?p=100:9999"' % BASE)
    esperar('document.readyState === "complete" && document.getElementById("P9999_USERNAME")', 45)
    js('(function(){apex.item("P9999_USERNAME").setValue(%s);apex.item("P9999_PASSWORD").setValue(%s);'
       'var b=[...document.querySelectorAll("button")].find(x=>/sign in|iniciar|entrar/i.test(x.innerText));'
       'if(b){b.click();}})()' % (json.dumps(USUARIO), json.dumps(CLAVE)))
    esperar('!!window.apex && document.readyState === "complete" && /session=\\d+/.test(location.href)', 60)
    ses = re.search(r"session=(\d+)", js("window.location.href") or "")
    if not ses:
        raise SystemExit("sin sesion")

    js('window.location.href="%s/f?p=100:5:%s"' % (BASE, ses.group(1)))
    esperar('document.readyState === "complete" && document.querySelectorAll(".js-select-invoice").length > 0', 60)
    time.sleep(3)
    js('(function(){var c=document.querySelector(".js-select-invoice");'
       'c.checked=true;c.dispatchEvent(new Event("change",{bubbles:true}));})()')
    time.sleep(2)
    js('(function(){var b=document.querySelector(\'[data-otel-label="BTN_NUEVO_DETALLE"]\');if(b){b.click();}})()')
    if not esperar('(function(){var f=document.querySelector("iframe");'
                   'return !!(f && f.contentDocument && f.contentDocument.getElementById("P6_CANTIDAD"));})()', 60):
        raise SystemExit("no abrio el dialogo de la linea")
    time.sleep(5)

    # ---------------------------------------------------------------- N1
    pct = valor("P6_PORCENTAGE_IMPUESTO")
    imp = valor("P6_ID_IMPUESTO")
    comprobar("N1 la linea nueva abre sin aviso de error", avisos() == "", avisos())
    comprobar("N1 el impuesto viene vacio", imp == "", imp)
    comprobar("N1 el % de IVA NO se queda en 16 en una linea en blanco",
              str(pct) in ("", "0", "0.00", "0,00"), pct)
    muestra = js(dlg("""var e=d.getElementById('P6_ID_PRODUCTO_SERVICIO');
                        return e ? String(e.value) : '';"""))
    comprobar("N1b el LOV sigue mostrando su texto de «sin elegir»",
              "-- Seleccione Producto/Servicio --" in str(muestra), muestra)

    # ---------------------------------------------------------------- N2
    # lo que hacia el Popup LOV al limpiarse: dejar su TEXTO como valor del item
    js(dlg("""
        var e = d.getElementById('P6_ID_PRODUCTO_SERVICIO');
        if (e) e.value = '-- Seleccione Producto/Servicio --';
        apex.item('P6_ID_PRODUCTO_SERVICIO').setValue('-- Seleccione Producto/Servicio --');
        apex.jQuery('#P6_ID_PRODUCTO_SERVICIO').trigger('change');
    """))
    time.sleep(6)
    comprobar("N2 con texto en el producto no sale ningun aviso", avisos() == "", avisos())
    comprobar("N2 no se registro un error nuevo", max_error() == err_antes,
              "id_error nuevo: %s" % max_error())

    # ---------------------------------------------------------------- N3
    js(dlg('apex.item("P6_ID_PRODUCTO_SERVICIO").setValue(%d);'
           'apex.jQuery("#P6_ID_PRODUCTO_SERVICIO").trigger("change");' % ID_ART))
    time.sleep(8)
    desc = valor("P6_DESCRIPCION")
    prec = valor("P6_PRECIO_UNITARIO")
    imp2 = valor("P6_ID_IMPUESTO")
    pct2 = valor("P6_PORCENTAGE_IMPUESTO")
    comprobar("N3 trae la descripcion del articulo", str(desc).strip() != "", desc)
    comprobar("N3 trae el precio del articulo", abs(num(prec) - float(PRECIO_ART)) < 0.01,
              "%s (esperado %s)" % (prec, PRECIO_ART))
    comprobar("N3 trae el impuesto", str(imp2).strip() != "", imp2)
    comprobar("N3 trae el % del impuesto", abs(num(pct2) - 16.0) < 0.01, pct2)

    js(dlg('apex.item("P6_CANTIDAD").setValue(2);'
           'apex.jQuery("#P6_CANTIDAD").trigger("change");'))
    time.sleep(5)
    sub = num(valor("P6_SUBTOTAL_LINEA"))
    iva = num(valor("P6_MONTO_IMPUESTO"))
    tot = num(valor("P6_MONTO_TOTAL_LINEA"))
    esperado_sub = round(2 * float(PRECIO_ART), 2)
    comprobar("N3 calcula subtotal, IVA y total",
              abs(sub - esperado_sub) < 0.02 and abs(iva - esperado_sub * 0.16) < 0.02
              and abs(tot - esperado_sub * 1.16) < 0.02,
              "subtotal=%s iva=%s total=%s (esperado %s/%s/%s)"
              % (sub, iva, tot, esperado_sub, round(esperado_sub * 0.16, 2), round(esperado_sub * 1.16, 2)))

    r = cmd("Page.captureScreenshot", format="png")
    if r.get("data"):
        with open(r"C:\Users\luism\OneDrive\Documents\Apex_luis\deploy\resultados\20261124_p6_linea.png", "wb") as fh:
            fh.write(base64.b64decode(r["data"]))
        print("  captura: deploy/resultados/20261124_p6_linea.png")

    # ---------------------------------------------------------------- N4
    comprobar("N4 ningun error nuevo en SYN_ERROR_LOG", max_error() == err_antes,
              "id_error %s -> %s" % (err_antes, max_error()))

finally:
    try:
        proc.terminate()
    except Exception:
        pass
    borrar_usuario()

print()
print("RESULTADO: FALLAS=%d" % len(fallas))
if fallas:
    for f in fallas:
        print("   -", f)
sys.exit(1 if fallas else 0)
