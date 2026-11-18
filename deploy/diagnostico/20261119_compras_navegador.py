"""Modulo de Compras (27 lista, 28 compra, 29 linea), con navegador real.

  C1  la lista (27) abre con el boton de alta y el menu trae Compras
  C2  «Nueva compra» guarda la cabecera
  C3  «Nueva linea» abre la linea, y al guardarla la compra cuadra (100 + 16 = 116)
  C4  «Registrar compra» la deja REGISTRADA, emite el comprobante y vuelve a la lista
  C5  la retencion es el 75 % del IVA en bolivares
  C6  la lista trae la compra, «Editar» la abre y un documento REGISTRADA no ofrece Guardar

Uso: python deploy/diagnostico/20261119_compras_navegador.py
Crea y borra su propio usuario, compra y retencion.
"""
import json, os, re, subprocess, sys, tempfile, time, urllib.request
import oracledb

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.path.insert(0, r"C:\Users\luism\OneDrive\Documents\Apex_luis\deploy\conexion")
from verificar_conexion import CONNECT_STRING, credenciales

EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
BASE = "https://gfd7e2575d251ae-sypexsql.adb.mx-monterrey-1.oraclecloudapps.com/ords"
USUARIO, CLAVE = "diag.compra", "Diag#2026"
FOLIO = "CMP-ZZ-1"
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

# limpieza previa
cur.execute("delete from retenciones_iva where id_compra in (select id_compra from compras where folio_factura = :f)", f=FOLIO)
con.commit()
cur.execute("delete from compras_det where id_compra in "
            "(select id_compra from compras where folio_factura = :f)", f=FOLIO)
con.commit()
cur.execute("delete from compras where folio_factura = :f", f=FOLIO)
con.commit()
cur.execute("begin delete from usuario_empresa where usuario_id in "
            "(select usuario_id from usuario where upper(username)='DIAG.COMPRA'); commit; "
            "delete from usuario where upper(username)='DIAG.COMPRA'; commit; end;")
cur.execute("""insert into usuario (username,email,password_hash,estado,id_empresa,rol_id,
                 debe_cambiar_clave,reintentos_fallidos)
               values ('diag.compra','diag.compra@synpex.local',
                 sypex_hash_password('Diag#2026'),'ACTIVO',1,
                 (select id_rol from syn_roles where codigo_rol='ADMIN'),'N',0)""")
con.commit()

cur.execute("""select p.id_proveedor, p.razon_social from proveedores p
                where p.id_empresa = 1 and nvl(p.estado,'ACTIVO') = 'ACTIVO' and rownum = 1""")
prov = cur.fetchone()
prov_creado = False
if not prov:
    cur.execute("""insert into proveedores (id_empresa, rif, razon_social, tipo_persona, cod_pais,
                       estado, retener_iva, porcentaje_retencion, es_spe, dias_credito)
                   values (1, 'J-CMP-PROV-1', 'Proveedor de prueba compras', 'J', 'VE',
                       'ACTIVO', 'S', 75, 'N', 30)""")
    con.commit()
    cur.execute("select id_proveedor, razon_social from proveedores where id_empresa=1 and rownum=1")
    prov = cur.fetchone()
    prov_creado = True
print("  proveedor de prueba:", prov)
con.close()

proc = subprocess.Popen([EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
                         "--remote-debugging-port=9283", "--window-size=1440,1000",
                         "--user-data-dir=" + os.path.join(tempfile.gettempdir(), "opencode", "edge-compra"),
                         "about:blank"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def obj():
    for _ in range(40):
        try:
            l = json.loads(urllib.request.urlopen("http://127.0.0.1:9283/json/list", timeout=2).read())
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
    mid = n[0]
    ws.send(json.dumps({"id": mid, "method": m, "params": p}))
    while True:
        r = json.loads(ws.recv())
        # los botones con confirmacion abren un confirm() del navegador: se acepta solo
        if r.get("method") == "Page.javascriptDialogOpening":
            n[0] += 1
            ws.send(json.dumps({"id": n[0], "method": "Page.handleJavaScriptDialog",
                                "params": {"accept": True}}))
            continue
        if r.get("id") == mid:
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


def boton(etiqueta):
    return js('(function(){var b=[...document.querySelectorAll("button,a")].find(function(x){'
              'return (x.getAttribute("data-otel-label")||"")===' + json.dumps(etiqueta) + ';});'
              'if(b){b.click();return "CLIC";}return "NO";})()')


def aceptar():
    """Pulsa el boton de aceptar del confirm de APEX (Cancelar es la salida)."""
    return js('(function(){var bs=[...document.querySelectorAll("button")].filter(function(b){'
              'return b.offsetParent!==null && !b.getAttribute("data-otel-label")'
              ' && (b.innerText||"").trim() && (b.innerText||"").trim()!=="Cancelar";});'
              'if(bs.length){bs[bs.length-1].click();return "ACEPTO:"+bs[bs.length-1].innerText.trim();}'
              'return "SIN CONFIRM";})()')


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

    # C1
    js('window.location.href="' + BASE + '/f?p=100:27:' + ses + '"')
    esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(4)
    texto = js("document.body.innerText") or ""
    comprobar("C1 la lista abre con el boton de alta", "Nueva compra" in texto)
    comprobar("C1 el menu trae Compras", "Compras" in texto)

    # C2
    boton("BTN_NUEVA_COMPRA")
    time.sleep(6)
    js('(function(){apex.item("P28_ID_PROVEEDOR").setValue(' + json.dumps(str(prov[0])) + ');'
       'apex.item("P28_FOLIO_FACTURA").setValue(' + json.dumps(FOLIO) + ');'
       'apex.item("P28_COD_MONEDA").setValue("VES");'
       'apex.item("P28_TIPO_CAMBIO").setValue(1);'
       'apex.item("P28_PORCENTAJE_RETENCION").setValue(75);return "OK";})()')
    time.sleep(2)
    boton("BTN_GUARDAR_COMPRA")
    time.sleep(9)

    con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
    cur = con.cursor()
    cur.execute("alter session set current_schema = WKSP_SYPEXWS")
    cur.execute("""select id_compra, estado, monto_total from compras where folio_factura = :f""", f=FOLIO)
    fila = cur.fetchone()
    comprobar("C2 la compra quedo guardada en BORRADOR", fila is not None and fila[1] == "BORRADOR", fila)
    id_compra = fila[0] if fila else None

    # C3: nueva linea
    boton("BTN_LINEA_COMPRA")
    time.sleep(9)
    # APEX sirve la pagina como URL amigable (linea-de-compra), no como f?p=100:29
    en29 = js("window.location.href") or ""
    en29 = en29 + " " + (js("document.title") or "")
    comprobar("C3 «Nueva linea» abre la pagina 29",
              ":29:" in en29 or "linea-de-compra" in en29.lower()
              or "linea de compra" in en29.lower(), en29[-60:])
    if "linea" in en29.lower():
        js('(function(){apex.item("P29_DESCRIPCION").setValue("Servicio de prueba");'
           'apex.item("P29_CANTIDAD").setValue(2);'
           'apex.item("P29_PRECIO_UNITARIO").setValue(50);'
           'var s=document.getElementById("P29_ID_IMPUESTO");'
           'if(s && s.options.length>1){apex.item("P29_ID_IMPUESTO").setValue(s.options[1].value);}'
           'apex.item("P29_PORCENTAJE_IMPUESTO").setValue(16);return "OK";})()')
        time.sleep(2)
        boton("BTN_GUARDAR_LINEA_COMPRA")
        time.sleep(9)

        cur.execute("""select subtotal, monto_impuesto, monto_total,
                              (select count(*) from compras_det where id_compra = :i) as lineas
                         from compras where id_compra = :i""", i=id_compra)
        t2 = cur.fetchone()
        print("  cabecera tras la linea:", t2)
        comprobar("C3 la linea entra y la cabecera cuadra",
                  t2 and t2[3] == 1 and float(t2[0]) == 100 and float(t2[1]) == 16 and float(t2[2]) == 116, t2)

        # C4: registrar (el boton pide confirmacion)
        boton("BTN_REGISTRAR_COMPRA")
        time.sleep(3)
        aceptar()
        time.sleep(10)
        cur.execute("select estado from compras where id_compra = :i", i=id_compra)
        comprobar("C4 la compra queda REGISTRADA", cur.fetchone()[0] == "REGISTRADA")
        # al registrar se vuelve a la lista (la 28 ya no es un dialogo)
        destino = (js("window.location.href") or "") + " " + (js("document.title") or "")
        comprobar("C4 tras registrar se vuelve a la lista",
                  "compras" in destino.lower(), destino[-60:])

        cur.execute("""select numero_comprobante, base_imponible_bs, iva_causado_bs,
                              iva_retenido_bs, estado
                         from retenciones_iva where id_compra = :i""", i=id_compra)
        ret = cur.fetchone()
        print("  retencion:", ret)
        comprobar("C4 se emitio el comprobante", ret is not None)
        if ret:
            comprobar("C5 el IVA en Bs es 16 (tasa 1)", abs(float(ret[2]) - 16) < 0.01, ret[2])
            comprobar("C5 la retencion es el 75 %", abs(float(ret[3]) - 12) < 0.01, ret[3])

        # C6: la lista trae la compra y «Editar» la abre (ya REGISTRADA, sin Guardar)
        js('window.location.href="' + BASE + '/f?p=100:27:' + ses + '"')
        esperar('document.readyState === "complete" && !!window.apex')
        time.sleep(5)
        texto = js("document.body.innerText") or ""
        comprobar("C6 la compra aparece en la lista", FOLIO in texto)
        abierto = js('(function(){var a=[...document.querySelectorAll("a")].find(function(x){'
                     'return (x.getAttribute("href")||"").indexOf("p28_id_compra")>=0;});'
                     'if(a){a.click();return "CLIC";}return "NO";})()')
        comprobar("C6 «Editar» de la lista se puede pulsar", abierto == "CLIC", abierto)
        time.sleep(9)
        folio_pantalla = js('(function(){var i=document.getElementById("P28_FOLIO_FACTURA");'
                            'return i?i.value:"SIN";})()')
        comprobar("C6 «Editar» abre la compra con sus datos", folio_pantalla == FOLIO, folio_pantalla)
        # un documento REGISTRADA es de solo lectura: no debe haber Guardar
        sin_guardar = js('(function(){return ![...document.querySelectorAll("button")].some(function(b){'
                         'return (b.getAttribute("data-otel-label")||"")==="BTN_GUARDAR_COMPRA";});})()')
        comprobar("C6 una compra REGISTRADA no ofrece Guardar", sin_guardar is True)
    con.close()
finally:
    proc.terminate()
    con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
    cur = con.cursor()
    cur.execute("alter session set current_schema = WKSP_SYPEXWS")
    cur.execute("delete from retenciones_iva where id_compra in (select id_compra from compras where folio_factura = :f)", f=FOLIO)
    con.commit()
    cur.execute("delete from compras_det where id_compra in "
                "(select id_compra from compras where folio_factura = :f)", f=FOLIO)
    con.commit()
    cur.execute("delete from compras where folio_factura = :f", f=FOLIO)
    con.commit()
    # el contador del periodo se devuelve al ultimo comprobante que quedo en la tabla:
    # los numeros de retencion son correlativos y una prueba no debe dejar huecos
    cur.execute("""merge into retencion_contador t
                   using (select 1 as id_empresa, to_char(sysdate, 'YYYYMM') as periodo,
                                 nvl((select max(nvl(to_number(substr(numero_comprobante, 7)), 0))
                                        from retenciones_iva
                                       where id_empresa = 1
                                         and substr(numero_comprobante, 1, 6) = to_char(sysdate, 'YYYYMM')),
                                     0) as ultimo
                            from dual) s
                      on (t.id_empresa = s.id_empresa and t.periodo = s.periodo)
                   when matched then update set t.ultimo = s.ultimo
                   when not matched then insert (id_empresa, periodo, ultimo)
                        values (s.id_empresa, s.periodo, s.ultimo)""")
    con.commit()
    if prov_creado:
        cur.execute("delete from proveedores where id_proveedor = :p", p=prov[0])
        con.commit()
    cur.execute("begin delete from usuario_empresa where usuario_id in "
                "(select usuario_id from usuario where upper(username)='DIAG.COMPRA'); commit; "
                "delete from usuario where upper(username)='DIAG.COMPRA'; commit; end;")
    con.commit()
    con.close()

print()
print("RESULTADO: FALLAS=" + str(fallas))
sys.exit(1 if fallas else 0)
