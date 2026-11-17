#!/usr/bin/env python3
"""Pagina 3 «Gestion de Usuarios»: el listado, «Ultimos errores» y «Ultimos intentos»
tienen que estar en PESTANAS (selector de regiones), no apilados.

Comprueba los metadatos (selector + las tres regiones incluidas) y el HTML real de
la pagina con un usuario temporal ADMIN. Sale con codigo 1 si algo falla.

Uso:  python deploy/diagnostico/20261116_pagina3_pestanas.py
"""
import os
import re
import subprocess
import sys
import tempfile

import oracledb

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
REPO = r"C:\Users\luism\OneDrive\Documents\Apex_luis"
sys.path.insert(0, os.path.join(REPO, "deploy", "conexion"))
from verificar_conexion import CONNECT_STRING, credenciales  # noqa: E402

USUARIO, CLAVE = "diag.pestanas3p", "Diag#2026"
fallas = 0


def comprueba(ok, texto, detalle=""):
    global fallas
    print("  [%s] %s%s" % ("OK   " if ok else "FALLA", texto,
                           "" if not detalle else " (%s)" % detalle))
    if not ok:
        fallas += 1


c = credenciales()
con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")

REGI0NES = ("gestión-de-usuarios", "ultimos-errores", "ultimos-intentos")

try:
    print("== metadatos ==")
    cur.execute("""select region_id, region_static_id, display_region_selector
                     from apex_application_page_regions
                    where application_id = 100 and page_id = 3""")
    filas = cur.fetchall()
    cur.execute("""select count(*) from apex_application_page_regions
                    where application_id = 100 and page_id = 3
                      and source_type_plugin_static_id = 'NATIVE_DISPLAY_SELECTOR'""")
    comprueba(cur.fetchone()[0] == 1, "la pagina 3 tiene un selector de regiones")

    incluidas = {f[1]: f[2] for f in filas}
    for rid in REGI0NES:
        comprueba(incluidas.get(rid) == "Yes",
                  "la region %s esta dentro del selector" % rid,
                  str(incluidas.get(rid)))

    print("== HTML real ==")
    salida = os.path.join(tempfile.gettempdir(), "opencode", "p3_pestanas.html")
    cur.execute("begin delete from usuario_empresa where usuario_id in "
                "(select usuario_id from usuario where upper(username)=upper(:u)); commit; "
                "delete from usuario where upper(username)=upper(:u); commit; end;", u=USUARIO)
    cur.execute("""insert into usuario (username,email,password_hash,estado,id_empresa,rol_id,
                                         debe_cambiar_clave,reintentos_fallidos)
                   values (:u,:e,sypex_hash_password(:p),'ACTIVO',1,
                           (select id_rol from syn_roles where codigo_rol='ADMIN'),'N',0)""",
                u=USUARIO, e=USUARIO + "@synpex.local", p=CLAVE)
    con.commit()

    r = subprocess.run([sys.executable, os.path.join(REPO, "deploy", "conexion", "abrir_pagina.py"),
                        USUARIO, CLAVE, "3", salida],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    texto = (r.stdout or "") + (r.stderr or "")
    m = re.search(r"HTTP (\d+)", texto)
    codigo = int(m.group(1)) if m else 0
    comprueba(codigo == 200, "la pagina 3 responde 200", str(codigo))
    html = open(salida, encoding="utf-8", errors="replace").read()

    m = re.search(r'<ul id="(\d+)_RDS".*?</ul>', html, re.S)
    comprueba(m is not None, "el HTML trae el selector de pestañas")
    if m:
        etiquetas = re.sub(r"<[^>]+>", "|", m.group(0))
        for esperada in ("Usuarios", "errores", "intentos"):
            comprueba(esperada.lower() in etiquetas.lower(),
                      "la pestaña «%s» esta pintada" % esperada)
        comprueba(html.count("a-RDS-link") >= 3, "hay al menos tres pestañas",
                  str(html.count("a-RDS-link")))
finally:
    try:
        cur.execute("begin delete from usuario_empresa where usuario_id in "
                    "(select usuario_id from usuario where upper(username)=upper(:u)); commit; "
                    "delete from usuario where upper(username)=upper(:u); commit; end;", u=USUARIO)
        con.commit()
    except Exception as e:  # noqa: BLE001
        print("  limpieza:", e)
    con.close()

print("\nRESULTADO: FALLAS=%d" % fallas)
sys.exit(1 if fallas else 0)
