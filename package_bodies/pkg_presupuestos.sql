create or replace PACKAGE BODY pkg_presupuestos AS

    ----------------------------------------------------------------------------
    -- PROCEDIMIENTO: Guardar o Actualizar Presupuesto
    ----------------------------------------------------------------------------
    PROCEDURE prc_guardar_presupuesto (
        p_id_presupuesto    IN OUT NUMBER,
        p_id_empresa        IN     NUMBER,
        p_id_cliente        IN     NUMBER,
        p_folio             IN     VARCHAR2,
        p_cod_moneda        IN     VARCHAR2,
        p_fecha_vencimiento IN     DATE,
        p_fecha_emision     IN     DATE,
        p_tipo_cambio       IN     NUMBER,
        p_estado            IN     VARCHAR2,
        p_observaciones     IN     VARCHAR2,
        p_usuario           IN     VARCHAR2
    ) IS
    BEGIN
    -- Seguridad: la empresa debe pertenecer al usuario de la sesion APEX
    if apex_application.g_user is not null
       and not fn_usuario_empresa_valida(apex_application.g_user, p_id_empresa) then
        raise_application_error(-20003, 'No tiene acceso a la empresa indicada.');
    end if;

        IF p_id_presupuesto IS NOT NULL THEN
            -- Actualización (Incluye MODIFICADO_POR)
            UPDATE presupuestos
               SET id_empresa        = p_id_empresa,
                   id_cliente        = p_id_cliente,
                   folio             = p_folio,
                   cod_moneda        = p_cod_moneda,
                   fecha_vencimiento = p_fecha_vencimiento,
                   fecha_emision     = p_fecha_emision,
                   tipo_cambio       = p_tipo_cambio,
                   estado            = p_estado,
                   observaciones     = p_observaciones,
                   modificado_por    = p_usuario
             WHERE id_presupuesto    = p_id_presupuesto;
        ELSE
            -- Inserción (Incluye CREADO_POR y opcionalmente MODIFICADO_POR)
            INSERT INTO presupuestos (
                id_empresa,
                id_cliente,
                folio,
                cod_moneda,
                fecha_vencimiento,
                fecha_emision,
                tipo_cambio,
                estado,
                observaciones,
                creado_por,
                modificado_por
            ) VALUES (
                p_id_empresa,
                p_id_cliente,
                p_folio,
                p_cod_moneda,
                p_fecha_vencimiento,
                p_fecha_emision,
                p_tipo_cambio,
                p_estado,
                p_observaciones,
                p_usuario,
                p_usuario
            ) RETURNING id_presupuesto INTO p_id_presupuesto;
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            RAISE_APPLICATION_ERROR(-20001, 'Error al procesar el presupuesto: ' || SQLERRM);
    END;
    ---------------------------------------------------------------------
    -- PROCEDIMIENTO: Procesar Presupuesto (Desde la vista de detalles / botón APEX)
    ----------------------------------------------------------------------------
    PROCEDURE prc_procesar_presupuesto (
        p_id_presupuesto    IN     NUMBER,
        p_usuario           IN     VARCHAR2,
        p_nuevo_estado      OUT    VARCHAR2,
        p_nuevas_obs        OUT    VARCHAR2
    ) IS
        v_estado_actual     VARCHAR2(50);
    BEGIN
        -- Consultamos el estado actual para definir la transición de estado lógica
        SELECT estado 
          INTO v_estado_actual 
          FROM presupuestos 
         WHERE id_presupuesto = p_id_presupuesto;

        -- Definimos la regla de negocio para el procesamiento:
        -- Si está PENDIENTE, al procesarlo pasa a ENVIADO (puedes ajustarlo según tu flujo: APROBADO, etc.)
        IF v_estado_actual IN ('PENDIENTE', 'APROBADO') THEN
            p_nuevo_estado := 'ENVIADO';
        ELSE
            -- Si ya se encuentra en otro estado, puedes mantenerlo o avanzar según convenga
            p_nuevo_estado := v_estado_actual; 
        END IF;

        -- Actualizamos el estado, la auditoría de modificación y agregamos una nota opcional en observaciones
        UPDATE presupuestos
           SET estado         = p_nuevo_estado,
               modificado_por = p_usuario,
               observaciones  = observaciones || ' [Procesado por ' || p_usuario || ' el ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI') || ']'
         WHERE id_presupuesto = p_id_presupuesto;

        -- Recuperamos los valores actualizados para la interfaz de Oracle APEX
        SELECT estado, observaciones
          INTO p_nuevo_estado, p_nuevas_obs
          FROM presupuestos
         WHERE id_presupuesto = p_id_presupuesto;

    EXCEPTION
        WHEN OTHERS THEN
            RAISE_APPLICATION_ERROR(-20003, 'Error al procesar el presupuesto: ' || SQLERRM);
    END prc_procesar_presupuesto;

    ----------------------------------------------------------------------------
    -- PROCEDIMIENTO: Cancelar Presupuesto
    ----------------------------------------------------------------------------
    PROCEDURE prc_cancelar_presupuesto (
        p_id_presupuesto    IN     NUMBER,
        p_usuario           IN     VARCHAR2,
        p_nuevo_estado      OUT    VARCHAR2,
        p_nuevas_obs        OUT    VARCHAR2
    ) IS
    BEGIN
        -- Actualizamos el estado a CANCELADO, registramos quién modificó y concatenamos la observación
        UPDATE presupuestos
           SET estado         = 'CANCELADO',
               modificado_por = p_usuario,
               observaciones  = observaciones || ' [Cancelado por ' || p_usuario || ' el ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI') || ']'
         WHERE id_presupuesto = p_id_presupuesto;

        -- Recuperamos los valores actualizados para devolverlos a APEX
        SELECT estado, observaciones
          INTO p_nuevo_estado, p_nuevas_obs
          FROM presupuestos
         WHERE id_presupuesto = p_id_presupuesto;

    EXCEPTION
        WHEN OTHERS THEN
            RAISE_APPLICATION_ERROR(-20002, 'Error al cancelar el presupuesto: ' || SQLERRM);
    END prc_cancelar_presupuesto;

END pkg_presupuestos;
/