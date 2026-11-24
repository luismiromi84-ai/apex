#!/usr/bin/env python3
# =============================================================================
# 20261121_libro_recibo_capturas.py
#
# Acabado de las dos ultimas pantallas del pase visual: Libro de compras y
# ventas (18) y Recibo (25, dialogo). No mide logica de negocio: mide que la
# pantalla se vea como el resto de la app.
#
# Libro (18):
#   L1  la banda de totales trae las cuatro cifras con sus rotulos
#   L2  el neto va destacado y las cifras cuadran con la base
#   L3  las cuatro regiones siguen en su orden (filtros, totales, IGTF, libro)
#   L4  los botones Excel fiscal y PDF siguen en la fila de filtros
#   L5  el informe del IGTF lleva sus encabezados en espanol
#   L6  no se ve el PL/SQL de ninguna region ni error de rejilla
#   L7  a 500 px los cuatro filtros van a media fila (ya no se leen "M...")
#   L8  a 500 px la banda envuelve y no hay desborde de la pagina
#
# Recibo (25):
#   R1  abre con la cabecera: recibo, insignia, cliente, moneda y fecha
#   R2  el resumen son cuatro tarjetas y el neto va en verde y mas grande
#   R3  los botones conservan su orden y "Salir" queda a la derecha
#   R4  al elegir la factura se refrescan la cabecera y el resumen
#   R5  al teclear el monto se refresca el resumen (monto, IGTF, neto)
#   R6  la etiqueta flotante no se queda encima de la cifra
#
# Capturas (deploy/resultados/):
#   20261121_libro_1440.png · 20261121_libro_500.png · 20261121_recibo.png
#
# Uso:  python deploy/diagnostico/20261121_libro_recibo_capturas.py
# Crea y borra su propio usuario temporal. No escribe nada de negocio.
# =============================================================================
import base64
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

EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
BASE = "https://gfd7e2575d251ae-sypexsql.adb.mx-monterrey-1.oraclecloudapps.com/ords"
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(REPO, "deploy", "conexion"))
from verificar_conexion import CONNECT_STRING as CS, credenciales  # noqa: E402

USUARIO, CLAVE = "diag.vis", "Diag#2026"
SALIDA = os.path.join(REPO, "deploy", "resultados")
PUERTO = 9293

R_FILTROS = "R43000000000000700"
R_TOTALES = "R43000000000000730"
R_IGTF = "R43000000000000890"
R_LIBRO = "R43000000000000710"
R_CAB = "R43000000000001510"
R_FORM = "R43000000000000802"
R_RESUMEN = "R43000000000001520"
R_ACCIONES = "R43000000000001530"

fallas = []


def comprobar(nombre, ok, detalle=""):
    print(("  OK  " if ok else "  MAL ") + nombre + ("" if ok else "  " + str(detalle)[:300]))
    if not ok:
        fallas.append(nombre)


def omitir(nombre, motivo):
    print("  OMIT " + nombre + "  " + motivo)


class Nav:
    def __init__(self):
        self.proc = subprocess.Popen(
            [EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
             "--window-size=1440,1000", f"--remote-debugging-port={PUERTO}",
             "--user-data-dir=" + os.path.join(tempfile.gettempdir(), "opencode", "edge-vis21"),
             "about:blank"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        objetivo = None
        for _ in range(40):
            try:
                lista = json.loads(urllib.request.urlopen(
                    f"http://127.0.0.1:{PUERTO}/json/list", timeout=2).read())
                pag = [t for t in lista if t.get("type") == "page"]
                if pag:
                    objetivo = pag[0]
                    break
            except Exception:
                pass
            time.sleep(0.5)
        self.ws = websocket.create_connection(objetivo["webSocketDebuggerUrl"], timeout=60)
        self.ws.settimeout(60)
        self.n = 0
        self.cmd("Page.enable")
        self.cmd("Runtime.enable")

    def cmd(self, method, **params):
        self.n += 1
        self.ws.send(json.dumps({"id": self.n, "method": method, "params": params}))
        while True:
            r = json.loads(self.ws.recv())
            if r.get("id") == self.n:
                return r.get("result", {})

    def js(self, expr):
        r = self.cmd("Runtime.evaluate", expression=expr, returnByValue=True, awaitPromise=True)
        if "exceptionDetails" in r:
            return "EXC: " + str(r["exceptionDetails"].get("exception", {}).get("description"))[:300]
        return r.get("result", {}).get("value")

    def esperar(self, cond, seg=45):
        fin = time.time() + seg
        while time.time() < fin:
            if self.js(cond):
                return True
            time.sleep(0.5)
        return False

    def tamano(self, ancho, alto):
        self.cmd("Emulation.setDeviceMetricsOverride", width=ancho, height=alto,
                 deviceScaleFactor=1, mobile=False)

    def captura(self, ruta):
        r = self.cmd("Page.captureScreenshot", format="png")
        datos = r.get("data")
        if not datos:
            return False
        with open(ruta, "wb") as fh:
            fh.write(base64.b64decode(datos))
        return True

    def cerrar(self):
        try:
            self.proc.terminate()
        except Exception:
            pass


EN_DIALOGO = """(function(){var f=document.querySelector("iframe");
  if(!f){return "SIN DIALOGO";}
  var w=f.contentWindow;var d=w.document;var apex=w.apex;%s})()"""


def numero(txt):
    """Primer importe del texto con formato 1.234,56 o 1,234.56."""
    m = re.search(r"-?[\d.,]+", txt or "")
    if not m:
        return None
    s = m.group(0)
    if re.search(r"\.\d{2}$", s):
        s = s.replace(",", "")
    else:
        s = s.replace(".", "").replace(",", ".")
    try:
        return float(s)
    except ValueError:
        return None


conn = oracledb.connect(user=credenciales()["DB_USER"], password=credenciales()["DB_PASSWORD"], dsn=CS)
cur = conn.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")
cur.execute("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario "
            "where upper(username) = 'DIAG.VIS'); commit; "
            "delete from usuario where upper(username) = 'DIAG.VIS'; commit; end;")
cur.execute("""insert into usuario (username, email, password_hash, estado, id_empresa, rol_id,
                                    debe_cambiar_clave, reintentos_fallidos)
               values (:u, :e, sypex_hash_password(:c), 'ACTIVO', 1,
                       (select id_rol from syn_roles where codigo_rol = 'ADMIN'), 'N', 0)""",
            u=USUARIO, e=USUARIO + "@synpex.local", c=CLAVE)
conn.commit()

# Lo que deberia sumar la banda del mes en curso, segun la base.
cur.execute("""select round(nvl(sum(sg * tot), 0), 2)
                 from (select case when f.estado = 'ANULADA' then 0 else 1 end
                              * case when f.tipo_documento = 'NC' then -1 else 1 end as sg,
                              nvl(f.monto_total, 0) * nvl(f.tipo_cambio, 1) as tot
                         from facturas f
                        where f.id_empresa = 1
                          and f.fecha_emision >= trunc(sysdate, 'MM')
                          and f.fecha_emision < add_months(trunc(sysdate, 'MM'), 1)
                       union all
                       select case when co.estado = 'ANULADA' then 0 else 1 end
                              * case when co.tipo_documento = 'NC' then -1 else 1 end,
                              nvl(co.monto_total, 0) * nvl(co.tipo_cambio, 1)
                                + nvl(co.igtf_bs, 0)
                         from compras co
                        where co.id_empresa = 1
                          and co.fecha_emision >= trunc(sysdate, 'MM')
                          and co.fecha_emision < add_months(trunc(sysdate, 'MM'), 1))""")
TOTAL_MES = float(cur.fetchone()[0] or 0)
cur.execute("""select id_recibo, id_factura, monto_cobrado, cod_moneda
                 from recibos where id_empresa = 1 and estado = 'ACTIVO'
                order by id_recibo desc fetch first 1 rows only""")
fila = cur.fetchone()
RECIBO = fila[0] if fila else None
cur.execute("""select id_factura from facturas
                where id_empresa = 1 and tipo_documento = 'FAC' and estado in ('TIMBRADA', 'PARCIAL')
                  and cod_moneda = 'USD' and fn_saldo_factura(id_factura) > 0.01
                order by id_factura desc fetch first 1 rows only""")
fila = cur.fetchone()
FACTURA = fila[0] if fila else None

nav = Nav()
try:
    nav.tamano(1440, 1000)
    nav.js('window.location.href="%s/f?p=100:9999"' % BASE)
    nav.esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(1)
    nav.js('(function(){apex.item("P9999_USERNAME").setValue(%s);apex.item("P9999_PASSWORD").setValue(%s);'
           'var b=[...document.querySelectorAll("button")].find(x=>/sign in|iniciar|entrar/i.test(x.innerText));'
           'if(b){b.click();}})()' % (json.dumps(USUARIO), json.dumps(CLAVE)))
    time.sleep(9)
    m = re.search(r"session=(\d+)", nav.js("window.location.href") or "")
    if not m:
        raise SystemExit("no se pudo entrar: " + str(nav.js("document.body.innerText"))[:200])
    ses = m.group(1)

    # ------------------------------------------------------------ Libro (18)
    print("Libro de compras y ventas (18)")
    nav.js('window.location.href="%s/f?p=100:18:%s"' % (BASE, ses))
    nav.esperar('document.readyState === "complete" && !!document.getElementById("%s")' % R_LIBRO, 60)
    time.sleep(8)
    nav.js("window.scrollTo(0,0)")
    time.sleep(1)
    comprobar("captura del libro a 1440", nav.captura(os.path.join(SALIDA, "20261121_libro_1440.png")))

    cifras = nav.js("(function(){var o=[];document.querySelectorAll('#%s .spx-banda-item')"
                    ".forEach(function(i){o.push(i.innerText.replace(/\\n/g,' ').trim());});return o;})()" % R_TOTALES) or []
    comprobar("L1 la banda de totales trae las cuatro cifras", len(cifras) == 4, cifras)
    etiquetas = [c.split(" ")[0].upper() for c in cifras]
    plano = " | ".join(cifras).upper()
    comprobar("L1 los cuatro rotulos estan",
              all(t in plano for t in ("TOTAL BS DEL PERIODO", "IGTF DE COMPRAS", "IVA RETENIDO", "NETO")),
              plano)
    comprobar("L1 el neto va destacado",
              nav.js("!!document.querySelector('#%s .spx-banda-item.spx-banda-neto')" % R_TOTALES) is True)
    valores = [numero(c.split(" ", 1)[1]) for c in cifras if " " in c]
    valores = [v for v in valores if v is not None]
    if TOTAL_MES:
        comprobar("L2 el total del periodo cuadra con la base", any(abs(v - TOTAL_MES) < 0.05 for v in valores),
                  "esperado %.2f, en pantalla %s" % (TOTAL_MES, valores))
    else:
        omitir("L2 el total del periodo cuadra con la base", "(no hay documentos en el mes)")
    cajas = nav.js("(function(){var o={};['%s','%s','%s','%s'].forEach(function(id){"
                   "var e=document.getElementById(id);o[id]=e?Math.round(e.getBoundingClientRect().top):null;});"
                   "return o;})()" % (R_FILTROS, R_TOTALES, R_IGTF, R_LIBRO))
    orden = [cajas[k] for k in (R_FILTROS, R_TOTALES, R_IGTF, R_LIBRO)] if isinstance(cajas, dict) else []
    comprobar("L3 las regiones siguen en su orden",
              len(orden) == 4 and all(orden[i] is not None and orden[i + 1] is not None
                                      and orden[i] < orden[i + 1] for i in range(3)), cajas)
    botones = nav.js("(function(){var o=[];document.querySelectorAll('#%s button').forEach(function(b){"
                     "o.push(b.innerText.trim() || b.getAttribute('data-otel-label'));});return o;})()" % R_FILTROS) or []
    comprobar("L4 los botones Excel fiscal y PDF siguen en filtros",
              any("Excel" in (b or "") for b in botones) and any("PDF" in (b or "") for b in botones), botones)
    encabezados = nav.js("(function(){var o=[];document.querySelectorAll('#%s th')"
                         ".forEach(function(t){o.push(t.innerText.trim());});return o;})()" % R_IGTF) or []
    comprobar("L5 el informe del IGTF lleva encabezados en espanol",
              encabezados[:5] == ["Moneda", "Cobros", "IGTF en divisa", "IGTF Bs", "Neto cobrado"], encabezados)
    texto = nav.js("document.body.innerText") or ""
    comprobar("L6 no se ve el PL/SQL de una region",
              "v_html" not in texto and "declare" not in texto and "spx-banda" not in texto)
    comprobar("L6 sin error de rejilla ni de region",
              "Column 13" not in texto and "cannot be rendered" not in texto)
    desborde = nav.js("document.documentElement.scrollWidth - window.innerWidth")
    comprobar("L6 el libro no desborda la ventana a 1440", (desborde or 0) <= 2, desborde)

    nav.tamano(500, 900)
    time.sleep(4)
    nav.js("window.scrollTo(0,0)")
    time.sleep(1)
    comprobar("captura del libro a 500", nav.captura(os.path.join(SALIDA, "20261121_libro_500.png")))
    anchos = nav.js("(function(){var o=[];document.querySelectorAll('#%s .col')"
                    ".forEach(function(c){o.push(Math.round(c.getBoundingClientRect().width));});return o;})()" % R_FILTROS) or []
    comprobar("L7 a 500 px los filtros van a media fila", len(anchos) >= 4 and min(anchos) >= 150, anchos)
    alto_banda = nav.js("(function(){var e=document.querySelector('#%s .spx-banda');"
                        "return e?Math.round(e.getBoundingClientRect().height):0;})()" % R_TOTALES)
    comprobar("L8 a 500 px la banda envuelve", (alto_banda or 0) > 60, alto_banda)
    desborde5 = nav.js("document.documentElement.scrollWidth - window.innerWidth")
    comprobar("L8 el libro no desborda a 500 px", (desborde5 or 0) <= 2, desborde5)

    # ------------------------------------------------------ Recibo (25)
    print("Recibo (25)")
    nav.tamano(1440, 1000)
    time.sleep(2)
    nav.js('window.location.href="%s/f?p=100:24:%s"' % (BASE, ses))
    nav.esperar('document.readyState === "complete" && !!document.querySelector("table.a-IRR-table")', 60)
    time.sleep(6)

    # R1/R3 sobre un recibo guardado, para no inventar nada.
    if RECIBO:
        abierto = nav.js("(function(){var a=document.querySelector('a[href*=\"p25_id_recibo%%3D%d\"]')"
                         "||document.querySelector('a[href*=\"p25_id_recibo=%d\"]');"
                         "if(a){a.click();return 'CLIC';}return 'NO';})()" % (RECIBO, RECIBO))
        time.sleep(10)
        cab = nav.js(EN_DIALOGO % "var e=d.querySelector('.spx-cab');return e?e.innerText.replace(/\\n/g,' | '):'NO';")
        comprobar("R1 el recibo guardado abre con su cabecera",
                  abierto == "CLIC" and isinstance(cab, str) and cab.startswith("Recibo"), (abierto, cab))
        comprobar("R1 la cabecera trae la insignia del estado",
                  nav.js(EN_DIALOGO % "var e=d.querySelector('.spx-cab .status-badge');"
                                      "return e?e.className:'NO';") and "status-badge" in
                  str(nav.js(EN_DIALOGO % "var e=d.querySelector('.spx-cab .status-badge');return e?e.className:'NO';")))
        tarjetas = nav.js(EN_DIALOGO % "var o=[];d.querySelectorAll('.spx-resumen .spx-card')"
                          ".forEach(function(c){var r=c.getBoundingClientRect();"
                          "o.push([c.className.replace('spx-card ',''),Math.round(r.top),Math.round(r.width)]);});return o;") or []
        comprobar("R2 el resumen son cuatro tarjetas", isinstance(tarjetas, list) and len(tarjetas) == 4, tarjetas)
        neto = nav.js(EN_DIALOGO % "var c=d.querySelector('.spx-resumen .spx-card--total');"
                                   "if(!c)return 'NO';var v=c.querySelector('.spx-card-val');"
                                   "return [w.getComputedStyle(v).color, w.getComputedStyle(v).fontSize,"
                                   " w.getComputedStyle(d.querySelector('.spx-card--sub .spx-card-val')).fontSize].join('|');")
        comprobar("R2 el neto va en verde y mas grande",
                  isinstance(neto, str) and "rgb(15, 118, 110)" in neto
                  and float(re.sub("[^0-9.]", "", neto.split("|")[1]) or 0) >= 24, neto)
        fila_btns = nav.js(EN_DIALOGO % "var o=[];d.querySelectorAll('#%s button').forEach(function(b){"
                                        "var r=b.getBoundingClientRect();o.push([b.innerText.trim(),Math.round(r.left),Math.round(r.top)]);});return o;" % R_ACCIONES) or []
        nombres = [b[0] for b in fila_btns if b[0]]
        comprobar("R3 los botones conservan su orden",
                  nombres[-1:] == ["Salir"] and all(n in nombres for n in ("Anular cobro", "Conciliar")), nombres)
        ancho_dialogo = nav.js(EN_DIALOGO % "return Math.round(d.body.getBoundingClientRect().width);") or 0
        salir = [b for b in fila_btns if b[0] == "Salir"]
        comprobar("R3 «Salir» queda a la derecha",
                  bool(salir) and salir[0][1] > ancho_dialogo * 0.7, (salir, ancho_dialogo))
        nav.js(EN_DIALOGO % 'var b=[...d.querySelectorAll("button")].find(function(x){'
                           'return x.innerText.trim()==="Salir";});if(b){b.click();}')
        time.sleep(6)

    # R4/R5/R6 en un recibo nuevo, sin guardar nada.
    nav.js('window.location.href="%s/f?p=100:24:%s"' % (BASE, ses))
    time.sleep(7)
    nav.js('(function(){var b=[...document.querySelectorAll("button,a")].find(function(x){'
           'return (x.getAttribute("data-otel-label")||"")==="BTN_NUEVO_COBRO" || /Registrar cobro/i.test(x.innerText);});'
           'if(b){b.click();}})()')
    time.sleep(9)
    cab0 = nav.js(EN_DIALOGO % "var e=d.querySelector('.spx-cab');return e?e.innerText.replace(/\\n/g,' | '):'NO';")
    comprobar("R4 el recibo nuevo abre en blanco y lo dice",
              isinstance(cab0, str) and "Elige la factura" in cab0, cab0)
    nav.js(EN_DIALOGO % ('apex.item("P25_ID_FACTURA").setValue("%s");'
                         'd.getElementById("P25_ID_FACTURA").dispatchEvent(new Event("change",{bubbles:true}));' % FACTURA))
    time.sleep(9)
    cab1 = nav.js(EN_DIALOGO % "var e=d.querySelector('.spx-cab');return e?e.innerText.replace(/\\n/g,' | '):'NO';")
    comprobar("R4 al elegir la factura se refresca la cabecera",
              isinstance(cab1, str) and "Recibo de" in cab1, cab1)
    nav.js(EN_DIALOGO % 'apex.item("P25_MONTO").setValue("1000");'
                       'd.getElementById("P25_MONTO").dispatchEvent(new Event("change",{bubbles:true}));')
    time.sleep(9)
    suma = nav.js(EN_DIALOGO % "var o=[];d.querySelectorAll('.spx-resumen .spx-card')"
                               ".forEach(function(c){o.push(c.innerText.replace(/\\n/g,' '));});return o;") or []
    plano2 = " | ".join(suma) if isinstance(suma, list) else ""
    comprobar("R5 al teclear el monto se refresca el resumen",
              "1.000,00" in plano2 or "1000,00" in plano2, plano2)
    comprobar("R5 el neto del recibo ya no esta vacio", "—" not in plano2.split("NETO")[-1], plano2)
    flotadas = nav.js(EN_DIALOGO % "var o=[];d.querySelectorAll('.t-Form-fieldContainer').forEach(function(c){"
                                   "var i=c.querySelector('input,select,textarea');if(!i)return;"
                                   "if((i.value||'').toString().trim()!=='' && !c.classList.contains('js-show-label'))"
                                   "o.push(i.id||i.name);});return o;")
    comprobar("R6 la etiqueta flotante no se queda encima de la cifra",
              isinstance(flotadas, list) and len(flotadas) == 0, flotadas)
    comprobar("captura del recibo", nav.captura(os.path.join(SALIDA, "20261121_recibo.png")))
finally:
    nav.cerrar()
    try:
        cur.execute("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario "
                    "where upper(username) = 'DIAG.VIS'); commit; "
                    "delete from usuario where upper(username) = 'DIAG.VIS'; commit; end;")
        conn.commit()
    except Exception as ex:
        print("limpieza:", ex)

print()
print("RESULTADO: FALLAS=%d" % len(fallas))
for f in fallas:
    print("  - " + f)
sys.exit(1 if fallas else 0)
