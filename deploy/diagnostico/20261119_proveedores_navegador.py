"""Modulo de Proveedores (paginas 22 y 23), con navegador real.

  P1  la lista (22) abre y trae el boton de alta
  P2  «Nuevo proveedor» guarda y la fila aparece en la lista
  P3  la fila guarda los datos (RIF, retencion, SPE, dias de credito)
  P4  «Editar» abre el dialogo con los valores guardados
  P5  un RIF invalido se rechaza y no crea nada
  P6  el menu trae «Proveedores»
  P7  una persona natural (Venezolano) se guarda: V-4666778-9 es un RIF valido
      (2026-11-19; antes el combo pasaba la letra «V» como tipo de persona y la
      validacion lo rechazaba siempre)

Uso: python deploy/diagnostico/20261119_proveedores_navegador.py
Sale con codigo 1 si hay fallas. Crea y borra su propio usuario y proveedor.
"""
import json, os, re, subprocess, sys, tempfile, time, urllib.request
import oracledb

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.path.insert(0, r"C:\Users\luism\OneDrive\Documents\Apex_luis\deploy\conexion")
from verificar_conexion import CONNECT_STRING, credenciales

EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
BASE = "https://gfd7e2575d251ae-sypexsql.adb.mx-monterrey-1.oraclecloudapps.com/ords"
USUARIO, CLAVE = "diag.prov", "Diag#2026"
NOMBRE = "Proveedor Prueba ZZ"
RIF = "J-99999999-9"
NOMBRE_N = "Proveedor Natural ZZ"
RIF_N = "V-4666778-9"
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
cur.execute("delete from proveedores where razon_social in (:n, :n2)", n=NOMBRE, n2=NOMBRE_N)
con.commit()
cur.execute("begin delete from usuario_empresa where usuario_id in "
            "(select usuario_id from usuario where upper(username)='DIAG.PROV'); commit; "
            "delete from usuario where upper(username)='DIAG.PROV'; commit; end;")
cur.execute("""insert into usuario (username,email,password_hash,estado,id_empresa,rol_id,
                 debe_cambiar_clave,reintentos_fallidos)
               values ('diag.prov','diag.prov@synpex.local',
                 sypex_hash_password('Diag#2026'),'ACTIVO',1,
                 (select id_rol from syn_roles where codigo_rol='ADMIN'),'N',0)""")
con.commit()

print("== Metadatos ==")
cur.execute("select count(*) from apex_application_pages where application_id=100 and page_id in (22,23)")
comprobar("existen las paginas 22 y 23", cur.fetchone()[0] == 2)
cur.execute("""select count(*) from apex_application_page_regions
                where application_id=100 and page_id=22 and region_static_id='proveedores-lista'
                  and source_type_plugin_static_id='NATIVE_IR'""")
comprobar("la 22 tiene el Interactive Report", cur.fetchone()[0] == 1)
cur.execute("""select count(*) from apex_application_page_proc
                where application_id=100 and page_id=23 and static_id='guardar-proveedor'
                  and instr(upper(process_source),'INSERT INTO PROVEEDORES') > 0""")
comprobar("la 23 guarda en PROVEEDORES", cur.fetchone()[0] == 1)
cur.execute("""select count(*) from apex_application_list_entries
                where application_id=100 and static_id='proveedores'""")
comprobar("el menu trae Proveedores", cur.fetchone()[0] == 1)
con.close()

proc = subprocess.Popen([EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
                         "--remote-debugging-port=9284", "--window-size=1440,1000",
                         "--user-data-dir=" + os.path.join(tempfile.gettempdir(), "opencode", "edge-prov"),
                         "about:blank"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def obj():
    for _ in range(40):
        try:
            l = json.loads(urllib.request.urlopen("http://127.0.0.1:9284/json/list", timeout=2).read())
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

    # P1
    js('window.location.href="' + BASE + '/f?p=100:22:' + ses + '"')
    esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(4)
    texto = js("document.body.innerText") or ""
    comprobar("P1 la lista abre con el boton de alta", "Nuevo proveedor" in texto, texto[:80])
    comprobar("P6 el menu trae Proveedores", "Proveedores" in texto)

    # P2: alta
    js('(function(){var b=[...document.querySelectorAll("button,a")].find(function(x){'
       'return (x.getAttribute("data-otel-label")||"")==="BTN_NUEVO_PROVEEDOR";});if(b){b.click();}})()')
    time.sleep(8)
    en_if('apex.item("P23_RAZON_SOCIAL").setValue(' + json.dumps(NOMBRE) + ');'
          'apex.item("P23_RIF").setValue(' + json.dumps(RIF) + ');'
          'apex.item("P23_TIPO_RIF").setValue("J");'
          'apex.item("P23_EMAIL").setValue("proveedor@prueba.local");'
          'apex.item("P23_TELEFONO").setValue("0414-1234567");'
          'apex.item("P23_DIAS_CREDITO").setValue(15);return "OK";')
    time.sleep(2)
    js('(function(){var d=document.querySelector("iframe").contentDocument;'
       'var b=d.querySelector(\'[data-otel-label="BTN_GUARDAR_PROVEEDOR"]\');if(b){b.click();}})()')
    time.sleep(10)
    print("  dialogos abiertos:", js("document.querySelectorAll('iframe').length"))

    con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
    cur = con.cursor()
    cur.execute("alter session set current_schema = WKSP_SYPEXWS")
    cur.execute("""select id_proveedor, id_empresa, rif, razon_social, tipo_persona, cod_pais,
                          retener_iva, porcentaje_retencion, es_spe, dias_credito, estado
                     from proveedores where razon_social = :n""", n=NOMBRE)
    fila = cur.fetchone()
    comprobar("P2 el proveedor quedo guardado", fila is not None)
    if fila:
        comprobar("P3 el RIF y la empresa son los tecleados", fila[2] == RIF and fila[1] == 1, fila)
        comprobar("P3 retencion 75 por defecto y los dias tecleados",
                  float(fila[7]) == 75 and int(fila[9]) == 15, (fila[7], fila[9]))
        comprobar("P3 nace ACTIVO y sin SPE", fila[10] == "ACTIVO" and fila[8] == "N", fila)

    # P2b: la lista muestra el proveedor recien creado
    texto = js("document.body.innerText") or ""
    comprobar("P2 la lista muestra el nuevo proveedor", NOMBRE in texto)

    # P4: editar. Se busca la fila de ESTE proveedor: la base puede tener otros
    # (los del dueño), ordenados antes por razon social.
    js('(function(){var n=' + json.dumps(NOMBRE) + ';'
       'var tr=[...document.querySelectorAll("tr")].find(function(t){'
       'return (t.innerText||"").indexOf(n)>=0;});'
       'if(!tr){return "sin fila";}'
       'var a=tr.querySelector(\'a[href*="p23_id_proveedor"]\');'
       'if(a){a.click();return "ok";}return "sin enlace";})()')
    time.sleep(8)
    valores = en_if('return JSON.stringify({n: apex.item("P23_RAZON_SOCIAL").getValue(),'
                    ' r: apex.item("P23_RIF").getValue(),'
                    ' d: apex.item("P23_DIAS_CREDITO").getValue()});')
    print("  dialogo al editar:", valores)
    comprobar("P4 el dialogo trae los valores guardados",
              NOMBRE in str(valores) and RIF in str(valores) and "15" in str(valores), valores)

    # se cambia el plazo y se guarda
    en_if('apex.item("P23_DIAS_CREDITO").setValue(30);return "OK";')
    js('(function(){var d=document.querySelector("iframe").contentDocument;'
       'var b=d.querySelector(\'[data-otel-label="BTN_GUARDAR_PROVEEDOR"]\');if(b){b.click();}})()')
    time.sleep(10)
    cur.execute("select dias_credito from proveedores where razon_social = :n", n=NOMBRE)
    comprobar("P4 la edicion guarda el cambio", int(cur.fetchone()[0]) == 30)

    # P5: RIF invalido
    js('(function(){var b=[...document.querySelectorAll("button,a")].find(function(x){'
       'return (x.getAttribute("data-otel-label")||"")==="BTN_NUEVO_PROVEEDOR";});if(b){b.click();}})()')
    time.sleep(8)
    en_if('apex.item("P23_RAZON_SOCIAL").setValue("Proveedor RIF malo ZZ");'
          'apex.item("P23_RIF").setValue("123");return "OK";')
    time.sleep(2)
    js('(function(){var d=document.querySelector("iframe").contentDocument;'
       'var b=d.querySelector(\'[data-otel-label="BTN_GUARDAR_PROVEEDOR"]\');if(b){b.click();}})()')
    time.sleep(8)
    aviso = js("document.body.innerText") or ""
    cur.execute("select count(*) from proveedores where razon_social = 'Proveedor RIF malo ZZ'")
    creados = cur.fetchone()[0]
    comprobar("P5 el RIF invalido se rechaza", creados == 0, creados)
    comprobar("P5 y no se crea el proveedor", creados == 0)

    # P7: persona natural. El combo guarda la LETRA «V»; el tipo de persona es «N».
    # Con el bug, fn_rif_cliente_valido recibia «V» y rechazaba cualquier RIF natural.
    js('window.location.href="' + BASE + '/f?p=100:22:' + ses + '"')
    esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(4)
    js('(function(){var b=[...document.querySelectorAll("button,a")].find(function(x){'
       'return (x.getAttribute("data-otel-label")||"")==="BTN_NUEVO_PROVEEDOR";});if(b){b.click();}})()')
    time.sleep(8)
    en_if('apex.item("P23_RAZON_SOCIAL").setValue(' + json.dumps(NOMBRE_N) + ');'
          'apex.item("P23_TIPO_RIF").setValue("V");'
          'apex.item("P23_RIF").setValue(' + json.dumps(RIF_N) + ');'
          'apex.item("P23_DIAS_CREDITO").setValue(0);return "OK";')
    time.sleep(2)
    js('(function(){var d=document.querySelector("iframe").contentDocument;'
       'var b=d.querySelector(\'[data-otel-label="BTN_GUARDAR_PROVEEDOR"]\');if(b){b.click();}})()')
    time.sleep(10)
    cur.execute("""select id_empresa, rif, tipo_persona from proveedores
                    where razon_social = :n""", n=NOMBRE_N)
    natural = cur.fetchone()
    comprobar("P7 el proveedor persona natural se guarda", natural is not None)
    if natural:
        comprobar("P7 guarda el tipo de persona N (no la letra V)",
                  natural[2] == "N", natural)
        comprobar("P7 guarda el RIF tecleado", natural[1] == RIF_N, natural)
    con.close()
finally:
    proc.terminate()
    con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
    cur = con.cursor()
    cur.execute("alter session set current_schema = WKSP_SYPEXWS")
    cur.execute("delete from proveedores where razon_social in (:n, 'Proveedor RIF malo ZZ', :n2)",
                n=NOMBRE, n2=NOMBRE_N)
    con.commit()
    cur.execute("begin delete from usuario_empresa where usuario_id in "
                "(select usuario_id from usuario where upper(username)='DIAG.PROV'); commit; "
                "delete from usuario where upper(username)='DIAG.PROV'; commit; end;")
    con.commit()
    con.close()

print()
print("RESULTADO: FALLAS=" + str(fallas))
sys.exit(1 if fallas else 0)
