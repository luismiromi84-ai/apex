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
        v_folio  presupuestos.folio%type;
        v_estado presupuestos.estado%type;
        v_tasa   number;
    BEGIN
    -- Seguridad: la empresa debe pertenecer al usuario de la sesion APEX
    if apex_application.g_user is not null
       and not fn_usuario_empresa_valida(apex_application.g_user, p_id_empresa) then
        raise_application_error(-20003, 'No tiene acceso a la empresa indicada.');
    end if;

        -- La tasa es obligatoria y se guarda en bolivares por unidad de la moneda
        -- del documento. Sin ella los montos en bolivares salen mal.
        v_tasa := fn_validar_tasa_documento(p_cod_moneda, p_fecha_emision, p_tipo_cambio);

        -- Un documento cerrado no se edita: CANCELADO y FACTURADO son finales.
        IF p_id_presupuesto IS NOT NULL
           AND NOT fn_presupuesto_editable(p_id_presupuesto) THEN
            SELECT folio, UPPER(estado)
              INTO v_folio, v_estado
              FROM presupuestos
             WHERE id_presupuesto = p_id_presupuesto;

            raise_application_error(-20024,
                'El presupuesto ' || v_folio || ' está ' || v_estado
                || ': no se puede modificar un documento cerrado. '
                || 'Crea uno nuevo.');
        END IF;

        IF p_id_presupuesto IS NOT NULL THEN
            -- Actualización (Incluye MODIFICADO_POR)
            UPDATE presupuestos SET
                   id_empresa        = p_id_empresa,
                   id_cliente        = p_id_cliente,
                   folio             = p_folio,
                   cod_moneda        = p_cod_moneda,
                   fecha_vencimiento = p_fecha_vencimiento,
                   fecha_emision     = p_fecha_emision,
                   tipo_cambio       = v_tasa,
                   estado            = p_estado,
                   observaciones     = p_observaciones,
                   modificado_por    = p_usuario
             WHERE id_presupuesto    = p_id_presupuesto;
        ELSE
            -- Insercion (Incluye CREADO_POR y opcionalmente MODIFICADO_POR)
            -- El folio lo asigna el contador de la empresa: el que traiga la
            -- pagina es solo una vista previa y puede haber cambiado si otro
            -- usuario guardo antes.
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
                fn_asignar_folio(p_id_empresa, 'PRESUPUESTO'),
                p_cod_moneda,
                p_fecha_vencimiento,
                p_fecha_emision,
                v_tasa,
                p_estado,
                p_observaciones,
                p_usuario,
                p_usuario
            ) RETURNING id_presupuesto INTO p_id_presupuesto;
        END IF;

    EXCEPTION
        WHEN DUP_VAL_ON_INDEX THEN
            RAISE_APPLICATION_ERROR(-20021,
                'El folio ' || p_folio || ' ya existe para esta empresa. Elige otro numero.');
        WHEN OTHERS THEN
            -- Los errores de negocio (-20xxx) se propagan tal cual, con su mensaje.
            IF SQLCODE BETWEEN -20999 AND -20000 THEN
                RAISE;
            END IF;
            prc_log_error(
                p_usuario   => nvl(v('APP_USER'), 'SISTEMA'),
                p_codigo    => 'ORA-' || lpad(to_char(abs(SQLCODE)), 5, '0'),
                p_mensaje   => 'No se pudo guardar el presupuesto',
                p_detalle   => SQLERRM,
                p_sentencia => dbms_utility.format_error_backtrace);
            RAISE_APPLICATION_ERROR(-20001,
                'No se pudo guardar el presupuesto. Avisa al administrador.');
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
        v_folio             presupuestos.folio%type;
    BEGIN
        -- Consultamos el estado actual para definir la transición de estado lógica
        SELECT folio, estado 
          INTO v_folio, v_estado_actual 
          FROM presupuestos 
         WHERE id_presupuesto = p_id_presupuesto;

        -- Regla de negocio: solo un presupuesto PENDIENTE se procesa (pasa a
        -- ENVIADO). Antes APROBADO tambien volvia a ENVIADO, que es un retroceso,
        -- y en cualquier otro estado reescribia el mismo estado dejando una nota
        -- "[Procesado por ...]" en observaciones sin haber hecho nada.
        IF v_estado_actual <> 'PENDIENTE' THEN
            raise_application_error(-20025,
                'El presupuesto ' || v_folio || ' está ' || v_estado_actual
                || ': solo se puede procesar uno PENDIENTE.');
        END IF;

        p_nuevo_estado := 'ENVIADO';

        -- Actualizamos el estado, la auditoría de modificación y agregamos una nota opcional en observaciones
        UPDATE presupuestos SET
               estado         = p_nuevo_estado,
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
            IF SQLCODE BETWEEN -20999 AND -20000 THEN
                RAISE;
            END IF;
            prc_log_error(
                p_usuario   => nvl(v('APP_USER'), 'SISTEMA'),
                p_codigo    => 'ORA-' || lpad(to_char(abs(SQLCODE)), 5, '0'),
                p_mensaje   => 'No se pudo procesar el presupuesto',
                p_detalle   => SQLERRM,
                p_sentencia => dbms_utility.format_error_backtrace);
            RAISE_APPLICATION_ERROR(-20003,
                'No se pudo procesar el presupuesto. Avisa al administrador.');
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
        UPDATE presupuestos SET
               estado         = 'CANCELADO',
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
            IF SQLCODE BETWEEN -20999 AND -20000 THEN
                RAISE;
            END IF;
            prc_log_error(
                p_usuario   => nvl(v('APP_USER'), 'SISTEMA'),
                p_codigo    => 'ORA-' || lpad(to_char(abs(SQLCODE)), 5, '0'),
                p_mensaje   => 'No se pudo cancelar el presupuesto',
                p_detalle   => SQLERRM,
                p_sentencia => dbms_utility.format_error_backtrace);
            RAISE_APPLICATION_ERROR(-20002,
                'No se pudo cancelar el presupuesto. Avisa al administrador.');
    END prc_cancelar_presupuesto;

END pkg_presupuestos;
/