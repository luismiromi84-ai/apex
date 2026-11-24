#!/usr/bin/env python3
# =============================================================================
# 20261120_facturacion_kpi_menu.py
#
# Las dos capturas del cambio del 2026-11-20, con navegador real:
#   deploy/resultados/20261120_facturacion_kpi_1440.png   la pagina 8 a 1440 px
#   deploy/resultados/20261120_facturacion_kpi_menu.png   el menu desplegado
#
# Y de paso comprueba, sobre el HTML que pinta APEX (no sobre el export):
#   K1..K5 los cinco indicadores nuevos, con su numero
#   K6     ya no estan «Emitidas» ni «Total facturado»
#   K7     los cinco numeros coinciden con la base (misma formula)
#   M1     el menu trae «Facturación» como grupo, con «Factura de Venta» primero
#   M2     «Clientes» sigue siendo la otra hija de «Facturación»
#
# Uso: python deploy/diagnostico/20261120_facturacion_kpi_menu.py
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
REPO = r"C:\Users\luism\OneDrive\Documents\Apex_luis"
sys.path.insert(0, os.path.join(REPO, "deploy", "conexion"))
from verificar_conexion import CONNECT_STRING as CS, credenciales  # noqa: E402

USUARIO, CLAVE = "diag.kpi", "Diag#2026"
SALIDA = os.path.join(REPO, "deploy", "resultados")
fallas = []


def comprobar(nombre, condicion, detalle=""):
    print(("  OK  " if condicion else "  MAL ") + nombre
          + ("" if condicion else " -> " + str(detalle)[:300]))
    if not condicion:
        fallas.append(nombre)


class Nav:
    def __init__(self, puerto=9294):
        self.proc = subprocess.Popen(
            [EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
             "--window-size=1440,1000", f"--remote-debugging-port={puerto}",
             f"--user-data-dir={os.path.join(tempfile.gettempdir(), 'opencode', 'edge-kpi')}",
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
        r = self.cmd("Runtime.evaluate", expression=expr, returnByValue=True, awaitPromise=True)
        if "exceptionDetails" in r:
            return "EXC: " + str(r["exceptionDetails"].get("exception", {}).get("description"))[:250]
        return r.get("result", {}).get("value")

    def esperar(self, cond, seg=40):
        fin = time.time() + seg
        while time.time() < fin:
            if self.js(cond):
                return True
            time.sleep(0.5)
        return False

    def captura(self, nombre):
        datos = self.cmd("Page.captureScreenshot", format="png").get("data")
        if not datos:
            return False
        with open(os.path.join(SALIDA, nombre), "wb") as fh:
            fh.write(base64.b64decode(datos))
        return True

    def cerrar(self):
        try:
            self.proc.terminate()
        except Exception:
            pass


# --------------------------------------------------------------------- datos
c = credenciales()
con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CS)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")
cur.execute("delete from syn_login_log where upper(usuario_intentado) = 'DIAG.KPI'")
cur.execute("""begin
                 for r in (select usuario_id from usuario where upper(username) = 'DIAG.KPI') loop
                     delete from usuario_empresa where usuario_id = r.usuario_id;
                     commit;
                     delete from usuario where usuario_id = r.usuario_id;
                     commit;
                 end loop;
               end;""")
cur.execute("""insert into usuario (username, email, password_hash, estado, id_empresa, rol_id,
                                   debe_cambiar_clave, reintentos_fallidos)
               values ('diag.kpi', 'diag.kpi@synpex.local', sypex_hash_password('Diag#2026'),
                       'ACTIVO', 1, (select id_rol from syn_roles where codigo_rol = 'ADMIN'), 'N', 0)""")
con.commit()

cur.execute("""select count(*),
                      count(case when estado = 'PENDIENTE' then 1 end),
                      count(case when estado = 'PARCIAL' then 1 end),
                      count(case when estado in ('TIMBRADA','PARCIAL')
                                  and fecha_vencimiento < trunc(sysdate)
                                  and fn_saldo_factura(id_factura) > 0.01 then 1 end),
                      nvl(sum(case when estado in ('TIMBRADA','PARCIAL')
                                   then fn_saldo_factura(id_factura) * nvl(tipo_cambio,1) end), 0),
                      nvl(sum(case when estado in ('TIMBRADA','PARCIAL')
                                    and fecha_vencimiento < trunc(sysdate)
                                   then fn_saldo_factura(id_factura) * nvl(tipo_cambio,1) end), 0)
                 from facturas
                where id_empresa = 1 and tipo_documento = 'FAC'
                  and nvl(estado, '#') <> 'ANULADA'""")
total, pen, par, ven, cob, vbs = cur.fetchone()
print("  base: pendientes=%s parciales=%s vencidas=%s por_cobrar=%.2f vencido=%.2f"
      % (pen, par, ven, cob, vbs))

nav = Nav()
try:
    nav.js('window.location.href="%s/f?p=100:9999"' % BASE)
    nav.esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(1)
    nav.js('(function(){apex.item("P9999_USERNAME").setValue(%s);'
           'apex.item("P9999_PASSWORD").setValue(%s);'
           'var b=[...document.querySelectorAll("button")].find(x=>/sign in|iniciar|entrar/i.test(x.innerText));'
           'if(b){b.click();}})()' % (json.dumps(USUARIO), json.dumps(CLAVE)))
    time.sleep(9)
    m = re.search(r"session=(\d+)", nav.js("window.location.href") or "")
    if not m:
        print("  MAL el login fallo:", (nav.js("document.body.innerText") or "")[:200])
        raise SystemExit(1)
    ses = m.group(1)

    # ---------------------------------------------------------- pagina 8
    nav.js('window.location.href="%s/f?p=100:8:%s"' % (BASE, ses))
    nav.esperar('!!document.querySelector(".spx-kpis .spx-card")', 45)
    time.sleep(4)
    comprobar("K0 la fila de indicadores se pinta",
              nav.js('document.querySelectorAll(".spx-kpis .spx-card").length') == 5,
              nav.js('document.querySelectorAll(".spx-kpis .spx-card").length'))

    tarjetas = nav.js('(function(){return JSON.stringify([...document.querySelectorAll'
                      '(".spx-kpis .spx-card")].map(function(c){return {'
                      'lbl: c.querySelector(".spx-card-lbl").textContent.trim(),'
                      'val: c.querySelector(".spx-card-val").textContent.trim()};}));})()')
    print("  tarjetas:", tarjetas)
    leidas = json.loads(tarjetas) if isinstance(tarjetas, str) and tarjetas.startswith("[") else []
    etiquetas = [t["lbl"] for t in leidas]
    comprobar("K1..K5 los cinco rotulos en orden",
              etiquetas == ["Pendientes", "Parciales", "Vencidas",
                            "Por cobrar (Bs)", "Saldo vencido (Bs)"], etiquetas)

    def num(txt):
        # 2026-11-23: el formato de la tarjeta es el venezolano (miles con punto,
        # decimales con coma) con el NLS '.,'. Antes el par estaba al reves y el
        # test se escribio contra '3,682,305.83', que era el fallo.
        if txt in ("", "—", "&#8212;"):
            return None
        return txt.replace(".", "").replace(",", ".")

    valores = [num(t["val"]) for t in leidas]
    comprobar("K7 los numeros coinciden con la base",
            len(valores) == 5
            and valores[0] == str(pen) and valores[1] == str(par) and valores[2] == str(ven)
            and valores[3] is not None and abs(float(valores[3]) - float(cob)) < 0.02
            and valores[4] is not None and abs(float(valores[4]) - float(vbs)) < 0.02,
            (valores, (pen, par, ven, cob, vbs)))

    html = nav.js("document.body.innerText") or ""
    comprobar("K6 ya no estan «Emitidas» ni «Total facturado»",
              "Emitidas" not in html and "Total facturado" not in html,
              [x for x in ("Emitidas", "Total facturado") if x in html])

    comprobar("K8 captura de la pagina 8 a 1440",
              nav.captura("20261120_facturacion_kpi_1440.png"))

    # ------------------------------------------------------------- el menu
    nav.js('window.location.href="%s/f?p=100:1:%s"' % (BASE, ses))
    nav.esperar('document.readyState === "complete" && !!window.apex')
    time.sleep(3)
    nav.js('(function(){var b=document.getElementById("t_Button_navControl");'
           'if(b && b.getAttribute("aria-expanded")==="false"){b.click();}return true;})()')
    time.sleep(1.5)
    nav.esperar('document.querySelectorAll(\'a[aria-level="1"]\').length > 4', 25)
    nav.js('(function(){var n=document.getElementById("t_TreeNav"); if(!n){return false;}'
           '[...n.querySelectorAll(".a-TreeView-toggle")].forEach(function(t){t.click();});'
           'return true;})()')
    nav.esperar('document.querySelectorAll(\'a[aria-level="2"]\').length >= 5', 25)
    time.sleep(1)

    grupos = nav.js('(function(){return JSON.stringify([...document.querySelectorAll'
                    '(\'#t_TreeNav a[aria-level="1"]\')].map(function(a){return {'
                    't: a.textContent.trim(), exp: a.getAttribute("aria-expanded")};}));})()')
    print("  primer nivel:", grupos)
    lista = json.loads(grupos) if isinstance(grupos, str) and grupos.startswith("[") else []
    nombres = [g["t"] for g in lista]
    comprobar("M1 «Facturación» es una entrada de primer nivel",
              "Facturación" in nombres, nombres)

    hijas = nav.js('(function(){var n=document.getElementById("t_TreeNav");'
                   'if(!n){return "SIN NAV";}'
                   'return JSON.stringify([...n.querySelectorAll(\'a[aria-level="2"]\')]'
                   '.map(function(x){return x.textContent.trim();}));})()')
    print("  hijas:", hijas)
    h = json.loads(hijas) if isinstance(hijas, str) and hijas.startswith("[") else []
    comprobar("M2 «Factura de Venta» va justo antes de «Clientes»",
              "Factura de Venta" in h and "Clientes" in h
              and h.index("Factura de Venta") + 1 == h.index("Clientes"), h)

    # Para la captura: desplegar «Facturación» con UN clic en su triangulo. Un
    # clic por grupo y volviendo a consultar el DOM: pulsar varios toggles de
    # una vez no vale porque el widget rehace el <li> y los demas nodos quedan
    # sueltos. El aria-expanded del enlace se queda en "false" aunque este
    # abierto, asi que no sirve para decidir si hay que pulsar.
    nav.js('(function(){var n=document.getElementById("t_TreeNav"); if(!n){return "SIN ARBOL";}'
           'var li=[...n.querySelectorAll("li")].find(function(l){'
           'var a=l.querySelector(\'a[aria-level="1"]\');'
           'return a && /^Facturaci/.test(a.textContent.trim());});'
           'if(!li){return "SIN GRUPO";}'
           'var t=li.querySelector(".a-TreeView-toggle");'
           'if(t){t.click();} return "CLIC";})()')
    nav.esperar('(function(){var h=[...document.querySelectorAll(\'#t_TreeNav a[aria-level="2"]\')];'
                'return h.filter(function(a){return /Factura de Venta|Clientes/'
                '.test(a.textContent) && a.getBoundingClientRect().height > 0;}).length === 2;})()', 20)
    time.sleep(1.5)

    visibles = nav.js('(function(){return [...document.querySelectorAll'
                      '(\'#t_TreeNav a[aria-level="2"]\')]'
                      '.filter(function(a){return a.getBoundingClientRect().height > 0;})'
                      '.map(function(a){return a.textContent.trim();});})()')
    comprobar("M2b «Factura de Venta» y «Clientes» se ven bajo Facturación",
              visibles == ["Factura de Venta", "Clientes"], visibles)

    comprobar("M3 captura del menu desplegado",
              nav.captura("20261120_facturacion_kpi_menu.png"))

    print()
    print("  LOS CINCO NUMEROS: pendientes=%s parciales=%s vencidas=%s por cobrar=%s vencido=%s"
          % tuple(t["val"] for t in leidas))
finally:
    nav.cerrar()
    cur.execute("delete from syn_login_log where upper(usuario_intentado) = 'DIAG.KPI'")
    cur.execute("""begin
                     for r in (select usuario_id from usuario where upper(username) = 'DIAG.KPI') loop
                         delete from usuario_empresa where usuario_id = r.usuario_id;
                         commit;
                         delete from usuario where usuario_id = r.usuario_id;
                         commit;
                     end loop;
                   end;""")
    con.commit()
    con.close()

print()
print("RESULTADO: FALLAS=" + str(len(fallas)))
for f in fallas:
    print("  - " + f)
sys.exit(1 if fallas else 0)
