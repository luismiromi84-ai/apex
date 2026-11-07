#!/usr/bin/env python3
# =============================================================================
# 20261107_subida_logo_navegador.py
#
# Prueba la subida del logo de la pagina 17 CON UN NAVEGADOR REAL (Edge headless
# por CDP), sin que nadie tenga que hacer clic: entra con un usuario, pone el
# archivo en el input, pulsa «Subir logo» y lee el mensaje de la pagina.
#
# Por que existe: la subida no se puede probar por HTTP. El archivo no viaja en
# un POST que se pueda armar a mano (APEX lo serializa desde el DOM) y el
# formulario tiene proteccion de estado de sesion. Con CDP se hace lo mismo que
# un dedo: DOM.setFileInputFiles + click.
#
# Uso (desde la raiz del repo):
#   python deploy/diagnostico/20261107_subida_logo_navegador.py admin.demo "Prueba#2026" 1 libreria/variantes/lockup_600.png
#
# Requiere: websocket-client (pip install websocket-client) y Edge instalado.
# Sale con codigo 0 si la pagina dice «Logo guardado», 1 si no.
# =============================================================================

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.request

import websocket

EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
BASE = ("https://gfd7e2575d251ae-sypexsql.adb.mx-monterrey-1.oraclecloudapps.com"
        "/ords")


class Navegador:
    def __init__(self, puerto):
        self.puerto = puerto
        self.proc = subprocess.Popen(
            [EDGE, "--headless=new", "--disable-gpu", "--no-first-run",
             f"--remote-debugging-port={puerto}",
             f"--user-data-dir={os.path.join(tempfile.gettempdir(), 'opencode', 'edge-perfil')}",
             "about:blank"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        objetivo = None
        for _ in range(40):
            try:
                lista = json.loads(urllib.request.urlopen(
                    f"http://127.0.0.1:{puerto}/json/list", timeout=2).read())
                paginas = [t for t in lista if t.get("type") == "page"]
                if paginas:
                    objetivo = paginas[0]
                    break
            except Exception:
                pass
            time.sleep(0.5)
        if not objetivo:
            raise SystemExit("Edge no arranco con depuracion")
        self.ws = websocket.create_connection(objetivo["webSocketDebuggerUrl"], timeout=60)
        self.n = 0
        self.cmd("Page.enable")
        self.cmd("Runtime.enable")
        self.cmd("DOM.enable")

    def cmd(self, method, **params):
        self.n += 1
        self.ws.send(json.dumps({"id": self.n, "method": method, "params": params}))
        while True:
            m = json.loads(self.ws.recv())
            if m.get("id") == self.n:
                return m.get("result", {})

    def js(self, expr):
        r = self.cmd("Runtime.evaluate", expression=expr, returnByValue=True, awaitPromise=True)
        if "exceptionDetails" in r:
            return "EXCEPCION: " + str(r["exceptionDetails"].get("exception", {}).get("description"))[:200]
        return r.get("result", {}).get("value")

    def esperar(self, condicion, segundos=30):
        fin = time.time() + segundos
        while time.time() < fin:
            if self.js(condicion):
                return True
            time.sleep(0.5)
        return False

    def cerrar(self):
        try:
            self.proc.terminate()
        except Exception:
            pass


def main():
    p = argparse.ArgumentParser()
    p.add_argument("usuario")
    p.add_argument("clave")
    p.add_argument("empresa")
    p.add_argument("archivo")
    p.add_argument("--puerto", type=int, default=9232)
    args = p.parse_args()

    archivo = os.path.abspath(args.archivo)
    if not os.path.exists(archivo):
        sys.exit("no existe el archivo " + archivo)

    nav = Navegador(args.puerto)
    try:
        nav.cmd("Page.navigate", url=f"{BASE}/f?p=100:9999")
        if not nav.esperar('document.readyState === "complete" && !!window.apex'):
            sys.exit("no cargo el login")
        time.sleep(1)
        nav.js('(function(){ apex.item("P9999_USERNAME").setValue(%s);'
               ' apex.item("P9999_PASSWORD").setValue(%s);'
               ' var b=[...document.querySelectorAll("button")].find(x=>/sign in|iniciar|entrar/i.test(x.innerText));'
               ' if(b){ b.click(); } })()' % (json.dumps(args.usuario), json.dumps(args.clave)))
        time.sleep(6)
        m = re.search(r"session=(\d+)", nav.js("window.location.href") or "")
        if not m:
            sys.exit("login fallido")
        sesion = m.group(1)

        nav.cmd("Page.navigate", url=f"{BASE}/f?p=100:17:{sesion}")
        if not nav.esperar('document.readyState === "complete" && !!document.getElementById("spx-logo-file")'):
            sys.exit("no cargo la pagina 17")
        time.sleep(1)
        nav.js('apex.item("P17_ID_EMPRESA").setValue(%s);' % json.dumps(args.empresa))

        doc = nav.cmd("DOM.getDocument", depth=-1)
        nodo = nav.cmd("DOM.querySelector", nodeId=doc["root"]["nodeId"], selector="#spx-logo-file")
        nav.cmd("DOM.setFileInputFiles", files=[archivo], nodeId=nodo["nodeId"])
        nav.js('[...document.querySelectorAll("button")].find(function(b){'
               ' return /Subir logo/i.test(b.innerText); }).click()')
        time.sleep(10)

        cuerpo = nav.js("document.body.innerText") or ""
        texto = re.sub(r"\s+", " ", cuerpo)
        print("mensaje:", texto[:300])
        ok = "Logo guardado" in texto
        print("RESULTADO:", "OK" if ok else "FALLO")
        return 0 if ok else 1
    finally:
        nav.cerrar()


if __name__ == "__main__":
    sys.exit(main())
