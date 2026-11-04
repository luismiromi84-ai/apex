create or replace PACKAGE BODY pkg_factura_detalle IS

    --------------------------------------------------------------------------------
    -- PROCEDIMIENTO: GUARDAR / ACTUALIZAR DETALLE
    --------------------------------------------------------------------------------
    PROCEDURE guardar_detalle (
        p_id_factura           IN NUMBER,
        p_id_detalle           IN OUT NUMBER,
        p_id_producto          IN VARCHAR2,
        p_id_impuesto          IN VARCHAR2,
        p_cantidad             IN VARCHAR2,
        p_precio_unitario      IN VARCHAR2,
        p_porc_descuento       IN VARCHAR2,
        p_monto_descuento      IN VARCHAR2,
        p_porc_impuesto        IN VARCHAR2,
        p_monto_impuesto       IN VARCHAR2,
        p_subtotal_linea       IN VARCHAR2,
        p_monto_total_linea    IN VARCHAR2,
        p_codigo_producto      IN VARCHAR2,
        p_descripcion          IN VARCHAR2,
        p_usuario              IN VARCHAR2
    ) IS
        v_tasa_cambio        NUMBER := 1;
        v_num_linea          NUMBER;
        v_id_producto_num    NUMBER;
        v_id_impuesto_num    NUMBER;
        
        v_cantidad           NUMBER;
        v_precio_unitario    NUMBER;
        v_porc_descuento     NUMBER;
        v_monto_descuento    NUMBER;
        v_porc_impuesto      NUMBER;
        v_monto_impuesto     NUMBER;
        v_subtotal_linea     NUMBER;
        v_total_linea        NUMBER;
        
        v_subtotal_bs        NUMBER;
        v_total_bs           NUMBER;
        v_estado_factura     VARCHAR2(50);
    BEGIN
        -- 0. Validar el estado de la factura antes de permitir cambios
        BEGIN
            SELECT estado, NVL(tipo_cambio, 1) 
              INTO v_estado_factura, v_tasa_cambio 
              FROM facturas 
             WHERE id_factura = p_id_factura;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                raise_application_error(-20001, 'La factura especificada no existe.');
        END;

        IF v_estado_factura = 'FACTURADO' THEN
            raise_application_error(-20002, 'No se pueden modificar ni agregar líneas a una factura que ya se encuentra en estado FACTURADO.');
        END IF;

        IF v_tasa_cambio <= 0 THEN v_tasa_cambio := 1; END IF;

        -- 1. Limpieza de IDs
        BEGIN v_id_producto_num := TO_NUMBER(REGEXP_SUBSTR(p_id_producto, '^[0-9]+')); EXCEPTION WHEN OTHERS THEN v_id_producto_num := NULL; END;
        BEGIN v_id_impuesto_num := TO_NUMBER(REGEXP_SUBSTR(p_id_impuesto, '^[0-9]+')); EXCEPTION WHEN OTHERS THEN v_id_impuesto_num := NULL; END;

        -- 2. Limpieza de valores numéricos usando tu función fn_clean_num
        v_cantidad        := fn_clean_num(p_cantidad);
        v_precio_unitario := fn_clean_num(p_precio_unitario);
        v_porc_descuento  := fn_clean_num(p_porc_descuento);
        v_monto_descuento := fn_clean_num(p_monto_descuento);
        v_porc_impuesto   := fn_clean_num(p_porc_impuesto);
        v_monto_impuesto  := fn_clean_num(p_monto_impuesto);
        v_subtotal_linea  := fn_clean_num(p_subtotal_linea);
        v_total_linea     := fn_clean_num(p_monto_total_linea);

        IF v_porc_impuesto = 0 AND p_porc_impuesto IS NULL THEN
            v_porc_impuesto := 16;
        END IF;

        v_subtotal_bs := v_subtotal_linea * v_tasa_cambio;
        v_total_bs    := v_total_linea * v_tasa_cambio;

        -- 3. DECISIÓN: SI TIENE ID_DETALLE EDITA (UPDATE), SI NO, CREA NUEVO (INSERT)
        IF p_id_detalle IS NOT NULL AND p_id_detalle > 0 THEN
            UPDATE facturas_det
               SET id_producto          = v_id_producto_num,
                   codigo_producto      = SUBSTR(p_codigo_producto, 1, 50),
                   descripcion          = SUBSTR(p_descripcion, 1, 500),
                   cantidad             = v_cantidad,
                   precio_unitario      = v_precio_unitario,
                   porcentaje_descuento = v_porc_descuento,
                   monto_descuento      = v_monto_descuento,
                   id_impuesto          = v_id_impuesto_num,
                   porcentaje_impuesto  = v_porc_impuesto,
                   monto_impuesto       = v_monto_impuesto,
                   subtotal_linea       = v_subtotal_linea,
                   monto_total_linea    = v_total_linea,
                   tasa_cambio_aplicada = v_tasa_cambio,
                   subtotal_bs          = v_subtotal_bs,
                   total_bs             = v_total_bs
             WHERE id_factura = p_id_factura
               and id_detalle = p_id_detalle;
               
            apex_application.g_print_success_message := 'El detalle de la factura se actualizó exitosamente.';
        ELSE
            SELECT NVL(MAX(num_linea), 0) + 1 
              INTO v_num_linea 
              FROM facturas_det 
             WHERE id_factura = p_id_factura;

            INSERT INTO facturas_det (
                id_factura, num_linea, id_producto, codigo_producto, descripcion,
                cantidad, precio_unitario, porcentaje_descuento, monto_descuento,
                id_impuesto, porcentaje_impuesto, monto_impuesto, subtotal_linea,
                monto_total_linea, tasa_cambio_aplicada, subtotal_bs, total_bs,
                creado_por, fecha_creacion
            ) VALUES (
                p_id_factura, v_num_linea, v_id_producto_num, SUBSTR(p_codigo_producto, 1, 50), SUBSTR(p_descripcion, 1, 500),
                v_cantidad, v_precio_unitario, v_porc_descuento, v_monto_descuento,
                v_id_impuesto_num, v_porc_impuesto, v_monto_impuesto, v_subtotal_linea,
                v_total_linea, v_tasa_cambio, v_subtotal_bs, v_total_bs,
                p_usuario, SYSTIMESTAMP
            ) RETURNING id_detalle INTO p_id_detalle;
            
            apex_application.g_print_success_message := 'El detalle de la factura se guardó exitosamente.';
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            raise_application_error(-20003, 'DEBUG ERROR: ' || SQLERRM);
    END guardar_detalle;

    --------------------------------------------------------------------------------
    -- PROCEDIMIENTO: ELIMINAR DETALLE
    --------------------------------------------------------------------------------
    PROCEDURE eliminar_detalle (
        p_id_factura           IN NUMBER,
        p_id_detalle           IN NUMBER
    ) IS
        v_estado_factura     VARCHAR2(50);
    BEGIN
        -- Validar el estado de la factura antes de eliminar
        BEGIN
            SELECT estado INTO v_estado_factura 
              FROM facturas 
             WHERE id_factura = p_id_factura;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                raise_application_error(-20001, 'La factura especificada no existe.');
        END;

        IF v_estado_factura = 'FACTURADO' THEN
            raise_application_error(-20002, 'No se pueden eliminar líneas de una factura que ya se encuentra en estado FACTURADO.');
        END IF;

        IF p_id_detalle IS NULL THEN
            raise_application_error(-20001, 'No se puede eliminar porque el ID del detalle está vacío.');
        END IF;

        DELETE FROM facturas_det
         WHERE id_factura = p_id_factura
           AND id_detalle = p_id_detalle;

        IF SQL%ROWCOUNT = 0 THEN
            raise_application_error(-20001, 'No se encontró el registro para eliminar.');
        END IF;

        apex_application.g_print_success_message := 'El detalle de la factura se ha eliminado correctamente.';
    EXCEPTION
        WHEN OTHERS THEN
            raise_application_error(-20002, SQLERRM);
    END eliminar_detalle;

END pkg_factura_detalle;
/