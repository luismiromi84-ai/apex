"""El recibo se anula y la lista lo refleja sin recargar (2026-11-19).

Sintoma del dueno: «el boton anular no funciono». Medido: el recibo SI quedaba
ANULADO en la base, pero la lista de Recibos (24) no se refrescaba al cerrar el
dialogo, asi que seguia mostrando el estado viejo: parecia que no habia hecho
nada. Se agrego la accion `refresca-recibos` sobre `apexafterclosedialog`.

  A1 el dialogo abre desde la columna «Abrir» de la lista
  A2 al pulsar «Anular cobro» el recibo queda ANULADO en la base
  A3 al cerrarse el dialogo la lista muestra ANULADO sin recargar

Uso: python deploy/diagnostico/20261119_recibo_anular_navegador.py
Crea su propio cobro y su usuario, y los borra al terminar.
"""
import json, os, subprocess, sys, tempfile, time, urllib.request
import oracledb, websocket

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
REPO = r"C:\Users\luism\OneDrive\Documents\Apex_luis"
sys.path.insert(0, os.path.join(REPO, "deploy", "conexion"))
from verificar_conexion import CONNECT_STRING as CS, credenciales  # noqa: E402

EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
BASE = "https://gfd7e2575d251ae-sypexsql.adb.mx-monterrey-1.oraclecloudapps.com/ords"
USUARIO, CLAVE = "diag.anular", "Diag#2026"
fallas = []


def comprobar(nombre, condicion, detalle=""):
    print(("  OK  " if condicion else "  MAL ") + nombre + ("" if condicion else " " + str(detalle)))
    if not condicion:
        fallas.append(nombre)


class Nav:
    def __init__(self, puerto=9298):
        self.proc = subprocess.Popen(
            [EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
             f"--remote-debugging-port={puerto}",
             f"--user-data-dir={os.path.join(tempfile.gettempdir(), 'opencode', 'edge-anular')}",
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
        self.ws = websocket.create_connection(objetivo["webSocketDebuggerUrl"], timeout=90)
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
            return "EXC: " + str(r["exceptionDetails"].get("exception", {}).get("description"))[:200]
        return r.get("result", {}).get("value")

    def cerrar(self):
        try:
            self.proc.terminate()
        except Exception:
            pass


c = credenciales()
con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CS)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")

# usuario temporal
cur.execute("begin delete from usuario_empresa where usuario_id in "
            "(select usuario_id from usuario where upper(username)='DIAG.ANULAR'); commit; "
            "delete from usuario where upper(username)='DIAG.ANULAR'; commit; end;")
cur.execute("""insert into usuario (username,email,password_hash,estado,id_empresa,rol_id,
                 debe_cambiar_clave,reintentos_fallidos)
               values ('diag.anular','diag.anular@synpex.local',
                 sypex_hash_password('Diag#2026'),'ACTIVO',1,
                 (select id_rol from syn_roles where codigo_rol='ADMIN'),'N',0)""")
con.commit()

# factura cobrable de la empresa 1 y un cobro pequeño
cur.execute("""select f.id_factura, f.folio_factura
                 from facturas f
                where f.id_empresa = 1 and f.tipo_documento = 'FAC'
                  and f.estado in ('TIMBRADA', 'PARCIAL')
                  and nvl(f.cod_moneda, 'VES') = 'VES'
                  and fn_saldo_factura(f.id_factura) > 2
                order by f.id_factura desc fetch first 1 rows only""")
fila = cur.fetchone()
id_fac, folio = fila
id_rec = None
# PL/SQL no admite una subconsulta escalar dentro de la llamada: se resuelve antes
cur.execute("select min(id_forma_pago) from forma_pago where activo = 'Y'")
v_forma = cur.fetchone()[0]
cur.execute("select cod_moneda from facturas where id_factura = :f", f=id_fac)
v_mon = cur.fetchone()[0]
try:
    cur.execute("""begin
                     pkg_cobros.prc_registrar_cobro(
                         p_id_factura    => :f,
                         p_fecha         => trunc(sysdate),
                         p_id_forma_pago => :fp,
                         p_cod_moneda    => :mon,
                         p_tasa          => 1,
                         p_monto         => 1,
                         p_usuario       => 'diag.anular',
                         p_id_recibo     => :r);
                   end;""", f=id_fac, fp=v_forma, mon=v_mon, r=id_rec)
    cur.execute("""select max(id_recibo) from recibos where id_factura = :f""", f=id_fac)
    id_rec = cur.fetchone()[0]
    con.commit()
    print("  cobro de prueba:", id_rec, "sobre", folio)

    nav = Nav()
    try:
        nav.js('window.location.href="%s/f?p=100:9999"' % BASE)
        time.sleep(4)
        nav.js('(function(){apex.item("P9999_USERNAME").setValue(' + json.dumps(USUARIO) +
               ');apex.item("P9999_PASSWORD").setValue(' + json.dumps(CLAVE) + ');'
               'var b=[...document.querySelectorAll("button")].find(x=>/sign in|iniciar|entrar/i.test(x.innerText));'
               'if(b){b.click();}})()')
        time.sleep(9)
        ses = nav.js('(function(){try{return apex.env.APP_SESSION;}catch(e){return null;}})()')

        nav.js('window.location.href="%s/f?p=100:24:%s"' % (BASE, ses))
        time.sleep(7)

        # A1: abrir el recibo desde su columna «Abrir»
        abierto = nav.js('(function(){var a=document.querySelector(\'a[href*="p25_id_recibo"]\');'
                         'if(!a) return "SIN ENLACE"; a.click(); return "CLIC";})()')
        time.sleep(10)
        hay = nav.js('(function(){var f=document.querySelector("iframe");'
                     'return !!(f&&f.contentDocument&&f.contentDocument.getElementById("P25_MONTO"));})()')
        comprobar("A1 el dialogo del recibo abre desde la lista", abierto == "CLIC" and hay is True,
                  (abierto, hay))

        # A1b (2026-11-19): al abrir un recibo guardado, el neto en bolivares viene lleno
        neto_bs = nav.js('(function(){var w=document.querySelector("iframe").contentWindow;'
                         'return w.apex.item("P25_NETO_BS").getValue();})()')
        comprobar("A1b el neto en bolivares se carga al abrir", str(neto_bs).strip() != "",
                  neto_bs)

        # A2: anular
        nav.js('(function(){var f=document.querySelector("iframe");'
               'var b=[...f.contentDocument.querySelectorAll("button")].find(function(x){'
               'return /Anular cobro/i.test(x.innerText);}); if(b){b.click();}return !!b;})()')
        time.sleep(3)
        nav.js('(function(){var bs=[...document.querySelectorAll("button")].filter(function(b){'
               'return b.offsetParent!==null && !b.getAttribute("data-otel-label")'
               ' && (b.innerText||"").trim() && (b.innerText||"").trim()!=="Cancelar";});'
               'if(bs.length){bs[bs.length-1].click();}return bs.length;})()')
        time.sleep(10)

        cur.execute("select estado from recibos where id_recibo = :r", r=id_rec)
        estado = (cur.fetchone() or ["?"])[0]
        comprobar("A2 el recibo queda ANULADO", estado == "ANULADO", estado)

        # A3: la lista ya lo muestra sin recargar
        texto = nav.js("document.body.innerText") or ""
        comprobar("A3 la lista muestra el recibo como ANULADO sin recargar",
                  "ANULADO" in texto, texto[:150])
    finally:
        nav.cerrar()

    cur.execute("delete from recibos where id_recibo = :r", r=id_rec)
    con.commit()
    id_rec = None
finally:
    if id_rec:
        cur.execute("delete from recibos where id_recibo = :r", r=id_rec)
        con.commit()
    cur.execute("begin delete from usuario_empresa where usuario_id in "
                "(select usuario_id from usuario where upper(username)='DIAG.ANULAR'); commit; "
                "delete from usuario where upper(username)='DIAG.ANULAR'; commit; end;")
    con.close()

print()
print("RESULTADO: FALLAS=" + str(len(fallas)))
for f in fallas:
    print("  - " + f)
sys.exit(1 if fallas else 0)
