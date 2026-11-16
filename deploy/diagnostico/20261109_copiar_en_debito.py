"""Una nota de DEBITO tambien puede traer lineas de su factura (suma a la deuda,
asi que no se le aplican los topes de la nota de credito)."""
import sys
sys.path.insert(0, r"C:\Users\luism\OneDrive\Documents\Apex_luis\deploy\conexion")
import oracledb
from verificar_conexion import CONNECT_STRING, credenciales

c = credenciales()
con = oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CONNECT_STRING)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")

fallas = 0
origen = cur.execute("""select f.id_factura, f.cod_moneda, f.tipo_cambio, f.id_cliente
                          from facturas f
                         where f.id_empresa = 1 and f.tipo_documento = 'FAC'
                           and f.estado <> 'ANULADA'
                           and (select count(*) from facturas_det d where d.id_factura = f.id_factura) >= 1
                         order by f.id_factura fetch first 1 rows only""").fetchone()
if not origen:
    print("  (no hay factura para probar)")
else:
    linea, total_linea = cur.execute("""select id_detalle, monto_total_linea from facturas_det
                                         where id_factura = :i order by num_linea
                                         fetch first 1 rows only""", i=origen[0]).fetchone()
    for tipo in ("NC", "ND"):
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
                p_observaciones => 'prueba copiar en ' || :t, p_cod_moneda => :mon,
                p_tipo_cambio => :tasa, p_usuario => 'PRUEBA',
                p_tipo_documento => :t, p_id_factura_origen => :orig,
                p_fecha_referencia => sysdate);
            end;
        """, id=salida, cli=origen[3], mon=origen[1], tasa=origen[2], t=tipo, orig=origen[0])
        nota = salida.getvalue()
        try:
            cur.execute("begin pkg_factura_detalle.copiar_lineas_de_factura(:n, :o, :l, 'PRUEBA'); end;",
                        n=nota, o=origen[0], l=str(linea))
            n, tot = cur.execute("""select count(*), nvl(sum(monto_total_linea),0)
                                      from facturas_det where id_factura = :i""", i=nota).fetchone()
            if n == 1 and abs(tot - total_linea) < 0.01:
                print("  OK  %s -> copio la linea (%s)" % (tipo, tot))
            else:
                fallas += 1
                print("  MAL %s -> %s linea(s), total %s" % (tipo, n, tot))
        except oracledb.DatabaseError as ex:
            error, = ex.args
            fallas += 1
            print("  MAL %s -> %s" % (tipo, error.message[:110]))

con.rollback()
con.close()
print("RESULTADO: FALLAS=%d" % fallas)
sys.exit(1 if fallas else 0)
