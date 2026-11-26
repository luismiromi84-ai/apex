# -*- coding: utf-8 -*-
"""Los tres arreglos (segunda tanda) en navegador real.

  N1 en la lista de Facturacion «Seleccionar» va antes que «Editar»
  N2 en una factura NUEVA no se ve la tarjeta «Lineas de la factura que acredita»
     y el icono de Guardar no gira (ni al enfocar)
  N3 en Administracion > Secuencias se puede fijar el correlativo escribiendolo
     con su formato (PRE-n), y luego se deja como estaba

    python deploy/diagnostico/20261124_tres_arreglos2_navegador.py
"""
import base64, json, os, re, subprocess, sys, tempfile, time, urllib.request

sys.path.insert(0, r"C:\Users\luism\OneDrive\Documents\Apex_luis\deploy\conexion")
import websocket
import oracledb
from verificar_conexion import CONNECT_STRING as CS, credenciales

BASE = "https://gfd7e2575d251ae-sypexsql.adb.mx-monterrey-1.oraclecloudapps.com/ords"
EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
USUARIO = "diag.tres2"
CLAVE = "Diag#2026"
PUERTO = 9288
EMPRESA = 1
SERIE = "PRESUPUESTO"

fallas = []


def comprobar(nombre, ok, detalle=""):
    print(("  OK  " if ok else "  MAL ") + nombre + (("  -> " + str(detalle)) if detalle else ""))
    if not ok:
        fallas.append(nombre)


conn = oracledb.connect(user=credenciales()["DB_USER"], password=credenciales()["DB_PASSWORD"], dsn=CS)
cur = conn.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")


def borrar_usuario():
    cur.execute("""begin
                     for r in (select usuario_id from usuario where upper(username) = :u) loop
                         delete from usuario_empresa where usuario_id = r.usuario_id;
                         commit;
                         delete from usuario where usuario_id = r.usuario_id;
                         commit;
                     end loop;
                   end;""", u=USUARIO.upper())
    conn.commit()


borrar_usuario()
cur.execute("""insert into usuario (username, email, password_hash, estado, id_empresa, rol_id,
                                    debe_cambiar_clave, reintentos_fallidos)
               values (:u, :u || '@synpex.local', sypex_hash_password(:c), 'ACTIVO', :e,
                       (select id_rol from syn_roles where codigo_rol = 'ADMIN'), 'N', 0)""",
            u=USUARIO, c=CLAVE, e=EMPRESA)
conn.commit()

cur.execute("select fn_maximo_real(:e, :s) from dual", e=EMPRESA, s=SERIE)
MAXREAL = cur.fetchone()[0] or 0
cur.execute("select ultimo from folio_contador where id_empresa = :e and tipo = :s", e=EMPRESA, s=SERIE)
r = cur.fetchone()
ANTES = r[0] if r else None
OBJETIVO = MAXREAL + 1
print("serie %s empresa %s: maximo real=%s, contador=%s, se fijara en %s" % (SERIE, EMPRESA, MAXREAL, ANTES, OBJETIVO))

proc = subprocess.Popen([EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
                         "--remote-debugging-port=%d" % PUERTO, "--window-size=1440,1000",
                         "--user-data-dir=" + os.path.join(tempfile.gettempdir(), "opencode", "edge-tres2"),
                         "about:blank"],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def objetivo():
    for _ in range(40):
        try:
            lista = json.loads(urllib.request.urlopen(
                "http://127.0.0.1:%d/json/list" % PUERTO, timeout=2).read())
            pag = [t for t in lista if t.get("type") == "page"]
            if pag:
                return pag[0]
        except Exception:
            pass
        time.sleep(0.5)
    raise SystemExit("no hay navegador")


ws = websocket.create_connection(objetivo()["webSocketDebuggerUrl"], timeout=90)
ws.settimeout(90)
n = [0]
for m in ("Page.enable", "Runtime.enable"):
    n[0] += 1
    ws.send(json.dumps({"id": n[0], "method": m, "params": {}}))
    while True:
        r = json.loads(ws.recv())
        if r.get("id") == n[0]:
            break


def cmd(m, **p):
    n[0] += 1
    ws.send(json.dumps({"id": n[0], "method": m, "params": p}))
    while True:
        r = json.loads(ws.recv())
        if r.get("id") == n[0]:
            return r.get("result", {})


def js(e):
    r = cmd("Runtime.evaluate", expression=e, returnByValue=True, awaitPromise=True)
    if "exceptionDetails" in r:
        d = r["exceptionDetails"]
        return "EXC: " + str(d.get("exception", {}).get("description") or d.get("text"))[:400]
    return r.get("result", {}).get("value")


def esperar(c, s=60):
    f = time.time() + s
    while time.time() < f:
        v = js(c)
        if v and not (isinstance(v, str) and v.startswith("EXC")):
            return True
        time.sleep(0.5)
    return False


DLG = """(function(){
  var f = document.querySelector('iframe');
  if (!f || !f.contentDocument) return 'SIN DIALOGO';
  var w = f.contentWindow, d = f.contentDocument;
  %s
})()"""


def confirmar():
    """APEX pinta su propio dialogo de confirmacion: se acepta pulsando su boton."""
    comun = js("""(function(){
        var b = [].slice.call(document.querySelectorAll(".ui-dialog button, .t-Dialog button, button"))
            .filter(function(x){ var t=(x.innerText||"").trim();
                return t && !/cancelar/i.test(t) && x.offsetParent !== null; });
        return b.length ? b[b.length-1].innerText.trim() : "SIN DIALOGO";
    })()""")
    js("""(function(){
        var b = [].slice.call(document.querySelectorAll(".ui-dialog button, .t-Dialog button, button"))
            .filter(function(x){ var t=(x.innerText||"").trim();
                return t && !/cancelar/i.test(t) && x.offsetParent !== null; });
        if (b.length) { b[b.length-1].click(); }
    })()""")
    return comun


try:
    js('window.location.href="%s/f?p=100:9999"' % BASE)
    esperar('document.readyState === "complete" && document.getElementById("P9999_USERNAME")', 45)
    js('(function(){apex.item("P9999_USERNAME").setValue(%s);apex.item("P9999_PASSWORD").setValue(%s);'
       'var b=[...document.querySelectorAll("button")].find(x=>/sign in|iniciar|entrar/i.test(x.innerText));'
       'if(b){b.click();}})()' % (json.dumps(USUARIO), json.dumps(CLAVE)))
    esperar('!!window.apex && document.readyState === "complete" && /session=\\d+/.test(location.href)', 60)
    ses = re.search(r"session=(\d+)", js("window.location.href") or "")
    if not ses:
        raise SystemExit("sin sesion")

    # ------------------------------------------------------------------ N1
    js('window.location.href="%s/f?p=100:8:%s"' % (BASE, ses.group(1)))
    esperar('document.readyState === "complete" && document.querySelectorAll(".js-select-invoice").length > 0', 60)
    time.sleep(4)
    cab = js("""(function(){
        var t = [].slice.call(document.querySelectorAll("th")).map(function(x){
            return (x.innerText||"").trim(); }).filter(function(x){ return x; });
        return JSON.stringify(t.slice(0, 4));
    })()""")
    print("  cabeceras de la lista:", cab)
    try:
        cab = json.loads(cab)
    except Exception:
        cab = []
    if len(cab) < 2:
        comprobar("N1 se pudieron leer las cabeceras de la lista", False, cab)
    else:
        comprobar("N1 la primera columna es «Seleccionar»", cab[0] == "Seleccionar", cab[:3])
        comprobar("N1 la segunda es «Editar»", cab[1] == "Editar", cab[:3])

    # ------------------------------------------------------------------ N2
    js('(function(){var b=[...document.querySelectorAll("button,a")].find(function(x){'
       'return /Nueva Facturas/i.test(x.innerText||"");}); if(b){b.click();}})()')
    if not esperar('(function(){var f=document.querySelector("iframe");'
                   'return !!(f && f.contentDocument && f.contentDocument.getElementById("P9_ESTADO"));})()', 60):
        raise SystemExit("no abrio la factura nueva")
    time.sleep(7)

    print("  dialogo:", js(DLG % """
        var r = d.getElementById("R43000000000000343");
        var b = [].slice.call(d.querySelectorAll(".t-Button")).filter(function(x){
            return /Guardar/i.test(x.innerText||""); })[0];
        var ic = b ? b.querySelector(".t-Icon--left") : null;
        var s = ic ? w.getComputedStyle(ic) : null;
        var rap = r ? r.getBoundingClientRect() : null;
        return JSON.stringify({
            id_factura: String(apex.item("P9_ID_FACTURA").getValue()||""),
            tarjeta_display: r ? (r.style.display || w.getComputedStyle(r).display) : "NO EXISTE",
            tarjeta_alto: rap ? Math.round(rap.height) : -1,
            icono_anim: s ? s.animationName : "?",
            icono_play: s ? s.animationPlayState : "?"
        });
    """))

    estado = js(DLG % """
        var r = d.getElementById("R43000000000000343");
        var rap = r ? r.getBoundingClientRect() : null;
        return JSON.stringify({
            display: r ? (r.style.display || w.getComputedStyle(r).display) : "NO EXISTE",
            alto: rap ? Math.round(rap.height) : -1
        });
    """)
    tarjeta = json.loads(estado) if str(estado).startswith("{") else {}
    comprobar("N2 la tarjeta de lineas no se ve en una factura nueva",
              tarjeta.get("display") == "none" or tarjeta.get("alto", 1) == 0, tarjeta)

    # enfocar Guardar y mirar que el icono NO gire
    anim = js(DLG % """
        var b = [].slice.call(d.querySelectorAll(".t-Button")).filter(function(x){
            return /Guardar/i.test(x.innerText||""); })[0];
        if (b) { b.focus(); }
        var ic = b ? b.querySelector(".t-Icon--left") : null;
        if (!ic) return "SIN ICONO";
        var s = w.getComputedStyle(ic);
        return s.animationName + " / " + s.animationPlayState + " / " + s.transform;
    """)
    comprobar("N2 con el foco en Guardar el icono no gira",
              "anim-spin" not in str(anim), anim)

    r = cmd("Page.captureScreenshot", format="png")
    if r.get("data"):
        with open(r"C:\Users\luism\OneDrive\Documents\Apex_luis\deploy\resultados\20261124_p9_factura_nueva.png", "wb") as fh:
            fh.write(base64.b64decode(r["data"]))

    # ------------------------------------------------------------------ N3
    js('window.location.href="%s/f?p=100:19:%s"' % (BASE, ses.group(1)))
    esperar('document.readyState === "complete" && !!window.apex && !!apex.item("P19S_ULTIMO")', 60)
    time.sleep(4)

    tipo_item = js('(function(){var e=document.getElementById("P19S_ULTIMO");'
                   'return e ? e.tagName + "/" + e.type : "SIN CAMPO";})()')
    comprobar("N3 el campo del correlativo es de texto", "text" in str(tipo_item).lower(), tipo_item)

    js('(function(){apex.item("P19S_SERIE").setValue("%s");'
       'apex.item("P19S_ULTIMO").setValue("PRE-%d");})()' % (SERIE, OBJETIVO))
    js("""(function(){
        var b = [].slice.call(document.querySelectorAll("button"))
            .filter(function(x){ return /Fijar el siguiente/i.test(x.innerText||""); })[0];
        if (b) { b.click(); }
    })()""")
    time.sleep(2)
    rot = confirmar()
    print("  confirmacion aceptada con:", rot)
    time.sleep(10)

    aviso = js("""(function(){
        var a = document.querySelector("#t_Alert_Success, .t-Alert--success");
        return a ? a.innerText.replace(/\\s+/g, " ").trim() : "SIN AVISO";
    })()""")
    print("  aviso:", str(aviso)[:160])
    comprobar("N3 el correlativo escrito como PRE-n se acepta",
              "fijada en %d" % OBJETIVO in str(aviso) or "fijada" in str(aviso), str(aviso)[:120])
    comprobar("N3 no aparece «debe ser un número válido»",
              "válido" not in str(aviso) and "valido" not in str(aviso), str(aviso)[:120])

    cur.execute("select ultimo from folio_contador where id_empresa = :e and tipo = :s", e=EMPRESA, s=SERIE)
    r = cur.fetchone()
    contador = r[0] if r else None
    comprobar("N3 el contador quedo en el numero escrito", contador == OBJETIVO, contador)

    # se deja como estaba: «Poner en el maximo real»
    js("""(function(){
        var b = [].slice.call(document.querySelectorAll("button"))
            .filter(function(x){ return /maximo real|máximo real/i.test(x.innerText||""); })[0];
        if (b) { b.click(); }
    })()""")
    time.sleep(2)
    confirmar()
    time.sleep(8)

finally:
    try:
        proc.terminate()
    except Exception:
        pass
    cur.execute("""merge into folio_contador f
                   using (select :e as id_empresa, :s as tipo from dual) s
                      on (f.id_empresa = s.id_empresa and f.tipo = s.tipo)
                   when matched then update set f.ultimo = :v
                   when not matched then insert (id_empresa, tipo, ultimo)
                        values (s.id_empresa, s.tipo, :v)""",
                e=EMPRESA, s=SERIE, v=(ANTES if ANTES is not None else MAXREAL))
    conn.commit()
    borrar_usuario()

print()
print("RESULTADO: FALLAS=%d" % len(fallas))
for f in fallas:
    print("   -", f)
sys.exit(1 if fallas else 0)
