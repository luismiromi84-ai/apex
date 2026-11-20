#!/usr/bin/env python3
# =============================================================================
# 20261120_nota_compra_navegador.py
#
# Boton "Traer lineas" de la compra (pagina 28): una nota de credito/debito de
# COMPRA trae las lineas de la factura que acredita, como el lado de ventas.
# Lo que se mide, con navegador real:
#
#   N1 en una nota (NC) con factura origen el boton se pinta
#   N2 al pulsarlo se copian las dos lineas de la factura
#   N3 el mensaje dice cuantas lineas se trajeron
#   N4 las lineas copiadas apuntan a la linea original (id_detalle_origen)
#   N5 en una factura normal (FAC) el boton NO se pinta
#   N6 pulsarlo otra vez NO duplica: dice «Ya estaban todas las lineas.»
#
# Crea y borra su propio usuario, proveedor y compras.
#
# Uso: python deploy/diagnostico/20261120_nota_compra_navegador.py
# =============================================================================
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.request

import oracledb
import websocket

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
REPO = r"C:\Users\luism\OneDrive\Documents\Apex_luis"
sys.path.insert(0, os.path.join(REPO, "deploy", "conexion"))
from verificar_conexion import CONNECT_STRING as CS, credenciales  # noqa: E402

EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
BASE = "https://gfd7e2575d251ae-sypexsql.adb.mx-monterrey-1.oraclecloudapps.com/ords"
USUARIO, CLAVE = "diag.nota", "Diag#2026"
# La nota va PRIMERO: sus lineas apuntan a las de la factura (FK_COMPRA_DET_ORIGEN).
FOLIOS = ("NCAP-NC-1", "NCAP-FAC-1")
fallas = []


def comprobar(nombre, condicion, detalle=""):
    print(("  OK  " if condicion else "  MAL ") + nombre + ("" if condicion else " -> " + str(detalle)[:300]))
    if not condicion:
        fallas.append(nombre)


def valor(v):
    x = v.getvalue()
    return x[0] if isinstance(x, (list, tuple)) else x


class Nav:
    def __init__(self, puerto=9298):
        self.proc = subprocess.Popen(
            [EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
             f"--remote-debugging-port={puerto}",
             f"--user-data-dir={os.path.join(tempfile.gettempdir(), 'opencode', 'edge-nota')}",
             "--window-size=1440,1000", "about:blank"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        objetivo = None
        for _ in range(40):
            try:
                lista = json.loads(urllib.request.urlopen(
                    f"http://127.0.0.1:{puerto}/json/list", timeout=2).read())
                pag = [t for t in lista if t.get("type") == "page"]
                if pag:
                    objetivo = pag[0]
                    break
            except Exception:
                pass
            time.sleep(0.5)
        self.ws = websocket.create_connection(objetivo["webSocketDebuggerUrl"], timeout=60)
        self.n = 0
        for m in ("Page.enable", "Runtime.enable"):
            self.cmd(m)

    def cmd(self, method, **params):
        self.n += 1
        self.ws.send(json.dumps({"id": self.n, "method": method, "params": params}))
        while True:
            r = json.loads(self.ws.recv())
            if r.get("id") == self.n:
                return r.get("result", {})

    def js(self, expr):
        try:
            r = self.cmd("Runtime.evaluate", expression=expr, returnByValue=True, awaitPromise=True)
        except Exception as e:
            return "WS: " + str(e)[:120]
        if "exceptionDetails" in r:
            return "EXC: " + str(r["exceptionDetails"].get("exception", {}).get("description"))[:200]
        return r.get("result", {}).get("value")

    def esperar(self, cond, seg=40):
        fin = time.time() + seg
        while time.time() < fin:
            if self.js(cond):
                return True
            time.sleep(0.5)
        return False

    def cerrar(self):
        try:
            self.proc.terminate()
        except Exception:
            pass


# =====================================================================
# Datos de la prueba
# =====================================================================
c = credenciales()
con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CS)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")


def limpiar():
    cur.execute("begin delete from usuario_empresa where usuario_id in "
                "(select usuario_id from usuario where upper(username)='DIAG.NOTA'); commit; "
                "delete from usuario where upper(username)='DIAG.NOTA'; commit; end;")
    for f in FOLIOS:
        cur.execute("delete from compras_det where id_compra in "
                    "(select id_compra from compras where folio_factura = :f)", f=f)
        con.commit()
        cur.execute("delete from compras where folio_factura = :f", f=f)
        con.commit()
    cur.execute("delete from proveedores where rif = 'NCAP-PROV'")
    con.commit()


limpiar()
cur.execute("""insert into usuario (username,email,password_hash,estado,id_empresa,rol_id,
                 debe_cambiar_clave,reintentos_fallidos)
               values ('diag.nota','diag.nota@synpex.local',
                 sypex_hash_password('Diag#2026'),'ACTIVO',1,
                 (select id_rol from syn_roles where codigo_rol='ADMIN'),'N',0)""")
con.commit()

cur.execute("select min(i.id_impuesto) from impuestos i join empresas e on e.cod_pais = i.cod_pais "
            "where e.id_empresa = 1 and i.estado = 'ACTIVO' "
            "and nvl(i.aplica_en,'LINEA') = 'LINEA' and i.porcentage = 16")
imp16 = cur.fetchone()[0]

cur.execute("""insert into proveedores (id_empresa, rif, razon_social, tipo_persona, cod_pais,
                 estado, retener_iva, porcentaje_retencion, es_spe, dias_credito)
               values (1, 'NCAP-PROV', 'Proveedor de la nota de compra', 'J', 'VE',
                 'ACTIVO', 'N', 0, 'N', 0)
               returning id_proveedor into :i""", i=cur.var(oracledb.NUMBER))
prov = int(valor(cur.bindvars["i"]))
con.commit()


def crea_compra(folio, tipo, origen, lineas):
    cur.execute("begin pkg_compras.prc_guardar_compra("
                "p_id_compra => :i, p_id_empresa => 1, p_id_proveedor => :p, "
                "p_tipo_documento => :t, p_folio_factura => :f, p_nro_control => '00-000995', "
                "p_fecha_emision => trunc(sysdate), p_cod_moneda => 'VES', p_tipo_cambio => 1, "
                "p_porcentaje_retencion => 0, p_id_compra_origen => :o, "
                "p_usuario => 'diag.nota'); end;",
                i=cur.var(oracledb.NUMBER), p=prov, t=tipo, f=folio, o=origen)
    cid = int(valor(cur.bindvars["i"]))
    con.commit()
    for k, (desc, cant, prec) in enumerate(lineas, start=1):
        cur.execute("begin pkg_compra_detalle.guardar_detalle(:d, :c, :n, null, :de, :q, :p, 0, 0, "
                    ":i, 16, 'diag.nota'); end;",
                    d=cur.var(oracledb.NUMBER), c=cid, n=k, de=desc, q=cant, p=prec, i=imp16)
        con.commit()
    return cid


fac = crea_compra("NCAP-FAC-1", "FAC", None,
                  [("Servicio de la factura", 2, 150.00), ("Repuesto de la factura", 1, 80.00)])
nc = crea_compra("NCAP-NC-1", "NC", fac, [])
con.close()
print("  factura=%s nota=%s" % (fac, nc))

nav = Nav()
try:
    nav.js('window.location.href="%s/f?p=100:9999"' % BASE)
    nav.esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(1)
    nav.js('(function(){apex.item("P9999_USERNAME").setValue(' + json.dumps(USUARIO) +
           ');apex.item("P9999_PASSWORD").setValue(' + json.dumps(CLAVE) + ');'
           'var b=[...document.querySelectorAll("button")].find(x=>/sign in|iniciar|entrar/i.test(x.innerText));'
           'if(b){b.click();}})()')
    time.sleep(9)
    ses = nav.js('(function(){try{return apex.env.APP_SESSION;}catch(e){return null;}})()')
    if not ses:
        import re
        m = re.search(r"session=(\d+)", nav.js("window.location.href") or "")
        ses = m.group(1) if m else ""
    print("  sesion:", ses)

    def abrir_compra(folio):
        nav.js('window.location.href="%s/f?p=100:27:%s"' % (BASE, ses))
        nav.esperar('document.readyState === "complete" && !!window.apex')
        time.sleep(6)
        ok = nav.js('(function(){var filas=[...document.querySelectorAll("table tbody tr")];'
                    'var f=filas.find(function(tr){return /%s/.test(tr.innerText);});'
                    'if(!f) return "SIN FILA";'
                    'var a=[...f.querySelectorAll("td a")].find(function(x){'
                    'return x.querySelector(".fa-pencil") || /editar/i.test(x.innerText);});'
                    'if(!a) return "SIN ENLACE"; a.click(); return "CLIC";})()' % folio)
        time.sleep(9)
        return ok

    BOTONES = ('(function(){return [...document.querySelectorAll("button")]'
               '.map(function(b){return b.getAttribute("data-otel-label")||"";})'
               '.filter(function(x){return /TRAER/.test(x);}).join("|");})()')

    # ---- N1/N2/N3/N4: la nota trae las lineas de la factura
    print("  abrir la nota:", abrir_compra("NCAP-NC-1"))
    bot = nav.js(BOTONES)
    comprobar("N1 en la nota se pinta el boton Traer lineas", "BTN_TRAER_COMPRA" in str(bot), bot)

    filas_antes = nav.js('(function(){var t=document.querySelector(".spx-det");'
                         'return t ? t.querySelectorAll("tbody tr").length : 0;})()')
    clic = nav.js('(function(){var b=[...document.querySelectorAll("button")]'
                  '.find(function(x){return (x.getAttribute("data-otel-label")||"")'
                  '==="BTN_TRAER_COMPRA";});if(!b) return "SIN BOTON";b.click();return "CLIC";})()')
    time.sleep(12)
    txt = nav.js("document.body.innerText") or ""
    filas = nav.js('(function(){var t=document.querySelector(".spx-det");'
                   'return t ? t.querySelectorAll("tbody tr").length : 0;})()')
    comprobar("N2 al pulsarlo se copian las dos lineas de la factura",
              clic == "CLIC" and str(filas_antes) == "0" and str(filas) == "2",
              "antes=%s despues=%s (%s)" % (filas_antes, filas, clic))
    comprobar("N3 el mensaje dice cuantas lineas se trajeron",
              "Se trajeron 2 lineas" in txt, txt[:200])

    # N4: en la base, cada linea copiada apunta a su original
    con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CS)
    cur = con.cursor()
    cur.execute("alter session set current_schema = WKSP_SYPEXWS")
    cur.execute("""select count(*), count(id_detalle_origen)
                     from compras_det where id_compra = :c""", c=nc)
    total, con_origen = cur.fetchone()
    cur.execute("""select count(*) from compras_det d
                    where d.id_compra = :c
                      and d.id_detalle_origen in (select o.id_detalle
                                                    from compras_det o
                                                   where o.id_compra = :f)""", c=nc, f=fac)
    apuntan = cur.fetchone()[0]
    con.close()
    comprobar("N4 las lineas copiadas apuntan a la linea original",
              total == 2 and con_origen == 2 and apuntan == 2,
              "lineas=%s con_origen=%s apuntan=%s" % (total, con_origen, apuntan))

    # N6 (2026-11-20): el boton es idempotente: la segunda pulsacion no duplica
    # y lo dice. Es lo que hacia falta con facturas de 20 o 50 lineas.
    nav.js('(function(){var b=[...document.querySelectorAll("button")]'
           '.find(function(x){return (x.getAttribute("data-otel-label")||"")'
           '==="BTN_TRAER_COMPRA";});if(!b) return "SIN BOTON";b.click();return "CLIC";})()')
    time.sleep(12)
    txt2 = nav.js("document.body.innerText") or ""
    filas2 = nav.js('(function(){var t=document.querySelector(".spx-det");'
                    'return t ? t.querySelectorAll("tbody tr").length : 0;})()')
    comprobar("N6 la segunda pulsacion no duplica y avisa",
              "Ya estaban todas las lineas" in txt2 and str(filas2) == "2",
              "filas=%s (%s)" % (filas2, (txt2 or "")[:160]))

    # ---- N5: en una factura normal el boton no sale
    print("  abrir la factura:", abrir_compra("NCAP-FAC-1"))
    bot_fac = nav.js(BOTONES)
    comprobar("N5 en una factura (FAC) el boton no se pinta", "BTN_TRAER" not in str(bot_fac), bot_fac)
finally:
    nav.cerrar()
    con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CS)
    cur = con.cursor()
    cur.execute("alter session set current_schema = WKSP_SYPEXWS")
    for f in FOLIOS:
        cur.execute("delete from compras_det where id_compra in "
                    "(select id_compra from compras where folio_factura = :f)", f=f)
        con.commit()
        cur.execute("delete from compras where folio_factura = :f", f=f)
        con.commit()
    cur.execute("delete from proveedores where rif = 'NCAP-PROV'")
    con.commit()
    cur.execute("begin delete from usuario_empresa where usuario_id in "
                "(select usuario_id from usuario where upper(username)='DIAG.NOTA'); commit; "
                "delete from usuario where upper(username)='DIAG.NOTA'; commit; end;")
    con.close()

print()
print("RESULTADO: FALLAS=" + str(len(fallas)))
for f in fallas:
    print("  - " + f)
sys.exit(1 if fallas else 0)
