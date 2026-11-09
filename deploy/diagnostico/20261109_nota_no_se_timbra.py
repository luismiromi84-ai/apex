import sys
sys.path.insert(0, r"C:\Users\luism\OneDrive\Documents\Apex_luis\deploy\conexion")
import oracledb
from verificar_conexion import CONNECT_STRING, credenciales

c = credenciales()
con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")

fallas = 0

# Se crea una nota de prueba dentro de la transaccion (se revierte al final):
# la NC que existia ya se proceso, no queda ninguna para probar.
origen = cur.execute("""select id_factura, cod_moneda, tipo_cambio, id_cliente from facturas
                         where id_empresa = 1 and tipo_documento = 'FAC' and estado <> 'ANULADA'
                         order by id_factura fetch first 1 rows only""").fetchone()
if origen:
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
            p_observaciones => 'prueba no se timbra', p_cod_moneda => :mon,
            p_tipo_cambio => :tasa, p_usuario => 'PRUEBA',
            p_tipo_documento => 'NC', p_id_factura_origen => :orig,
            p_fecha_referencia => sysdate);
        end;
    """, id=salida, cli=origen[3], mon=origen[1], tasa=origen[2], orig=origen[0])
    nota = salida.getvalue()
    try:
        cur.execute("begin pkg_facturacion.prc_procesar_factura(:i, 'PRUEBA'); end;", i=nota)
        fallas += 1
        print("  MAL NC %s -> no rechazo" % nota)
    except oracledb.DatabaseError as ex:
        error, = ex.args
        if error.code == 20050:
            print("  OK  NC %s -> rechazada con -20050" % nota)
        else:
            fallas += 1
            print("  MAL NC %s -> %s" % (nota, error.message[:90]))
for tipo in ("NC", "ND", "FAC"):
    fila = cur.execute("""select id_factura, estado from facturas where tipo_documento = :t
                           and estado not in ('ANULADA','PAGADA','TIMBRADA')
                          order by id_factura desc fetch first 1 rows only""", t=tipo).fetchone()
    if not fila:
        print("  (no hay %s que probar)" % tipo)
        continue
    try:
        cur.execute("begin pkg_facturacion.prc_procesar_factura(:i, 'PRUEBA'); end;",
                    i=fila[0])
        if tipo == "FAC":
            print("  OK  %s %s -> procesada" % (tipo, fila[0]))
        else:
            fallas += 1
            print("  MAL %s %s -> no rechazo" % (tipo, fila[0]))
    except oracledb.DatabaseError as ex:
        error, = ex.args
        if tipo == "FAC":
            fallas += 1
            print("  MAL FAC %s -> %s" % (fila[0], error.message[:90]))
        elif error.code == 20050:
            print("  OK  %s %s -> rechazada con -20050" % (tipo, fila[0]))
        else:
            fallas += 1
            print("  MAL %s %s -> %s" % (tipo, fila[0], error.message[:90]))

con.rollback()
con.close()
print("RESULTADO: FALLAS=%d" % fallas)
sys.exit(1 if fallas else 0)
