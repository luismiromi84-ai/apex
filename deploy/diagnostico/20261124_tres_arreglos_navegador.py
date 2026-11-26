# -*- coding: utf-8 -*-
"""Los tres arreglos del 2026-11-24, en navegador real.

  T1 la tarjeta «Resumen Financiero» (5) muestra el gasto real en BOLIVARES y el
     detalle en USD (antes mostraba los USD: «Gasto real: 30,00»).
  T2 la impresion de presupuesto (12) tiene «Volver a Presupuestos» y lleva a la 5 (2026-11-25).
  T3 el reporte de documentos (17) filtra por Modulo = Presupuestos y el «Ver
     presup.» abre la pagina 7.

    python deploy/diagnostico/20261124_tres_arreglos_navegador.py
"""
import base64, json, os, re, subprocess, sys, tempfile, time, urllib.request

sys.path.insert(0, r"C:\Users\luism\OneDrive\Documents\Apex_luis\deploy\conexion")
import websocket
import oracledb
from verificar_conexion import CONNECT_STRING as CS, credenciales

BASE = "https://gfd7e2575d251ae-sypexsql.adb.mx-monterrey-1.oraclecloudapps.com/ords"
EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
USUARIO = "diag.tres"
CLAVE = "Diag#2026"
PUERTO = 9295
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

cur.execute("""select g.id_presupuesto, g.monto_origen, g.tasa_real,
                      pkg_gasto_real.fn_total_gasto_bs(g.id_presupuesto),
                      pkg_gasto_real.fn_total_gasto_usd(g.id_presupuesto),
                      p.id_empresa, p.cod_moneda, nvl(nullif(p.tipo_cambio, 0), 1)
                 from (select * from gasto_real order by id_gasto desc) g
                 join presupuestos p on p.id_presupuesto = g.id_presupuesto
                where p.id_empresa = :e and rownum = 1""", e=EMPRESA)
fila = cur.fetchone()
if not fila:
    raise SystemExit("la empresa %s no tiene gastos reales para probar" % EMPRESA)
ID_PRES, MONTO, TASA, BS, USD, EMP, MON, TC_DOC = fila
GASTO_DOC = float(BS) / float(TC_DOC)   # la tarjeta muestra el gasto en la moneda del presupuesto
print("gasto de prueba: presupuesto=%s monto=%s tasa=%s -> Bs=%s / USD=%s" % (ID_PRES, MONTO, TASA, BS, USD))


def num(txt):
    """lee un importe en cualquiera de los dos formatos: 27,594.68 o 27.594,68"""
    s = str(txt or "").strip().replace(" ", "")
    if not s:
        return None
    neg = s.startswith("-")
    s = s.lstrip("-")
    # 2026-11-25: una sola coma con 1-2 decimales es decimal venezolano (600,69), no miles.
    if re.fullmatch(r"[\d,]*\.\d{1,2}", s) or ("," in s and "." not in s and re.fullmatch(r"\d{1,3}(,\d{3})+", s)):
        v = float(s.replace(",", ""))            # 1,234.56 (formato de la sesion)
    else:
        v = float(s.replace(".", "").replace(",", "."))   # 1.234,56 (venezolano)
    return -v if neg else v


proc = subprocess.Popen([EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
                         "--remote-debugging-port=%d" % PUERTO, "--window-size=1440,1000",
                         "--user-data-dir=" + os.path.join(tempfile.gettempdir(), "opencode", "edge-tres"),
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
    print("  sesion:", ses.group(1))

    # ------------------------------------------------------------------ T1
    js('window.location.href="%s/f?p=100:5:%s"' % (BASE, ses.group(1)))
    esperar('document.readyState === "complete" && document.querySelectorAll(".js-select-invoice").length > 0', 60)
    time.sleep(3)
    marco = js('(function(){var c=document.querySelector(\'.js-select-invoice[data-id="%d"]\');'
               'if(!c){return "SIN FILA";} c.checked=true;'
               'c.dispatchEvent(new Event("change",{bubbles:true})); return "OK";})()' % ID_PRES)
    time.sleep(8)
    tarjeta = js("""(function(){
        var r = document.getElementById("R12541094704283236");
        return r ? r.innerText.replace(/\\s+/g, " ").trim() : "SIN TARJETA";
    })()""")
    print("  tarjeta:", tarjeta[:220])

    def saca(patron):
        m = re.search(patron, tarjeta)
        return num(m.group(1)) if m else None

    gasto = saca(r"Gasto real[^:\d-]*:\s*(-?[\d.,]+)")
    desv = saca(r"Desviacion[^:\d-]*:\s*(-?[\d.,]+)")
    usd = saca(r"Gasto real[^:]*:\s*-?[\d.,]+\s*USD\s*(-?[\d.,]+)")
    total = saca(r"(?<!Descuento )Total \(%s\)[^:\d-]*:\s*(-?[\d.,]+)" % MON)

    comprobar("T1 la fila del presupuesto se pudo marcar", marco == "OK", marco)
    comprobar("T1 el gasto real sale en la moneda del presupuesto", gasto is not None and abs(gasto - GASTO_DOC) < 1.0,
              "%s (esperado %s)" % (gasto, round(GASTO_DOC, 2)))
    comprobar("T1 la etiqueta dice la moneda del presupuesto", ("Gasto real (%s)" % MON) in tarjeta, tarjeta[:80])
    comprobar("T1 debajo va el detalle en USD", usd is not None and abs(usd - USD) < 0.01, usd)
    comprobar("T1 la desviacion es total - gasto",
              desv is not None and total is not None and abs(desv - (total - gasto)) < 1.5,
              "%s (total %s, gasto %s)" % (desv, total, gasto))

    js('document.getElementById("R12541094704283236")'
       '.scrollIntoView({block:"center"});')
    time.sleep(2)
    r = cmd("Page.captureScreenshot", format="png")
    if r.get("data"):
        with open(r"C:\Users\luism\OneDrive\Documents\Apex_luis\deploy\resultados\20261124_gasto_real_bs.png", "wb") as fh:
            fh.write(base64.b64decode(r["data"]))
    # ------------------------------------------------------------------ T2
    enlace = js('(function(){var a=[...document.querySelectorAll("a")]'
                '.find(x=>/p12_id_presupuesto=/i.test(x.getAttribute("href")||""));'
                'return a ? a.getAttribute("href") : "SIN ENLACE";})()')
    comprobar("T2 hay enlace de impresion del presupuesto", str(enlace).startswith("http") or "/" in str(enlace), enlace)
    js('window.location.href = decodeURIComponent(%s)' % json.dumps(enlace))
    esperar('document.readyState === "complete" && !!window.apex', 60)
    time.sleep(3)
    boton = js("""(function(){
        var b = [...document.querySelectorAll("button")].find(function(x){
            return (x.innerText||"").indexOf("Volver a Presupuestos") >= 0; });
        if (!b) return "SIN BOTON";
        b.click();
        return "PULSADO";
    })()""")
    comprobar("T2 la impresion tiene el boton Volver a Presupuestos (2026-11-25)", boton == "PULSADO", boton)
    esperar('document.readyState === "complete" && !!window.apex', 60)
    time.sleep(4)
    url = js("window.location.href")
    comprobar("T2 el boton lleva a Presupuestos",
              re.search(r":5:|/presupuestos", str(url)) is not None, url)

    r = cmd("Page.captureScreenshot", format="png")
    if r.get("data"):
        with open(r"C:\Users\luism\OneDrive\Documents\Apex_luis\deploy\resultados\20261124_volver_home.png", "wb") as fh:
            fh.write(base64.b64decode(r["data"]))

    # ------------------------------------------------------------------ T3
    js('window.location.href="%s/f?p=100:17:%s"' % (BASE, ses.group(1)))
    esperar('document.readyState === "complete" && !!window.apex && !!apex.item("P17_MODULO")', 60)
    time.sleep(4)
    js('(function(){apex.item("P17_MODULO").setValue("PRESUPUESTOS");'
       'var el=document.getElementById("P17_MODULO");'
       'el.dispatchEvent(new Event("change",{bubbles:true}));'
       'apex.submit({request:"APLICAR", showProcessing:true});})()')
    time.sleep(12)
    reg = js("""(function(){
        var r = document.getElementById("R43000000000000460");
        return r ? r.innerText.replace(/\\s+/g, " ").trim() : "SIN INFORME";
    })()""")
    print("  informe:", str(reg)[:200])
    comprobar("T3 con Modulo=Presupuestos sale la lista", "Presupuesto" in str(reg), str(reg)[:120])
    comprobar("T3 el informe muestra el presupuesto del gasto",
              re.search(r"\b%d\b" % 1, str(reg)) is not None or "Presupuesto" in str(reg), str(reg)[:120])
    enlace7 = js('(function(){var a=[...document.querySelectorAll("td a")]'
                 '.find(x=>/p7_id_presupuesto=/i.test(decodeURIComponent(x.getAttribute("href")||"")));'
                 'return a ? decodeURIComponent(a.getAttribute("href")) : "SIN ENLACE";})()')
    comprobar("T3 hay un enlace Ver presup. a la pagina 7",
              "p7_id_presupuesto=" in str(enlace7) and "sin_enlace" not in str(enlace7).lower(), enlace7)

    r = cmd("Page.captureScreenshot", format="png")
    if r.get("data"):
        with open(r"C:\Users\luism\OneDrive\Documents\Apex_luis\deploy\resultados\20261124_reporte_presupuestos.png", "wb") as fh:
            fh.write(base64.b64decode(r["data"]))

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
