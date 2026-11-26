# -*- coding: utf-8 -*-
"""Los arreglos del 2026-11-25, en navegador real.

  N1 la nota de credito abre con Estado «PROCESADA» y la «Factura origen» con su FOLIO
  N2 en la lista de Facturacion no se ofrece «Cobrar» en una nota ni en una PENDIENTE,
     y si en una factura TIMBRADA con saldo
  N3 el «Volver» de la impresion de presupuesto (12) va a Presupuestos (5) y el de la
     factura (11) a Facturacion (8)

    python deploy/diagnostico/20261125_estados_volver_cobrar_navegador.py
"""
import base64, json, os, re, subprocess, sys, tempfile, time, urllib.request

sys.path.insert(0, r"C:\Users\luism\OneDrive\Documents\Apex_luis\deploy\conexion")
import websocket
import oracledb
from verificar_conexion import CONNECT_STRING as CS, credenciales

BASE = "https://gfd7e2575d251ae-sypexsql.adb.mx-monterrey-1.oraclecloudapps.com/ords"
EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
USUARIO = "diag.est25"
CLAVE = "Diag#2026"
PUERTO = 9287
EMPRESA = 6

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


borrar_usuario()
cur.execute("""insert into usuario (username, email, password_hash, estado, id_empresa, rol_id,
                                    debe_cambiar_clave, reintentos_fallidos)
               values (:u, :u || '@synpex.local', sypex_hash_password(:c), 'ACTIVO', :e,
                       (select id_rol from syn_roles where codigo_rol = 'ADMIN'), 'N', 0)""",
            u=USUARIO, c=CLAVE, e=EMPRESA)
conn.commit()

cur.execute("""select folio_factura from facturas
                where id_empresa = :e and tipo_documento = 'FAC' and estado = 'TIMBRADA'
                  and fn_saldo_factura(id_factura) > 0.01 order by id_factura desc fetch first 1 rows only""", e=EMPRESA)
r = cur.fetchone()
FOLIO_COBRABLE = r[0] if r else None
print("empresa %s: factura cobrable de prueba = %s" % (EMPRESA, FOLIO_COBRABLE))

proc = subprocess.Popen([EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
                         "--remote-debugging-port=%d" % PUERTO, "--window-size=1440,1000",
                         "--user-data-dir=" + os.path.join(tempfile.gettempdir(), "opencode", "edge-est25"),
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


DLG = """(function(){
  var f = document.querySelector('iframe');
  if (!f || !f.contentDocument) return 'SIN DIALOGO';
  var w = f.contentWindow, d = f.contentDocument;
  %s
})()"""

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

    js('window.location.href="%s/f?p=100:8:%s"' % (BASE, ses.group(1)))
    esperar('document.readyState === "complete" && document.querySelectorAll(".js-select-invoice").length > 0', 60)
    time.sleep(5)

    # ------------------------------------------------------------------ N2
    filas = js("""(function(){
        var tabla = [].slice.call(document.querySelectorAll("table")).filter(function(t){
            return t.querySelector("tbody tr") && t.querySelectorAll("th").length > 3; })[0];
        if (!tabla) return "SIN TABLA";
        var ths = [].slice.call(tabla.querySelectorAll("th")).map(function(t){return (t.innerText||"").trim();});
        var iF = ths.indexOf("Folio"), iC = ths.indexOf("Cobrar");
        var out = [];
        [].slice.call(tabla.querySelectorAll("tbody tr")).forEach(function(tr){
            if (tr.children.length < 3) return;
            out.push({ folio: (tr.children[iF]||{innerText:""}).innerText.trim(),
                       cobrar: (tr.children[iC]||{innerText:""}).innerText.trim() });
        });
        return JSON.stringify(out);
    })()""")
    print("  filas (folio -> cobrar):", filas)
    try:
        filas = json.loads(filas)
    except Exception:
        filas = []

    por_folio = {f["folio"]: f["cobrar"] for f in filas}
    comprobar("N2 la nota de credito NC-1 no ofrece «Cobrar»",
              por_folio.get("NC-1", "X") == "", por_folio.get("NC-1", "no esta"))
    comprobar("N2 la factura PENDIENTE F-7 no ofrece «Cobrar»",
              por_folio.get("F-7", "X") == "", por_folio.get("F-7", "no esta"))
    if FOLIO_COBRABLE:
        comprobar("N2 la factura TIMBRADA con saldo si ofrece «Cobrar»",
                  "Cobrar" in str(por_folio.get(FOLIO_COBRABLE, "")), por_folio.get(FOLIO_COBRABLE, "no esta"))

    # ------------------------------------------------------------------ N1
    # Se abre la nota desde el reporte (17): su «Ver» es un enlace de dialogo, igual
    # que el de la lista de la 8 pero sin el clon del encabezado fijo por medio.
    js('window.location.href="%s/f?p=100:17:%s"' % (BASE, ses.group(1)))
    esperar('document.readyState === "complete" && !!window.apex && !!apex.item("P17_MODULO")', 60)
    time.sleep(4)
    js('(function(){apex.item("P17_MODULO").setValue("VENTAS");'
       'document.getElementById("P17_MODULO").dispatchEvent(new Event("change",{bubbles:true}));'
       'apex.submit({request:"APLICAR", showProcessing:true});})()')
    time.sleep(12)
    clic = js("""(function(){
        var a = [...document.querySelectorAll("td a")].filter(function(x){
            return /p9_id_factura=2115/i.test(decodeURIComponent(x.getAttribute("href")||"")); })[0];
        if (!a) return "SIN ENLACE A LA NOTA";
        a.click();
        return "PULSADO";
    })()""")
    print("  clic en la nota:", clic)
    if esperar('(function(){var f=document.querySelector("iframe");'
               'return !!(f && f.contentDocument && f.contentDocument.getElementById("P9_ESTADO_TXT"));})()', 60):
        time.sleep(5)
        estado = js(DLG % 'return String(w.apex.item("P9_ESTADO_TXT").getValue()||"");')
        origen = js(DLG % """var e=d.getElementById("P9_ID_FACTURA_ORIGEN");
                             return e ? String(e.value) : "SIN CAMPO";""")
        print("  estado visible:", estado, "| factura origen:", origen)
        comprobar("N1 el estado de la nota dice PROCESADA", str(estado).upper() == "PROCESADA", estado)
        comprobar("N1 la factura origen muestra el FOLIO (F-5), no el id",
                  "F-5" in str(origen) and "2112" not in str(origen).replace("F-5", ""), origen)
        r = cmd("Page.captureScreenshot", format="png")
        if r.get("data"):
            with open(r"C:\Users\luism\OneDrive\Documents\Apex_luis\deploy\resultados\20261125_nota_procesada.png", "wb") as fh:
                fh.write(base64.b64decode(r["data"]))
    else:
        comprobar("N1 se abrio la nota en el dialogo", False, "no abrio")

    # ------------------------------------------------------------------ N3
    js('window.location.href="%s/f?p=100:5:%s"' % (BASE, ses.group(1)))
    esperar('document.readyState === "complete" && document.querySelectorAll(".js-select-invoice").length > 0', 60)
    time.sleep(4)
    enlace12 = js('(function(){var a=[...document.querySelectorAll("a")]'
                  '.find(x=>/p12_id_presupuesto=/i.test(decodeURIComponent(x.getAttribute("href")||"")));'
                  'return a ? decodeURIComponent(a.getAttribute("href")) : "SIN ENLACE";})()')
    if str(enlace12).startswith("http") or "/" in str(enlace12):
        js('window.location.href = %s' % json.dumps(enlace12))
        esperar('document.readyState === "complete" && !!window.apex', 60)
        time.sleep(3)
        rot12 = js("""(function(){
            var b = [].slice.call(document.querySelectorAll("button"))
                .filter(function(x){ return /Volver/i.test(x.innerText||""); })[0];
            return b ? b.innerText.trim() : "SIN BOTON";
        })()""")
        js("""(function(){
            var b = [].slice.call(document.querySelectorAll("button"))
                .filter(function(x){ return /Volver/i.test(x.innerText||""); })[0];
            if (b) { b.click(); }
        })()""")
        esperar('document.readyState === "complete" && !!window.apex', 60)
        time.sleep(4)
        url = str(js("window.location.href"))
        print("  boton 12:", rot12, "| url:", url[:90])
        comprobar("N3 la impresion de presupuesto vuelve a Presupuestos",
                  re.search(r":5:|/presupuestos", url) is not None, url)
    else:
        comprobar("N3 hay enlace de impresion de presupuesto", False, enlace12)

    js('window.location.href="%s/f?p=100:8:%s"' % (BASE, ses.group(1)))
    esperar('document.readyState === "complete" && document.querySelectorAll(".js-select-invoice").length > 0', 60)
    time.sleep(4)
    enlace11 = js('(function(){var a=[...document.querySelectorAll("a")]'
                  '.find(x=>/p11_id_factura=/i.test(decodeURIComponent(x.getAttribute("href")||"")));'
                  'return a ? decodeURIComponent(a.getAttribute("href")) : "SIN ENLACE";})()')
    if str(enlace11).startswith("http") or "/" in str(enlace11):
        js('window.location.href = %s' % json.dumps(enlace11))
        esperar('document.readyState === "complete" && !!window.apex', 60)
        time.sleep(3)
        js("""(function(){
            var b = [].slice.call(document.querySelectorAll("button"))
                .filter(function(x){ return /Volver/i.test(x.innerText||""); })[0];
            if (b) { b.click(); }
        })()""")
        esperar('document.readyState === "complete" && !!window.apex', 60)
        time.sleep(4)
        url = str(js("window.location.href"))
        print("  url tras el Volver de la 11:", url[:90])
        comprobar("N3 la impresion de factura vuelve a Facturacion",
                  re.search(r":8:|/facturacion", url) is not None, url)
    else:
        comprobar("N3 hay enlace de impresion de factura", False, enlace11)

finally:
    try:
        proc.terminate()
    except Exception:
        pass
    borrar_usuario()

print()
print("RESULTADO: FALLAS=%d" % len(fallas))
for f in fallas:
    print("   -", f)
sys.exit(1 if fallas else 0)
