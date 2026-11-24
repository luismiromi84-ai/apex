# -*- coding: utf-8 -*-
"""Comprueba por HTTP que las tres pantallas del inventario responden y traen lo suyo."""
import os
import re
import subprocess
import sys

REPO = r"C:\Users\luism\OneDrive\Documents\Apex_luis"
sys.path.insert(0, os.path.join(REPO, "deploy", "conexion"))
import oracledb
from verificar_conexion import CONNECT_STRING, credenciales

USUARIO = "diag.inv"
CLAVE = "Diag#2026"
fallas = []


def comprobar(nombre, ok, detalle=""):
    print(("  OK  " if ok else "  MAL ") + nombre + (("  -> " + str(detalle)) if detalle else ""))
    if not ok:
        fallas.append(nombre)


con = oracledb.connect(user=credenciales()["DB_USER"], password=credenciales()["DB_PASSWORD"], dsn=CONNECT_STRING)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")


def limpiar():
    cur.execute("""begin
                     for r in (select usuario_id from usuario where upper(username) = :u) loop
                         delete from usuario_empresa where usuario_id = r.usuario_id;
                         commit;
                         delete from usuario where usuario_id = r.usuario_id;
                         commit;
                     end loop;
                   end;""", u=USUARIO.upper())
    con.commit()


limpiar()
cur.execute("""insert into usuario (username, email, password_hash, estado, id_empresa, rol_id,
                                    debe_cambiar_clave, reintentos_fallidos)
               values (:u, :u || '@synpex.local', sypex_hash_password(:c), 'ACTIVO', 1,
                       (select id_rol from syn_roles where codigo_rol = 'ADMIN'), 'N', 0)""",
            u=USUARIO, c=CLAVE)
con.commit()

try:
    # ojo: el id DOM de una region es R<id numerico>, no su static id
    for pagina, marcas in [(42, ["ARTICULOS", "VALOR (BS)", "R43000000000001933",
                                 "R43000000000001932"]),
                           (43, ["Filtrar", "R43000000000001950", "R43000000000001957"]),
                           (44, ["P44_MOTIVO", "Guardar ajuste", "R43000000000001971"])]:
        salida = os.path.join(os.environ.get("TEMP", "."), "inv_p%d.html" % pagina)
        r = subprocess.run([sys.executable, "deploy/conexion/abrir_pagina.py",
                            USUARIO, CLAVE, str(pagina), salida],
                           cwd=REPO, capture_output=True, text=True, encoding="utf-8",
                           errors="replace")
        html = open(salida, encoding="utf-8", errors="replace").read() if os.path.exists(salida) else ""
        comprobar("pagina %d responde con contenido" % pagina, len(html) > 20000, len(html))
        for m in marcas:
            comprobar("pagina %d trae %s" % (pagina, m), m in html)
        comprobar("pagina %d sin error de APEX" % pagina,
                  "ORA-" not in html and "Se ha producido" not in html)
finally:
    limpiar()
    con.close()

print("RESULTADO: FALLAS=%d" % len(fallas))
sys.exit(1 if fallas else 0)
