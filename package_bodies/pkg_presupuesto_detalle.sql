create or replace PACKAGE BODY pkg_presupuesto_detalle IS

    --------------------------------------------------------------------------------
    -- PROCEDIMIENTO: GUARDAR DETALLE (INSERT / UPDATE)
    --------------------------------------------------------------------------------
    PROCEDURE guardar_detalle (
        p_id_presupuesto         IN NUMBER,
        p_id_detalle             IN OUT NUMBER,
        p_id_producto_servicio   IN VARCHAR2,
        p_cantidad               IN VARCHAR2,
        p_precio_unitario        IN VARCHAR2,
        p_id_impuesto            IN VARCHAR2,
        p_porcentaje_descuento   IN VARCHAR2,
        p_monto_descuento        IN VARCHAR2,
        p_porcentaje_impuesto    IN VARCHAR2,
        p_subtotal_linea         IN VARCHAR2,
        p_descripcion            IN VARCHAR2
    ) IS
        v_cantidad           NUMBER;
        v_precio_unitario    NUMBER;
        v_id_impuesto_num    NUMBER;
        v_pct_descuento      NUMBER;
        v_monto_descuento    NUMBER;
        v_pct_impuesto       NUMBER;
        v_subtotal_linea     NUMBER;
        v_monto_impuesto     NUMBER;
        v_monto_total_linea  NUMBER;
        v_subtotal_cab       NUMBER := 0;
        v_iva_cab            NUMBER := 0;
        v_total_cab          NUMBER := 0;
        v_estado_presupuesto VARCHAR2(50);
    BEGIN
        -- 0. Validar que el ID del presupuesto maestro no sea NULL
        IF p_id_presupuesto IS NULL THEN
            raise_application_error(-20001, 'No se ha proporcionado un ID de Presupuesto válido.');
        END IF;

        -- 0.1. Validar el estado del presupuesto antes de permitir cambios
        BEGIN
            SELECT estado INTO v_estado_presupuesto 
              FROM presupuestos 
             WHERE id_presupuesto = p_id_presupuesto;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                raise_application_error(-20002, 'El presupuesto especificado no existe.');
        END;

        IF UPPER(v_estado_presupuesto) IN ('CANCELADO', 'FACTURADO') THEN
            raise_application_error(-20003,
                'No se pueden modificar ni agregar líneas a un presupuesto en estado '
                || UPPER(v_estado_presupuesto) || ': es un documento cerrado.');
        END IF;

        -- 1. Limpieza y conversión a NUMBER usando tu función fn_clean_num
        v_cantidad           := fn_clean_num(p_cantidad);
        v_precio_unitario    := fn_clean_num(p_precio_unitario);
        v_id_impuesto_num    := fn_clean_num(p_id_impuesto);
        v_pct_descuento      := fn_clean_num(p_porcentaje_descuento);
        v_monto_descuento    := fn_clean_num(p_monto_descuento);
        v_pct_impuesto       := fn_clean_num(p_porcentaje_impuesto);
        v_subtotal_linea     := fn_clean_num(p_subtotal_linea);

        -- 2. Calcular Impuesto y Total de la Línea
        v_monto_impuesto     := v_subtotal_linea * (v_pct_impuesto / 100);
        v_monto_total_linea  := v_subtotal_linea + v_monto_impuesto;

        -- 3. Guardar o Actualizar el Detalle
        IF p_id_detalle IS NULL THEN
            INSERT INTO presupuestos_det (
                id_presupuesto,
                id_producto_servicio,
                cantidad,
                precio_unitario,
                id_impuesto,
                porcentaje_descuento,
                monto_descuento,
                porcentaje_impuesto,
                monto_impuesto,
                subtotal_linea,
                monto_total_linea,
                descripcion
            ) VALUES (
                p_id_presupuesto,
                p_id_producto_servicio,
                v_cantidad,
                v_precio_unitario,
                v_id_impuesto_num,
                v_pct_descuento,
                v_monto_descuento,
                v_pct_impuesto,
                v_monto_impuesto,
                v_subtotal_linea,
                v_monto_total_linea,
                p_descripcion
            ) RETURNING id_detalle INTO p_id_detalle;

            apex_application.g_print_success_message := 'El Detalle del Presupuesto se guardó exitosamente.';
        ELSE
            UPDATE presupuestos_det SET
                   id_producto_servicio = p_id_producto_servicio,
                   cantidad             = v_cantidad,
                   precio_unitario      = v_precio_unitario,
                   id_impuesto          = v_id_impuesto_num,
                   porcentaje_descuento = v_pct_descuento,
                   monto_descuento      = v_monto_descuento,
                   porcentaje_impuesto  = v_pct_impuesto,
                   monto_impuesto       = v_monto_impuesto,
                   subtotal_linea       = v_subtotal_linea,
                   monto_total_linea    = v_monto_total_linea,
                   descripcion          = p_descripcion
             WHERE id_detalle           = p_id_detalle;

            apex_application.g_print_success_message := 'El Detalle del Presupuesto se actualizó exitosamente.';
        END IF;

        -- 4. Obtener los acumulados reales de todas las líneas del presupuesto
        SELECT NVL(SUM(subtotal_linea), 0),
               NVL(SUM(monto_impuesto), 0),
               NVL(SUM(monto_total_linea), 0)
          INTO v_subtotal_cab, v_iva_cab, v_total_cab
          FROM presupuestos_det
         WHERE id_presupuesto = p_id_presupuesto;

        -- 5. Actualización de la cabecera (PRESUPUESTOS)
        UPDATE presupuestos SET
               subtotal     = v_subtotal_cab,
               impuesto_iva = v_iva_cab,
               total        = v_total_cab
         WHERE id_presupuesto = p_id_presupuesto;

    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE BETWEEN -20999 AND -20000 THEN
                RAISE;
            END IF;
            prc_log_error(
                p_usuario   => nvl(v('APP_USER'), 'SISTEMA'),
                p_codigo    => 'ORA-' || lpad(to_char(abs(SQLCODE)), 5, '0'),
                p_mensaje   => 'No se pudo guardar la linea del presupuesto',
                p_detalle   => SQLERRM,
                p_sentencia => dbms_utility.format_error_backtrace);
            raise_application_error(-20004,
                'No se pudo guardar la línea. Avisa al administrador.');
    END guardar_detalle;

    --------------------------------------------------------------------------------
    -- PROCEDIMIENTO: ELIMINAR DETALLE
    --------------------------------------------------------------------------------
    PROCEDURE eliminar_detalle (
        p_id_presupuesto         IN NUMBER,
        p_id_detalle             IN NUMBER
    ) IS
        v_subtotal_cab       NUMBER := 0;
        v_iva_cab            NUMBER := 0;
        v_total_cab          NUMBER := 0;
        v_estado_presupuesto VARCHAR2(50);
    BEGIN
        -- 0. Validar estado del presupuesto antes de eliminar
        BEGIN
            SELECT estado INTO v_estado_presupuesto 
              FROM presupuestos 
             WHERE id_presupuesto = p_id_presupuesto;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                raise_application_error(-20001, 'El presupuesto especificado no existe.');
        END;

        IF UPPER(v_estado_presupuesto) IN ('CANCELADO', 'FACTURADO') THEN
            raise_application_error(-20002,
                'No se pueden eliminar líneas de un presupuesto en estado '
                || UPPER(v_estado_presupuesto) || ': es un documento cerrado.');
        END IF;

        IF p_id_detalle IS NULL THEN
            raise_application_error(-20003, 'No se puede eliminar porque el ID del detalle está vacío.');
        END IF;

        -- 1. Eliminar el registro
        DELETE FROM presupuestos_det
         WHERE id_presupuesto = p_id_presupuesto
           AND id_detalle     = p_id_detalle;

        IF SQL%ROWCOUNT = 0 THEN
            raise_application_error(-20004, 'No se encontró el registro para eliminar.');
        END IF;

        -- 2. Recalcular los acumulados de la cabecera tras la eliminación
        SELECT NVL(SUM(subtotal_linea), 0),
               NVL(SUM(monto_impuesto), 0),
               NVL(SUM(monto_total_linea), 0)
          INTO v_subtotal_cab, v_iva_cab, v_total_cab
          FROM presupuestos_det
         WHERE id_presupuesto = p_id_presupuesto;

        UPDATE presupuestos SET
               subtotal     = v_subtotal_cab,
               impuesto_iva = v_iva_cab,
               total        = v_total_cab
         WHERE id_presupuesto = p_id_presupuesto;

        apex_application.g_print_success_message := 'El Detalle se eliminó exitosamente.';
    EXCEPTION
        WHEN OTHERS THEN
            -- Los errores de negocio (-20xxx) se propagan tal cual: envolverlos
            -- le enseñaba jerga técnica al usuario y le ocultaba el motivo.
            IF SQLCODE BETWEEN -20999 AND -20000 THEN
                RAISE;
            END IF;
            prc_log_error(
                p_usuario   => nvl(v('APP_USER'), 'SISTEMA'),
                p_codigo    => 'ORA-' || lpad(to_char(abs(SQLCODE)), 5, '0'),
                p_mensaje   => 'No se pudo eliminar la linea del presupuesto',
                p_detalle   => SQLERRM,
                p_sentencia => dbms_utility.format_error_backtrace);
            raise_application_error(-20005,
                'No se pudo eliminar la línea. Avisa al administrador.');
    END eliminar_detalle;

END pkg_presupuesto_detalle;
/