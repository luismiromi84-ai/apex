"""Al guardar un cobro y cerrar el dialogo, la lista de la pagina 8 se refresca sola.

  L1  tras cobrar desde la lista, la fila de la factura pasa a PAGADA sin recargar
  L2  el saldo que muestra la lista es 0

Uso: python deploy/diagnostico/20261119_cobro_refresca_lista_navegador.py
Crea y borra su propia factura y su usuario.
"""
import json, os, re, subprocess, sys, tempfile, time, urllib.request
import oracledb

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.path.insert(0, r"C:\Users\luism\OneDrive\Documents\Apex_luis\deploy\conexion")
from verificar_conexion import CONNECT_STRING, credenciales

EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
BASE = "https://gfd7e2575d251ae-sypexsql.adb.mx-monterrey-1.oraclecloudapps.com/ords"
USUARIO, CLAVE = "diag.refresca", "Diag#2026"
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
            "(select usuario_id from usuario where upper(username)='DIAG.REFRESCA'); commit; "
            "delete from usuario where upper(username)='DIAG.REFRESCA'; commit; end;")
cur.execute("""insert into usuario (username,email,password_hash,estado,id_empresa,rol_id,
                 debe_cambiar_clave,reintentos_fallidos)
               values ('diag.refresca','diag.refresca@synpex.local',
                 sypex_hash_password('Diag#2026'),'ACTIVO',1,
                 (select id_rol from syn_roles where codigo_rol='ADMIN'),'N',0)""")
con.commit()

cur.execute("""select id_cliente from clientes
                where id_empresa = 1 and nvl(es_agente_retencion,'N') = 'N' and rownum = 1""")
id_cli = cur.fetchone()[0]
salida_num = cur.var(oracledb.DB_TYPE_NUMBER)
cur.execute("""declare v_id number; begin
                 pkg_facturacion.prc_guardar_factura(
                   p_id_factura => v_id, p_id_empresa => 1, p_folio_factura => 'REF-ZZ-2',
                   p_id_cliente => :c, p_id_presupuesto => null,
                   p_rfc_emisor => 'J-1', p_rfc_receptor => 'J-2', p_uuid_fiscal => null,
                   p_uso_cfdi => null, p_forma_pago => null, p_metodo_pago => null,
                   p_condicion_pago => null, p_fecha_emision => '18/11/2026',
                   p_fecha_vencimiento => null, p_estado => 'PENDIENTE',
                   p_subtotal => 100, p_monto_impuesto => 16, p_monto_total => 116,
                   p_observaciones => 'prueba del refresco de la lista', p_cod_moneda => 'USD',
                   p_tipo_cambio => 915.7476, p_usuario => 'VERIF', p_tipo_documento => 'FAC');
                 :salida := v_id;
               end;""", c=id_cli, salida=salida_num)
con.commit()
id_fac = salida_num.getvalue()
cur.execute("""insert into facturas_det (id_factura, num_linea, descripcion, cantidad, precio_unitario,
                   id_impuesto, porcentaje_impuesto, monto_impuesto, subtotal_linea, monto_total_linea,
                   tasa_cambio_aplicada, subtotal_bs, total_bs)
               values (:f, 1, 'Servicio', 1, 100, 1, 16, 16, 100, 116, 915.7476, 91574.76, 106226.72)""",
            f=id_fac)
con.commit()
cur.execute("begin pkg_facturacion.prc_procesar_factura(:f, 'VERIF'); end;", f=id_fac)
con.commit()
print("  factura de prueba:", id_fac)
con.close()

proc = subprocess.Popen([EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
                         "--remote-debugging-port=9286", "--window-size=1440,900",
                         "--user-data-dir=" + os.path.join(tempfile.gettempdir(), "opencode", "edge-ref6"),
                         "about:blank"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def obj():
    for _ in range(40):
        try:
            l = json.loads(urllib.request.urlopen("http://127.0.0.1:9286/json/list", timeout=2).read())
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


def fila(i):
    return js('(function(){var tr=document.querySelector(\'tr[data-id="' + str(i) + '"]\');'
              'return tr ? tr.innerText.replace(/\\s+/g," ").substring(0,140) : "SIN FILA";})()')


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

    js('window.location.href="' + BASE + '/f?p=100:8:' + ses + '"')
    esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(4)
    print("  antes:", fila(id_fac))

    # abrir el cobro desde la columna Cobrar y guardarlo
    js('(function(){var m=' + json.dumps("p25_id_factura%3D" + str(id_fac)) + ';'
       'var a=[...document.querySelectorAll(\'a[href*="a-dialog-open"]\')]'
       '.find(function(x){return x.getAttribute("href").indexOf(m)>=0;});'
       'if(a){a.click();}})()')
    time.sleep(8)
    js('(function(){var w=document.querySelector("iframe").contentWindow;var a=w.apex;'
       'a.item("P25_MONTO").setValue(116);'
       'var s=w.document.getElementById("P25_ID_FORMA_PAGO");'
       'if(s.options.length>1){s.selectedIndex=1;s.dispatchEvent(new Event("change",{bubbles:true}));}'
       'a.item("P25_REFERENCIA").setValue("TRF-REF-1");return "OK";})()')
    time.sleep(4)
    js('(function(){var d=document.querySelector("iframe").contentDocument;'
       'var b=d.querySelector(\'[data-otel-label="BTN_GUARDAR_COBRO"]\');if(b){b.click();}})()')
    time.sleep(12)

    print("  dialogos abiertos:", js("document.querySelectorAll('iframe').length"))
    print("  despues:", fila(id_fac))
    texto = str(fila(id_fac))
    comprobar("L1 la fila pasa a PAGADA sin recargar", "PAGADA" in texto, texto)
    comprobar("L2 el saldo queda en 0", ("0.00" in texto or "0,00" in texto), texto)
finally:
    proc.terminate()
    con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
    cur = con.cursor()
    cur.execute("alter session set current_schema = WKSP_SYPEXWS")
    cur.execute("delete from recibos where id_factura = :f", f=id_fac)
    con.commit()
    cur.execute("delete from facturas where id_factura = :f", f=id_fac)
    con.commit()
    cur.execute("begin delete from usuario_empresa where usuario_id in "
                "(select usuario_id from usuario where upper(username)='DIAG.REFRESCA'); commit; "
                "delete from usuario where upper(username)='DIAG.REFRESCA'; commit; end;")
    con.commit()
    # La factura de prueba consumio folio y N de control: se dejan los contadores
    # en el maximo real para no abrir un hueco en la numeracion fiscal (2026-11-21).
    cur.execute("""merge into folio_contador f
                   using (select 'FAC' tipo,
                                 nvl(max(to_number(regexp_substr(folio_factura, '[0-9]+$'))), 0) ultimo
                            from facturas where id_empresa = 1 and tipo_documento = 'FAC') d
                      on (f.id_empresa = 1 and f.tipo = d.tipo)
                   when matched then update set f.ultimo = d.ultimo
                   when not matched then insert (id_empresa, tipo, ultimo)
                        values (1, d.tipo, d.ultimo)""")
    cur.execute("""merge into folio_contador f
                   using (select 'CONTROL' tipo,
                                 nvl(max(to_number(regexp_substr(nro_control, '[0-9]+$'))), 0) ultimo
                            from facturas
                           where nro_control is not null
                             and regexp_like(trim(nro_control), '^[0-9]{2}-[0-9]{6}$')
                             and id_empresa = 1) d
                      on (f.id_empresa = 1 and f.tipo = d.tipo)
                   when matched then update set f.ultimo = d.ultimo
                   when not matched then insert (id_empresa, tipo, ultimo)
                        values (1, d.tipo, d.ultimo)""")
    con.commit()
    con.close()

print()
print("RESULTADO: FALLAS=" + str(fallas))
sys.exit(1 if fallas else 0)
