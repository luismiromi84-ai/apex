"""Ejecuta el codigo guardado de la accion 'Lee la cabecera...' con la factura origen
vacia, para comprobar que ya no levanta ORA-01403."""
import json
import re
import sys
sys.path.insert(0, r"C:\Users\luism\OneDrive\Documents\Apex_luis\deploy\conexion")
import oracledb
from verificar_conexion import CONNECT_STRING, credenciales

c = credenciales()
con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")
cur.execute("select attributes from apex_application_page_da_acts where action_id = 43000000000000346")
codigo = json.loads(cur.fetchone()[0].read())["plsql_code"]

# binds -> variable local, y esa variable se declara en el propio bloque
cuerpo = re.sub(r":[A-Z0-9_]+", "v_bind", codigo)
cuerpo = cuerpo.replace("declare", "declare\n    v_bind varchar2(4000);", 1)

fallas = 0
for valor, etiqueta in (("''", "factura origen vacia"), ("'999999'", "factura que no existe"),
                        ("'16'", "factura real")):
    bloque = cuerpo.replace("v_bind varchar2(4000);", "v_bind varchar2(4000) := %s;" % valor, 1)
    try:
        cur.execute(bloque)
        print("  OK  %s -> sin error" % etiqueta)
    except Exception as ex:
        fallas += 1
        print("  MAL %s -> %s" % (etiqueta, str(ex)[:160]))
con.rollback()
con.close()
print("RESULTADO: FALLAS=%d" % fallas)
sys.exit(1 if fallas else 0)
