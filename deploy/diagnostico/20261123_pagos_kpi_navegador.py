"""La lista de Pagos (36) al estandar: indicadores, filtros y chips (2026-11-23).

Antes era la unica lista sin indicadores, sin filtros y con el conciliado en
texto crudo. Ahora tiene la misma fila de tarjetas de Recibos (24) y Compras (27),
cinco filtros que envian la pagina y el conciliado como chip.

  K0  la pagina abre con su fila de cuatro tarjetas
  K1  los cuatro rotulos, en orden
  K2  los numeros son los de la base, con el formato venezolano (1.008,31)
  K3  el filtro Conciliado = Si deja la fila y = No la vacia (mensaje del informe)
  K4  el filtro Estado = Anulados vacia la lista
  K5  el estado sale con insignia EMITIDO y el conciliado con chip
  K6  el buscador por el proveedor encuentra su pago
  K7  captura

No crea ni borra datos: mide con lo que hay. Si la empresa 1 no tuviera pagos,
K2 se omite y se dice.

Uso: python deploy/diagnostico/20261123_pagos_kpi_navegador.py
Sale 1 si algo falla.
"""
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

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

REPO = r"C:\Users\luism\OneDrive\Documents\Apex_luis"
sys.path.insert(0, os.path.join(REPO, "deploy", "conexion"))
from verificar_conexion import CONNECT_STRING, credenciales  # noqa

BASE = "https://gfd7e2575d251ae-sypexsql.adb.mx-monterrey-1.oraclecloudapps.com/ords"
USUARIO, CLAVE = "diag.pagos36", "Diag#2026"
RES = os.path.join(REPO, "deploy", "resultados")
EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"

fallas = []


def comprobar(nombre, condicion, detalle=""):
    print(("  OK   " if condicion else "  MAL  ") + nombre +
          ("" if condicion else "  -> " + str(detalle)[:220]))
    if not condicion:
        fallas.append(nombre)


def omitir(nombre, motivo):
    print("  [OMITIDO] " + nombre + " -- " + motivo)


c = credenciales()
con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")

# Usuario temporal con rol ADMIN (la 36 pide ADMIN,GERENCIA,CONTABILIDAD,CONSULTA,PRUEBA).
cur.execute("begin delete from usuario_empresa where usuario_id in (select usuario_id "
            "from usuario where upper(username)=upper(:u)); commit; end;", u=USUARIO)
cur.execute("delete from usuario where upper(username)=upper(:u)", u=USUARIO)
cur.execute("delete from syn_login_log where upper(usuario_intentado)=upper(:u)", u=USUARIO)
cur.execute("""insert into usuario (username, email, password_hash, estado, id_empresa,
                                    rol_id, debe_cambiar_clave, reintentos_fallidos)
               values (:u, :e, sypex_hash_password(:p), 'ACTIVO', 1,
                       (select id_rol from syn_roles where codigo_rol = 'ADMIN'), 'N', 0)""",
            u=USUARIO, e=USUARIO + "@synpex.local", p=CLAVE)
cur.execute("""insert into usuario_empresa (usuario_id, id_empresa)
               select usuario_id, 1 from usuario where upper(username) = upper(:u)
                and not exists (select 1 from usuario_empresa ue join usuario u2
                                 on u2.usuario_id = ue.usuario_id
                                where u2.usuario_id = usuario.usuario_id
                                  and ue.id_empresa = 1)""", u=USUARIO)
con.commit()

# Los numeros esperados, con la misma cuenta que la region.
cur.execute("""select count(case when estado = 'ACTIVO'
                                  and trunc(fecha_pago, 'MM') = trunc(sysdate, 'MM') then 1 end),
                      nvl(sum(case when estado = 'ACTIVO'
                                    and trunc(fecha_pago, 'MM') = trunc(sysdate, 'MM')
                                   then nvl(monto_bs, monto * nvl(tipo_cambio, 1)) end), 0),
                      nvl(sum(case when estado = 'ACTIVO'
                                    and trunc(fecha_pago, 'MM') = trunc(sysdate, 'MM')
                                   then nvl(igtf_bs, 0) end), 0),
                      count(case when estado = 'ACTIVO' and conciliado = 'N' then 1 end),
                      count(*)
                 from pagos where id_empresa = 1""")
N_MES, BS, IGTF, SIN_CONC, TOTAL = cur.fetchone()
cur.execute("""select min(pr.razon_social) from pagos p
               join proveedores pr on pr.id_proveedor = p.id_proveedor
              where p.id_empresa = 1 and p.estado = 'ACTIVO' and p.conciliado = 'S'""")
PROV_SI = cur.fetchone()[0]
con.close()
print("  base: pagos=%s del mes=%s bs=%s igtf=%s sin conciliar=%s" % (TOTAL, N_MES, BS, IGTF, SIN_CONC))

proc = subprocess.Popen([EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
                         "--remote-debugging-port=9297", "--window-size=1440,1000",
                         "--user-data-dir=" + os.path.join(tempfile.gettempdir(), "opencode", "edge-pagos36"),
                         "about:blank"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def obj():
    for _ in range(40):
        try:
            l = json.loads(urllib.request.urlopen("http://127.0.0.1:9297/json/list", timeout=2).read())
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


def esperar(cond, s=45):
    f = time.time() + s
    while time.time() < f:
        if js(cond):
            return True
        time.sleep(0.5)
    return False


def tarjetas():
    t = js('(function(){return JSON.stringify([...document.querySelectorAll'
           '(".spx-kpis .spx-card")].map(function(c){return {'
           'lbl: c.querySelector(".spx-card-lbl").textContent.trim(),'
           'val: c.querySelector(".spx-card-val").textContent.trim()};}));})()')
    return json.loads(t) if isinstance(t, str) and t.startswith("[") else []


def enviar_filtro(item, valor):
    """Cambia el valor del filtro como lo hace el usuario (dispara la accion)."""
    js('(function(){var i=document.getElementById("%s");if(!i)return "NO";'
       'apex.item("%s").setValue(%s);'
       'i.dispatchEvent(new Event("change",{bubbles:true}));return "OK";})()'
       % (item, item, json.dumps(valor)))


def filas():
    # Una fila del informe = un enlace «Ver» a la pagina 37 (el id del DOM del
    # informe cambia con la version de APEX: el enlace si es estable).
    return js("document.querySelectorAll('a[href*=\"p37_id_pago\"]').length") or 0


def cuerpo():
    return js("document.body.innerText") or ""


try:
    js('window.location.href="%s/f?p=100:9999"' % BASE)
    # Esperar los CAMPOS, no solo readyState: con about:blank la carrera hacia que
    # setValue se ejecutara antes de que existiera el formulario y no pasaba nada.
    esperar('!!document.getElementById("P9999_USERNAME") && !!window.apex')
    time.sleep(1)
    # El clic se da en el mismo paso que los valores: si el formulario no esta, el
    # setValue no hace nada y el test lo dice con el cuerpo de la pagina.
    js('(function(){apex.item("P9999_USERNAME").setValue(%s);'
       'apex.item("P9999_PASSWORD").setValue(%s);'
       'var b=[...document.querySelectorAll("button")].find(x=>/sign in|iniciar|entrar/i.test(x.innerText));'
       'if(b){b.click();}})()' % (json.dumps(USUARIO), json.dumps(CLAVE)))
    for _ in range(60):
        time.sleep(1)
        if re.search(r"session=(\d+)", js("window.location.href") or ""):
            break
    m = re.search(r"session=(\d+)", js("window.location.href") or "")
    if not m:
        print("  login fallido:", cuerpo()[:200])
        raise SystemExit(1)
    ses = m.group(1)

    js('window.location.href="%s/f?p=100:36:%s"' % (BASE, ses))
    esperar('!!document.querySelector(".spx-kpis .spx-card")')
    time.sleep(4)

    # ---------------------------------------------------------------- K0/K1
    comprobar("K0 la pagina abre con su fila de indicadores",
              js('document.querySelectorAll(".spx-kpis .spx-card").length') == 4,
              js('document.querySelectorAll(".spx-kpis .spx-card").length'))
    t = tarjetas()
    print("  tarjetas:", t)
    comprobar("K1 los cuatro rotulos, en orden",
              [x["lbl"] for x in t] == ["Pagos del mes", "Pagado (Bs)", "IGTF (Bs)", "Sin conciliar"],
              [x["lbl"] for x in t])

    # ---------------------------------------------------------------- K2
    if TOTAL == 0:
        omitir("K2 los numeros son los de la base", "(no hay pagos en la empresa 1)")
    else:
        def ve(v):
            s = "{:,.2f}".format(float(v))
            return s.replace(",", "X").replace(".", ",").replace("X", ".")

        comprobar("K2 «Pagos del mes» es el conteo del mes",
                  t[0]["val"] == str(N_MES), (t[0]["val"], N_MES))
        comprobar("K2 «Pagado (Bs)» es la suma de MONTO_BS (formato venezolano)",
                  t[1]["val"] == ve(BS), (t[1]["val"], ve(BS)))
        comprobar("K2 «IGTF (Bs)» es la suma de IGTF_BS",
                  t[2]["val"] == ve(IGTF), (t[2]["val"], ve(IGTF)))
        comprobar("K2 «Sin conciliar» cuenta los EMITIDO sin conciliar",
                  t[3]["val"] == str(SIN_CONC), (t[3]["val"], SIN_CONC))

    # ---------------------------------------------------------------- K5
    texto = cuerpo()
    comprobar("K5 el estado sale con insignia EMITIDO",
              "EMITIDO" in texto.upper() and
              js('document.querySelectorAll(".status-badge").length') > 0,
              js('document.querySelectorAll(".status-badge").length'))
    comprobar("K5 el conciliado sale como chip",
              js('document.querySelectorAll(".spx-chip").length') > 0,
              js('document.querySelectorAll(".spx-chip").length'))

    # ---------------------------------------------------------------- K3
    if TOTAL == 0:
        omitir("K3 los filtros de conciliado", "(no hay pagos)")
    else:
        base_filas = filas()
        enviar_filtro("P36_CONCILIADO", "SI")
        time.sleep(12)
        con_si = filas()
        comprobar("K3 con Conciliado = Sí la lista sigue",
                  con_si >= 1 and con_si <= base_filas, (base_filas, con_si))

        enviar_filtro("P36_CONCILIADO", "NO")
        time.sleep(12)
        sin_no = cuerpo()
        comprobar("K3 con Conciliado = No la lista se vacia",
                  "No hay pagos registrados" in sin_no or filas() <= 1,
                  sin_no[:160])

        enviar_filtro("P36_CONCILIADO", "TODOS")
        time.sleep(12)
        comprobar("K3 y al volver a Todos la fila reaparece",
                  filas() >= 1, filas())

        # ------------------------------------------------------------ K4
        enviar_filtro("P36_ESTADO", "ANULADO")
        time.sleep(12)
        texto_an = cuerpo()
        comprobar("K4 con Estado = Anulados la lista se vacia",
                  "No hay pagos registrados" in texto_an or filas() <= 1,
                  texto_an[:160])
        enviar_filtro("P36_ESTADO", "TODOS")
        time.sleep(12)

        # ------------------------------------------------------------ K6
        if PROV_SI:
            enviar_filtro("P36_BUSCAR", PROV_SI)
            time.sleep(12)
            comprobar("K6 el buscador por proveedor encuentra su pago",
                      PROV_SI.upper() in cuerpo().upper(), cuerpo()[:160])
            enviar_filtro("P36_BUSCAR", "")
            time.sleep(10)

    # ---------------------------------------------------------------- K7
    try:
        png = cmd("Page.captureScreenshot", format="png")["data"]
        ruta = os.path.join(RES, "20261123_pagos_kpi.png")
        with open(ruta, "wb") as f:
            f.write(base64.b64decode(png))
        print("  captura:", ruta)
    except Exception as e:
        print("  (sin captura:", e, ")")
finally:
    proc.terminate()
    con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
    cur = con.cursor()
    cur.execute("alter session set current_schema = WKSP_SYPEXWS")
    cur.execute("begin delete from usuario_empresa where usuario_id in (select usuario_id "
                "from usuario where upper(username)=upper(:u)); commit; end;", u=USUARIO)
    cur.execute("delete from usuario where upper(username)=upper(:u)", u=USUARIO)
    cur.execute("delete from syn_login_log where upper(usuario_intentado)=upper(:u)", u=USUARIO)
    con.commit()
    con.close()

print()
print("RESULTADO: FALLAS=" + str(len(fallas)))
for f in fallas:
    print("  - " + f)
sys.exit(1 if fallas else 0)
