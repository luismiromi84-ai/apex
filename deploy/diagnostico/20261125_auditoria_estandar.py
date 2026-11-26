#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Auditoria del estandar visual, pantalla por pantalla (2026-11-25).

Recorre las paginas normales con un usuario temporal ADMIN, a 1440 y a 500 px, guarda la captura
y mide lo que define el estandar de la app:
  - errores de APEX en pantalla (ORA-, «Se ha producido», violacion de checksum)
  - banda azul en las cabeceras de region y su alto
  - formato numerico: cifras con formato de EEUU (1,234.56) frente al venezolano (1.234,56)
  - tarjetas de indicadores (spx-card): tamano de etiqueta y cifra
  - botones con el icono que gira (t-Button--hoverIconSpin)
  - etiquetas flotantes que tapan un valor (campo con valor sin js-show-label)
  - tokens sin sustituir (#ALGO#) y textos en ingles de APEX
  - desbordamiento horizontal a 500 px
Es un INVENTARIO: imprime los hallazgos y deja JSON + capturas en
deploy/resultados/20261125_auditoria/. Crea y borra su propio usuario.

    python deploy/diagnostico/20261125_auditoria_estandar.py            # todas
    python deploy/diagnostico/20261125_auditoria_estandar.py 5 8        # solo esas
"""
import base64
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
OUT = os.path.join(REPO, "deploy", "resultados", "20261125_auditoria")
USUARIO, CLAVE = "diag.audit", "Diag#2026"
PAGINAS = [int(x) for x in sys.argv[1:]] or [1, 3, 5, 8, 13, 16, 17, 18, 19, 20, 22, 24, 27,
                                              28, 29, 34, 36, 37, 40, 42, 43, 44, 45]
os.makedirs(OUT, exist_ok=True)


class Nav:
    def __init__(self, puerto=9301):
        self.proc = subprocess.Popen(
            [EDGE, "--headless=new", "--disable-gpu", "--no-first-run", "--hide-scrollbars",
             "--remote-debugging-port=%d" % puerto,
             "--user-data-dir=%s" % os.path.join(tempfile.gettempdir(), "opencode", "edge-auditoria"),
             "--window-size=1440,900", "about:blank"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        objetivo = None
        for _ in range(40):
            try:
                lista = json.loads(urllib.request.urlopen(
                    "http://127.0.0.1:%d/json/list" % puerto, timeout=2).read())
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
            r = self.cmd("Runtime.evaluate", expression=expr, returnByValue=True,
                         awaitPromise=True)
        except Exception as e:
            return "WS: " + str(e)[:120]
        if "exceptionDetails" in r:
            return "EXC: " + str(r["exceptionDetails"].get("exception", {}).get("description"))[:200]
        return r.get("result", {}).get("value")

    def esperar(self, cond, seg=45):
        fin = time.time() + seg
        while time.time() < fin:
            if self.js(cond):
                return True
            time.sleep(0.5)
        return False

    def medida(self, ancho, alto=900):
        self.cmd("Emulation.setDeviceMetricsOverride", width=ancho, height=alto,
                 deviceScaleFactor=1, mobile=False)

    def captura(self, ruta):
        h = self.js("Math.min(Math.max(document.documentElement.scrollHeight,"
                    "document.body.scrollHeight), 6500)")
        alto = int(h) if isinstance(h, (int, float)) and h > 200 else 900
        r = self.cmd("Page.captureScreenshot", format="png", captureBeyondViewport=True,
                     clip={"x": 0, "y": 0, "width": self.js("window.innerWidth") or 1440,
                           "height": alto, "scale": 1})
        if r.get("data"):
            with open(ruta, "wb") as fh:
                fh.write(base64.b64decode(r["data"]))

    def cerrar(self):
        try:
            self.proc.terminate()
        except Exception:
            pass


MEDIR = r"""(function(){
  function vis(e){var s=getComputedStyle(e);if(s.display==='none'||s.visibility==='hidden')return false;
    var r=e.getBoundingClientRect();return r.width>0&&r.height>0;}
  var res={};
  var txt=document.body.innerText||'';
  var m=txt.match(/(ORA-\d{5}[^\n]{0,90}|Se ha producido[^\n]{0,90}|Violaci.n de la protecci[^\n]{0,60}|[^\n]{0,40}identificador no v.lido[^\n]{0,40}|no se puede presentar[^\n]{0,40})/);
  res.error=m?m[0]:null;
  var us=txt.match(/(^|[^\d.,])\d{1,3}(,\d{3})+\.\d{2}(?!\d)/g)||[];
  var ve=txt.match(/\d{1,3}(\.\d{3})+,\d{2}(?!\d)/g)||[];
  res.num={us:us.length, us_ej:us.slice(0,3).map(function(s){return s.trim();}),
           ve:ve.length, ve_ej:ve.slice(0,2)};
  var hs=[].slice.call(document.querySelectorAll('.t-Region-header')).filter(vis);
  res.cabeceras=hs.map(function(h){var s=getComputedStyle(h);var t=h.querySelector('.t-Region-title');
     return {alto:Math.round(h.getBoundingClientRect().height),
             azul:/rgb\(0, (118|82)/.test(s.backgroundImage+' '+s.backgroundColor),
             titulo:t?t.textContent.trim().slice(0,30):''};});
  var cards=[].slice.call(document.querySelectorAll('.spx-card')).filter(vis);
  res.cards=cards.length?{n:cards.length, fuentes:[].slice.call(cards[0].querySelectorAll('*')).map(function(e){
     return (e.className||'').toString().split(' ')[0]+':'+getComputedStyle(e).fontSize;}).slice(0,4)}:null;
  res.spin=document.querySelectorAll('.t-Button--hoverIconSpin').length;
  var tapa=[];
  [].slice.call(document.querySelectorAll('.t-Form-fieldContainer--floatingLabel')).forEach(function(fc){
     if(!vis(fc))return; var i=fc.querySelector('input:not([type=hidden]),select,textarea'); if(!i)return;
     var val=(i.tagName==='SELECT')?((i.options[i.selectedIndex]||{}).text||''):i.value;
     if(val&&val.trim()&&!fc.classList.contains('js-show-label')) tapa.push(i.id);});
  res.etiqueta_tapa=tapa;
  res.tokens=(txt.match(/#[A-Z][A-Z0-9_]{2,}#/g)||[]).slice(0,5);
  res.ingles=(txt.match(/\b(No data found|Search|Actions|Rows|Reset|Apply|Cancel|Submit|Delete|Create|Save|Edit|Close)\b/g)||[]).slice(0,8);
  res.desborde=document.documentElement.scrollWidth-window.innerWidth;
  res.titulo=document.title;
  return res;})()"""


def entrar(nav):
    nav.medida(1440)
    nav.js('window.location.href="%s/f?p=100:9999"' % BASE)
    nav.esperar('!!document.getElementById("P9999_USERNAME") && !!window.apex')
    time.sleep(1)
    nav.js('(function(){apex.item("P9999_USERNAME").setValue(%s);apex.item("P9999_PASSWORD").setValue(%s);'
           'var b=[...document.querySelectorAll("button")].find(x=>/sign in|iniciar|entrar/i.test(x.innerText));'
           'if(b){b.click();}})()' % (json.dumps(USUARIO), json.dumps(CLAVE)))
    nav.esperar('!!window.apex && !!apex.env && apex.env.APP_PAGE_ID != "9999" && !!apex.env.APP_SESSION', 40)
    return nav.js('(function(){try{return apex.env.APP_SESSION;}catch(e){return null;}})()')


def hallazgos(a, b):
    h = []
    if a.get("error"):
        h.append("ERROR: " + a["error"])
    n = a.get("num") or {}
    if n.get("us"):
        h.append("cifras con formato EEUU: %d %s (VE: %d)" % (n["us"], n.get("us_ej"), n.get("ve", 0)))
    cab = [x for x in a.get("cabeceras") or [] if x["alto"] > 8]
    sin_azul = [x["titulo"] for x in cab if not x["azul"]]
    if sin_azul:
        h.append("cabecera sin banda azul: %s" % sin_azul)
    altos = sorted(set(x["alto"] for x in cab))
    if any(x > 52 for x in altos):
        h.append("cabecera alta %s" % altos)
    if a.get("spin"):
        h.append("iconos que giran: %d" % a["spin"])
    if a.get("etiqueta_tapa"):
        h.append("etiqueta tapa valor: %s" % a["etiqueta_tapa"])
    if a.get("tokens"):
        h.append("tokens sin sustituir: %s" % a["tokens"])
    if a.get("ingles"):
        h.append("texto en ingles: %s" % sorted(set(a["ingles"])))
    if (b or {}).get("desborde", 0) > 4:
        h.append("desborde horizontal a 500 px: %d px" % b["desborde"])
    return h


def principal():
    global total
    c = credenciales()
    con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CS)
    cur = con.cursor()
    cur.execute("alter session set current_schema = WKSP_SYPEXWS")
    BORRA = ("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario "
             "where upper(username)=upper(:u)); commit; delete from usuario where upper(username)=upper(:u); "
             "commit; end;")
    cur.execute(BORRA, u=USUARIO)
    cur.execute("""insert into usuario (username,email,password_hash,estado,id_empresa,rol_id,
                                         debe_cambiar_clave,reintentos_fallidos)
                   values (:u,:e,sypex_hash_password(:p),'ACTIVO',1,
                           (select id_rol from syn_roles where codigo_rol='ADMIN'),'N',0)""",
                u=USUARIO, e=USUARIO + "@synpex.local", p=CLAVE)
    con.commit()

    resultado = {}
    total = 0
    nav = Nav()
    try:
        ses = entrar(nav)
        if not ses:
            sys.exit("login fallido")
        for pag in PAGINAS:
            r = {}
            for ancho in (1440, 500):
                nav.medida(ancho)
                nav.js('window.location.href="%s/f?p=100:%d:%s"' % (BASE, pag, ses))
                nav.esperar('document.readyState === "complete" && !!window.apex', 40)
                time.sleep(3)
                r[ancho] = nav.js(MEDIR)
                nav.captura(os.path.join(OUT, "p%02d_%d.png" % (pag, ancho)))
            resultado[pag] = r
            a = r[1440] if isinstance(r[1440], dict) else {"error": str(r[1440])}
            b = r[500] if isinstance(r[500], dict) else {}
            h = hallazgos(a, b)
            total += len(h)
            print("p%-3d %-34s %s  tarjetas=%s" % (pag, (a.get("titulo") or "")[:34],
                                                 "OK" if not h else "--", a.get("cards")))
            for x in h:
                print("       - " + x)
    finally:
        nav.cerrar()
        cur.execute(BORRA, u=USUARIO)
        con.close()
        with open(os.path.join(OUT, "auditoria.json"), "w", encoding="utf-8") as fh:
            json.dump(resultado, fh, ensure_ascii=False, indent=1)

    print("\nHALLAZGOS=%d   capturas y JSON en %s" % (total, OUT))


if __name__ == "__main__":
    principal()
