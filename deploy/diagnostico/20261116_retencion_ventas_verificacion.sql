-- =============================================================================
-- 20261116_retencion_ventas_verificacion.sql
--
-- Retencion de IVA del cliente en la factura de venta (Task 6).
-- Todo el DML va dentro de un SAVEPOINT y se revierte.
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261116_retencion_ventas_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

begin
    begin execute immediate 'drop table tmp_retv_fallas purge'; exception when others then null; end;
end;
/

create table tmp_retv_fallas (caso varchar2(300))
/

declare
    type t_lista is table of varchar2(300);
    v_fallas t_lista := t_lista();
    v_msg    varchar2(300);

    v_cli_con number;
    v_cli_sin number;
    v_fac      number;
    v_fac2     number;
    v_pct      number;
    v_ret      number;
    v_editable boolean;

    procedure falla(p_texto varchar2) is
    begin
        v_fallas.extend;
        v_fallas(v_fallas.last) := substrb(p_texto, 1, 300);
    end;

    function nueva_factura(p_cliente number, p_folio varchar2, p_comprobante varchar2,
                           p_pct number) return number is
        v_id number;
    begin
        pkg_facturacion.prc_guardar_factura(
            p_id_factura => v_id, p_id_empresa => 1, p_folio_factura => p_folio,
            p_id_cliente => p_cliente, p_id_presupuesto => null,
            p_rfc_emisor => 'J-1', p_rfc_receptor => 'J-2', p_uuid_fiscal => null,
            p_uso_cfdi => null, p_forma_pago => null, p_metodo_pago => null,
            p_condicion_pago => null, p_fecha_emision => '16/11/2026',
            p_fecha_vencimiento => null, p_estado => 'PENDIENTE',
            p_subtotal => 100, p_monto_impuesto => 16, p_monto_total => 116,
            p_observaciones => null, p_cod_moneda => 'VES', p_tipo_cambio => 1,
            p_usuario => 'test_retv', p_tipo_documento => 'FAC',
            p_porcentaje_retencion => p_pct,
            p_nro_comprobante_retencion => p_comprobante);
        return v_id;
    end;
begin
    savepoint sp_retv;

    insert into clientes (id_empresa, rif, razon_social, es_agente_retencion, porcentaje_retencion)
    values (1, 'J-TESTRETV-1', 'Cliente que retiene', 'S', 75)
    returning id_cliente into v_cli_con;

    insert into clientes (id_empresa, rif, razon_social, es_agente_retencion, porcentaje_retencion)
    values (1, 'J-TESTRETV-2', 'Cliente que no retiene', 'N', 75)
    returning id_cliente into v_cli_sin;

    -- V1: el porcentaje sale del cliente y la retencion es el 75 % del IVA en Bs.
    -- Desde el 2026-11-17 el monto se calcula del detalle (el IGTF no se retiene),
    -- asi que la factura necesita su linea de IVA. Y desde el 2026-11-19, retener
    -- sin comprobante de 14 digitos no se puede guardar: V3 cubre ese rechazo.
    v_fac := nueva_factura(v_cli_con, 'RETV-1', '20261100000001', null);
    insert into facturas_det (id_factura, num_linea, descripcion, cantidad, precio_unitario,
                              id_impuesto, porcentaje_impuesto, monto_impuesto,
                              subtotal_linea, monto_total_linea, tasa_cambio_aplicada,
                              subtotal_bs, total_bs)
    values (v_fac, 1, 'Servicio', 1, 100,
            (select id_impuesto from impuestos
              where cod_pais = 'VE' and cod_impuesto = 'IVA_GEN' and rownum = 1),
            16, 16, 100, 116, 1, 100, 116);
    select porcentaje_retencion, retencion_iva_bs into v_pct, v_ret
      from facturas where id_factura = v_fac;
    if v_pct <> 75 then falla('V1: porcentaje ' || v_pct || ' en vez de 75'); end if;
    if v_ret <> 12 then falla('V1: retencion ' || v_ret || ' en vez de 12'); end if;

    -- V2: un cliente que no retiene deja la retencion en 0.
    v_fac2 := nueva_factura(v_cli_sin, 'RETV-2', null, null);
    select retencion_iva_bs into v_ret from facturas where id_factura = v_fac2;
    if v_ret <> 0 then falla('V2: retencion ' || v_ret || ' en vez de 0'); end if;

    -- V3: el comprobante del cliente se valida a 14 digitos.
    begin
        v_fac2 := nueva_factura(v_cli_con, 'RETV-3', '123', null);
        falla('V3: acepto un comprobante de 3 digitos');
    exception
        when others then
            if sqlcode <> -20081 then falla('V3: codigo ' || sqlcode || ' en vez de -20081'); end if;
    end;

    -- V4: registrar el comprobante cierra la factura.
    v_fac2 := nueva_factura(v_cli_con, 'RETV-4', '20261100000099', null);
    insert into facturas_det (id_factura, num_linea, descripcion, cantidad, precio_unitario,
                              id_impuesto, porcentaje_impuesto, monto_impuesto,
                              subtotal_linea, monto_total_linea, tasa_cambio_aplicada,
                              subtotal_bs, total_bs)
    values (v_fac2, 1, 'Servicio', 1, 100,
            (select id_impuesto from impuestos
              where cod_pais = 'VE' and cod_impuesto = 'IVA_GEN' and rownum = 1),
            16, 16, 100, 116, 1, 100, 116);
    select retencion_iva_bs into v_ret from facturas where id_factura = v_fac2;
    if v_ret <> 12 then falla('V4: retencion con comprobante ' || v_ret || ' en vez de 12'); end if;

    v_editable := fn_factura_editable(v_fac2);
    if v_editable then falla('V4: la factura con comprobante sigue editable'); end if;

    begin
        pkg_facturacion.prc_actualizar(
            p_id_factura => v_fac2, p_id_empresa => 1, p_folio_factura => 'RETV-4',
            p_id_cliente => v_cli_con, p_id_presupuesto => null,
            p_rfc_emisor => 'J-1', p_rfc_receptor => 'J-2', p_uuid_fiscal => null,
            p_uso_cfdi => null, p_forma_pago => null, p_metodo_pago => null,
            p_condicion_pago => null, p_fecha_emision => '16/11/2026',
            p_fecha_vencimiento => null, p_estado => 'PENDIENTE',
            p_subtotal => 100, p_monto_impuesto => 16, p_monto_total => 116,
            p_observaciones => 'cambio', p_cod_moneda => 'VES', p_tipo_cambio => 1,
            p_tipo_documento => 'FAC', p_nro_control => null, p_id_factura_origen => null);
        falla('V4: prc_actualizar dejo editar una factura con comprobante');
    exception
        when others then
            if sqlcode <> -20024 then falla('V4: codigo ' || sqlcode || ' en vez de -20024'); end if;
    end;

    -- V5: las pantallas tienen los campos.
    declare
        v_n number;
    begin
        select count(*) into v_n from apex_application_page_items
         where application_id = 100 and page_id = 9 and item_name = 'P9_PORCENTAJE_RETENCION';
        if v_n = 0 then falla('V5: falta P9_PORCENTAJE_RETENCION'); end if;

        select count(*) into v_n from apex_application_page_items
         where application_id = 100 and page_id = 9 and item_name = 'P9_RETENCION_IVA_BS';
        if v_n = 0 then falla('V5: falta P9_RETENCION_IVA_BS'); end if;

        select count(*) into v_n from apex_application_page_items
         where application_id = 100 and page_id = 9 and item_name = 'P9_NRO_COMPROBANTE_RETENCION';
        if v_n = 0 then falla('V5: falta P9_NRO_COMPROBANTE_RETENCION'); end if;

        select count(*) into v_n from apex_application_page_items
         where application_id = 100 and page_id = 21 and item_name = 'P21_ES_AGENTE_RETENCION';
        if v_n = 0 then falla('V5: falta P21_ES_AGENTE_RETENCION'); end if;

        select count(*) into v_n from apex_application_page_items
         where application_id = 100 and page_id = 21 and item_name = 'P21_PORCENTAJE_RETENCION';
        if v_n = 0 then falla('V5: falta P21_PORCENTAJE_RETENCION'); end if;

        select count(*) into v_n from apex_application_page_regions
         where application_id = 100 and page_id = 20
           and upper(region_source) like '%RETENCION%';
        if v_n = 0 then falla('V5: la lista de clientes no muestra la retencion'); end if;
    end;

    rollback to sp_retv;

    for i in 1 .. v_fallas.count loop
        insert into tmp_retv_fallas values (v_fallas(i));
    end loop;
exception
    when others then
        rollback to sp_retv;
        v_msg := substrb('V?: el caso revento: ' || sqlerrm, 1, 300);
        insert into tmp_retv_fallas values (v_msg);
end;
/

declare
    v_fallas number;
    v_lista  varchar2(3000);
begin
    select count(*) into v_fallas from tmp_retv_fallas;
    select substrb(listagg(caso, ' | ' on overflow truncate) within group (order by caso), 1, 3000)
      into v_lista from tmp_retv_fallas;
    execute immediate 'drop table tmp_retv_fallas purge';
    raise_application_error(-20100, substrb('RESULTADO: FALLAS=' || v_fallas || ' | ' || v_lista, 1, 3000));
end;
/
