-- =============================================================================
-- 20261116_impreso_retencion_verificacion.sql
--
-- Bloque de retencion en la factura impresa (Task 7).
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261116_impreso_retencion_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

begin
    begin execute immediate 'drop table tmp_impret_fallas purge'; exception when others then null; end;
end;
/

create table tmp_impret_fallas (caso varchar2(300))
/

declare
    type t_lista is table of varchar2(300);
    v_fallas t_lista := t_lista();
    v_msg    varchar2(300);

    v_cli    number;
    v_cli2   number;
    v_fac    number;
    v_fac2   number;
    v_html   clob;
    v_html2  clob;

    procedure falla(p_texto varchar2) is
    begin
        v_fallas.extend;
        v_fallas(v_fallas.last) := substrb(p_texto, 1, 300);
    end;
begin
    savepoint sp_imp;

    insert into clientes (id_empresa, rif, razon_social, es_agente_retencion, porcentaje_retencion)
    values (1, 'J-TESTIMP-1', 'Cliente agente', 'S', 75)
    returning id_cliente into v_cli;

    insert into clientes (id_empresa, rif, razon_social, es_agente_retencion, porcentaje_retencion)
    values (1, 'J-TESTIMP-2', 'Cliente normal', 'N', 75)
    returning id_cliente into v_cli2;

    pkg_facturacion.prc_guardar_factura(
        p_id_factura => v_fac, p_id_empresa => 1, p_folio_factura => 'IMP-1',
        p_id_cliente => v_cli, p_id_presupuesto => null,
        p_rfc_emisor => 'J-1', p_rfc_receptor => 'J-2', p_uuid_fiscal => null,
        p_uso_cfdi => null, p_forma_pago => null, p_metodo_pago => null,
        p_condicion_pago => null, p_fecha_emision => '16/11/2026',
        p_fecha_vencimiento => null, p_estado => 'PENDIENTE',
        p_subtotal => 100, p_monto_impuesto => 16, p_monto_total => 116,
        p_observaciones => null, p_cod_moneda => 'VES', p_tipo_cambio => 1,
        p_usuario => 'test_imp', p_tipo_documento => 'FAC');

    pkg_facturacion.prc_guardar_factura(
        p_id_factura => v_fac2, p_id_empresa => 1, p_folio_factura => 'IMP-2',
        p_id_cliente => v_cli2, p_id_presupuesto => null,
        p_rfc_emisor => 'J-1', p_rfc_receptor => 'J-2', p_uuid_fiscal => null,
        p_uso_cfdi => null, p_forma_pago => null, p_metodo_pago => null,
        p_condicion_pago => null, p_fecha_emision => '16/11/2026',
        p_fecha_vencimiento => null, p_estado => 'PENDIENTE',
        p_subtotal => 100, p_monto_impuesto => 16, p_monto_total => 116,
        p_observaciones => null, p_cod_moneda => 'VES', p_tipo_cambio => 1,
        p_usuario => 'test_imp', p_tipo_documento => 'FAC');

    insert into facturas_det (id_factura, num_linea, descripcion, cantidad, precio_unitario,
                             id_impuesto, porcentaje_impuesto, monto_impuesto, subtotal_linea,
                             monto_total_linea, tasa_cambio_aplicada, subtotal_bs, total_bs)
    values (v_fac, 1, 'Servicio', 1, 100, 1, 16, 16, 100, 116, 1, 100, 116);

    v_html  := pkg_reportes_factura.fn_imprimir_factura(v_fac);
    insert into facturas_det (id_factura, num_linea, descripcion, cantidad, precio_unitario,
                             id_impuesto, porcentaje_impuesto, monto_impuesto, subtotal_linea,
                             monto_total_linea, tasa_cambio_aplicada, subtotal_bs, total_bs)
    values (v_fac2, 1, 'Servicio', 1, 100, 1, 16, 16, 100, 116, 1, 100, 116);

    v_html2 := pkg_reportes_factura.fn_imprimir_factura(v_fac2);

    -- I1: la factura con retencion imprime el IVA retenido y el neto.
    if instr(v_html, 'IVA retenido') = 0 then
        falla('I1: no imprime el IVA retenido');
    end if;
    if instr(v_html, 'Neto a cobrar') = 0 then
        falla('I1: no imprime el neto a cobrar');
    end if;

    -- I2: el total sigue siendo el bruto del documento.
    if instr(v_html, 'TOTAL') = 0 then
        falla('I2: no imprime el total en la moneda del documento');
    end if;
    if instr(v_html, '116,00') = 0 then
        falla('I2: el total no es el bruto (116,00)');
    end if;

    -- I3: una factura sin retencion no imprime el bloque.
    if instr(v_html2, 'IVA retenido') > 0 then
        falla('I3: imprime retencion en una factura sin retencion');
    end if;

    rollback to sp_imp;

    for i in 1 .. v_fallas.count loop
        insert into tmp_impret_fallas values (v_fallas(i));
    end loop;
exception
    when others then
        rollback to sp_imp;
        v_msg := substrb('I?: el caso revento: ' || sqlerrm, 1, 300);
        insert into tmp_impret_fallas values (v_msg);
end;
/

declare
    v_fallas number;
    v_lista  varchar2(3000);
begin
    select count(*) into v_fallas from tmp_impret_fallas;
    select substrb(listagg(caso, ' | ' on overflow truncate) within group (order by caso), 1, 3000)
      into v_lista from tmp_impret_fallas;
    execute immediate 'drop table tmp_impret_fallas purge';
    raise_application_error(-20100, substrb('RESULTADO: FALLAS=' || v_fallas || ' | ' || v_lista, 1, 3000));
end;
/
