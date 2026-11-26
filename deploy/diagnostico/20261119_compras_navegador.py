"""Modulo de Compras (27 lista, 28 compra, 29 linea), con navegador real.

  C1  la lista (27) abre con el boton de alta y el menu trae Compras
  C2  «Nueva compra» guarda la cabecera; la moneda, la tasa y el % de retencion
      se proponen solos (moneda local, tasa del dia, 75 del proveedor) y los DOS
      numeros del proveedor (N. de factura y N. de control) salen de su serie
  C3  «Nueva linea» abre la linea, y al guardarla la compra cuadra (100 + 16 = 116).
      C3a: al elegir el producto se traen descripcion, precio e impuesto del catalogo
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
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
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
for _sql in ("delete from retenciones_det where id_compra in (select id_compra from compras where folio_factura = :f)",
             "delete from retenciones where id_compra in (select id_compra from compras where folio_factura = :f)",
             "delete from retenciones_iva where id_compra in (select id_compra from compras where folio_factura = :f)"):
    cur.execute(_sql, f=FOLIO)
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
# la serie del proveedor se lee ANTES de abrir el navegador (la conexion se cierra
# aqui): es la propuesta que la pagina 28 debe pintar al abrir una compra nueva
cur.execute("""select fn_siguiente_folio(1, 'FAC_PROV'),
                      fn_siguiente_folio(1, 'CONTROL_PROV')
                 from dual""")
serie_folio, serie_control = cur.fetchone()
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

    # C2a: la moneda se propone sola (la local de la empresa 1) y en bolivares la tasa es 1
    moneda0 = js('apex.item("P28_COD_MONEDA").getValue()')
    tasa0 = js('apex.item("P28_TIPO_CAMBIO").getValue()')
    print("  al abrir: moneda=%r tasa=%r" % (moneda0, tasa0))
    comprobar("C2 la moneda se propone sola", str(moneda0) == "VES", moneda0)
    try:
        ok_t0 = abs(float(str(tasa0).replace(",", "")) - 1) < 0.0001
    except Exception:
        ok_t0 = False
    comprobar("C2 en bolivares la tasa es 1", ok_t0, tasa0)

    # C2d (2026-11-18): los DOS numeros del proveedor se proponen solos desde su
    # serie en FOLIO_CONTADOR (FAC_PROV y CONTROL_PROV), sin teclearlos.
    folio_pant = str(js('apex.item("P28_FOLIO_FACTURA").getValue()') or "")
    control_pant = str(js('apex.item("P28_NRO_CONTROL").getValue()') or "")
    print("  numeros propuestos: factura=%r control=%r" % (folio_pant, control_pant))
    comprobar("C2 el N. de factura del proveedor viene propuesto",
              folio_pant == str(serie_folio), (folio_pant, serie_folio))
    comprobar("C2 el N. de control del proveedor viene propuesto",
              control_pant == str(serie_control), (control_pant, serie_control))
    comprobar("C2 el control tiene la forma 00-000001",
              bool(re.match(r"^\d{2}-\d{6}$", control_pant)), control_pant)

    # C2b: el % de retencion sale del maestro del proveedor (75)
    js('(function(){apex.item("P28_ID_PROVEEDOR").setValue(' + json.dumps(str(prov[0])) + ');'
       'apex.item("P28_ID_PROVEEDOR").element.dispatchEvent(new Event("change",{bubbles:true}));'
       'return "OK";})()')
    time.sleep(4)
    pct = js('apex.item("P28_PORCENTAJE_RETENCION").getValue()')
    print("  % retencion propuesto:", pct)
    try:
        ok_pct = abs(float(str(pct).replace(",", "")) - 75) < 0.0001
    except Exception:
        ok_pct = False
    comprobar("C2 el % de retencion sale del proveedor", ok_pct, pct)

    # C2c: en divisa trae la tasa del dia (y no 1)
    js('(function(){apex.item("P28_COD_MONEDA").setValue("USD");'
       'apex.item("P28_COD_MONEDA").element.dispatchEvent(new Event("change",{bubbles:true}));'
       'return "OK";})()')
    time.sleep(4)
    tasa_usd = js('apex.item("P28_TIPO_CAMBIO").getValue()')
    print("  tasa en USD:", tasa_usd)
    try:
        ok_usd = float(str(tasa_usd).replace(",", "")) > 1
    except Exception:
        ok_usd = False
    comprobar("C2 en divisa trae la tasa del dia", ok_usd, tasa_usd)

    # se vuelve a bolivares para que el resto de la prueba siga en Bs
    js('(function(){apex.item("P28_COD_MONEDA").setValue("VES");'
       'apex.item("P28_COD_MONEDA").element.dispatchEvent(new Event("change",{bubbles:true}));'
       'return "OK";})()')
    time.sleep(4)
    # el folio se escribe DESPUES de que la accion dinamica termine: si se pone en
    # el mismo instante, la respuesta de la accion lo pisa (2026-11-18).
    js('apex.item("P28_FOLIO_FACTURA").setValue(' + json.dumps(FOLIO) + ')')
    time.sleep(1)
    print("  items antes de guardar:", js('(function(){return {prov:apex.item("P28_ID_PROVEEDOR").getValue(),'
                                          ' folio:apex.item("P28_FOLIO_FACTURA").getValue(),'
                                          ' mon:apex.item("P28_COD_MONEDA").getValue(),'
                                          ' tasa:apex.item("P28_TIPO_CAMBIO").getValue(),'
                                          ' pct:apex.item("P28_PORCENTAJE_RETENCION").getValue()};})()'))
    boton("BTN_GUARDAR_COMPRA")
    time.sleep(9)
    print("  avisos tras guardar:", js('(function(){var o=[];'
                                       'document.querySelectorAll(".a-Notification, .t-Alert")'
                                       '.forEach(function(e){o.push((e.innerText||"").replace(/\\s+/g," ").trim());});'
                                       'return o;})()'))

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
    # el titulo lleva tilde desde el 2026-11-19 («Línea de compra»): comparar sin acentos
    plano = (en29.lower().replace("í", "i").replace("á", "a").replace("é", "e")
             .replace("ó", "o").replace("ú", "u"))
    comprobar("C3 «Nueva linea» abre la pagina 29",
              ":29:" in en29 or "linea-de-compra" in plano or "linea de compra" in plano, en29[-60:])
    if "linea" in en29.lower():
        # C3a (2026-11-19): al elegir el producto, el catalogo trae descripcion,
        # precio sugerido e impuesto. Antes el precio habia que teclearlo.
        cur.execute("""select id_producto_servicio, nombre, precio_sugerido, impuesto_aplicable
                         from producto_servicio
                        where nvl(estado, 'ACTIVO') = 'ACTIVO'
                          and id_empresa = 1
                        order by codigo""")
        prod = cur.fetchone()
        cur.execute("""select min(i.id_impuesto)
                         from impuestos i join empresas e on e.cod_pais = i.cod_pais
                        where e.id_empresa = 1 and i.estado = 'ACTIVO'
                          and nvl(i.aplica_en, 'LINEA') = 'LINEA'
                          and i.porcentage = :p""", p=prod[3])
        imp_esperado = cur.fetchone()[0]

        js('(function(){apex.item("P29_ID_PRODUCTO_SERVICIO").setValue("%d");'
           'var el=document.getElementById("P29_ID_PRODUCTO_SERVICIO");'
           'if(el){el.dispatchEvent(new Event("change",{bubbles:true}));}return "OK";})()' % prod[0])
        time.sleep(6)
        precio_pant = js('apex.item("P29_PRECIO_UNITARIO").getValue()')
        desc_pant = js('apex.item("P29_DESCRIPCION").getValue()')
        imp_pant = js('apex.item("P29_ID_IMPUESTO").getValue()')
        print("  al elegir %s: precio=%r desc=%r impuesto=%r"
              % (prod[1], precio_pant, desc_pant, imp_pant))
        try:
            ok_precio = abs(float(str(precio_pant).replace(",", ".")) - float(prod[2])) < 0.01
        except Exception:
            ok_precio = False
        comprobar("C3a el precio unitario se trae del catalogo", ok_precio,
                  (precio_pant, prod[2]))
        comprobar("C3a la descripcion se trae del catalogo",
                  (desc_pant or "").strip() == (prod[1] or "").strip(), (desc_pant, prod[1]))
        comprobar("C3a el impuesto se propone con el % del producto",
                  str(imp_pant) == str(imp_esperado), (imp_pant, imp_esperado))

        js('(function(){apex.item("P29_DESCRIPCION").setValue("Servicio de prueba");'
           'apex.item("P29_CANTIDAD").setValue(2);'
           'apex.item("P29_PRECIO_UNITARIO").setValue(50);'
           'var s=document.getElementById("P29_ID_IMPUESTO");'
           'if(s){var op=[...s.options].find(function(o){return /16/.test(o.textContent);});'
           'if(op){apex.item("P29_ID_IMPUESTO").setValue(op.value);}}'
           'return "OK";})()')
        # el % lo pone la accion del impuesto (2026-11-19): hay que dejarla terminar
        time.sleep(6)
        print("  % del impuesto tras elegirlo:", js('apex.item("P29_PORCENTAJE_IMPUESTO").getValue()'))
        boton("BTN_GUARDAR_LINEA_COMPRA")
        time.sleep(9)

        cur.execute("""select subtotal, monto_impuesto, monto_total,
                              (select count(*) from compras_det where id_compra = :i) as lineas
                         from compras where id_compra = :i""", i=id_compra)
        t2 = cur.fetchone()
        print("  cabecera tras la linea:", t2)
        comprobar("C3 la linea entra y la cabecera cuadra",
                  t2 and t2[3] == 1 and float(t2[0]) == 100 and float(t2[1]) == 16 and float(t2[2]) == 116, t2)

        # C3b: la region «Lineas de la compra» se PINTA como tabla, no como codigo.
        # El 2026-11-18 estaba guardada como contenido ESTATICO y la pagina mostraba
        # el PL/SQL entero (declare ... v_html ... end).
        cuerpo = js("document.body.innerText") or ""
        comprobar("C3b la pagina no muestra el codigo de la region",
                  "fn_clean_num" not in cuerpo and "v_html" not in cuerpo, cuerpo[:150])
        comprobar("C3b la linea se ve en la tabla",
                  "Servicio de prueba" in cuerpo, cuerpo[:200])

        # captura de la region ya pintada, como evidencia para el dueno
        try:
            import base64 as b64
            png = cmd("Page.captureScreenshot", format="png")["data"]
            ruta = os.path.join(REPO, "deploy", "resultados", "20261118_compra_lineas.png")
            with open(ruta, "wb") as f:
                f.write(b64.b64decode(png))
            print("  captura:", ruta)
        except Exception as e:
            print("  (sin captura:", e, ")")

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

        cur.execute("""select numero_comprobante, base_imponible_bs, impuesto_bs,
                              retenido_bs, estado
                         from retenciones where id_compra = :i and tipo = 'IVA'""", i=id_compra)
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

        # C7 (2026-11-19): el resumen de la compra (base, exento, IVA, retención, neto)
        texto28 = js("document.body.innerText") or ""
        # 2026-11-20: el resumen paso de tabla a cuatro tarjetas (Subtotal, IVA,
        # Retencion, Total) con la tasa y el neto debajo.
        texto28_may = texto28.upper()
        faltan = [c for c in ("SUBTOTAL", "IVA", "RETENCION IVA", "TOTAL",
                              "NETO A PAGAR") if c not in texto28_may]
        comprobar("C7 el resumen de la compra sale con sus cuatro tarjetas y el neto",
                  not faltan, faltan)

        # C7b (2026-11-22): el IGTF del resumen es la FOTO congelada en la compra,
        # no un calculo en vivo. Para probarlo la compra se pasa a divisa (el IGTF
        # solo existe en divisas) con su tasa y un igtf_bs conocido; la pantalla
        # tiene que mostrar 123.45 (con el calculo en vivo saldria 0: la empresa no
        # es SPE y la forma de pago no lo genera).
        cur.execute("update compras set cod_moneda = 'USD', tipo_cambio = 900, "
                    "igtf_bs = 123.45 where id_compra = :i", i=id_compra)
        cur.execute("update compras_det set tasa_cambio_aplicada = 900 where id_compra = :i",
                    i=id_compra)
        con.commit()
        js("location.reload()")
        esperar('document.readyState === "complete" && !!window.apex')
        time.sleep(6)
        ok_igtf = esperar('document.body.innerText.indexOf("123,45") >= 0', 45)
        texto_igtf = js("document.body.innerText") or ""
        comprobar("C7b el resumen muestra el IGTF guardado en la compra", ok_igtf,
                  [l for l in texto_igtf.splitlines() if "IGTF" in l.upper()][:2])

        # C8 (2026-11-19): el boton «Imprimir comprobante» lleva al comprobante
        clic_imp = js('(function(){var b=[...document.querySelectorAll("button,a")].find(function(x){'
                      'return (x.getAttribute("data-otel-label")||"")==="BTN_IMPRIMIR_RETENCION";});'
                      'if(!b) return "NO"; b.click(); return "CLIC";})()')
        time.sleep(10)
        cuerpo_ret = js("document.body.innerText") or ""
        comprobar("C8 el comprobante de retención se imprime",
                  clic_imp == "CLIC" and "COMPROBANTE DE RETENCI" in cuerpo_ret.upper()
                  and "I.V.A." in cuerpo_ret,
                  (clic_imp, cuerpo_ret[:120]))

        # C9 (2026-11-23): el boton «Imprimir compra» abre la factura de compra (39)
        # con los datos del proveedor, el IGTF congelado del C7b y la nota de que el
        # documento es del proveedor.
        js('window.location.href="' + BASE + '/f?p=100:27:' + ses + '"')
        esperar('document.readyState === "complete" && !!window.apex')
        time.sleep(5)
        js('(function(){var a=[...document.querySelectorAll("a")].find(function(x){'
           'return (x.getAttribute("href")||"").indexOf("p28_id_compra")>=0;});'
           'if(a){a.click();}})()')
        esperar('document.readyState === "complete" && !!window.apex')
        time.sleep(8)
        clic_cmp = boton("BTN_IMPRIMIR_COMPRA")
        time.sleep(10)
        cuerpo_cmp = js("document.body.innerText") or ""
        comprobar("C9 la compra ofrece «Imprimir compra»", clic_cmp == "CLIC", clic_cmp)
        comprobar("C9 abre la factura de compra", "FACTURA DE COMPRA" in cuerpo_cmp.upper(),
                  cuerpo_cmp[:120])
        comprobar("C9 con el folio del proveedor", FOLIO in cuerpo_cmp,
                  [l for l in cuerpo_cmp.splitlines() if "FOLIO" in l.upper()][:2])
        comprobar("C9 con el IGTF congelado de la compra", "123,45" in cuerpo_cmp,
                  [l for l in cuerpo_cmp.splitlines() if "IGTF" in l.upper()][:2])
        comprobar("C9 y avisa de que el documento es del proveedor",
                  "no sustituye al original" in cuerpo_cmp.lower(), cuerpo_cmp[-200:])
        try:
            import base64 as b64
            png = cmd("Page.captureScreenshot", format="png", captureBeyondViewport=True)["data"]
            ruta = os.path.join(REPO, "deploy", "resultados", "20261123_factura_compra.png")
            with open(ruta, "wb") as f:
                f.write(b64.b64decode(png))
            print("  captura:", ruta)
        except Exception as e:
            print("  (sin captura:", e, ")")
    con.close()
finally:
    proc.terminate()
    con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
    cur = con.cursor()
    cur.execute("alter session set current_schema = WKSP_SYPEXWS")
    for _sql in ("delete from retenciones_det where id_compra in (select id_compra from compras where folio_factura = :f)",
                 "delete from retenciones where id_compra in (select id_compra from compras where folio_factura = :f)",
                 "delete from retenciones_iva where id_compra in (select id_compra from compras where folio_factura = :f)"):
        cur.execute(_sql, f=FOLIO)
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
                                        from retenciones
                                       where id_empresa = 1
                                         and substr(numero_comprobante, 1, 6) = to_char(sysdate, 'YYYYMM')),
                                     0) as ultimo
                            from dual) s
                      on (t.id_empresa = s.id_empresa and t.periodo = s.periodo)
                   when matched then update set t.ultimo = s.ultimo
                   when not matched then insert (id_empresa, periodo, ultimo)
                        values (s.id_empresa, s.periodo, s.ultimo)""")
    con.commit()
    # la serie CONTROL_PROV de las compras se devuelve a su maximo real: la prueba
    # deja la compra con el control propuesto y, al borrarla, no debe quedar el
    # contador por delante (el dueño pidio correlativos sin saltos, 2026-11-18).
    cur.execute("""merge into folio_contador f
                   using (select 1 as id_empresa, 'CONTROL_PROV' as tipo,
                                 nvl(max(to_number(regexp_substr(nro_control, '[0-9]+$'))), 0) as ultimo
                            from compras
                           where id_empresa = 1
                             and nro_control is not null
                             and regexp_like(trim(nro_control), '^[0-9]{2}-[0-9]{6}$')) s
                      on (f.id_empresa = s.id_empresa and f.tipo = s.tipo)
                   when matched then update set f.ultimo = s.ultimo
                   when not matched then insert (id_empresa, tipo, ultimo)
                        values (s.id_empresa, s.tipo, s.ultimo)""")
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
