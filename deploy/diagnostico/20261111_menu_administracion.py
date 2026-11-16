#!/usr/bin/env python3
"""El menu de Administracion (19) lleva a Datos fiscales (18) y Logo (17).

Comprueba las dos caras:
 1. Metadatos de APEX: los botones de la 19 apuntan a 18 y 17 (y siguen con la
    condicion de rol); la 3 ya no tiene ninguno de los dos.
 2. HTTP real con un usuario temporal: la 19 ofrece los accesos, la 3 no, y las
    cuatro paginas responden 200.

Uso:  python deploy/diagnostico/20261111_menu_administracion.py
Sale con codigo 1 si algo falla.
"""
import os
import re
import subprocess
import sys
import tempfile

import oracledb

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(REPO, "deploy", "conexion"))
from verificar_conexion import CONNECT_STRING, credenciales  # noqa: E402

USUARIO = "diag.menu.admin"
CLAVE = "Diag#2026"
fallas = 0

# Lo que se busca en el HTML: los botones de la pagina 19 por su nombre interno
# (APEX los pinta como <button data-otel-labeL="..."> y engancha el enlace por JS,
# asi que NO hay href que mirar).
MARCAS = {
    17: ("BTN_LOGO_ADMIN",),
    18: ("BTN_FISCAL_ADMIN",),
}
VIEJOS = ("BTN_LOGOS", "BTN_FISCAL")


def comprueba(ok, texto, detalle=""):
    global fallas
    print("  [%s] %s%s" % ("OK   " if ok else "FALLA", texto,
                           "" if not detalle else " (%s)" % detalle))
    if not ok:
        fallas += 1


def enlaces(html):
    """Botones de acceso (17/18) presentes en el HTML."""
    destino = set()
    for pagina, marcas in MARCAS.items():
        if any(m in html for m in marcas):
            destino.add(pagina)
    return destino


def abrir(cur, pagina, ruta):
    r = subprocess.run([sys.executable, os.path.join(REPO, "deploy", "conexion", "abrir_pagina.py"),
                        USUARIO, CLAVE, str(pagina), ruta],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    salida = (r.stdout or "") + (r.stderr or "")
    m = re.search(r"HTTP (\d+)", salida)
    codigo = int(m.group(1)) if m else 0
    with open(ruta, encoding="utf-8", errors="replace") as f:
        return codigo, f.read()


def main():
    c = credenciales()
    con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
    cur = con.cursor()
    cur.execute("alter session set current_schema = WKSP_SYPEXWS")
    tmp = tempfile.mkdtemp(prefix="menu_admin_")

    try:
        print("== Metadatos (botones de la app) ==")
        cur.execute("""select page_id, button_name, redirect_url, condition_expression1
                         from apex_application_page_buttons
                        where application_id = 100 and page_id in (3, 19)""")
        filas = cur.fetchall()
        apuntan = {}
        for pagina, nombre, url, cond in filas:
            url = url or ""
            for destino, marcas in MARCAS.items():
                if any(m in url.lower() for m in (":%d" % destino,)):
                    apuntan.setdefault(pagina, set()).add(destino)
        comprueba(apuntan.get(19, set()) >= {17, 18},
                  "la pagina 19 tiene botones a Datos fiscales y Logo",
                  ",".join(str(x) for x in sorted(apuntan.get(19, set()))))
        comprueba(not (apuntan.get(3, set()) & {17, 18}),
                  "la pagina 3 ya no lleva a esos datos",
                  ",".join(str(x) for x in sorted(apuntan.get(3, set()))))
        con_rol = [n for p, n, u, cond in filas
                   if p == 19 and (u or "").lower().find(":1") >= 0
                   and "fn_tiene_rol" in (cond or "").lower()]
        comprueba(len(con_rol) >= 2, "los dos botones conservan la condicion de rol",
                  str(len(con_rol)))

        print("== HTTP con un usuario temporal ==")
        cur.execute("begin delete from usuario_empresa where usuario_id in "
                    "(select usuario_id from usuario where upper(username) = upper(:u)); commit; end;", u=USUARIO)
        cur.execute("delete from usuario where upper(username) = upper(:u)", u=USUARIO)
        cur.execute("""insert into usuario (username, email, password_hash, estado, id_empresa, rol_id,
                                            debe_cambiar_clave, reintentos_fallidos)
                       values (:u, :e, sypex_hash_password(:p), 'ACTIVO', 1,
                               (select id_rol from syn_roles where codigo_rol = 'ADMIN'), 'N', 0)""",
                    u=USUARIO, e=USUARIO + "@synpex.local", p=CLAVE)
        con.commit()

        html = {}
        for pagina in (19, 3, 17, 18):
            codigo, cuerpo = abrir(cur, pagina, os.path.join(tmp, "p%d.html" % pagina))
            html[pagina] = cuerpo
            comprueba(codigo == 200, "la pagina %d responde 200" % pagina, str(codigo))

        comprueba(enlaces(html[19]) >= {17, 18}, "la 19 muestra los accesos",
                  ",".join(str(x) for x in sorted(enlaces(html[19]))))
        comprueba(not (enlaces(html[3]) & {17, 18})
                  and not any(v in html[3] for v in VIEJOS),
                  "la 3 ya no los muestra",
                  ",".join(str(x) for x in sorted(enlaces(html[3]))))
    finally:
        try:
            cur.execute("begin delete from usuario_empresa where usuario_id in "
                        "(select usuario_id from usuario where upper(username) = upper(:u)); commit; end;", u=USUARIO)
            cur.execute("delete from usuario where upper(username) = upper(:u)", u=USUARIO)
            con.commit()
        except Exception:
            pass
        cur.close()
        con.close()

    print("\nRESULTADO: FALLAS=%d" % fallas)
    return 1 if fallas else 0


if __name__ == "__main__":
    sys.exit(main())
