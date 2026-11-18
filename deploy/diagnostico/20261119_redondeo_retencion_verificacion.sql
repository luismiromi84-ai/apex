-- =============================================================================
-- 20261119_redondeo_retencion_verificacion.sql
--
-- Redondeo de la linea de factura y comprobante de retencion obligatorio
-- (2026-11-19):
--   R1  el recuadro de la pagina 8 sale de un solo origen (subtotal_linea +
--       monto_descuento), no de cantidad x precio recalculado
--   R2  lo mismo en el recuadro de la pagina 5
--   R3  el proceso de la pagina 10 redondea el precio unitario a 2 decimales
--   R4  no queda ninguna linea de factura descuadrada contra el precio impreso
--   R5  la cabecera de cada factura abierta es la suma de su detalle
--   R6  guardar una FAC con retencion y sin comprobante lanza -20064
--   R7  con un comprobante de 14 digitos deja guardar
--   R8  el boton de la pagina 9 dice Anular, con icono fa-ban, confirmacion y
--       la condicion de rol y de modo consulta
--   R9  cero objetos invalidos
--
-- Todo el DML va dentro de un SAVEPOINT y se revierte.
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261119_redondeo_retencion_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

begin
    begin execute immediate 'drop table tmp_round_fallas purge'; exception when others then null; end;
end;
/

create table tmp_round_fallas (caso varchar2(300))
/

declare
    type t_lista is table of varchar2(300);
    v_fallas t_lista := t_lista();
    v_msg    varchar2(300);
    v_n      number;
    v_cli    number;
    v_fac    number;
    v_pct    number;

    procedure falla(p_texto varchar2) is
    begin
        v_fallas.extend;
        v_fallas(v_fallas.count) := substrb(p_texto, 1, 300);
    end;
begin
    savepoint sp_round;

    -- R1 / R2: los dos recuadros usan subtotal_linea + monto_descuento.
    select count(*) into v_n
      from apex_260100.apex_application_page_regions
     where application_id = 100 and page_id in (5, 8)
       and region_name = 'Resumen Financiero'
       and instr(upper(region_source), 'SUBTOTAL_LINEA') > 0
       and instr(upper(region_source), 'PRECIO_UNITARIO') = 0;
    if v_n <> 2 then
        falla('R1/R2: algun recuadro (5 u 8) sigue calculando el bruto con cantidad x precio');
    end if;

    -- R3: el proceso de la linea de factura redondea el precio.
    select count(*) into v_n
      from apex_260100.apex_application_page_proc
     where application_id = 100 and page_id = 10
       and instr(upper(process_source), 'ROUND(FN_CLEAN_NUM(:P10_PRECIO_UNITARIO), 2)') > 0;
    if v_n = 0 then
        falla('R3: el proceso de la pagina 10 no redondea el precio unitario a 2 decimales');
    end if;

    -- R4: ninguna linea de factura descuadrada contra el precio de 2 decimales.
    select count(*) into v_n
      from facturas_det d
     where d.subtotal_linea + nvl(d.monto_descuento, 0)
           <> round(d.cantidad * round(d.precio_unitario, 2), 2);
    if v_n > 0 then
        falla('R4: hay ' || v_n || ' linea(s) de factura que no cuadran con cantidad x precio');
    end if;

    -- R5: la cabecera cuadra con el detalle en los documentos abiertos.
    select count(*) into v_n
      from facturas f
     where f.estado in ('PENDIENTE', 'TIMBRADA', 'PARCIAL')
       and exists (select 1 from facturas_det d where d.id_factura = f.id_factura)
       and (abs(f.subtotal - (select nvl(sum(d.subtotal_linea), 0) from facturas_det d
                               where d.id_factura = f.id_factura)) > 0.01
            or abs(f.monto_total - (select nvl(sum(d.monto_total_linea), 0) from facturas_det d
                                     where d.id_factura = f.id_factura)) > 0.01);
    if v_n > 0 then
        falla('R5: ' || v_n || ' factura(s) con la cabecera distinta de la suma de su detalle');
    end if;

    -- R6 / R7: comprobante de retencion obligatorio (en una factura nueva).
    select min(f.id_factura) into v_fac
      from facturas f join clientes c on c.id_cliente = f.id_cliente
     where f.id_empresa = 1 and f.tipo_documento = 'FAC'
       and nvl(c.es_agente_retencion, 'N') = 'S';

    if v_fac is null then
        falla('R6: no hay ninguna factura de un cliente que retenga IVA para probar');
    else
        select f.id_cliente, greatest(nvl(f.porcentaje_retencion, 0), 75) into v_cli, v_pct
          from facturas f where f.id_factura = v_fac;

        begin
            declare
                v_id number;
            begin
                pkg_facturacion.prc_guardar_factura(
                    p_id_factura => v_id, p_id_empresa => 1, p_folio_factura => 'T-RET-1',
                    p_id_cliente => v_cli, p_id_presupuesto => null,
                    p_rfc_emisor => null, p_rfc_receptor => null, p_uuid_fiscal => null,
                    p_uso_cfdi => null, p_forma_pago => null, p_metodo_pago => null,
                    p_condicion_pago => null, p_fecha_emision => '01/11/2026',
                    p_fecha_vencimiento => null, p_estado => 'PENDIENTE',
                    p_subtotal => 0, p_monto_impuesto => 0, p_monto_total => 0,
                    p_observaciones => 'verificacion', p_cod_moneda => 'VES',
                    p_tipo_cambio => 1, p_usuario => 'VERIF',
                    p_tipo_documento => 'FAC', p_porcentaje_retencion => v_pct,
                    p_nro_comprobante_retencion => null);
            end;
            falla('R6: se pudo guardar una factura con retencion y sin comprobante');
        exception
            when others then
                if instr(sqlerrm, '20064') = 0 then
                    falla('R6: el error no es el -20064: ' || substrb(sqlerrm, 1, 120));
                end if;
        end;

        begin
            declare
                v_id number;
            begin
                pkg_facturacion.prc_guardar_factura(
                    p_id_factura => v_id, p_id_empresa => 1, p_folio_factura => 'T-RET-2',
                    p_id_cliente => v_cli, p_id_presupuesto => null,
                    p_rfc_emisor => null, p_rfc_receptor => null, p_uuid_fiscal => null,
                    p_uso_cfdi => null, p_forma_pago => null, p_metodo_pago => null,
                    p_condicion_pago => null, p_fecha_emision => '01/11/2026',
                    p_fecha_vencimiento => null, p_estado => 'PENDIENTE',
                    p_subtotal => 0, p_monto_impuesto => 0, p_monto_total => 0,
                    p_observaciones => 'verificacion', p_cod_moneda => 'VES',
                    p_tipo_cambio => 1, p_usuario => 'VERIF',
                    p_tipo_documento => 'FAC', p_porcentaje_retencion => v_pct,
                    p_nro_comprobante_retencion => '20261100000001');
            end;
        exception
            when others then
                falla('R7: con comprobante de 14 digitos no dejo guardar: ' || substrb(sqlerrm, 1, 120));
        end;
    end if;

    rollback to sp_round;

    -- R8: el boton de la pagina 9 es Anular, con icono y confirmacion.
    select count(*) into v_n
      from apex_260100.apex_application_page_buttons
     where application_id = 100 and page_id = 9 and button_name = 'BTN_CANCELAR'
       and label = 'Anular'
       and icon_css_classes = 'fa-ban'
       and confirm_message is not null
       and instr(upper(condition_expression1), 'FN_TIENE_ROL') > 0
       and instr(upper(condition_expression1), 'P9_MODO_VER') > 0;
    if v_n = 0 then
        falla('R8: el boton de la pagina 9 no es Anular con fa-ban, confirmacion y sus guardas');
    end if;

    -- R9: cero invalidos.
    select count(*) into v_n
      from all_objects
     where owner = 'WKSP_SYPEXWS' and status <> 'VALID'
       and object_type in ('FUNCTION', 'PROCEDURE', 'PACKAGE', 'PACKAGE BODY', 'TRIGGER', 'VIEW');
    if v_n > 0 then
        falla('R9: hay ' || v_n || ' objeto(s) invalido(s)');
    end if;

    for i in 1 .. v_fallas.count loop
        insert into tmp_round_fallas values (v_fallas(i));
    end loop;
exception
    when others then
        rollback to sp_round;
        v_msg := substrb('R?: el caso revento: ' || sqlerrm, 1, 300);
        insert into tmp_round_fallas values (v_msg);
end;
/

declare
    v_fallas number;
    v_lista  varchar2(3000);
begin
    select count(*) into v_fallas from tmp_round_fallas;
    select substrb(listagg(caso, ' | ' on overflow truncate) within group (order by caso), 1, 3000)
      into v_lista from tmp_round_fallas;
    execute immediate 'drop table tmp_round_fallas purge';
    raise_application_error(-20100, substrb('RESULTADO: FALLAS=' || v_fallas || ' | ' || v_lista, 1, 3000));
end;
/
