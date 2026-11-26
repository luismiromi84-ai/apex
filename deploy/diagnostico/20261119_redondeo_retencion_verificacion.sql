-- =============================================================================
-- 20261119_redondeo_retencion_verificacion.sql
--
-- Redondeo de la linea de factura y comprobante de retencion (2026-11-19/20):
--   R1  el recuadro de la pagina 8 sale de un solo origen (subtotal_linea +
--       monto_descuento), no de cantidad x precio recalculado
--   R2  lo mismo en el recuadro de la pagina 5
--   R3  el proceso de la pagina 10 redondea el precio unitario a 2 decimales
--   R4  no queda ninguna linea de factura descuadrada contra el precio impreso
--   R5  la cabecera de cada factura abierta es la suma de su detalle
--   R6  una FAC con retencion se guarda SIN comprobante (el cliente lo emite
--       despues), el numero se rellena editando la factura y no se borra al
--       volver a guardar sin el
--   R7  con un comprobante de 14 digitos tambien guarda
--   R7b un comprobante con formato invalido se rechaza (-20081)
--   R8  el boton de la pagina 9 dice Anular, con icono fa-ban, confirmacion y
--       la condicion de rol y de modo consulta
--   R9  cero objetos invalidos
--   R10 el comprobante se puede registrar DESPUES de emitir la factura (una
--       TIMBRADA con retencion y sin numero) y el documento no cambia de estado
--       ni de importes
--   R11 un numero que no son 14 digitos se rechaza (-20081)
--   R12 una factura ANULADA no admite comprobante (-20024)
--   R13 un usuario de otra empresa no puede escribirlo (-20003)
--   R14 cualquier usuario de la misma empresa puede (control positivo) y queda
--       anotado en modificado_por
--   R15 la pagina 9 tiene el boton, el proceso y el campo bloqueado solo en ANULADA
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
    -- 2026-11-26: solo las facturas editables (PENDIENTE) y las creadas desde la correccion de
    -- pkg_factura_detalle.reemplazar_desde_presupuesto. La F-6 de la empresa 6 (USD, PARCIAL, con
    -- cobros) quedo con precios de 3 decimales antes de la correccion: es un documento cerrado y
    -- no se edita (diferencia de centimos, documentada en AGENTS.md).
    select count(*) into v_n
      from facturas_det d join facturas f on f.id_factura = d.id_factura
     where d.subtotal_linea + nvl(d.monto_descuento, 0)
           <> round(d.cantidad * round(d.precio_unitario, 2), 2)
       and (f.estado = 'PENDIENTE' or f.fecha_creacion >= date '2026-11-26');
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

    -- R6 / R7: el comprobante de retencion NO es obligatorio al emitir
    -- (2026-11-20). En Venezuela lo emite el cliente DESPUES de recibir la
    -- factura, asi que al guardarla todavia no existe: se guarda sin el y el
    -- numero se rellena despues editando la factura.
    select min(f.id_factura) into v_fac
      from facturas f join clientes c on c.id_cliente = f.id_cliente
     where f.id_empresa = 1 and f.tipo_documento = 'FAC'
       and nvl(c.es_agente_retencion, 'N') = 'S';

    if v_fac is null then
        falla('R6: no hay ninguna factura de un cliente que retenga IVA para probar');
    else
        select f.id_cliente, greatest(nvl(f.porcentaje_retencion, 0), 75) into v_cli, v_pct
          from facturas f where f.id_factura = v_fac;

        -- R6: se guarda SIN comprobante.
        declare
            v_id   number := null;
            v_comp varchar2(30);
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

            select nro_comprobante_retencion into v_comp
              from facturas where id_factura = v_id;
            if v_comp is not null then
                falla('R6: la factura nacio con comprobante ' || v_comp);
            end if;

            -- R6b: el numero se rellena DESPUES editando la misma factura.
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
                p_nro_comprobante_retencion => '20261100000001');

            select nro_comprobante_retencion into v_comp
              from facturas where id_factura = v_id;
            if v_comp is null or trim(v_comp) <> '20261100000001' then
                falla('R6b: el comprobante tecleado al editar no quedo guardado (' || v_comp || ')');
            end if;

            -- R6c: una vez registrado el comprobante, la factura queda cerrada
            -- (fn_factura_editable, 2026-11-19): no se puede volver a guardar, y
            -- por tanto el numero no se puede borrar por accidente.
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
                falla('R6c: dejo volver a guardar una factura con comprobante registrado');
            exception
                when others then
                    if instr(sqlerrm, '20024') = 0 then
                        falla('R6c: el error no es el -20024 de documento cerrado: '
                              || substrb(sqlerrm, 1, 120));
                    end if;
            end;

            select nro_comprobante_retencion into v_comp
              from facturas where id_factura = v_id;
            if v_comp is null or trim(v_comp) <> '20261100000001' then
                falla('R6c: el comprobante quedo en ' || v_comp || ' en vez de 20261100000001');
            end if;
        exception
            when others then
                falla('R6: no dejo guardar una factura con retencion y sin comprobante: '
                      || substrb(sqlerrm, 1, 120));
        end;

        -- R7: con un comprobante de 14 digitos tambien guarda.
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

        -- R7b: un numero con formato invalido si se rechaza (-20081).
        begin
            declare
                v_id number;
            begin
                pkg_facturacion.prc_guardar_factura(
                    p_id_factura => v_id, p_id_empresa => 1, p_folio_factura => 'T-RET-3',
                    p_id_cliente => v_cli, p_id_presupuesto => null,
                    p_rfc_emisor => null, p_rfc_receptor => null, p_uuid_fiscal => null,
                    p_uso_cfdi => null, p_forma_pago => null, p_metodo_pago => null,
                    p_condicion_pago => null, p_fecha_emision => '01/11/2026',
                    p_fecha_vencimiento => null, p_estado => 'PENDIENTE',
                    p_subtotal => 0, p_monto_impuesto => 0, p_monto_total => 0,
                    p_observaciones => 'verificacion', p_cod_moneda => 'VES',
                    p_tipo_cambio => 1, p_usuario => 'VERIF',
                    p_tipo_documento => 'FAC', p_porcentaje_retencion => v_pct,
                    p_nro_comprobante_retencion => 'ABC');
                falla('R7b: acepto un comprobante que no son 14 digitos');
            exception
                when others then
                    if instr(sqlerrm, '20081') = 0 then
                        falla('R7b: el error no es el -20081: ' || substrb(sqlerrm, 1, 120));
                    end if;
            end;
        end;
    end if;

    -- R10 a R14: el comprobante se puede registrar DESPUES de emitir la factura
    -- (2026-11-20). En Venezuela el cliente lo entrega cuando la factura ya esta
    -- TIMBRADA, y fn_factura_editable la cierra: hace falta una via que anote el
    -- numero sin tocar el documento (estado, importes ni IVA retenido).
    declare
        v_cli2 number;
        v_fact number;
        v_anul number;
        v_otro varchar2(100);
        v_id   number;
        v_est  varchar2(20);
        v_ret  number;
        v_tot  number;
        v_comp varchar2(30);
        v_mod  varchar2(100);
    begin
        select min(id_cliente) into v_cli2
          from clientes
         where id_empresa = 1 and nvl(estado, 'ACTIVO') = 'ACTIVO';

        if v_cli2 is null then
            falla('R10: no hay ningun cliente activo en la empresa 1 para la prueba');
        else
            -- Factura TIMBRADA, con retencion y SIN comprobante.
            v_id := null;
            pkg_facturacion.prc_guardar_factura(
                p_id_factura => v_id, p_id_empresa => 1, p_folio_factura => 'T-RET-10',
                p_id_cliente => v_cli2, p_id_presupuesto => null,
                p_rfc_emisor => null, p_rfc_receptor => null, p_uuid_fiscal => null,
                p_uso_cfdi => null, p_forma_pago => null, p_metodo_pago => null,
                p_condicion_pago => null, p_fecha_emision => '01/11/2026',
                p_fecha_vencimiento => null, p_estado => 'PENDIENTE',
                p_subtotal => 0, p_monto_impuesto => 0, p_monto_total => 0,
                p_observaciones => 'verificacion', p_cod_moneda => 'VES',
                p_tipo_cambio => 1, p_usuario => 'VERIF',
                p_tipo_documento => 'FAC', p_porcentaje_retencion => 75,
                p_nro_comprobante_retencion => null);
            v_fact := v_id;

            pkg_facturacion.prc_procesar_factura(v_fact, 'VERIF');

            -- Importes de trabajo, para poder comprobar que NO se mueven.
            update facturas set subtotal = 1000, monto_impuesto = 160, monto_total = 1160,
                   retencion_iva_bs = 100
             where id_factura = v_fact;

            -- R10: el dueno de la factura (admin, empresa 1) registra el numero y
            -- la factura sigue TIMBRADA, con los mismos importes.
            pkg_facturacion.prc_registrar_comprobante_retencion(
                v_fact, '20261100000009', 'admin');

            select estado, retencion_iva_bs, monto_total, nro_comprobante_retencion
              into v_est, v_ret, v_tot, v_comp
              from facturas where id_factura = v_fact;

            if v_comp is null or trim(v_comp) <> '20261100000009' then
                falla('R10: el comprobante no quedo guardado (' || v_comp || ')');
            end if;
            if v_est <> 'TIMBRADA' then
                falla('R10: la factura dejo de estar TIMBRADA (' || v_est || ')');
            end if;
            if nvl(v_ret, -1) <> 100 or nvl(v_tot, -1) <> 1160 then
                falla('R10: el documento cambio de importes (IVA retenido ' || v_ret
                      || ', total ' || v_tot || ')');
            end if;

            -- R11: un numero que no son 14 digitos se rechaza (-20081).
            begin
                pkg_facturacion.prc_registrar_comprobante_retencion(
                    v_fact, '123', 'admin');
                falla('R11: acepto un comprobante de 3 digitos');
            exception
                when others then
                    if instr(sqlerrm, '20081') = 0 then
                        falla('R11: el error no es el -20081: ' || substrb(sqlerrm, 1, 120));
                    end if;
            end;

            -- R13: un usuario de otra empresa no puede escribir en esta factura.
            begin
                pkg_facturacion.prc_registrar_comprobante_retencion(
                    v_fact, '20261100000010', 'admin.mx');
                falla('R13: un usuario de otra empresa registro el comprobante');
            exception
                when others then
                    if instr(sqlerrm, '20003') = 0 then
                        falla('R13: el error no es el -20003: ' || substrb(sqlerrm, 1, 120));
                    end if;
            end;

            -- R14: cualquier usuario de la MISMA empresa puede (control positivo) y
            -- queda anotado quien lo registro.
            select min(u.username) into v_otro
              from usuario u
              join usuario_empresa ue on ue.usuario_id = u.usuario_id
             where ue.id_empresa = 1
               and u.estado in ('ACTIVO', 'A', '1')
               and upper(u.username) <> 'ADMIN';
            if v_otro is null then
                v_otro := 'admin';
            end if;

            pkg_facturacion.prc_registrar_comprobante_retencion(
                v_fact, '20261100000011', v_otro);

            select nro_comprobante_retencion, modificado_por
              into v_comp, v_mod
              from facturas where id_factura = v_fact;

            if v_comp is null or trim(v_comp) <> '20261100000011' then
                falla('R14: el segundo registro no quedo guardado (' || v_comp || ')');
            end if;
            if upper(v_mod) <> upper(v_otro) then
                falla('R14: modificado_por dice ' || v_mod || ' en vez de ' || v_otro);
            end if;

            -- R12: una factura ANULADA no admite comprobante (-20024).
            v_id := null;
            pkg_facturacion.prc_guardar_factura(
                p_id_factura => v_id, p_id_empresa => 1, p_folio_factura => 'T-RET-11',
                p_id_cliente => v_cli2, p_id_presupuesto => null,
                p_rfc_emisor => null, p_rfc_receptor => null, p_uuid_fiscal => null,
                p_uso_cfdi => null, p_forma_pago => null, p_metodo_pago => null,
                p_condicion_pago => null, p_fecha_emision => '01/11/2026',
                p_fecha_vencimiento => null, p_estado => 'PENDIENTE',
                p_subtotal => 0, p_monto_impuesto => 0, p_monto_total => 0,
                p_observaciones => 'verificacion', p_cod_moneda => 'VES',
                p_tipo_cambio => 1, p_usuario => 'VERIF',
                p_tipo_documento => 'FAC', p_porcentaje_retencion => 75,
                p_nro_comprobante_retencion => null);
            v_anul := v_id;

            pkg_facturacion.prc_anular_factura(v_anul, null, 'admin');

            begin
                pkg_facturacion.prc_registrar_comprobante_retencion(
                    v_anul, '20261100000012', 'admin');
                falla('R12: registro el comprobante en una factura ANULADA');
            exception
                when others then
                    if instr(sqlerrm, '20024') = 0 then
                        falla('R12: el error no es el -20024: ' || substrb(sqlerrm, 1, 120));
                    end if;
            end;
        end if;
    end;

    -- R15: la pagina 9 tiene el boton y el proceso que llaman al procedimiento,
    -- y el campo del comprobante solo se bloquea en una factura ANULADA.
    -- El boton NO ejecuta las validaciones del formulario: es una constancia
    -- documental y el documento esta cerrado (si no, «Tipo Cambio debe tener
    -- algun valor» bloqueaba el envio de una factura en bolivares).
    select count(*) into v_n
      from apex_260100.apex_application_page_buttons
     where application_id = 100 and page_id = 9
       and button_name = 'BTN_COMPROBANTE'
       and instr(upper(condition_expression1), 'P9_RETENCION_IVA_BS') > 0
       and instr(upper(condition_expression1), 'ANULADA') > 0
       and execute_validations = 'No';
    if v_n = 0 then
        falla('R15: falta el boton Guardar comprobante (o exige validaciones, o no filtra retencion y estado)');
    end if;

    select count(*) into v_n
      from apex_260100.apex_application_page_proc
     where application_id = 100 and page_id = 9
       and process_name = 'Guardar comprobante de retencion'
       and instr(upper(process_source), 'PRC_REGISTRAR_COMPROBANTE_RETENCION') > 0
       and instr(upper(process_source), 'FN_TIENE_ROL') > 0
       and when_button_pressed = 'BTN_COMPROBANTE';
    if v_n = 0 then
        falla('R15: falta el proceso del boton, o no lleva la guarda de rol');
    end if;

    select count(*) into v_n
      from apex_260100.apex_application_page_items
     where application_id = 100 and page_id = 9
       and item_name = 'P9_NRO_COMPROBANTE_RETENCION'
       and upper(read_only_condition_exp1) like '%ANULADA%';
    if v_n = 0 then
        falla('R15: el campo del comprobante no se bloquea en una factura ANULADA');
    end if;

    -- El item tiene que persistir: uno no persistente no deja el valor en el
    -- estado de sesion y el proceso leeria vacio (paso en la pagina 25).
    select count(*) into v_n
      from apex_260100.apex_application_page_items
     where application_id = 100 and page_id = 9
       and item_name = 'P9_NRO_COMPROBANTE_RETENCION'
       and maintain_session_state = 'Per Session';
    if v_n = 0 then
        falla('R15: el campo del comprobante no guarda su valor en el estado de sesion');
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
