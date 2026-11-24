"""Capturas y comprobaciones visuales del rediseno de la compra (pagina 28).

El dueno pidio (2026-11-19) que la compra «se vea profesional»: fuera el
degradado azul de las cabeceras, una banda con folio/proveedor/estado/fecha,
cuatro tarjetas de resumen con el total grande y las dos monedas, las filas de
ISLR cuando hay concepto, la tasa BCV con su fecha, la tabla de lineas con
acciones y sumatoria, y la auditoria al pie. Y que en un telefono la barra azul
no ocupe media pantalla.

La revision del 2026-11-20 anadio tres cosas que este script vigila:

  V13 la compra de OTRA empresa no pinta nada (resumen, lineas, cabecera ni
      auditoria) aunque se meta su id en el item, que no esta protegido
  V14 en un BORRADOR la tarjeta de retencion y el neto son los que salen del
      detalle (antes la retencion salia 0,00 porque la columna solo se escribe
      al emitir), contrastados contra pkg_retenciones
  V15 el concepto de ISLR del proveedor llega a la compra nueva, sigue al
      proveedor mientras la compra no exista, no se pierde al reenviar la pagina
      y no se toca en un documento que ya existe
  V16 el boton del comprobante de ISLR depende del comprobante emitido
  V16b con el comprobante ANULADO el boton tampoco sale

  V1  la 28 abre sin el error de rejilla y sin mostrar PL/SQL
  V2  la cabecera de la compra trae folio, proveedor, insignia y fecha
  V3  hay cuatro tarjetas, el total esta a 42 px y es la mas ancha, a la derecha
  V4  la banda de pago trae la tasa BCV con su fecha y el neto en las dos monedas
  V5  con concepto de ISLR salen base, tarifa/sustraendo y retenido
  V6  la tabla de lineas trae la columna Acciones y la fila de sumatoria
  V7  en BORRADOR se ve el concepto de ISLR y los iconos de borrar
  V8  en REGISTRADA la insignia dice Procesada y estan los dos comprobantes
  V8b la URL del comprobante de ISLR lleva el tipo y el checksum
  V9  a 500 px la barra azul mide menos de 50 px y las tarjetas se apilan
  V10 a 500 px no hay desbordamiento horizontal de la pagina
  V11 el icono de borrar de una linea la quita (confirmacion y peticion POST)
  V12 la auditoria del pie son dos lineas compactas (creado y modificacion)

  El acabado del 2026-11-20 (tarjetas con tinte, banda de pago, tabla con
  cebra y botones circulares) se vigila con:

  V17 cada tarjeta tiene su tinte y el total el verde con borde reforzado
  V18 los chips ejecutivos dicen proveedor, documento, moneda y retencion
  V19 la tabla tiene cebra, hover y los importes a la derecha (cabecera igual)
  V20 las acciones son botones circulares de 36 px
  V21 las observaciones llevan contador de caracteres
  V22 a 500 px el total ocupa la fila entera y nada se sale de la pantalla

Uso: python deploy/diagnostico/20261119_compra_rediseno_capturas.py
Crea y borra su propio usuario, proveedores y compras; devuelve el contador de
retenciones a su sitio (los numeros son fiscales y una prueba no deja huecos).
"""
import json
import os
import re
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
USUARIO, CLAVE = "diag.rediseno", "Diag#2026"
RES = os.path.join(REPO, "deploy", "resultados")
FOLIOS = ("CAP-ZZ-1", "CAP-ZZ-2", "CAP-ZZ-3", "CAP-ZZ-4")
fallas = []


def comprobar(nombre, condicion, detalle=""):
    print(("  OK  " if condicion else "  MAL ") + nombre + ("" if condicion else " -> " + str(detalle)[:300]))
    if not condicion:
        fallas.append(nombre)


def valor(v):
    """Valor de un bind OUT: oracledb devuelve lista o escalar segun el caso."""
    x = v.getvalue()
    return x[0] if isinstance(x, (list, tuple)) else x


def casi_igual(a, b, tol=0.02):
    return a is not None and b is not None and abs(float(a) - float(b)) <= tol


class Nav:
    def __init__(self, puerto=9297):
        self.proc = subprocess.Popen(
            [EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
             f"--remote-debugging-port={puerto}",
             f"--user-data-dir={os.path.join(tempfile.gettempdir(), 'opencode', 'edge-rediseno')}",
             "--window-size=1440,900", "about:blank"],
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

    def tam(self, ancho, alto):
        self.cmd("Emulation.setDeviceMetricsOverride", width=ancho, height=alto,
                 deviceScaleFactor=1, mobile=False)
        time.sleep(1.5)

    def captura(self, ruta):
        import base64
        r = self.cmd("Page.captureScreenshot", format="png", captureBeyondViewport=False)
        if r.get("data"):
            with open(ruta, "wb") as fh:
                fh.write(base64.b64decode(r["data"]))
            return ruta
        return "SIN CAPTURA"

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
cur.execute("begin delete from usuario_empresa where usuario_id in "
            "(select usuario_id from usuario where upper(username)='DIAG.REDISENO'); commit; "
            "delete from usuario where upper(username)='DIAG.REDISENO'; commit; end;")
cur.execute("""insert into usuario (username,email,password_hash,estado,id_empresa,rol_id,
                 debe_cambiar_clave,reintentos_fallidos)
               values ('diag.rediseno','diag.rediseno@synpex.local',
                 sypex_hash_password('Diag#2026'),'ACTIVO',1,
                 (select id_rol from syn_roles where codigo_rol='ADMIN'),'N',0)""")
con.commit()

# limpieza de una corrida anterior (comprobantes, lineas, compras y proveedores)
for f in FOLIOS:
    cur.execute("delete from retenciones_det where id_compra in "
                "(select id_compra from compras where folio_factura = :f)", f=f)
    con.commit()
    cur.execute("delete from retenciones where id_compra in "
                "(select id_compra from compras where folio_factura = :f)", f=f)
    con.commit()
    cur.execute("delete from compras_det where id_compra in "
                "(select id_compra from compras where folio_factura = :f)", f=f)
    con.commit()
    cur.execute("delete from compras where folio_factura = :f", f=f)
    con.commit()
cur.execute("delete from proveedores where rif in ('CAP-PROV-A', 'CAP-PROV-B')")
con.commit()

cur.execute("select min(id_concepto) from islr_conceptos where codigo = '057'")
con057 = cur.fetchone()[0]
cur.execute("select min(id_concepto) from islr_conceptos where codigo = '063'")
con063 = cur.fetchone()[0]
cur.execute("select min(i.id_impuesto) from impuestos i join empresas e on e.cod_pais = i.cod_pais "
            "where e.id_empresa = 1 and i.estado = 'ACTIVO' "
            "and nvl(i.aplica_en,'LINEA') = 'LINEA' and i.porcentage = 16")
imp16 = cur.fetchone()[0]
cur.execute("select nvl(max(ultimo), 0) from retencion_contador "
            "where id_empresa = 1 and periodo = to_char(sysdate, 'YYYYMM')")
contador_ini = cur.fetchone()[0]

cur.execute("""insert into proveedores (id_empresa, rif, razon_social, tipo_persona, cod_pais,
                 estado, retener_iva, porcentaje_retencion, es_spe, dias_credito, id_concepto_islr)
               values (1, 'CAP-PROV-A', 'Proveedor con concepto ISLR', 'J', 'VE',
                 'ACTIVO', 'S', 75, 'N', 0, :c)
               returning id_proveedor into :i""",
            c=con057, i=cur.var(oracledb.NUMBER))
prov_a = int(valor(cur.bindvars["i"]))
con.commit()
cur.execute("""insert into proveedores (id_empresa, rif, razon_social, tipo_persona, cod_pais,
                 estado, retener_iva, porcentaje_retencion, es_spe, dias_credito, id_concepto_islr)
               values (2, 'CAP-PROV-B', 'Proveedor de la empresa 2', 'J', 'MX',
                 'ACTIVO', 'N', 0, 'N', 0, null)
               returning id_proveedor into :i""",
            i=cur.var(oracledb.NUMBER))
prov_b = int(valor(cur.bindvars["i"]))
con.commit()


def crea_compra(folio, empresa, proveedor, moneda, tasa, control, lineas):
    cid = None
    cur.execute("begin pkg_compras.prc_guardar_compra(:i, :e, :p, 'FAC', :f, :n, trunc(sysdate), "
                ":m, :t, 75, null, null, null, -1, 'diag.rediseno'); end;",
                i=cur.var(oracledb.NUMBER), e=empresa, p=proveedor, f=folio, n=control,
                m=moneda, t=tasa)
    cid = int(valor(cur.bindvars["i"]))
    con.commit()
    for k, (desc, cant, prec, pct) in enumerate(lineas, start=1):
        cur.execute("begin pkg_compra_detalle.guardar_detalle(:d, :c, :n, null, :de, :q, :p, 0, 0, "
                    ":i, :pi, 'diag.rediseno'); end;",
                    d=cur.var(oracledb.NUMBER), c=cid, n=k, de=desc, q=cant, p=prec,
                    i=imp16, pi=pct)
        con.commit()
    return cid


lineas_grandes = [("Servicio de mantenimiento anual", 2, 450.00, 16),
                  ("Repuesto de bomba hidraulica", 1, 580.00, 16)]

cap1 = crea_compra("CAP-ZZ-1", 1, prov_a, "USD", 916.6477, "00-000777", lineas_grandes)
cap2 = crea_compra("CAP-ZZ-2", 1, prov_a, "USD", 916.6477, "00-000778", lineas_grandes)
cap4 = crea_compra("CAP-ZZ-4", 1, prov_a, "VES", 1, "00-000779",
                   [("Servicio minimo", 1, 1.00, 16)])
# la compra de la empresa 2 va por INSERT: prc_guardar_compra valida que el usuario
# sea de esa empresa y aqui solo hace falta el documento para probar la fuga
cur.execute("""insert into compras (id_empresa, id_proveedor, tipo_documento, folio_factura,
                 nro_control, fecha_emision, cod_moneda, tipo_cambio, porcentaje_retencion,
                 estado, creado_por, id_concepto_islr)
               values (2, :p, 'FAC', 'CAP-ZZ-3', '00-000780', trunc(sysdate), 'USD', 916.6477,
                 75, 'BORRADOR', 'diag.rediseno', :c)
               returning id_compra into :i""",
            p=prov_b, c=con057, i=cur.var(oracledb.NUMBER))
cap3 = int(valor(cur.bindvars["i"]))
con.commit()
cur.execute("""insert into compras_det (id_compra, num_linea, descripcion, cantidad,
                 precio_unitario, porcentaje_descuento, monto_descuento, id_impuesto,
                 porcentaje_impuesto, monto_impuesto, subtotal_linea, total_linea)
               values (:c, 1, 'Linea de la empresa 2', 1, 100, 0, 0, :i, 16, 16, 100, 116)""",
            c=cap3, i=imp16)
con.commit()

# CAP-ZZ-1 y CAP-ZZ-4 se REGISTRAN por el camino real: emite los comprobantes y
# guarda la foto de la retencion (es lo que la pantalla tiene que ensenar).
cur.execute("begin pkg_compras.prc_registrar_compra(:c, 'diag.rediseno'); end;", c=cap1)
con.commit()
cur.execute("begin pkg_compras.prc_registrar_compra(:c, 'diag.rediseno'); end;", c=cap4)
con.commit()

# lo que la pantalla DEBE decir, calculado en SQL (no a mano)
cur.execute("""select c.monto_total, c.tipo_cambio, nvl(c.retencion_iva_bs, 0),
                      nvl(c.id_concepto_islr, 0)
                 from compras c where c.id_compra = :c""", c=cap1)
tot1, tasa1, ret1, con1 = cur.fetchone()
cur.execute("select nvl(pkg_retenciones.fn_islr_retencion_bs(:c, :k), 0) from dual",
            c=cap1, k=con1)
islr1 = cur.fetchone()[0]
neto1 = round((round(tot1 * tasa1, 2) - ret1 - islr1) / tasa1, 2)

cur.execute("""select c.monto_total, c.tipo_cambio, nvl(c.retencion_iva_bs, 0),
                      nvl(c.id_concepto_islr, 0)
                 from compras c where c.id_compra = :c""", c=cap2)
tot2, tasa2, ret2, con2 = cur.fetchone()
cur.execute("select nvl(pkg_retenciones.fn_retencion_bs(:c), 0) from dual", c=cap2)
ret2_vivo = cur.fetchone()[0]
cur.execute("select nvl(pkg_retenciones.fn_islr_retencion_bs(:c, :k), 0) from dual",
            c=cap2, k=con2)
islr2 = cur.fetchone()[0]
neto2 = round((round(tot2 * tasa2, 2) - ret2_vivo - islr2) / tasa2, 2)

cur.execute("select count(*) from retenciones where id_compra = :c and tipo = 'ISLR'", c=cap4)
cap4_islr = cur.fetchone()[0]
con.close()
print("  compras: 1=%s (registrada) 2=%s (borrador) 3=%s (empresa 2) 4=%s (bajo umbral)"
      % (cap1, cap2, cap3, cap4))
print("  esperado borrador: retencion %.2f %s, neto %.2f %s"
      % (ret2_vivo, "USD", neto2, "USD"))
print("  esperado registrada: retencion %.2f, neto %.2f, comprobantes ISLR de la 4: %d"
      % (ret1, neto1, cap4_islr))

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

    LEE_RESUMEN = ('(function(){function num(t){t=String(t).replace(/[^0-9,.-]/g,"");'
                   't=t.replace(/\\./g,"").replace(",",".");var n=parseFloat(t);'
                   'return isNaN(n)?null:n;}'
                   'var cards=document.querySelectorAll(".spx-resumen .spx-card");'
                   'var pie=document.querySelector(".spx-banda");'
                   'var m=pie?pie.innerText.match(/Neto a pagar:?\\s*(-?[0-9.,]+)/i):null;'
                   'return JSON.stringify({ret: cards.length>2?'
                   'num(cards[2].querySelector(".spx-card-val").innerText):null,'
                   'neto: m?num(m[1]):null, pie: pie?pie.innerText.replace(/\\s+/g," "):""});})()')

    # ---- BORRADOR: diseno, ISLR en vivo y capturas
    print("  abrir BORRADOR:", abrir_compra("CAP-ZZ-2"))
    nav.tam(1440, 1000)
    txt = nav.js("document.body.innerText") or ""
    comprobar("V1 la 28 abre sin error de rejilla y sin PL/SQL",
              "cannot be rendered" not in txt and "12 Columns" not in txt
              and "fn_clean_num" not in txt and "v_html" not in txt, txt[:200])

    cab = nav.js('(function(){var c=document.querySelector(".spx-cab");'
                 'if(!c) return "SIN CABECERA";'
                 'return c.innerText.replace(/\\s+/g," ");})()')
    comprobar("V2 la cabecera trae folio, proveedor, insignia y fecha",
              isinstance(cab, str) and "CAP-ZZ-2" in cab and "Pendiente" in cab
              and "Proveedor con concepto ISLR" in cab and "/" in cab, cab)

    tarjetas = nav.js('(function(){var t=document.querySelectorAll(".spx-resumen .spx-card");'
                      'if(t.length!==4) return "TARJETAS " + t.length;'
                      'var tot=document.querySelector(".spx-card--total .spx-card-val");'
                      'return Math.round(parseFloat(getComputedStyle(tot).fontSize)) + "px";})()')
    comprobar("V3 hay cuatro tarjetas y el total a 42 px", tarjetas == "42px", tarjetas)

    ancho_tot = nav.js('(function(){var t=document.querySelectorAll(".spx-resumen .spx-card");'
                       'if(t.length!==4) return "SIN TARJETAS";'
                       'var a=t[0].getBoundingClientRect(), d=t[3].getBoundingClientRect();'
                       'var mas = d.width > a.width + 10;'
                       'var derecha = d.right >= Math.max(a.right, t[1].getBoundingClientRect().right,'
                       ' t[2].getBoundingClientRect().right) - 1;'
                       'return (mas && derecha) ? "MAS ANCHA Y A LA DERECHA"'
                       ' : "anchos " + Math.round(a.width) + "/" + Math.round(d.width);})()')
    comprobar("V3b el total es la tarjeta mas ancha y esta al extremo derecho",
              ancho_tot == "MAS ANCHA Y A LA DERECHA", ancho_tot)

    tintes = nav.js('(function(){var t=document.querySelectorAll(".spx-resumen .spx-card");'
                    'if(t.length!==4) return "SIN TARJETAS";'
                    'var bg=[...t].map(function(c){return getComputedStyle(c).backgroundColor;});'
                    'var borde=getComputedStyle(t[3]).borderTopWidth + " "'
                    ' + getComputedStyle(t[3]).borderTopColor;'
                    'var unicos = bg.filter(function(v,i){return bg.indexOf(v)===i;}).length;'
                    'return JSON.stringify({bg:bg, unicos:unicos, borde:borde});})()')
    try:
        tt = json.loads(tintes)
    except Exception:
        tt = {}
    comprobar("V17 las cuatro tarjetas tienen tinte propio y el total borde verde",
              tt.get("unicos") == 4 and "2px" in str(tt.get("borde"))
              and "22, 160, 133" in str(tt.get("borde")), tintes)

    chips = nav.js('(function(){var c=document.querySelectorAll(".spx-chips .spx-chip");'
                   'return c.length + " / " + [...c].map(function(x){'
                   'return x.innerText.replace(/\\s+/g," ").trim();}).join(" | ");})()')
    comprobar("V18 los chips dicen proveedor, documento, moneda y retencion",
              isinstance(chips, str) and chips.startswith("4 /")
              and "Proveedor:" in chips and "CAP-ZZ-2" in chips
              and "USD" in chips and "75" in chips, chips)

    pie = nav.js('document.querySelector(".spx-banda") ? document.querySelector(".spx-banda").innerText : "SIN BANDA"')
    comprobar("V4 la banda de pago trae la tasa BCV con su fecha y el neto",
              isinstance(pie, str) and "TASA BCV" in pie.upper()
              and "VIGENTE AL" in pie.upper() and "NETO A PAGAR" in pie.upper()
              and "(Bs." in pie, pie)

    islr = nav.js('(function(){var t=document.querySelector(".spx-lineas");'
                  'return t ? t.innerText.replace(/\\s+/g," ") : "SIN ISLR";})()')
    comprobar("V5 con concepto de ISLR salen base, tarifa/sustraendo y retenido",
              isinstance(islr, str) and "ISLR concepto" in islr and "tarifa" in islr
              and "sustraendo" in islr and "Retenido" in islr, islr)

    det = nav.js('(function(){var t=document.querySelector(".spx-det");'
                 'if(!t) return "SIN TABLA";'
                 'var th=[...t.querySelectorAll("th")].map(function(x){return x.innerText.trim();});'
                 'var pie=t.querySelector("tfoot");'
                 'return th.join("|") + " / " + (pie ? pie.innerText.replace(/\\s+/g," ") : "SIN SUMATORIA");})()')
    comprobar("V6 la tabla de lineas trae Acciones y la sumatoria",
              isinstance(det, str) and "ACCIONES" in det.upper()
              and "TOTAL DE LAS" in det.upper(), det)

    zebra = nav.js('(function(){var t=document.querySelector(".spx-det");'
                   'if(!t) return "SIN TABLA";'
                   'var f=t.querySelectorAll("tbody tr");'
                   'if(f.length<2) return "UNA FILA";'
                   'var b1=getComputedStyle(f[0]).backgroundColor;'
                   'var b2=getComputedStyle(f[1]).backgroundColor;'
                   'var nums=[...t.querySelectorAll("td.num")].map(function(c){'
                   'return getComputedStyle(c).textAlign;});'
                   'var th=[...t.querySelectorAll("th.num")].map(function(c){'
                   'return getComputedStyle(c).textAlign;});'
                   'var hover=false;'
                   'for(var i=0;i<document.styleSheets.length;i++){try{'
                   'var rs=document.styleSheets[i].cssRules;'
                   'for(var k=0;k<rs.length;k++){'
                   'if(rs[k].selectorText && rs[k].selectorText.indexOf(".spx-det tbody tr:hover")>=0){hover=true;}}}'
                   'catch(e){}}'
                   'return JSON.stringify({b1:b1, b2:b2, nums:nums, th:th, hover:hover});})()')
    try:
        zz = json.loads(zebra)
    except Exception:
        zz = {}
    comprobar("V19 la tabla tiene cebra, hover y los importes a la derecha",
              zz.get("b1") != zz.get("b2")
              and all(x == "right" for x in zz.get("nums", ["x"]))
              and all(x == "right" for x in zz.get("th", ["x"]))
              and zz.get("hover") is True, zebra)

    acc = nav.js('(function(){var a=document.querySelector(".spx-det .spx-acc a");'
                 'if(!a) return "SIN BOTON";'
                 'var s=getComputedStyle(a);'
                 'return JSON.stringify({w:Math.round(a.getBoundingClientRect().width),'
                 'h:Math.round(a.getBoundingClientRect().height), r:s.borderRadius});})()')
    try:
        aa = json.loads(acc)
    except Exception:
        aa = {}
    comprobar("V20 las acciones son botones circulares de 36 px",
              aa.get("w") == 36 and aa.get("h") == 36
              and str(aa.get("r")) in ("50%", "18px"), acc)

    cuenta = nav.js('(function(){var c=document.getElementById("spx-obs-count");'
                    'if(!c) return "SIN CONTADOR";'
                    'var ta=document.getElementById("P28_OBSERVACIONES");'
                    'var borde=getComputedStyle(ta).borderLeftWidth;'
                    'return c.innerText.trim() + " / borde " + borde;})()')
    comprobar("V21 las observaciones llevan contador y acento a la izquierda",
              isinstance(cuenta, str) and "caracteres" in cuenta and "4px" in cuenta, cuenta)

    concepto = nav.js('(function(){var e=document.getElementById("P28_ID_CONCEPTO_ISLR");'
                      'if(!e) return "SIN ITEM";'
                      'var col=e.closest(".col")||e.parentElement;'
                      'return (col && col.offsetParent!==null) ? "VISIBLE" : "OCULTA";})()')
    borrar = nav.js('(function(){return document.querySelectorAll(".spx-det .fa-trash").length;})()')
    comprobar("V7 en BORRADOR se ve el concepto de ISLR y los iconos de borrar",
              concepto == "VISIBLE" and str(borrar) == "2", "%s / %s" % (concepto, borrar))

    # V14: la retencion y el neto del borrador, contra pkg_retenciones
    leido = nav.js(LEE_RESUMEN)
    try:
        d = json.loads(leido)
    except Exception:
        d = {"ret": None, "neto": None, "pie": leido}
    ret2_doc = round(ret2_vivo / tasa2, 2)
    comprobar("V14a en BORRADOR la tarjeta de retencion es la del detalle",
              casi_igual(d.get("ret"), ret2_doc), "%s vs %.2f" % (d.get("ret"), ret2_doc))
    comprobar("V14b el neto a pagar del borrador descuenta IVA e ISLR",
              casi_igual(d.get("neto"), neto2), "%s vs %.2f" % (d.get("neto"), neto2))

    # V23 (2026-11-20): la retencion se lee POSITIVA y la deduccion se explica
    # debajo de la etiqueta; la aritmetica del neto no cambia.
    ret_card = nav.js('(function(){var t=document.querySelectorAll(".spx-resumen .spx-card");'
                      'if(t.length<4) return "SIN TARJETAS";'
                      'var c=t[2];'
                      'var nota=c.querySelector(".spx-card-nota");'
                      'return JSON.stringify({val:c.querySelector(".spx-card-val").innerText.trim(),'
                      'sub:c.querySelector(".spx-card-sub").innerText.trim(),'
                      'nota: nota?nota.innerText.trim():"SIN NOTA",'
                      'lbl:c.querySelector(".spx-card-lbl").innerText.trim()});})()')
    try:
        rc = json.loads(ret_card)
    except Exception:
        rc = {}
    comprobar("V23 la retencion se lee positiva y dice Descontado del pago",
              rc.get("nota") == "Descontado del pago"
              and "-" not in str(rc.get("val")) and "-" not in str(rc.get("sub"))
              and "Bs." in str(rc.get("sub")), ret_card)

    # V24: en escritorio la tabla conserva todas sus columnas
    cols_pc = nav.js('(function(){var t=document.querySelector(".spx-det");'
                     'if(!t) return "SIN TABLA";'
                     'var vis=function(s){var e=t.querySelector(s);'
                     'return e ? getComputedStyle(e).display !== "none" : "SIN CELDA";};'
                     'return JSON.stringify({sub:vis("th.spx-col-sub"), iva:vis("th.spx-col-iva")});})()')
    try:
        cp = json.loads(cols_pc)
    except Exception:
        cp = {}
    comprobar("V24 en escritorio se ven las columnas Subtotal e IVA",
              cp.get("sub") is True and cp.get("iva") is True, cols_pc)

    print("  captura:", nav.captura(os.path.join(RES, "20261120_compra_premium_1440.png")))
    import shutil
    shutil.copyfile(os.path.join(RES, "20261120_compra_premium_1440.png"),
                    os.path.join(RES, "20261120_nota_compra_1440.png"))
    print("  captura:", os.path.join(RES, "20261120_nota_compra_1440.png"))

    nav.js("window.scrollTo(0, document.body.scrollHeight)")
    time.sleep(1.5)
    aud = nav.js('(function(){var a=document.querySelector(".spx-aud");'
                 'return a ? a.innerText.replace(/\\s+/g," ") : "SIN AUDITORIA";})()')
    comprobar("V12 la auditoria del pie son dos lineas compactas",
              isinstance(aud, str) and "Creado:" in aud and "ltima modificaci" in aud, aud)
    print("  captura:", nav.captura(os.path.join(RES, "20261119_compra_pie_1440.png")))

    # ---- a 500 px
    nav.tam(500, 1000)
    nav.js("window.location.reload()")
    nav.esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(8)
    alto = nav.js('(function(){var h=document.querySelector(".t-Header");'
                  'return h ? Math.round(h.getBoundingClientRect().height) : -1;})()')
    comprobar("V9a a 500 px la barra azul mide menos de 50 px",
              isinstance(alto, (int, float)) and 0 < alto < 50, alto)
    apiladas = nav.js('(function(){var c=document.querySelectorAll(".spx-resumen .spx-card");'
                      'if(c.length<4) return "SIN TARJETAS";'
                      'var a=c[0].getBoundingClientRect(), b=c[2].getBoundingClientRect();'
                      'return (b.top > a.bottom - 2) ? "APILADAS" : "EN LINEA";})()')
    comprobar("V9b a 500 px las tarjetas se apilan", apiladas == "APILADAS", apiladas)
    ancho = nav.js('(function(){return document.documentElement.scrollWidth'
                   ' - document.documentElement.clientWidth;})()')
    comprobar("V10 a 500 px no hay desbordamiento horizontal",
              isinstance(ancho, (int, float)) and ancho <= 1, ancho)
    total_movil = nav.js('(function(){var t=document.querySelectorAll(".spx-resumen .spx-card");'
                         'if(t.length!==4) return "SIN TARJETAS";'
                         'var a=t[0].getBoundingClientRect(), d=t[3].getBoundingClientRect();'
                         'var anchoFila=Math.round(d.width);'
                         'return JSON.stringify({ancho:anchoFila,'
                         'doble: anchoFila > Math.round(a.width)+10,'
                         'fuente: Math.round(parseFloat(getComputedStyle('
                         'document.querySelector(".spx-card--total .spx-card-val")).fontSize))});})()')
    try:
        tm = json.loads(total_movil)
    except Exception:
        tm = {}
    comprobar("V22 a 500 px el total ocupa la fila entera y baja a 30 px",
              tm.get("doble") is True and tm.get("fuente") == 30, total_movil)
    print("  captura:", nav.captura(os.path.join(RES, "20261119_cabecera_500.png")))
    nav.js('(function(){var c=document.querySelector(".spx-chips")'
           '||document.querySelector(".spx-resumen");'
           'if(!c) return "SIN CHIPS";'
           'window.scrollTo(0, c.getBoundingClientRect().top + window.pageYOffset - 70);'
           'return "OK";})()')
    time.sleep(1.5)
    print("  captura:", nav.captura(os.path.join(RES, "20261120_compra_premium_500.png")))

    # V25 (2026-11-20): en un telefono la tabla de lineas se queda con
    # Descripcion, Cantidad, Precio, Total y Acciones: IVA y Subtotal se ocultan.
    cols_movil = nav.js('(function(){var t=document.querySelector(".spx-det");'
                        'if(!t) return "SIN TABLA";'
                        'var vis=function(s){var e=t.querySelector(s);'
                        'return e ? getComputedStyle(e).display !== "none" : "SIN CELDA";};'
                        'var ths=[...t.querySelectorAll("thead th")].filter(function(e){'
                        'return getComputedStyle(e).display !== "none";})'
                        '.map(function(e){return e.innerText.trim();});'
                        'return JSON.stringify({sub:vis("th.spx-col-sub"), iva:vis("th.spx-col-iva"),'
                        'visibles:ths});})()')
    try:
        cm = json.loads(cols_movil)
    except Exception:
        cm = {}
    comprobar("V25 a 500 px se ocultan IVA y Subtotal y quedan las cinco columnas",
              cm.get("sub") is False and cm.get("iva") is False
              and [x.lower() for x in (cm.get("visibles") or [])]
              == ["#", "descripción", "cantidad", "precio", "total", "acciones"],
              cols_movil)
    desborde = nav.js('(function(){var w=document.querySelector(".spx-det-wrap");'
                      'if(!w) return "SIN TABLA";'
                      'return w.scrollWidth - w.clientWidth;})()')
    comprobar("V26 a 500 px la tabla de lineas no necesita scroll horizontal",
              isinstance(desborde, (int, float)) and desborde <= 1, desborde)
    nav.js('(function(){var t=document.querySelector(".spx-det-wrap");'
           'if(!t) return "SIN TABLA";'
           'window.scrollTo(0, t.getBoundingClientRect().top + window.pageYOffset - 70);'
           'return "OK";})()')
    time.sleep(1.5)
    print("  captura:", nav.captura(os.path.join(RES, "20261120_nota_compra_500.png")))

    # ---- V13: con el id de una compra de OTRA empresa no se pinta nada
    nav.tam(1440, 1000)
    nav.js("window.location.reload()")
    nav.esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(7)
    antes = nav.js('(function(){return [!!document.querySelector(".spx-resumen"),'
                   '!!document.querySelector(".spx-det")].join(",");})()')
    nav.js('apex.item("P28_ID_COMPRA").setValue("%s");' % cap3)
    nav.js('apex.submit({request:"APLICAR"});')
    time.sleep(10)
    despues = nav.js('(function(){return [!!document.querySelector(".spx-resumen"),'
                     '!!document.querySelector(".spx-det"),!!document.querySelector(".spx-cab"),'
                     '!!document.querySelector(".spx-aud")].join(",");})()')
    comprobar("V13 una compra de otra empresa no pinta resumen, lineas, cabecera ni auditoria",
              antes == "true,true" and despues == "false,false,false,false",
              "antes=%s despues=%s" % (antes, despues))

    # ---- REGISTRADA: insignia, comprobantes y el neto de la foto
    nav.js('window.location.href="%s/f?p=100:28:%s"' % (BASE, ses))
    nav.esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(6)
    print("  abrir REGISTRADA:", abrir_compra("CAP-ZZ-1"))
    cab1 = nav.js('(function(){var c=document.querySelector(".spx-cab");'
                  'return c ? c.innerText.replace(/\\s+/g," ") : "SIN CABECERA";})()')
    botones = nav.js('(function(){return [...document.querySelectorAll("button")]'
                     '.map(function(b){return b.getAttribute("data-otel-label")||b.innerText.trim();})'
                     '.filter(function(x){return /IMPRIMIR|imprimir/i.test(x);}).join("|");})()')
    comprobar("V8 en REGISTRADA la insignia dice Procesada y estan los dos comprobantes",
              isinstance(cab1, str) and "Procesada" in cab1
              and "BTN_IMPRIMIR_RETENCION" in str(botones)
              and "BTN_IMPRIMIR_RET_ISLR" in str(botones), "%s / %s" % (cab1, botones))
    url_islr = nav.js('(function(){var i=apex.item("P28_URL_RETENCION_ISLR");'
                      'return i ? i.getValue() : "SIN ITEM";})()')
    bajo = str(url_islr).lower().replace("%3d", "=")
    comprobar("V8b la URL del comprobante de ISLR lleva el tipo y el checksum",
              "p31_tipo=islr" in bajo and "cs=" in bajo, str(url_islr)[:160])
    leido1 = nav.js(LEE_RESUMEN)
    try:
        d1 = json.loads(leido1)
    except Exception:
        d1 = {"ret": None, "neto": None, "pie": leido1}
    ret1_doc = round(ret1 / tasa1, 2)
    comprobar("V8c en REGISTRADA la retencion es la foto del comprobante",
              casi_igual(d1.get("ret"), ret1_doc), "%s vs %.2f" % (d1.get("ret"), ret1_doc))
    comprobar("V8d el neto de la compra procesada cuadra con el libro",
              casi_igual(d1.get("neto"), neto1), "%s vs %.2f" % (d1.get("neto"), neto1))
    print("  captura:", nav.captura(os.path.join(RES, "20261119_compra_registrada_1440.png")))

    # ---- V16: sin comprobante de ISLR (bajo el umbral) el boton no sale
    print("  abrir bajo umbral:", abrir_compra("CAP-ZZ-4"))
    botones4 = nav.js('(function(){return [...document.querySelectorAll("button")]'
                      '.map(function(b){return b.getAttribute("data-otel-label")||b.innerText.trim();})'
                      '.filter(function(x){return /IMPRIMIR|imprimir/i.test(x);}).join("|");})()')
    comprobar("V16 sin comprobante de ISLR el boton no se pinta",
              cap4_islr == 0 and "BTN_IMPRIMIR_RETENCION" in str(botones4)
              and "BTN_IMPRIMIR_RET_ISLR" not in str(botones4),
              "comprobantes=%s botones=%s" % (cap4_islr, botones4))

    # ---- V16b: un comprobante de ISLR ANULADO tampoco ofrece el boton.
    # El estado de un comprobante anulado es 'ANULADO'; la condicion comparaba con
    # 'ANULADA' y por eso el boton seguia saliendo (imprimia un papel anulado).
    con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CS)
    cur = con.cursor()
    cur.execute("alter session set current_schema = WKSP_SYPEXWS")
    cur.execute("update retenciones set estado = 'ANULADO' "
                "where id_compra = :c and tipo = 'ISLR'", c=cap1)
    con.commit()
    cur.execute("select count(*) from retenciones where id_compra = :c and tipo = 'ISLR' "
                "and estado <> 'ANULADO'", c=cap1)
    quedan = cur.fetchone()[0]
    con.close()
    print("  abrir con el comprobante anulado:", abrir_compra("CAP-ZZ-1"))
    botones5 = nav.js('(function(){return [...document.querySelectorAll("button")]'
                      '.map(function(b){return b.getAttribute("data-otel-label")||b.innerText.trim();})'
                      '.filter(function(x){return /IMPRIMIR|imprimir/i.test(x);}).join("|");})()')
    comprobar("V16b con el comprobante de ISLR ANULADO el boton no se pinta",
              quedan == 0 and "BTN_IMPRIMIR_RETENCION" in str(botones5)
              and "BTN_IMPRIMIR_RET_ISLR" not in str(botones5),
              "vigentes=%s botones=%s" % (quedan, botones5))

    # ---- V15: el concepto del proveedor llega a un alta y no pisa lo elegido
    # Se entra por el boton «Nueva compra» de la lista: es el camino real y ademas
    # limpia la cache de la pagina 28 (si no, P28_ID_COMPRA sigue con la compra
    # anterior en el estado de sesion y no seria un alta).
    nav.js('window.location.href="%s/f?p=100:27:%s"' % (BASE, ses))
    nav.esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(6)
    nav.js('(function(){var b=[...document.querySelectorAll("button,a")].find(function(x){'
           'return (x.getAttribute("data-otel-label")||"")==="BTN_NUEVA_COMPRA";});'
           'if(b){b.click();}return b?"CLIC":"SIN BOTON";})()')
    time.sleep(9)
    es_alta = nav.js('(function(){var i=apex.item("P28_ID_COMPRA");'
                      'return i ? String(i.getValue()) : "SIN ITEM";})()')
    comprobar("V15a0 «Nueva compra» abre un alta (P28_ID_COMPRA vacio)",
              es_alta in ("", "null", "None"), es_alta)
    nav.js('(function(){apex.item("P28_ID_PROVEEDOR").setValue("%s");'
           'var e=document.getElementById("P28_ID_PROVEEDOR");'
           'if(e){e.dispatchEvent(new Event("change",{bubbles:true}));}return "OK";})()' % prov_a)
    time.sleep(5)
    con_auto = nav.js('apex.item("P28_ID_CONCEPTO_ISLR").getValue()')
    comprobar("V15a elegir el proveedor propone su concepto de ISLR",
              str(con_auto) == str(con057), "%s vs %s" % (con_auto, con057))

    # V15b: un proveedor SIN concepto deja el campo vacio (el concepto sigue al
    # proveedor mientras la compra no exista).
    nav.js('(function(){apex.item("P28_ID_PROVEEDOR").setValue("%s");'
           'var e=document.getElementById("P28_ID_PROVEEDOR");'
           'if(e){e.dispatchEvent(new Event("change",{bubbles:true}));}return "OK";})()' % prov_b)
    time.sleep(5)
    con_b = nav.js('apex.item("P28_ID_CONCEPTO_ISLR").getValue()')
    comprobar("V15b un proveedor sin concepto deja el campo vacio",
              str(con_b) in ("", "null", "None"), con_b)

    # V15c: un concepto elegido a mano NO se pierde al reenviar la pagina (un guardado
    # que falle la validacion vuelve a pasar por el cargador).
    nav.js('apex.item("P28_ID_CONCEPTO_ISLR").setValue("%s");' % con063)
    nav.js('apex.submit({request:"APLICAR"});')
    time.sleep(10)
    con_tras = nav.js('apex.item("P28_ID_CONCEPTO_ISLR").getValue()')
    comprobar("V15c el cargador no borra el concepto elegido al reenviar",
              str(con_tras) == str(con063), "%s vs %s" % (con_tras, con063))

    # V15d: en un documento que YA existe el concepto no se toca al cambiar de proveedor
    print("  abrir BORRADOR para V15d:", abrir_compra("CAP-ZZ-2"))
    con_antes = nav.js('apex.item("P28_ID_CONCEPTO_ISLR").getValue()')
    nav.js('(function(){apex.item("P28_ID_PROVEEDOR").setValue("%s");'
           'var e=document.getElementById("P28_ID_PROVEEDOR");'
           'if(e){e.dispatchEvent(new Event("change",{bubbles:true}));}return "OK";})()' % prov_b)
    time.sleep(5)
    con_desp = nav.js('apex.item("P28_ID_CONCEPTO_ISLR").getValue()')
    comprobar("V15d en un documento existente el concepto no se pisa",
              str(con_antes) == str(con057) and str(con_desp) == str(con057),
              "%s -> %s (esperado %s)" % (con_antes, con_desp, con057))

    # ---- V11: borrar una linea (confirmacion + peticion POST)
    print("  abrir BORRADOR otra vez:", abrir_compra("CAP-ZZ-2"))
    nav.js("window.confirm = function () { return true; };")
    clic = nav.js('(function(){var i=document.querySelector(".spx-det .fa-trash");'
                  'if(!i) return "SIN BOTE"; var a=i.closest("a"); if(!a) return "SIN ENLACE";'
                  'a.click(); return "CLIC";})()')
    time.sleep(10)
    filas = nav.js('(function(){var t=document.querySelector(".spx-det");'
                   'return t ? t.querySelectorAll("tbody tr").length : -1;})()')
    comprobar("V11 el icono de borrar quita la linea de la compra",
              clic == "CLIC" and str(filas) == "1", "%s / filas=%s" % (clic, filas))
finally:
    nav.cerrar()
    con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CS)
    cur = con.cursor()
    cur.execute("alter session set current_schema = WKSP_SYPEXWS")
    for f in FOLIOS:
        cur.execute("delete from retenciones_det where id_compra in "
                    "(select id_compra from compras where folio_factura = :f)", f=f)
        con.commit()
        cur.execute("delete from retenciones where id_compra in "
                    "(select id_compra from compras where folio_factura = :f)", f=f)
        con.commit()
        cur.execute("delete from compras_det where id_compra in "
                    "(select id_compra from compras where folio_factura = :f)", f=f)
        con.commit()
        cur.execute("delete from compras where folio_factura = :f", f=f)
        con.commit()
    cur.execute("delete from proveedores where rif in ('CAP-PROV-A', 'CAP-PROV-B')")
    con.commit()
    # el contador de retenciones vuelve al ultimo comprobante que quedo: los numeros
    # son fiscales y una prueba no debe dejar huecos
    cur.execute("""merge into retencion_contador t
                   using (select 1 as id_empresa, to_char(sysdate, 'YYYYMM') as periodo,
                                 nvl((select max(nvl(to_number(substr(numero_comprobante, 7)), 0))
                                        from retenciones
                                       where id_empresa = 1
                                         and substr(numero_comprobante, 1, 6) = to_char(sysdate, 'YYYYMM')),
                                     :ini) as ultimo
                            from dual) s
                      on (t.id_empresa = s.id_empresa and t.periodo = s.periodo)
                   when matched then update set t.ultimo = s.ultimo
                   when not matched then insert (id_empresa, periodo, ultimo)
                        values (s.id_empresa, s.periodo, s.ultimo)""", ini=contador_ini)
    con.commit()
    cur.execute("begin delete from usuario_empresa where usuario_id in "
                "(select usuario_id from usuario where upper(username)='DIAG.REDISENO'); commit; "
                "delete from usuario where upper(username)='DIAG.REDISENO'; commit; end;")
    con.close()

print()
print("RESULTADO: FALLAS=" + str(len(fallas)))
for f in fallas:
    print("  - " + f)
sys.exit(1 if fallas else 0)
