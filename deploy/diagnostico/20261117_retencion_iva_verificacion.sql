-- =============================================================================
-- 20261117_retencion_iva_verificacion.sql
--
-- Retencion de IVA del cliente, de punta a punta (2026-11-17):
--   R1  la retencion se calcula sobre el IVA, no sobre IVA + IGTF
--   R2  al agregar lineas a una factura ya creada, el trigger recalcula la retencion
--   R3  el monto se recalcula aunque la cabecera traiga monto_impuesto = 0 (alta)
--   R4  un cliente que no es agente de retencion deja la retencion en 0
--   R5  la pagina 21 (Cliente) guarda ES_AGENTE_RETENCION y PORCENTAJE_RETENCION
--   R6  la pagina 9 trae el % del cliente al elegirlo (accion dinamica)
--   R7  la pagina 9 refresca el IVA retenido y avisa si falta el comprobante
--   R8  el comprobante sigue validado a 14 digitos
--
-- Todo el DML va dentro de un SAVEPOINT y se revierte.
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261117_retencion_iva_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

begin
    begin execute immediate 'drop table tmp_retiva_fallas purge'; exception when others then null; end;
end;
/

create table tmp_retiva_fallas (caso varchar2(300))
/

declare
    type t_lista is table of varchar2(300);
    v_fallas t_lista := t_lista();
    v_msg    varchar2(300);

    v_cli_agente number;
    v_cli_normal number;
    v_fac        number;
    v_pct        number;
    v_ret        number;
    v_id_iva     number;
    v_id_igtf    number;
    v_n          number;

    procedure falla(p_texto varchar2) is
    begin
        v_fallas.extend;
        v_fallas(v_fallas.last) := substrb(p_texto, 1, 300);
    end;

    procedure linea(p_factura number, p_num number, p_subtotal number,
                    p_impuesto number, p_id_impuesto number, p_pct number) is
    begin
        insert into facturas_det (id_factura, num_linea, descripcion, cantidad, precio_unitario,
                                  id_impuesto, porcentaje_impuesto, monto_impuesto,
                                  subtotal_linea, monto_total_linea, tasa_cambio_aplicada,
                                  subtotal_bs, total_bs)
        values (p_factura, p_num, 'Linea ' || p_num, 1, p_subtotal,
                p_id_impuesto, p_pct, p_impuesto,
                p_subtotal, p_subtotal + p_impuesto, 1,
                p_subtotal, p_subtotal + p_impuesto);
    end;

    function nueva_factura(p_cliente number, p_folio varchar2, p_comprobante varchar2,
                           p_pct number, p_impuesto number) return number is
        v_id number;
    begin
        pkg_facturacion.prc_guardar_factura(
            p_id_factura => v_id, p_id_empresa => 1, p_folio_factura => p_folio,
            p_id_cliente => p_cliente, p_id_presupuesto => null,
            p_rfc_emisor => 'J-1', p_rfc_receptor => 'J-2', p_uuid_fiscal => null,
            p_uso_cfdi => null, p_forma_pago => null, p_metodo_pago => null,
            p_condicion_pago => null, p_fecha_emision => '17/11/2026',
            p_fecha_vencimiento => null, p_estado => 'PENDIENTE',
            p_subtotal => 100, p_monto_impuesto => p_impuesto, p_monto_total => 100 + p_impuesto,
            p_observaciones => null, p_cod_moneda => 'VES', p_tipo_cambio => 1,
            p_usuario => 'test_retiva', p_tipo_documento => 'FAC',
            p_porcentaje_retencion => p_pct,
            p_nro_comprobante_retencion => p_comprobante);
        return v_id;
    end;
begin
    savepoint sp_retiva;

    select id_impuesto into v_id_iva from impuestos
     where cod_pais = 'VE' and cod_impuesto = 'IVA_GEN' and rownum = 1;
    select id_impuesto into v_id_igtf from impuestos
     where cod_pais = 'VE' and cod_impuesto = 'IGTF' and rownum = 1;

    insert into clientes (id_empresa, rif, razon_social, es_agente_retencion, porcentaje_retencion)
    values (1, 'J-TESTRIVA-1', 'Cliente agente (verificacion)', 'S', 75)
    returning id_cliente into v_cli_agente;

    insert into clientes (id_empresa, rif, razon_social, es_agente_retencion, porcentaje_retencion)
    values (1, 'J-TESTRIVA-2', 'Cliente normal (verificacion)', 'N', 75)
    returning id_cliente into v_cli_normal;

    -- R1: factura nueva sin lineas -> 0; con lineas, 75 % solo del IVA (el IGTF no entra)
    v_fac := nueva_factura(v_cli_agente, 'RETIVA-1', null, 75, 0);
    linea(v_fac, 1, 100, 16, v_id_iva, 16);
    linea(v_fac, 2, 50, 1.5, v_id_igtf, 3);
    select porcentaje_retencion, retencion_iva_bs into v_pct, v_ret
      from facturas where id_factura = v_fac;
    if v_pct <> 75 then falla('R1: porcentaje ' || v_pct || ' en vez de 75'); end if;
    if v_ret <> 12 then
        falla('R1: retencion ' || v_ret || ' en vez de 12 (75% del IVA 16, sin el IGTF)');
    end if;

    -- R2: cambiar una linea del detalle vuelve a calcular la retencion
    update facturas_det set monto_impuesto = 32, total_bs = 232, monto_total_linea = 132
     where id_factura = v_fac and num_linea = 1;
    select retencion_iva_bs into v_ret from facturas where id_factura = v_fac;
    if v_ret <> 24 then falla('R2: tras editar la linea la retencion quedo en ' || v_ret || ' en vez de 24'); end if;

    -- R3: la cabecera trae monto_impuesto = 0 (como en un alta) y aun asi se calcula
    v_fac := nueva_factura(v_cli_agente, 'RETIVA-2', null, 50, 0);
    linea(v_fac, 1, 100, 16, v_id_iva, 16);
    select retencion_iva_bs into v_ret from facturas where id_factura = v_fac;
    if v_ret <> 8 then falla('R3: con cabecera en 0 la retencion quedo en ' || v_ret || ' en vez de 8'); end if;

    -- R4: cliente que no retiene -> 0
    v_fac := nueva_factura(v_cli_normal, 'RETIVA-3', null, null, 16);
    select retencion_iva_bs into v_ret from facturas where id_factura = v_fac;
    if v_ret <> 0 then falla('R4: un cliente normal retuvo ' || v_ret); end if;

    -- R8: el comprobante sigue validado a 14 digitos
    begin
        v_fac := nueva_factura(v_cli_agente, 'RETIVA-4', '123', 75, 16);
        falla('R8: acepto un comprobante de 3 digitos');
    exception
        when others then
            if sqlcode <> -20081 then falla('R8: codigo ' || sqlcode || ' en vez de -20081'); end if;
    end;

    -- R5: la pagina 21 guarda el flag del agente (insert y update)
    select nvl(sum(regexp_count(lower(process_source), 'es_agente_retencion')), 0) into v_n
      from apex_application_page_proc
     where application_id = 100 and page_id = 21;
    if v_n < 2 then
        falla('R5: el proceso de la pagina 21 menciona es_agente_retencion ' || v_n || ' veces (esperado 2: alta y edicion)');
    end if;
    select nvl(sum(regexp_count(lower(process_source), 'porcentaje_retencion')), 0) into v_n
      from apex_application_page_proc
     where application_id = 100 and page_id = 21;
    if v_n < 2 then falla('R5: el proceso de la pagina 21 no guarda porcentaje_retencion en alta y edicion'); end if;

    -- R6: la pagina 9 trae el % del cliente al elegirlo (evento sobre el cliente;
    -- el codigo de la accion se vigila en 20261117_retencion_iva_pagina.py porque
    -- APEX no expone los atributos de las acciones dinamicas en el diccionario)
    select count(*) into v_n from apex_application_page_da
     where application_id = 100 and page_id = 9
       and upper(when_element) = 'P9_ID_CLIENTE';
    if v_n = 0 then falla('R6: no hay evento de cambio sobre P9_ID_CLIENTE en la pagina 9'); end if;

    -- R7: el proceso refresca el IVA retenido y avisa si falta el comprobante
    -- (se busca 'comprobante de retenci' sin la o final: el texto lleva acento)
    select count(*) into v_n from apex_application_page_proc
     where application_id = 100 and page_id = 9
       and process_name = 'Insert/update Facturacion'
       and instr(lower(process_source), ':p9_retencion_iva_bs') > 0
       and instr(lower(process_source), 'comprobante de retenci') > 0;
    if v_n = 0 then
        falla('R7: el proceso de guardado no refresca P9_RETENCION_IVA_BS o no avisa del comprobante');
    end if;

    rollback to sp_retiva;

    for i in 1 .. v_fallas.count loop
        insert into tmp_retiva_fallas values (v_fallas(i));
    end loop;
exception
    when others then
        rollback to sp_retiva;
        v_msg := substrb('R?: el caso revento: ' || sqlerrm, 1, 300);
        insert into tmp_retiva_fallas values (v_msg);
end;
/

declare
    v_fallas number;
    v_lista  varchar2(3000);
begin
    select count(*) into v_fallas from tmp_retiva_fallas;
    select substrb(listagg(caso, ' | ' on overflow truncate) within group (order by caso), 1, 3000)
      into v_lista from tmp_retiva_fallas;
    execute immediate 'drop table tmp_retiva_fallas purge';
    raise_application_error(-20100, substrb('RESULTADO: FALLAS=' || v_fallas || ' | ' || v_lista, 1, 3000));
end;
/
