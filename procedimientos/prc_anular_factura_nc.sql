-- =============================================================================
-- prc_anular_factura_nc.sql
--
-- Anular una factura EMITIENDO la nota de credito por el total (2026-11-19).
--
-- Fiscalmente una factura con folio y numero de control no se borra ni se deja
-- sin efecto cambiando el estado: se emite una nota de credito que la
-- referencia y luego se marca la factura como ANULADA. Este procedimiento hace
-- las dos cosas en una sola transaccion:
--   1. crea la NC (mismo cliente, empresa, moneda y tasa que la factura, con su
--      fecha de emision como referencia de tasa),
--   2. copia todas las lineas de la factura (IVA y alicuota de la original),
--   3. marca la factura ANULADA y libera el presupuesto (prc_anular_factura).
--
-- No aplica a notas de credito ni de debito: esas se anulan directo (no se hace
-- una nota de una nota). Si la factura ya tiene cobros activos, prc_anular_factura
-- lo rechaza (-20091) y no se crea nada, porque se valida antes.
--
-- Errores propios: -20065 factura sin lineas, -20066 documento que no es FAC.
-- =============================================================================

create or replace procedure prc_anular_factura_nc (
    p_id_factura IN  NUMBER,
    p_id_nc      OUT NUMBER,
    p_usuario    IN  VARCHAR2
) is
    v_id       NUMBER := fn_clean_num(TO_CHAR(p_id_factura));
    v_fac      facturas%rowtype;
    v_lineas   NUMBER;
    v_cobros   NUMBER;
    v_id_nc    NUMBER;
    v_tipo     VARCHAR2(10);
begin
    p_id_nc := NULL;

    SELECT * INTO v_fac FROM facturas WHERE id_factura = v_id;

    v_tipo := NVL(UPPER(TRIM(v_fac.tipo_documento)), 'FAC');

    IF v_tipo <> 'FAC' THEN
        raise_application_error(-20066,
            'Solo se anula con nota de credito una factura. Una nota se anula directamente.');
    END IF;

    IF UPPER(TRIM(NVL(v_fac.estado, '#'))) = 'ANULADA' THEN
        raise_application_error(-20025,
            'La factura ' || v_fac.folio_factura || ' ya esta ANULADA.');
    END IF;

    SELECT COUNT(*) INTO v_lineas FROM facturas_det WHERE id_factura = v_id;
    IF v_lineas = 0 THEN
        raise_application_error(-20065,
            'La factura ' || v_fac.folio_factura
            || ' no tiene lineas: no hay nada que acreditar.');
    END IF;

    -- Se comprueba antes de crear nada: con cobros vivos no se anula.
    SELECT COUNT(*) INTO v_cobros
      FROM recibos WHERE id_factura = v_id AND estado = 'ACTIVO';
    IF v_cobros > 0 THEN
        raise_application_error(-20091,
            'La factura ' || v_fac.folio_factura || ' tiene ' || v_cobros
            || CASE WHEN v_cobros = 1 THEN ' cobro registrado' ELSE ' cobros registrados' END
            || ': anula primero los cobros y despues la factura.');
    END IF;

    -- 1) cabecera de la nota: lo que no depende de las lineas se copia tal cual.
    v_id_nc := NULL;
    pkg_facturacion.prc_guardar_factura(
        p_id_factura         => v_id_nc,
        p_id_empresa         => v_fac.id_empresa,
        p_folio_factura      => NULL,
        p_id_cliente         => v_fac.id_cliente,
        p_id_presupuesto     => NULL,
        p_rfc_emisor         => v_fac.rfc_emisor,
        p_rfc_receptor       => v_fac.rfc_receptor,
        p_uuid_fiscal        => NULL,
        p_uso_cfdi           => v_fac.uso_cfdi,
        p_forma_pago         => v_fac.forma_pago,
        p_metodo_pago        => v_fac.metodo_pago,
        p_condicion_pago     => TO_CHAR(v_fac.condicion_pago),
        p_fecha_emision      => TO_CHAR(SYSDATE, 'DD/MM/YYYY'),
        p_fecha_vencimiento  => NULL,
        p_estado             => 'PENDIENTE',
        p_subtotal           => 0,
        p_monto_impuesto     => 0,
        p_monto_total        => 0,
        p_observaciones      => 'Nota de credito de la factura ' || v_fac.folio_factura
                                || CASE WHEN v_fac.nro_control IS NOT NULL
                                        THEN ', N. de Control ' || v_fac.nro_control ELSE '' END
                                || ', del ' || TO_CHAR(v_fac.fecha_emision, 'DD/MM/YYYY')
                                || '. Anula la factura en su totalidad.',
        p_cod_moneda         => v_fac.cod_moneda,
        p_tipo_cambio        => v_fac.tipo_cambio,
        p_usuario            => NVL(p_usuario, v('APP_USER')),
        p_tipo_documento     => 'NC',
        p_nro_control        => NULL,
        p_id_factura_origen  => v_id,
        p_fecha_referencia   => v_fac.fecha_emision,
        p_porcentaje_retencion => 0
    );
    p_id_nc := v_id_nc;

    -- 2) las lineas, con el IVA y la alicuota de la factura original.
    pkg_factura_detalle.copiar_desde_factura(
        p_id_factura        => v_id_nc,
        p_id_factura_origen => v_id,
        p_usuario           => NVL(p_usuario, v('APP_USER'))
    );

    -- 3) la nota queda emitida: la anulacion surte efecto cuando la NC existe
    -- como documento timbrado (si quedara en borrador, el libro dejaria de
    -- mostrar la venta sin la nota que la respalda).
    pkg_facturacion.prc_procesar_factura(
        p_id_factura => v_id_nc,
        p_usuario    => NVL(p_usuario, v('APP_USER'))
    );

    -- 4) la factura queda ANULADA y se libera el presupuesto.
    pkg_facturacion.prc_anular_factura(
        p_id_factura     => v_id,
        p_id_presupuesto => v_fac.id_presupuesto,
        p_usuario        => NVL(p_usuario, v('APP_USER'))
    );
end;
/
