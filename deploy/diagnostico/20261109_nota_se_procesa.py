"""Procesar una nota de credito (decision del dueno, 2026-11-09).

Contexto: se probo bloquear el procesado de las notas porque 'timbrar' es del
CFDI mexicano. El dueno lo revirtio: una nota que queda PENDIENTE no rebaja el
saldo de su factura, asi que tiene que poder procesarse como cualquier documento.
Este script comprueba que la nota se procesa y queda en TIMBRADA.

Se crea la nota dentro de una transaccion que se revierte al final.
"""
import sys
sys.path.insert(0, r"C:\Users\luism\OneDrive\Documents\Apex_luis\deploy\conexion")
import oracledb
from verificar_conexion import CONNECT_STRING, credenciales

c = credenciales()
con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")

fallas = 0

origen = cur.execute("""select id_factura, cod_moneda, tipo_cambio, id_cliente from facturas
                         where id_empresa = 1 and tipo_documento = 'FAC' and estado <> 'ANULADA'
                         order by id_factura fetch first 1 rows only""").fetchone()
if not origen:
    print("  (no hay factura de la que sacar una nota)")
else:
    salida = cur.var(oracledb.NUMBER)
    cur.execute("""
        begin
          pkg_facturacion.prc_guardar_factura(
            p_id_factura => :id, p_id_empresa => 1, p_folio_factura => null,
            p_id_cliente => :cli, p_id_presupuesto => null,
            p_rfc_emisor => 'X', p_rfc_receptor => null, p_uuid_fiscal => null,
            p_uso_cfdi => null, p_forma_pago => null, p_metodo_pago => null,
            p_condicion_pago => null, p_fecha_emision => to_char(sysdate,'DD/MM/YYYY'),
            p_fecha_vencimiento => null, p_estado => 'PENDIENTE',
            p_subtotal => 0, p_monto_impuesto => 0, p_monto_total => 0,
            p_observaciones => 'prueba procesar nota', p_cod_moneda => :mon,
            p_tipo_cambio => :tasa, p_usuario => 'PRUEBA',
            p_tipo_documento => 'NC', p_id_factura_origen => :orig,
            p_fecha_referencia => sysdate);
        end;
    """, id=salida, cli=origen[3], mon=origen[1], tasa=origen[2], orig=origen[0])
    nota = salida.getvalue()
    cur.execute("begin pkg_facturacion.prc_procesar_factura(:i, 'PRUEBA'); end;", i=nota)
    estado = cur.execute("select estado from facturas where id_factura = :i", i=nota).fetchone()[0]
    if estado == "TIMBRADA":
        print("  OK  NC %s -> procesada y en TIMBRADA" % nota)
    else:
        fallas += 1
        print("  MAL NC %s -> quedo en %s" % (nota, estado))

con.rollback()
con.close()
print("RESULTADO: FALLAS=%d" % fallas)
sys.exit(1 if fallas else 0)
