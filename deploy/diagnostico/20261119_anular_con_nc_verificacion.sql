-- =============================================================================
-- 20261119_anular_con_nc_verificacion.sql
--
-- Documento emitido inmutable y anulación con nota de credito (2026-11-19):
--   E1  fn_factura_editable: solo el borrador (PENDIENTE) es editable
--   E2  guardar la cabecera de una TIMBRADA se rechaza (-20024)
--   E3  agregar y eliminar lineas de una TIMBRADA se rechaza
--   A1  anular una TIMBRADA crea la NC por el total y la deja ANULADA
--   A2  la NC copia todas las lineas con su origen
--   A3  con cobros activos no se anula y NO se crea la NC (-20091)
--   A4  una nota no se anula con otra nota (-20066)
--   A5  una factura sin lineas no se anula con NC (-20065)
--   A6  el boton Anular usa fn_factura_anulable y el proceso llama a la NC
--
-- Todo el DML va dentro de un SAVEPOINT y se revierte.
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261119_anular_con_nc_verificacion.sql
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

begin
    begin execute immediate 'drop table tmp_annc_fallas purge'; exception when others then null; end;
end;
/

create table tmp_annc_fallas (caso varchar2(300))
/

declare
    type t_lista is table of varchar2(300);
    v_fallas t_lista := t_lista();
    v_msg    varchar2(300);
    v_cli    number;
    v_fac    number;
    v_nc     number;
    v_tipo   varchar2(10);
    v_estado varchar2(20);
    v_total  number;
    v_nc_tot number;
    v_n      number;

    procedure falla(p varchar2) is
    begin
        v_fallas.extend;
        v_fallas(v_fallas.count) := substrb(p, 1, 300);
    end;

    function nueva_factura(p_estado varchar2) return number is
        v_id number;
    begin
        pkg_facturacion.prc_guardar_factura(
            p_id_factura => v_id, p_id_empresa => 1, p_folio_factura => null,
            p_id_cliente => v_cli, p_id_presupuesto => null,
            p_rfc_emisor => 'J-1', p_rfc_receptor => 'J-2', p_uuid_fiscal => null,
            p_uso_cfdi => null, p_forma_pago => null, p_metodo_pago => null,
            p_condicion_pago => null, p_fecha_emision => '10/11/2026',
            p_fecha_vencimiento => null, p_estado => 'PENDIENTE',
            p_subtotal => 0, p_monto_impuesto => 0, p_monto_total => 0,
            p_observaciones => 'verificacion anular con nc', p_cod_moneda => 'VES',
            p_tipo_cambio => 1, p_usuario => 'VERIF', p_tipo_documento => 'FAC',
            p_porcentaje_retencion => 0);
        insert into facturas_det (id_factura, num_linea, descripcion, cantidad, precio_unitario,
                   id_impuesto, porcentaje_impuesto, monto_impuesto, subtotal_linea,
                   monto_total_linea, tasa_cambio_aplicada, subtotal_bs, total_bs)
        values (v_id, 1, 'Servicio', 1, 100, 1, 16, 16, 100, 116, 1, 100, 116);
        if p_estado <> 'PENDIENTE' then
            pkg_facturacion.prc_procesar_factura(v_id, 'VERIF');
        end if;
        return v_id;
    end;
begin
    savepoint sp_annc;

    select min(id_cliente) into v_cli
      from clientes where id_empresa = 1 and nvl(es_agente_retencion, 'N') = 'N';

    -- E1
    v_fac := nueva_factura('PENDIENTE');
    if not fn_factura_editable(v_fac) then
        falla('E1: una PENDIENTE deberia ser editable');
    end if;
    if not fn_factura_editable(null) then
        falla('E1: un id nulo deberia ser editable (alta)');
    end if;

    pkg_facturacion.prc_procesar_factura(v_fac, 'VERIF');
    select estado into v_estado from facturas where id_factura = v_fac;
    if fn_factura_editable(v_fac) then
        falla('E1: una TIMBRADA sigue siendo editable');
    end if;

    -- E2
    begin
        pkg_facturacion.prc_actualizar(
            p_id_factura        => v_fac,
            p_id_empresa        => 1,
            p_folio_factura     => 'X',
            p_id_cliente        => v_cli,
            p_id_presupuesto    => null,
            p_rfc_emisor        => null,
            p_rfc_receptor      => null,
            p_uuid_fiscal       => null,
            p_uso_cfdi          => null,
            p_forma_pago        => null,
            p_metodo_pago       => null,
            p_condicion_pago    => null,
            p_fecha_emision     => '10/11/2026',
            p_fecha_vencimiento => null,
            p_estado            => 'TIMBRADA',
            p_subtotal          => 0,
            p_monto_impuesto    => 0,
            p_monto_total       => 0,
            p_observaciones     => 'x',
            p_cod_moneda        => 'VES',
            p_tipo_cambio       => 1);
        falla('E2: se pudo guardar la cabecera de una TIMBRADA');
    exception
        when others then
            if instr(sqlerrm, '20024') = 0 then
                falla('E2: el error no es el -20024: ' || substrb(sqlerrm, 1, 120));
            end if;
    end;

    -- E3
    declare
        v_det number;
    begin
        pkg_factura_detalle.guardar_detalle(
            p_id_factura        => v_fac,
            p_id_detalle        => v_det,
            p_id_producto       => null,
            p_id_impuesto       => '1',
            p_cantidad          => '1',
            p_precio_unitario   => '10',
            p_porc_descuento    => '0',
            p_monto_descuento   => '0',
            p_porc_impuesto     => '16',
            p_monto_impuesto    => '1.6',
            p_subtotal_linea    => '10',
            p_monto_total_linea => '11.6',
            p_codigo_producto   => null,
            p_descripcion       => 'otra',
            p_usuario           => 'VERIF');
        falla('E3: se pudo agregar una linea a una TIMBRADA');
    exception
        when others then
            if instr(sqlerrm, '20002') = 0 and instr(sqlerrm, '20003') = 0 then
                falla('E3: el error no es de documento cerrado: ' || substrb(sqlerrm, 1, 120));
            end if;
    end;

    -- A1 / A2
    select monto_total into v_total from facturas where id_factura = v_fac;
    prc_anular_factura_nc(p_id_factura => v_fac, p_id_nc => v_nc, p_usuario => 'VERIF');

    select estado into v_estado from facturas where id_factura = v_fac;
    if v_estado <> 'ANULADA' then
        falla('A1: la factura no quedo ANULADA (' || v_estado || ')');
    end if;
    if v_nc is null then
        falla('A1: no se creo la nota de credito');
    else
        select tipo_documento, estado, monto_total, id_factura_origen
          into v_tipo, v_estado, v_nc_tot, v_n
          from facturas where id_factura = v_nc;
        if v_tipo <> 'NC' then falla('A1: el documento creado no es NC (' || v_tipo || ')'); end if;
        if v_estado <> 'TIMBRADA' then falla('A1: la NC no nace timbrada (' || v_estado || ')'); end if;
        if abs(v_nc_tot - v_total) > 0.01 then
            falla('A1: la NC no es por el total (' || v_nc_tot || ' vs ' || v_total || ')');
        end if;
        if v_n <> v_fac then
            falla('A1: la NC no apunta a la factura');
        end if;
        select count(*) into v_n from facturas_det where id_factura = v_nc;
        if v_n <> 1 then
            falla('A2: la NC no copio las lineas (' || v_n || ')');
        end if;
        select count(*) into v_n from facturas_det
         where id_factura = v_nc and id_detalle_origen is not null;
        if v_n <> 1 then
            falla('A2: las lineas de la NC no guardan su origen (' || v_n || ')');
        end if;
    end if;

    -- A3: con un cobro vivo no se anula
    v_fac := nueva_factura('TIMBRADA');
    v_nc := null;
    insert into recibos (id_empresa, id_factura, fecha_cobro, cod_moneda, monto_cobrado,
                         monto_bs, monto_factura, monto_neto, estado, creado_por)
    values (1, v_fac, trunc(sysdate), 'VES', 10, 10, 10, 10, 'ACTIVO', 'VERIF');
    begin
        prc_anular_factura_nc(p_id_factura => v_fac, p_id_nc => v_nc, p_usuario => 'VERIF');
        falla('A3: se anulo una factura con cobros');
    exception
        when others then
            if instr(sqlerrm, '20091') = 0 then
                falla('A3: el error no es el -20091: ' || substrb(sqlerrm, 1, 120));
            end if;
            if v_nc is not null then
                falla('A3: creo la NC aunque no podia anular');
            end if;
    end;

    -- A4: una nota no se anula con otra nota
    select min(id_factura) into v_n from facturas where tipo_documento = 'NC';
    begin
        prc_anular_factura_nc(p_id_factura => v_n,
                              p_id_nc => v_nc, p_usuario => 'VERIF');
        falla('A4: anulo una nota con otra nota');
    exception
        when others then
            if instr(sqlerrm, '20066') = 0 and instr(sqlerrm, '20065') = 0 then
                falla('A4: el error no es el esperado: ' || substrb(sqlerrm, 1, 120));
            end if;
    end;

    rollback to sp_annc;

    -- A6: el boton y el proceso
    select count(*) into v_n from apex_260100.apex_application_page_buttons
     where application_id = 100 and page_id = 9 and button_name = 'BTN_CANCELAR'
       and instr(upper(condition_expression1), 'FN_FACTURA_ANULABLE') > 0
       and instr(upper(condition_expression1), 'FN_FACTURA_EDITABLE') = 0;
    if v_n = 0 then
        falla('A6: el boton Anular no usa fn_factura_anulable');
    end if;

    select count(*) into v_n from apex_260100.apex_application_page_proc
     where application_id = 100 and page_id = 9 and process_name = 'Elimiar factura'
       and instr(upper(process_source), 'PRC_ANULAR_FACTURA_NC') > 0;
    if v_n = 0 then
        falla('A6: el proceso de anular no llama a prc_anular_factura_nc');
    end if;

    for i in 1 .. v_fallas.count loop
        insert into tmp_annc_fallas values (v_fallas(i));
    end loop;
exception
    when others then
        rollback to sp_annc;
        v_msg := substrb('?: el caso revento: ' || sqlerrm, 1, 300);
        insert into tmp_annc_fallas values (v_msg);
end;
/

declare
    v_fallas number;
    v_lista  varchar2(3000);
begin
    select count(*) into v_fallas from tmp_annc_fallas;
    select substrb(listagg(caso, ' | ' on overflow truncate) within group (order by caso), 1, 3000)
      into v_lista from tmp_annc_fallas;
    execute immediate 'drop table tmp_annc_fallas purge';
    raise_application_error(-20100, substrb('RESULTADO: FALLAS=' || v_fallas || ' | ' || v_lista, 1, 3000));
end;
/
