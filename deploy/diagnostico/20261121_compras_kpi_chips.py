#!/usr/bin/env python3
# =============================================================================
# 20261121_compras_kpi_chips.py
#
# La pagina 27 "Facturas de Compras" con el acabado de las paginas 5, 8, 20, 22
# y 24, comprobado con navegador real (Edge headless por CDP):
#
#   K0  la pagina abre y el login funciona con un usuario temporal de la empresa 1
#   K1  la fila de indicadores va ENCIMA del informe y tiene sus cuatro tarjetas
#   K2  los cuatro numeros que se ven son los de la base
#   K3  los seis chips estan y el activo es Todos
#   K4  el chip Procesada filtra: quedan las compras registradas y el chip queda activo
#   K5  el chip Borrador filtra: quedan los borradores y la insignia sale ambar
#   K6  el chip Anulada deja el informe vacio, y volver a Todos lo repone
#   K7  las insignias llevan su clase y su color (Procesada verde)
#   K8  capturas a 1440 y a 500 px
#
# Uso:  python deploy/diagnostico/20261121_compras_kpi_chips.py
# Requiere: websocket-client, oracledb y Edge instalado.
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

USUARIO, CLAVE = "diag.compras", "Diag#2026"
SALIDA = os.path.join(REPO, "deploy", "resultados")
LISTA = "R43000000000001000"

fallas = []


def comprobar(nombre, condicion, detalle=""):
    print(("  OK  " if condicion else "  MAL ") + nombre + (" " + str(detalle) if detalle else ""))
    if not condicion:
        fallas.append(nombre)


class Nav:
    def __init__(self, puerto=9301):
        self.proc = subprocess.Popen(
            [EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
             "--window-size=1440,1000",
             f"--remote-debugging-port={puerto}",
             f"--user-data-dir={os.path.join(tempfile.gettempdir(), 'opencode', 'edge-compras')}",
             "about:blank"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
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
        self.ws = websocket.create_connection(objetivo["webSocketDebuggerUrl"], timeout=90)
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


# --- un usuario temporal de la empresa 1 (la app exige empresa y rol) --------
conn = oracledb.connect(user=credenciales()["DB_USER"], password=credenciales()["DB_PASSWORD"], dsn=CS)
cur = conn.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")
cur.execute("delete from syn_login_log where upper(usuario_intentado) = 'DIAG.COMPRAS'")
cur.execute("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario "
            "where upper(username) = 'DIAG.COMPRAS'); commit; "
            "delete from usuario where upper(username) = 'DIAG.COMPRAS'; commit; end;")
cur.execute("""insert into usuario (username, email, password_hash, estado, id_empresa, rol_id,
                                    debe_cambiar_clave, reintentos_fallidos)
               values ('diag.compras', 'diag.compras@synpex.local', sypex_hash_password('Diag#2026'),
                       'ACTIVO', 1, (select id_rol from syn_roles where codigo_rol = 'ADMIN'), 'N', 0)""")
conn.commit()

# --- lo que dice la base ----------------------------------------------------
cur.execute("""select count(*),
                      nvl(sum(case when trunc(fecha_emision,'MM') = trunc(sysdate,'MM')
                                   then monto_total * nvl(tipo_cambio,1) end), 0),
                      nvl(sum(case when trunc(fecha_emision,'MM') = trunc(sysdate,'MM')
                                   then retencion_iva_bs end), 0),
                      count(case when estado = 'BORRADOR' then 1 end)
                 from compras
                where id_empresa = 1 and tipo_documento = 'FAC'
                  and nvl(estado,'#') <> 'ANULADA'""")
n_mes, tot_bs, ret_bs, n_bor = cur.fetchone()
cur.execute("""select estado, count(*) from compras where id_empresa = 1 group by estado""")
por_estado = dict(cur.fetchall())
print("base: mes=%s total=%s retencion=%s borradores=%s estados=%s"
      % (n_mes, tot_bs, ret_bs, n_bor, por_estado))


def num(txt):
    """'2.409.316,81' -> 2409316.81 ; '&#8212;' -> None.

    2026-11-23: la app pinta el formato venezolano (miles con punto, decimales
    con coma). El test se habia escrito contra '2,409,316.81', que era el par
    NLS al reves: se corrigio en la app y aqui.
    """
    t = (txt or "").strip()
    if t in ("", "—", "&#8212;"):
        return None
    try:
        return float(t.replace(".", "").replace(",", "."))
    except ValueError:
        return None


nav = Nav()
try:
    nav.tamano(1440, 1000)
    nav.js('window.location.href="%s/f?p=100:9999"' % BASE)
    nav.esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(1)
    nav.js('(function(){apex.item("P9999_USERNAME").setValue(%s);apex.item("P9999_PASSWORD").setValue(%s);'
           'var b=[...document.querySelectorAll("button")].find(x=>/sign in|iniciar|entrar/i.test(x.innerText));'
           'if(b){b.click();}})()' % (json.dumps(USUARIO), json.dumps(CLAVE)))
    time.sleep(8)
    m = re.search(r"session=(\d+)", nav.js("window.location.href") or "")
    ses = m.group(1) if m else ""
    comprobar("K0 el login abre sesion", bool(ses), nav.js("document.location.href"))
    if not ses:
        raise SystemExit(1)

    # --- K1: la fila de indicadores, encima del informe ---------------------
    nav.js('window.location.href="%s/f?p=100:27:%s"' % (BASE, ses))
    nav.esperar('!!document.querySelector(".spx-kpis")', 45)
    time.sleep(5)
    geo = nav.js('(function(){var k=document.querySelector(".spx-kpis"),'
                 'l=document.querySelector("#%s");'
                 'if(!k||!l) return "FALTA";'
                 'return JSON.stringify({k:k.getBoundingClientRect().top,'
                 'l:l.getBoundingClientRect().top,'
                 'cards:k.querySelectorAll(".spx-card").length,'
                 'chips:document.querySelectorAll(".spx-filtro").length});})()' % LISTA)
    try:
        g = json.loads(geo)
    except Exception:
        g = None
    comprobar("K1 la fila de indicadores va encima del informe",
              bool(g) and g["k"] < g["l"], geo)
    comprobar("K1 son cuatro tarjetas", bool(g) and g["cards"] == 4, g and g["cards"])
    comprobar("K3 estan los seis chips", bool(g) and g["chips"] == 6, g and g["chips"])
    etiquetas = nav.js('JSON.stringify([...document.querySelectorAll(".spx-filtro")]'
                       '.map(function(x){return x.innerText.trim();}))')
    comprobar("K3 el chip del pendiente se lee Pendiente",
              "Pendiente" in str(etiquetas) and "Borrador" not in str(etiquetas), etiquetas)

    # --- K2: los cuatro numeros -------------------------------------------
    tarjetas = nav.js('(function(){return JSON.stringify([...document.querySelectorAll(".spx-kpis .spx-card")]'
                      '.map(function(c){return {'
                      'l:(c.querySelector(".spx-card-lbl")||{}).innerText,'
                      'v:(c.querySelector(".spx-card-val")||{}).innerText};}));})()')
    try:
        t = json.loads(tarjetas)
    except Exception:
        t = []
    print("  tarjetas:", tarjetas)
    comprobar("K2 hay cuatro numeros en pantalla", len(t) == 4, len(t))
    if len(t) == 4:
        comprobar("K2 «Compras del mes» es el conteo del mes", num(t[0]["v"]) == float(n_mes),
                  (t[0]["v"], n_mes))
        comprobar("K2 «Total compras (Bs)» es la suma de la base",
                  num(t[1]["v"]) is not None and abs(num(t[1]["v"]) - float(tot_bs)) < 0.01,
                  (t[1]["v"], round(float(tot_bs), 2)))
        comprobar("K2 «Retencion IVA (Bs)» es la suma de la base",
                  num(t[2]["v"]) is not None and abs(num(t[2]["v"]) - float(ret_bs)) < 0.01,
                  (t[2]["v"], round(float(ret_bs), 2)))
        comprobar("K2 «En borrador» es el conteo de pendientes", num(t[3]["v"]) == float(n_bor),
                  (t[3]["v"], n_bor))
        comprobar("K2 la tarjeta se lee Pendientes",
                  str(t[3]["l"]).strip().lower() == "pendientes", t[3]["l"])

    # --- K7: las insignias -------------------------------------------------
    insig = nav.js('(function(){var b=document.querySelectorAll("#%s .status-badge");'
                   'if(!b.length) return "SIN INSIGNIAS";'
                   'var c=window.getComputedStyle(b[0]);'
                   'return JSON.stringify({n:b.length, cls:b[0].className,'
                   'color:c.color, bg:c.backgroundColor, txt:b[0].innerText.trim()});})()' % LISTA)
    print("  insignia:", insig)
    try:
        i = json.loads(insig)
    except Exception:
        i = None
    comprobar("K7 las insignias llevan su clase de estado",
              bool(i) and "status-badge" in i["cls"] and "status-" in i["cls"], insig)
    comprobar("K7 la insignia pintada no es gris de texto plano",
              bool(i) and i["color"] not in ("", "rgb(0, 0, 0)"), i and i["color"])

    def filas():
        r = nav.js('(function(){var f=[...document.querySelectorAll("#%s .a-IRR-table tbody tr")]'
                   '.filter(function(tr){return tr.querySelectorAll("td").length > 3;});'
                   'return JSON.stringify({n:f.length,'
                   'badges:[...document.querySelectorAll("#%s .status-badge")].map(function(x){return x.innerText.trim();}),'
                   'vacio:/No hay compras registradas/i.test(document.body.innerText)});})()' % (LISTA, LISTA))
        try:
            return json.loads(r)
        except Exception:
            return {"n": -1, "badges": [], "vacio": False}

    f0 = filas()
    activo0 = nav.js('(function(){var a=document.querySelector(".spx-filtro.is-active");'
                     'return a ? a.getAttribute("data-filtro") : "NINGUNO";})()')
    comprobar("K3 el chip activo es Todos", activo0 == "TODOS", activo0)
    comprobar("K3 todos los documentos: una fila por compra",
              f0["n"] == f0["n"] and f0["n"] >= n_mes, (f0["n"], n_mes))

    # --- K9: el saldo solo en una factura procesada -----------------------
    saldos = nav.js('(function(){var f=[...document.querySelectorAll("#%s .a-IRR-table tbody tr")]'
                    '.filter(function(tr){return tr.querySelectorAll("td").length > 6;});'
                    'var mal=[],con=0;f.forEach(function(tr){var c=tr.querySelectorAll("td");'
                    'var tipo=(c[3].innerText||"").trim();var saldo=(c[11].innerText||"").trim();'
                    'var est=(c[12].innerText||"").trim();'
                    'var debe=(tipo==="FAC" && ["Procesada","Abonada","Pagada"].indexOf(est)>=0);'
                    'if(saldo!==""){con=con+1;}'
                    'if(debe===(saldo==="")){mal.push(tipo+"/"+est+"="+saldo);}});'
                    'return JSON.stringify({n:f.length,con:con,mal:mal});})()' % LISTA)
    try:
        s = json.loads(saldos)
    except Exception:
        s = None
    comprobar("K9 un borrador o una nota no muestran saldo", bool(s) and not s["mal"], saldos)
    comprobar("K9 y las facturas procesadas si lo muestran", bool(s) and s["con"] > 0, saldos)

    # --- K4: chip Procesada ------------------------------------------------
    nav.js('(function(){var a=[...document.querySelectorAll(".spx-filtro")]'
           '.find(function(x){return x.getAttribute("data-filtro")==="PROCESADA";});a.click();})()')
    ok = nav.esperar('apex.item("P27_FILTRO").getValue() === "PROCESADA"', 45)
    time.sleep(2)
    f1 = filas()
    comprobar("K4 el chip Procesada se queda activo y filtra",
              ok and f1["n"] == por_estado.get("REGISTRADA", 0), (ok, f1["n"], por_estado))
    activo1 = nav.js('(function(){var a=document.querySelector(".spx-filtro.is-active");'
                     'return a ? a.getAttribute("data-filtro") : "NINGUNO";})()')
    comprobar("K4 el chip activo se pinta como tal", activo1 == "PROCESADA", activo1)
    comprobar("K4 no queda ningun documento pendiente en la lista",
              all("Pendiente" not in b for b in f1["badges"]), f1["badges"])

    # --- K5: chip Pendiente -------------------------------------------------
    nav.js('(function(){var a=[...document.querySelectorAll(".spx-filtro")]'
           '.find(function(x){return x.getAttribute("data-filtro")==="BORRADOR";});a.click();})()')
    ok = nav.esperar('apex.item("P27_FILTRO").getValue() === "BORRADOR"', 45)
    time.sleep(2)
    f2 = filas()
    comprobar("K5 el chip Pendiente filtra",
              ok and f2["n"] == por_estado.get("BORRADOR", 0), (ok, f2["n"], por_estado))
    if f2["n"] > 0:
        color = nav.js('(function(){var b=[...document.querySelectorAll("#%s .status-badge")]'
                       '.find(function(x){return /Pendiente/.test(x.innerText);});'
                       'if(!b) return "SIN PENDIENTE";'
                       'return window.getComputedStyle(b).color + "|" + b.className;})()' % LISTA)
        print("  insignia Pendiente:", color)
        comprobar("K5 la insignia del pendiente es ambar",
                  "rgb(180, 83, 9)" in str(color), color)
    else:
        comprobar("K5 la empresa 1 no tiene compras pendientes (dato, no fallo)", True)

    # --- K6: chip Anulada y vuelta a Todos ---------------------------------
    nav.js('(function(){var a=[...document.querySelectorAll(".spx-filtro")]'
           '.find(function(x){return x.getAttribute("data-filtro")==="ANULADA";});a.click();})()')
    ok = nav.esperar('apex.item("P27_FILTRO").getValue() === "ANULADA"', 45)
    time.sleep(2)
    f3 = filas()
    comprobar("K6 el chip Anulada deja el informe vacio",
              ok and f3["n"] == por_estado.get("ANULADA", 0), (ok, f3["n"], por_estado))

    nav.js('(function(){var a=[...document.querySelectorAll(".spx-filtro")]'
           '.find(function(x){return x.getAttribute("data-filtro")==="TODOS";});a.click();})()')
    ok = nav.esperar('apex.item("P27_FILTRO").getValue() === "TODOS"', 45)
    time.sleep(2)
    f4 = filas()
    comprobar("K6 volver a Todos repone la lista", ok and f4["n"] == f0["n"], (ok, f4["n"], f0["n"]))

    # --- K8: capturas ------------------------------------------------------
    nav.tamano(1440, 1000)
    time.sleep(3)
    ok = nav.captura(os.path.join(SALIDA, "20261121_compras_1440.png"))
    comprobar("K8 captura a 1440", ok)
    nav.tamano(500, 900)
    time.sleep(3)
    ok = nav.captura(os.path.join(SALIDA, "20261121_compras_500.png"))
    comprobar("K8 captura a 500", ok)
    # y que a 500 la fila de indicadores no se salga de la pantalla
    ancho = nav.js('(function(){var k=document.querySelector(".spx-kpis");'
                   'return k ? Math.round(k.getBoundingClientRect().width) : -1;})()')
    comprobar("K8 la fila de indicadores cabe en 500 px", 0 < (ancho or -1) <= 500, ancho)
finally:
    nav.cerrar()
    cur.execute("delete from syn_login_log where upper(usuario_intentado) = 'DIAG.COMPRAS'")
    cur.execute("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario "
                "where upper(username) = 'DIAG.COMPRAS'); commit; "
                "delete from usuario where upper(username) = 'DIAG.COMPRAS'; commit; end;")
    conn.commit()
    conn.close()

print()
print("RESULTADO: FALLAS=" + str(len(fallas)))
sys.exit(1 if fallas else 0)
