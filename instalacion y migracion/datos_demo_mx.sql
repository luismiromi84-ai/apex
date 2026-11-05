-- =============================================================================
-- datos_demo_mx.sql - documentos de ejemplo para la empresa 2 (Mexico)
--
-- Por que existe: la empresa 2 solo tenia clientes (201-203) y ninguna factura ni
-- presupuesto, asi que mx.demo entraba a las listas y las veia vacias.
--
-- Ids: dentro del rango del dataset demo (1000-1999) para que
--      deploy/migrations/20261105_purgar_demo.sql los borre junto con el resto.
--      Presupuestos y facturas 1201-1206; presupuestos_det 1471+; facturas_det 1921+.
--      (Cada tabla tiene su propio espacio de ids, no chocan entre si.)
--
-- Moneda: MXN, tipo de cambio 1 (base USD). Folios correlativos POR EMPRESA:
--      presupuestos 1-6; facturas F-1 a F-6.
--
-- Los campos fiscales de factura (RFC emisor/receptor, uso CFDI, metodo y forma
-- de pago) SI se rellenan aqui: en las facturas de la empresa 1 estan nulos.
--
-- Ejecutar:
--   python deploy/conexion/importar_export.py "instalacion y migracion/datos_demo_mx.sql"
--
-- Es reejecutable: empieza borrando su propio rango.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;
/

delete from facturas_det     where id_factura     between 1201 and 1206;
/

delete from facturas         where id_factura     between 1201 and 1206;
/

delete from presupuestos_det where id_presupuesto between 1201 and 1206;
/

delete from presupuestos     where id_presupuesto between 1201 and 1206;
/

-- -----------------------------------------------------------------------------
-- Presupuestos (6) y su detalle. Cabeceras en 0: el trigger calcula los totales.
-- -----------------------------------------------------------------------------
declare
    v_estados sys.odcivarchar2list := sys.odcivarchar2list(
        'PENDIENTE','ENVIADO','APROBADO','RECHAZADO','APROBADO','ENVIADO');
    v_id_pre  number;
    v_cliente number;
    v_fecha   date;
    v_prod    number;
    v_precio  number;
    v_cant    number;
    v_bruto   number;
    v_iva     number;
begin
    for i in 1 .. 6 loop
        v_id_pre  := 1200 + i;
        v_cliente := 200 + mod(i, 3) + 1;          -- 201, 202, 203
        v_fecha   := add_months(trunc(sysdate,'MM'), -mod(i,4)) + mod(i,20);

        insert into presupuestos (id_presupuesto, id_empresa, folio, id_cliente, fecha_emision,
                                  fecha_vencimiento, estado, cod_moneda, tipo_cambio,
                                  subtotal, impuesto_iva, total, observaciones, creado_por)
        values (v_id_pre, 2, i, v_cliente, v_fecha, v_fecha + 30,
                v_estados(i), 'MXN', 1, 0, 0, 0,
                'Presupuesto de ejemplo Mexico', 'ADMIN_SYPEX');

        for j in 1 .. 2 loop
            v_prod   := 1000 + mod(i + j, 10) + 1;
            v_cant   := 1 + mod(i + j, 3);
            select precio_sugerido into v_precio
              from producto_servicio where id_producto_servicio = v_prod;
            v_bruto  := v_cant * v_precio;
            v_iva    := round(v_bruto * 16 / 100, 2);

            insert into presupuestos_det (id_detalle, id_presupuesto, id_producto_servicio,
                                          descripcion, cantidad, precio_unitario, subtotal_linea,
                                          porcentage_descuento, monto_descuento,
                                          id_impuesto, porcentage_impuesto, monto_impuesto,
                                          monto_total_linea)
            values (1460 + i*10 + j, v_id_pre, v_prod,
                    'Linea ' || j || ' del presupuesto ' || (1200 + i),
                    v_cant, v_precio, v_bruto,
                    0, 0, 4, 16, v_iva, v_bruto + v_iva);
        end loop;
    end loop;
end;
/

-- -----------------------------------------------------------------------------
-- Facturas (6) y su detalle, con datos fiscales de Mexico.
-- -----------------------------------------------------------------------------
declare
    v_id_fac  number;
    v_cliente number;
    v_rif     varchar2(20);
    v_fecha   date;
    v_estado  varchar2(20);
    v_tipo    varchar2(3);
    v_prod    number;
    v_codigo  varchar2(20);
    v_precio  number;
    v_cant    number;
    v_bruto   number;
    v_iva     number;
    v_forma   varchar2(3);
begin
    for i in 1 .. 6 loop
        v_id_fac  := 1200 + i;
        v_cliente := 200 + mod(i, 3) + 1;
        select rif into v_rif from clientes where id_cliente = v_cliente;
        v_fecha   := add_months(trunc(sysdate,'MM'), -mod(i,4)) + mod(i,15);
        v_tipo    := case when i <= 4 then 'FAC' when i = 5 then 'NC' else 'ND' end;
        v_estado  := case mod(i,3) when 0 then 'PAGADA' when 1 then 'PENDIENTE' else 'TIMBRADA' end;
        v_forma   := case when mod(i,2) = 0 then '03' else '01' end;   -- 03 transferencia, 01 efectivo

        insert into facturas (id_factura, id_empresa, id_cliente, id_presupuesto, tipo_documento,
                              folio_factura, cod_moneda, tipo_cambio, fecha_emision,
                              fecha_vencimiento, estado, subtotal, monto_impuesto, monto_total,
                              rfc_emisor, rfc_receptor, uso_cfdi, metodo_pago, forma_pago,
                              condicion_pago, observaciones, creado_por)
        values (v_id_fac, 2, v_cliente, case when i <= 3 then 1200 + i end, v_tipo,
                'F-' || i, 'MXN', 1, v_fecha,
                v_fecha + 30, v_estado, 0, 0, 0,
                'MXE010101AAA', v_rif, 'G03', 'PUE', v_forma,
                case when mod(i,2) = 0 then 4 else 1 end,
                'Factura de ejemplo Mexico', 'ADMIN_SYPEX');

        for j in 1 .. 2 loop
            v_prod   := 1000 + mod(i + j, 10) + 1;
            v_cant   := 1 + mod(i + j, 2);
            select precio_sugerido, codigo into v_precio, v_codigo
              from producto_servicio where id_producto_servicio = v_prod;
            v_bruto  := v_cant * v_precio;
            v_iva    := round(v_bruto * 16 / 100, 2);

            insert into facturas_det (id_detalle, id_factura, num_linea, id_producto, codigo_producto,
                                      descripcion, cantidad, precio_unitario,
                                      porcentaje_descuento, monto_descuento, id_impuesto,
                                      porcentaje_impuesto, monto_impuesto,
                                      subtotal_linea, monto_total_linea,
                                      tasa_cambio_aplicada, subtotal_bs, total_bs,
                                      porcentage_impuesto, porcentage_descuento, creado_por)
            values (1910 + i*10 + j, v_id_fac, j, v_prod, v_codigo,
                    'Linea ' || j || ' del documento ' || (1200 + i),
                    v_cant, v_precio,
                    0, 0, 4,
                    16, v_iva,
                    v_bruto, v_bruto + v_iva,
                    1, v_bruto, v_bruto + v_iva,
                    16, 0, 'ADMIN_SYPEX');
        end loop;
    end loop;
end;
/

commit;
/

-- -----------------------------------------------------------------------------
-- Validaciones: las cuatro deben devolver los valores esperados
-- -----------------------------------------------------------------------------
select 'presupuestos empresa 2' as control, count(*) as filas from presupuestos where id_empresa = 2;
/

select 'facturas empresa 2' as control, count(*) as filas from facturas where id_empresa = 2;
/

select 'cabeceras que no cuadran con su detalle' as control, count(*) as filas
  from presupuestos p
 where abs(p.total - nvl((select sum(d.monto_total_linea) from presupuestos_det d
                           where d.id_presupuesto = p.id_presupuesto), 0)) > 0.01;
/

select 'facturas con algun campo fiscal nulo' as control, count(*) as filas
  from facturas
 where id_empresa = 2
   and (rfc_emisor is null or rfc_receptor is null or uso_cfdi is null
        or metodo_pago is null or forma_pago is null);
/
