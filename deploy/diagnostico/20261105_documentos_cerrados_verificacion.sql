-- =============================================================================
-- 20261105_documentos_cerrados_verificacion.sql
--
-- Verifica que un documento cerrado no se pueda editar.
--
-- El defecto: con mx.demo se podia editar la factura PAGADA F-3 (1203) de la
-- empresa 2. La cabecera no comprobaba nada y el detalle solo bloqueaba el
-- estado FACTURADO, que no es el que se usa.
--
-- Regla: PAGADA y ANULADA son estados finales. Para corregir la factura hay
--        que anularla y emitir otra.
--
-- Casos:
--   C1  fn_factura_editable(null) = true        (es un alta)
--   C2  fn_factura_editable(PAGADA) = false
--   C3  fn_factura_editable(ANULADA) = false
--   C4  fn_factura_editable(PENDIENTE) = true
--   C5  Editar la cabecera de una PAGADA falla con -20024
--   C6  Editar la cabecera de una ANULADA falla con -20024
--   C7  Editar la cabecera de una PENDIENTE sigue funcionando
--   C8  Agregar/editar linea de una PAGADA falla con -20002
--   C9  Eliminar linea de una PAGADA falla con -20002
--   C10 Reemplazar el detalle de una PAGADA falla con -20002
--   C11..C13 Los datos quedan intactos
--
-- Todo va en una transaccion que se revierte: no deja rastro.
--
-- Ejecutar con:
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261105_documentos_cerrados_verificacion.sql
-- El resumen sale en el mensaje del raise ('RESULTADO: FALLAS=0 ...'): codigo de
-- salida 1 con FALLAS=0 significa EXITO, igual que en las demas verificaciones.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;
/

declare
    v_fallas    number := 0;
    v_casos     number := 0;

    v_pagada    facturas.id_factura%type;
    v_anulada   facturas.id_factura%type;
    v_pendiente facturas.id_factura%type;

    v_facturas_antes number;
    v_lineas_antes   number;
    v_total_antes    number;

    v_facturas_ahora number;
    v_lineas_ahora   number;
    v_total_ahora    number;

    procedimiento_error constant varchar2(10) := 'FALLA ';

    procedure resultado (p_nombre varchar2, p_condicion boolean) is
    begin
        v_casos := v_casos + 1;
        if not p_condicion then
            v_fallas := v_fallas + 1;
            dbms_output.put_line(procedimiento_error || p_nombre);
        end if;
    end;

    -- Edita la cabecera con los mismos valores que ya tiene: lo unico que
    -- cambia es la observacion, y la guarda debe rechazarlo.
    procedure editar_cabecera (p_id number) is
        r facturas%rowtype;
    begin
        select * into r from facturas where id_factura = p_id;

        pkg_facturacion.prc_actualizar(
            p_id_factura        => r.id_factura,
            p_id_empresa        => r.id_empresa,
            p_folio_factura     => r.folio_factura,
            p_id_cliente        => r.id_cliente,
            p_id_presupuesto    => r.id_presupuesto,
            p_rfc_emisor        => r.rfc_emisor,
            p_rfc_receptor      => r.rfc_receptor,
            p_uuid_fiscal       => r.uuid_fiscal,
            p_uso_cfdi          => r.uso_cfdi,
            p_forma_pago        => r.forma_pago,
            p_metodo_pago       => r.metodo_pago,
            p_condicion_pago    => to_char(r.condicion_pago),
            p_fecha_emision     => to_char(r.fecha_emision, 'DD/MM/YYYY'),
            p_fecha_vencimiento => to_char(r.fecha_vencimiento, 'DD/MM/YYYY'),
            p_estado            => r.estado,
            p_subtotal          => r.subtotal,
            p_monto_impuesto    => r.monto_impuesto,
            p_monto_total       => r.monto_total,
            p_observaciones     => r.observaciones || ' [prueba]',
            p_cod_moneda        => r.cod_moneda,
            p_tipo_cambio       => r.tipo_cambio);
    end;

begin
    select count(*), nvl(sum(monto_total), 0)
      into v_facturas_antes, v_total_antes
      from facturas;
    select count(*) into v_lineas_antes from facturas_det;

    select min(id_factura) into v_pagada     from facturas where estado = 'PAGADA';
    select min(id_factura) into v_anulada    from facturas where estado = 'ANULADA';
    select min(id_factura) into v_pendiente  from facturas where estado = 'PENDIENTE';

    -- C1..C4: la funcion de apoyo
    resultado('C1 fn_factura_editable(null)', fn_factura_editable(null));
    resultado('C2 PAGADA no es editable',     not fn_factura_editable(v_pagada));
    resultado('C3 ANULADA no es editable',    not fn_factura_editable(v_anulada));
    resultado('C4 PENDIENTE es editable',     fn_factura_editable(v_pendiente));

    -- C5: cabecera de una PAGADA
    v_casos := v_casos + 1;
    begin
        savepoint c5;
        editar_cabecera(v_pagada);
        rollback to savepoint c5;
        v_fallas := v_fallas + 1;
        dbms_output.put_line(procedimiento_error || 'C5 cabecera PAGADA no dio error');
    exception
        when others then
            if sqlcode <> -20024 then
                v_fallas := v_fallas + 1;
                dbms_output.put_line(procedimiento_error || 'C5 cabecera PAGADA dio '
                                     || sqlcode || ': ' || substr(sqlerrm, 1, 90));
            end if;
    end;

    -- C6: cabecera de una ANULADA
    v_casos := v_casos + 1;
    begin
        savepoint c6;
        editar_cabecera(v_anulada);
        rollback to savepoint c6;
        v_fallas := v_fallas + 1;
        dbms_output.put_line(procedimiento_error || 'C6 cabecera ANULADA no dio error');
    exception
        when others then
            if sqlcode <> -20024 then
                v_fallas := v_fallas + 1;
                dbms_output.put_line(procedimiento_error || 'C6 cabecera ANULADA dio '
                                     || sqlcode || ': ' || substr(sqlerrm, 1, 90));
            end if;
    end;

    -- C7: cabecera de una PENDIENTE (debe seguir funcionando)
    v_casos := v_casos + 1;
    begin
        savepoint c7;
        editar_cabecera(v_pendiente);
        rollback to savepoint c7;
    exception
        when others then
            v_fallas := v_fallas + 1;
            dbms_output.put_line(procedimiento_error || 'C7 cabecera PENDIENTE dio '
                                 || sqlcode || ': ' || substr(sqlerrm, 1, 90));
    end;

    -- C8: agregar/editar linea de una PAGADA
    v_casos := v_casos + 1;
    declare
        v_id_detalle number := null;
    begin
        savepoint c8;
        pkg_factura_detalle.guardar_detalle(
            p_id_factura        => v_pagada,
            p_id_detalle        => v_id_detalle,
            p_id_producto       => null,
            p_id_impuesto       => null,
            p_cantidad          => '1',
            p_precio_unitario   => '1',
            p_porc_descuento    => '0',
            p_monto_descuento   => '0',
            p_porc_impuesto     => '0',
            p_monto_impuesto    => '0',
            p_subtotal_linea    => '1',
            p_monto_total_linea => '1',
            p_codigo_producto   => 'X',
            p_descripcion       => 'prueba',
            p_usuario           => 'prueba');
        rollback to savepoint c8;
        v_fallas := v_fallas + 1;
        dbms_output.put_line(procedimiento_error || 'C8 linea de PAGADA no dio error');
    exception
        when others then
            if sqlcode <> -20002 then
                v_fallas := v_fallas + 1;
                dbms_output.put_line(procedimiento_error || 'C8 linea de PAGADA dio '
                                     || sqlcode || ': ' || substr(sqlerrm, 1, 90));
            end if;
    end;

    -- C9: eliminar linea de una PAGADA
    v_casos := v_casos + 1;
    declare
        v_id_detalle facturas_det.id_detalle%type;
    begin
        select min(id_detalle) into v_id_detalle
          from facturas_det where id_factura = v_pagada;

        savepoint c9;
        pkg_factura_detalle.eliminar_detalle(
            p_id_factura => v_pagada,
            p_id_detalle => v_id_detalle);
        rollback to savepoint c9;
        v_fallas := v_fallas + 1;
        dbms_output.put_line(procedimiento_error || 'C9 borrar linea de PAGADA no dio error');
    exception
        when others then
            if sqlcode <> -20002 then
                v_fallas := v_fallas + 1;
                dbms_output.put_line(procedimiento_error || 'C9 borrar linea de PAGADA dio '
                                     || sqlcode || ': ' || substr(sqlerrm, 1, 90));
            end if;
    end;

    -- C10: reemplazar el detalle de una PAGADA
    v_casos := v_casos + 1;
    begin
        savepoint c10;
        pkg_factura_detalle.reemplazar_desde_presupuesto(
            p_id_factura     => v_pagada,
            p_id_presupuesto => null,
            p_factor         => 1,
            p_tasa_cambio    => 1,
            p_usuario        => 'prueba');
        rollback to savepoint c10;
        v_fallas := v_fallas + 1;
        dbms_output.put_line(procedimiento_error || 'C10 reemplazar de PAGADA no dio error');
    exception
        when others then
            if sqlcode <> -20002 then
                v_fallas := v_fallas + 1;
                dbms_output.put_line(procedimiento_error || 'C10 reemplazar de PAGADA dio '
                                     || sqlcode || ': ' || substr(sqlerrm, 1, 90));
            end if;
    end;

    -- C11..C13: nada cambio
    select count(*), nvl(sum(monto_total), 0)
      into v_facturas_ahora, v_total_ahora
      from facturas;
    select count(*) into v_lineas_ahora from facturas_det;

    resultado('C11 facturas intactas', v_facturas_antes = v_facturas_ahora);
    resultado('C12 lineas intactas',   v_lineas_antes = v_lineas_ahora);
    resultado('C13 totales intactos',  v_total_antes = v_total_ahora);

    -- C14: el boton Guardar de la pagina 9 exige la misma funcion, para que en
    -- un documento cerrado no se pueda ni intentar guardar.
    declare
        v_botones number;
    begin
        select count(*) into v_botones
          from apex_application_page_buttons
         where application_id = 100
           and page_id = 9
           and button_name = 'BTN_GUARDAR'
           and upper(condition_expression1) like '%FN_FACTURA_EDITABLE%';
        resultado('C14 el boton Guardar exige fn_factura_editable', v_botones = 1);
    end;

    rollback;

    if v_fallas > 0 then
        raise_application_error(-20100, 'RESULTADO: FALLAS=' || v_fallas
            || ' de ' || v_casos || ' casos');
    end if;

    raise_application_error(-20100, 'RESULTADO: FALLAS=0 de ' || v_casos || ' casos');
end;
/
