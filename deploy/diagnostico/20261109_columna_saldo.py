"""Comprueba que la lista de Facturacion trae las columnas Notas y Saldo con el
calculo correcto (F-1041 1392,00 · F-1042 92,70, con las notas del dueno)."""
import sys
sys.path.insert(0, r"C:\Users\luism\OneDrive\Documents\Apex_luis\deploy\conexion")
import oracledb
from verificar_conexion import CONNECT_STRING, credenciales

c = credenciales()
con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")

# la consulta tal como esta guardada en APEX, con el usuario del dueno
sql = cur.execute("""select region_source from apex_application_page_regions
                      where region_id = 29963866505095675""").fetchone()[0].read()
sql = sql.replace(":APP_USER", "'luis'").rstrip().rstrip(";")
sql = sql.replace(":F_EMPRESA_ACTIVA", "1")

fallas = 0
try:
    filas = cur.execute(sql).fetchall()
    cols = [d[0].lower() for d in cur.description]
    i_id = cols.index("id_factura")
    i_folio, i_total = cols.index("folio"), cols.index("total")
    i_notas, i_saldo = cols.index("notas_credito"), cols.index("saldo")
    for f in filas:
        print("  %-8s total %10.2f  notas %10.2f  saldo %10.2f"
              % (f[i_folio], f[i_total], f[i_notas], f[i_saldo]))
        # El saldo ya no es total - notas: desde los cobros (2026-11-17) tambien
        # resta lo cobrado y suma las notas de debito. La verdad es
        # fn_saldo_factura, que es lo que usan el reporte y el boton «Cobrar».
        esperado = cur.execute("select fn_saldo_factura(:i) from dual",
                               {"i": f[i_id]}).fetchone()[0]
        if abs(esperado - f[i_saldo]) > 0.01:
            fallas += 1
            print("    MAL el saldo no es fn_saldo_factura (%0.2f vs %0.2f)"
                  % (f[i_saldo], esperado))
except Exception as ex:
    fallas += 1
    print("  MAL la consulta de la lista no corre:", str(ex)[:160])

# Las dos columnas tienen que salir con formato numerico (como Subtotal y Total).
cur.execute("""select column_alias, nvl(format_mask, '#')
                 from apex_application_page_ir_col
                where application_id = 100 and page_id = 8
                  and column_alias in ('NOTAS_CREDITO', 'SALDO')""")
mascaras = dict(cur.fetchall())
for col in ("NOTAS_CREDITO", "SALDO"):
    print("  %-14s formato %r" % (col, mascaras.get(col)))
    if mascaras.get(col) != "999G999G999G999G990D00":
        fallas += 1
        print("    MAL la columna no tiene el formato numerico de la lista")

con.close()
print("RESULTADO: FALLAS=%d" % fallas)
sys.exit(1 if fallas else 0)
