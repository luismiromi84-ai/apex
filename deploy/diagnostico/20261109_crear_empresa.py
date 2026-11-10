"""Reproduce el proceso «Crear empresa» de la pagina 19 con los binds sustituidos, en
una transaccion que se revierte: tiene que crear la fila sin chocar con la PK."""
import sys
sys.path.insert(0, r"C:\Users\luism\OneDrive\Documents\Apex_luis\deploy\conexion")
import oracledb
from verificar_conexion import CONNECT_STRING, credenciales

c = credenciales()
con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")
cur.execute("select count(*) from empresas")
antes = cur.fetchone()[0]

ok = False
try:
    cur.execute("""
    declare
        v_nueva number;
    begin
        select nvl(max(id_empresa), 0) + 1 into v_nueva from empresas;

        insert into empresas (id_empresa, nombre_empresa, cod_pais, tipo_ident_fiscal, rfc, estado,
                              fecha_creacion)
        values (v_nueva, 'EMPRESA DE PRUEBA', 'VE', 'RIF', 'J-99999999-9', 'ACTIVO', systimestamp);
    end;
    """)
    ok = True
except Exception as ex:
    print("  MAL el proceso fallo:", str(ex)[:160])

cur.execute("select id_empresa, nombre_empresa from empresas where nombre_empresa = 'EMPRESA DE PRUEBA'")
fila = cur.fetchone()
if ok and fila:
    print("  OK  creo la empresa con id", fila[0])
else:
    print("  MAL no creo la empresa")

con.rollback()
cur.execute("select count(*) from empresas")
print("  filas antes/despues del rollback:", antes, cur.fetchone()[0])
con.close()
