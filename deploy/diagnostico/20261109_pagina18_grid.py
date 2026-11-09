"""La pagina 18 tiene que renderizar: comprueba que ningun item pase de 12 columnas
(el error WWV_FLOW_GRID_LAYOUT.MORE_THAN_SUPPORTED_COLUMNS)."""
import sys
sys.path.insert(0, r"C:\Users\luism\OneDrive\Documents\Apex_luis\deploy\conexion")
import oracledb
from verificar_conexion import CONNECT_STRING, credenciales

c = credenciales()
con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")

fallas = 0
cur.execute("""select item_name, display_sequence, nvl(column_span, 0),
                      nvl(begins_on_new_row, 'Yes'), nvl(grid_column, 0)
                 from apex_application_page_items
                where application_id = 100 and page_id = 18
                order by display_sequence""")
acumulado = 0
for nombre, seq, span, nueva_fila, col in cur:
    ancho = span if span else 12
    if nueva_fila == 'Yes':
        acumulado = 0
    acumulado += ancho
    if acumulado > 12:
        fallas += 1
        print("  MAL %s (seq %s): la fila pasa de 12 columnas (%s)" % (nombre, seq, acumulado))
    if col and (col + ancho - 1) > 12:
        fallas += 1
        print("  MAL %s: columna %s + span %s pasa de 12" % (nombre, col, ancho))

print("items revisados de la pagina 18")
con.close()
print("RESULTADO: FALLAS=%d" % fallas)
sys.exit(1 if fallas else 0)
