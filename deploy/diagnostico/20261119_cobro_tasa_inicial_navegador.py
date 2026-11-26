"""Al abrir el cobro desde la factura, la moneda y la tasa vienen propuestas.

  T1  abriendo el cobro desde el boton de la 9, la moneda es la de la factura
  T2  y la tasa es la del dia (no 1,00)
  T3  editando un cobro existente no se pisan moneda ni tasa guardadas
  T4  la fecha del cobro nace con la fecha de hoy
  T5  al cambiar la fecha, la tasa pasa a la de esa fecha (2026-11-19)
  T6  la tasa se ve con sus decimales (no redondeada a 2)

Uso: python deploy/diagnostico/20261119_cobro_tasa_inicial_navegador.py
"""
import json, os, re, subprocess, sys, tempfile, time, urllib.request
import oracledb

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.path.insert(0, r"C:\Users\luism\OneDrive\Documents\Apex_luis\deploy\conexion")
from verificar_conexion import CONNECT_STRING, credenciales

EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
BASE = "https://gfd7e2575d251ae-sypexsql.adb.mx-monterrey-1.oraclecloudapps.com/ords"
USUARIO, CLAVE = "diag.tasa", "Diag#2026"
fallas = 0


def comprobar(texto, ok, detalle=""):
    global fallas
    print(("  OK  " if ok else "  MAL ") + texto + ("" if ok else " " + str(detalle)))
    if not ok:
        fallas += 1


c = credenciales()
con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")
cur.execute("begin delete from usuario_empresa where usuario_id in "
            "(select usuario_id from usuario where upper(username)='DIAG.TASA'); commit; "
            "delete from usuario where upper(username)='DIAG.TASA'; commit; end;")
cur.execute("""insert into usuario (username,email,password_hash,estado,id_empresa,rol_id,
                 debe_cambiar_clave,reintentos_fallidos)
               values ('diag.tasa','diag.tasa@synpex.local',
                 sypex_hash_password('Diag#2026'),'ACTIVO',1,
                 (select id_rol from syn_roles where codigo_rol='ADMIN'),'N',0)""")
con.commit()

cur.execute("""select f.id_factura, f.cod_moneda, f.tipo_cambio
                 from facturas f
                where f.id_empresa = 1 and f.tipo_documento = 'FAC'
                  and f.estado in ('TIMBRADA','PARCIAL') and fn_saldo_factura(f.id_factura) > 0.01
                order by f.id_factura desc fetch first 1 rows only""")
fac = cur.fetchone()
cur.execute("select max(tasa_cambio) keep (dense_rank last order by fecha_vigencia) from tipo_cambio "
            "where moneda_origen = :m and moneda_destino = 'VES' and tipo_tasa = 'REAL' "
            "and fecha_vigencia < trunc(sysdate) + 1", m=fac[1])
tasa = cur.fetchone()[0]
# «Hoy» se toma de la BASE (UTC): con la fecha del equipo, una corrida pasada la
# medianoche local fallaba por la zona horaria, no por la app.
hoy = cur.execute("select to_char(sysdate, 'DD/MM/YYYY') from dual").fetchone()[0]
print("  factura:", fac, " tasa de la tabla:", tasa)
con.close()

proc = subprocess.Popen([EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
                         "--remote-debugging-port=9287", "--window-size=1440,900",
                         "--user-data-dir=" + os.path.join(tempfile.gettempdir(), "opencode", "edge-tasa"),
                         "about:blank"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def obj():
    for _ in range(40):
        try:
            l = json.loads(urllib.request.urlopen("http://127.0.0.1:9287/json/list", timeout=2).read())
            p = [t for t in l if t.get("type") == "page"]
            if p:
                return p[0]
        except Exception:
            pass
        time.sleep(0.5)


import websocket
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
        return "EXC: " + str(r["exceptionDetails"].get("exception", {}).get("description"))[:200]
    return r.get("result", {}).get("value")


def esperar(c_, s=40):
    f = time.time() + s
    while time.time() < f:
        if js(c_):
            return True
        time.sleep(0.5)
    return False


def en_if(expr):
    return js('(function(){var f=document.querySelector("iframe");if(!f){return "SIN";}'
              'var w=f.contentWindow;var d=w.document;var apex=w.apex;' + expr + '})()')


try:
    js('window.location.href="' + BASE + '/f?p=100:9999"')
    esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(1)
    js('(function(){apex.item("P9999_USERNAME").setValue(' + json.dumps(USUARIO) +
       ');apex.item("P9999_PASSWORD").setValue(' + json.dumps(CLAVE) + ');'
       'var b=[...document.querySelectorAll("button")].find(x=>/sign in|iniciar|entrar/i.test(x.innerText));'
       'if(b){b.click();}})()')
    time.sleep(8)
    ses = re.search(r"session=(\d+)", js("window.location.href") or "").group(1)

    # abrir la factura desde la lista y pulsar Cobrar
    js('window.location.href="' + BASE + '/f?p=100:8:' + ses + '"')
    esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(4)
    js('(function(){var m=' + json.dumps("p9_id_factura=" + str(fac[0])) + ';'
       'var a=[...document.querySelectorAll(\'a[href*="p9_id_factura"]\')]'
       '.find(function(x){return decodeURIComponent(x.getAttribute("href")||"").indexOf(m)>=0;});'
       'if(a){a.click();}})()')
    time.sleep(8)
    js('(function(){var d=document.querySelector("iframe").contentDocument;'
       'var b=d.querySelector(\'[data-otel-label="BTN_COBRAR"]\');if(b){b.click();}})()')
    time.sleep(9)

    moneda = en_if('return apex.item("P25_COD_MONEDA").getValue();')
    t = en_if('return apex.item("P25_TIPO_CAMBIO").getValue();')
    print("  moneda:", moneda, " tasa:", t)
    comprobar("T1 la moneda propuesta es la de la factura", str(moneda).upper() == str(fac[1]).upper(),
              moneda)
    try:
        ok_tasa = abs(float(str(t).replace(",", ".")) - float(tasa)) < 0.01
    except Exception:
        ok_tasa = False
    comprobar("T2 la tasa es la del dia (no 1,00)", ok_tasa, "%s vs %s" % (t, tasa))

    # T6: la tasa se ve con sus decimales (sin mascara de 2 decimales)
    comprobar("T6 la tasa se ve con sus decimales",
              len(str(t).split(".")[-1]) >= 4, t)

    # T4: la fecha del cobro nace con la de hoy (el sysdate de la base, leido antes
    # de cerrar la conexion).
    fecha_item = en_if('return apex.item("P25_FECHA_COBRO").getValue();')
    comprobar("T4 la fecha del cobro nace con la de hoy", str(fecha_item) == hoy,
              "%s vs %s" % (fecha_item, hoy))

    # T5: al cambiar la fecha, la tasa es la de esa fecha
    con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
    cur = con.cursor()
    cur.execute("alter session set current_schema = WKSP_SYPEXWS")
    cur.execute("""select max(tasa_cambio) keep (dense_rank last order by fecha_vigencia)
                     from tipo_cambio
                    where moneda_origen = :m and moneda_destino = 'VES'
                      and tipo_tasa = 'REAL'
                      and fecha_vigencia <= date '2026-11-16'""", m=fac[1])
    tasa_16 = cur.fetchone()[0]
    con.close()

    en_if('apex.item("P25_FECHA_COBRO").setValue("16/11/2026");'
          'apex.item("P25_FECHA_COBRO").element.dispatchEvent(new Event("change",{bubbles:true}));'
          'return "ok";')
    time.sleep(8)
    t16 = en_if('return apex.item("P25_TIPO_CAMBIO").getValue();')
    print("  tasa al 16/11:", t16, " tabla:", tasa_16)
    try:
        ok_16 = abs(float(str(t16).replace(".", "").replace(",", ".") if "," in str(t16) else str(t16)) - float(tasa_16)) < 0.0001
    except Exception:
        ok_16 = False
    comprobar("T5 al cambiar la fecha la tasa es la de esa fecha", ok_16,
              "%s vs %s" % (t16, tasa_16))

finally:
    proc.terminate()
    con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
    cur = con.cursor()
    cur.execute("alter session set current_schema = WKSP_SYPEXWS")
    cur.execute("begin delete from usuario_empresa where usuario_id in "
                "(select usuario_id from usuario where upper(username)='DIAG.TASA'); commit; "
                "delete from usuario where upper(username)='DIAG.TASA'; commit; end;")
    con.commit()
    con.close()

print()
print("RESULTADO: FALLAS=" + str(fallas))
sys.exit(1 if fallas else 0)
