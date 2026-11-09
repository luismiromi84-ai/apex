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

        IF UPPER(v_estado_factura) IN ('PAGADA', 'ANULADA', 'FACTURADO') THEN
            raise_application_error(-20002,
                'No se pueden modificar ni agregar líneas a una factura en estado '
                || UPPER(v_estado_factura) || ': es un documento cerrado.');
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
            UPDATE facturas_det SET
                   id_producto          = v_id_producto_num,
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
            -- Los errores de negocio (-20xxx) se propagan tal cual, con su
            -- mensaje: envolverlos en 'DEBUG ERROR' le enseñaba jerga al usuario
            -- y le ocultaba el motivo real.
            IF SQLCODE BETWEEN -20999 AND -20000 THEN
                RAISE;
            END IF;
            prc_log_error(
                p_usuario   => nvl(v('APP_USER'), 'SISTEMA'),
                p_codigo    => 'ORA-' || lpad(to_char(abs(SQLCODE)), 5, '0'),
                p_mensaje   => 'No se pudo guardar la linea de la factura',
                p_detalle   => SQLERRM,
                p_sentencia => dbms_utility.format_error_backtrace);
            raise_application_error(-20003,
                'No se pudo guardar la línea. Avisa al administrador.');
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

        IF UPPER(v_estado_factura) IN ('PAGADA', 'ANULADA', 'FACTURADO') THEN
            raise_application_error(-20002,
                'No se pueden eliminar líneas de una factura en estado '
                || UPPER(v_estado_factura) || ': es un documento cerrado.');
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
            -- Los errores de negocio (-20xxx) se propagan tal cual, con su
            -- mensaje: antes se reetiquetaban como -20002 con 'ORA-20002: ...'
            -- delante, y el usuario veia el error duplicado.
            IF SQLCODE BETWEEN -20999 AND -20000 THEN
                RAISE;
            END IF;
            prc_log_error(
                p_usuario   => nvl(v('APP_USER'), 'SISTEMA'),
                p_codigo    => 'ORA-' || lpad(to_char(abs(SQLCODE)), 5, '0'),
                p_mensaje   => 'No se pudo eliminar la linea de la factura',
                p_detalle   => SQLERRM,
                p_sentencia => dbms_utility.format_error_backtrace);
            raise_application_error(-20004,
                'No se pudo eliminar la línea. Avisa al administrador.');
    END eliminar_detalle;

    --------------------------------------------------------------------------------
    -- PROCEDIMIENTO: REEMPLAZAR EL DETALLE DESDE UN PRESUPUESTO
    -- Vivia dentro de PKG_FACTURACION.prc_guardar_factura, con el INSERT directo.
    -- Se movio aqui para que todos los INSERT sobre FACTURAS_DET esten en el
    -- mismo package: el bug de los porcentajes se pudo colar justo por tener dos
    -- escritores.
    --------------------------------------------------------------------------------
    PROCEDURE reemplazar_desde_presupuesto (
        p_id_factura     IN NUMBER,
        p_id_presupuesto IN NUMBER,
        p_factor         IN NUMBER,
        p_tasa_cambio    IN NUMBER,
        p_usuario        IN VARCHAR2
    ) IS
        v_factor number := nvl(p_factor, 1);
        v_tasa   number := nvl(p_tasa_cambio, 1);
        v_estado facturas.estado%type;
    BEGIN
        -- Un documento cerrado no se reconstruye.
        BEGIN
            SELECT estado INTO v_estado FROM facturas WHERE id_factura = p_id_factura;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                raise_application_error(-20001, 'La factura especificada no existe.');
        END;

        IF UPPER(v_estado) IN ('PAGADA', 'ANULADA', 'FACTURADO') THEN
            raise_application_error(-20002,
                'No se puede reemplazar el detalle de una factura en estado '
                || UPPER(v_estado) || ': es un documento cerrado.');
        END IF;

        DELETE FROM facturas_det WHERE id_factura = p_id_factura;

        INSERT INTO facturas_det (
            id_factura, num_linea, id_producto, codigo_producto, descripcion,
            cantidad, precio_unitario, porcentaje_descuento, monto_descuento,
            id_impuesto, porcentaje_impuesto, monto_impuesto, subtotal_linea,
            monto_total_linea, tasa_cambio_aplicada, subtotal_bs, total_bs,
            creado_por
        )
        SELECT
            p_id_factura,
            ROW_NUMBER() OVER (ORDER BY pd.id_detalle) AS num_linea,
            pd.id_producto_servicio,
            NULL AS codigo_producto,
            pd.descripcion,
            pd.cantidad,
            pd.precio_unitario * v_factor,
            NVL(pd.porcentaje_descuento, 0),
            NVL(pd.monto_descuento, 0) * v_factor,
            pd.id_impuesto,
            NVL(pd.porcentaje_impuesto, 16),
            NVL(pd.monto_impuesto, 0) * v_factor,
            NVL(pd.subtotal_linea, pd.cantidad * pd.precio_unitario - NVL(pd.monto_descuento, 0)) * v_factor,
            NVL(pd.monto_total_linea, (pd.cantidad * pd.precio_unitario - NVL(pd.monto_descuento, 0)) + NVL(pd.monto_impuesto, 0)) * v_factor,
            v_tasa,
            (NVL(pd.subtotal_linea, pd.cantidad * pd.precio_unitario - NVL(pd.monto_descuento, 0)) * v_factor) * v_tasa,
            (NVL(pd.monto_total_linea, (pd.cantidad * pd.precio_unitario - NVL(pd.monto_descuento, 0)) + NVL(pd.monto_impuesto, 0)) * v_factor) * v_tasa,
            p_usuario
          FROM presupuestos_det pd
         WHERE pd.id_presupuesto = p_id_presupuesto;
    END reemplazar_desde_presupuesto;

    -- ---------------------------------------------------------------------
    -- Nota de credito/debito: traer todas las lineas de la factura original
    -- ---------------------------------------------------------------------
    PROCEDURE copiar_desde_factura (
        p_id_factura        IN NUMBER,
        p_id_factura_origen IN NUMBER,
        p_usuario           IN VARCHAR2
    ) IS
        v_lista varchar2(4000);
    BEGIN
        -- La logica (y los topes) viven en un solo sitio: se le pasa la lista
        -- con TODAS las lineas del origen.
        SELECT LISTAGG(d.id_detalle, ',') WITHIN GROUP (ORDER BY d.id_detalle)
          INTO v_lista
          FROM facturas_det d
         WHERE d.id_factura = p_id_factura_origen;

        copiar_lineas_de_factura(p_id_factura, p_id_factura_origen, v_lista, p_usuario);
    END copiar_desde_factura;

    -- ---------------------------------------------------------------------
    -- Nota de credito: copiar SOLO las lineas marcadas de la factura origen
    -- ---------------------------------------------------------------------
    PROCEDURE copiar_lineas_de_factura (
        p_id_factura        IN NUMBER,
        p_id_factura_origen IN NUMBER,
        p_id_detalles       IN VARCHAR2,
        p_usuario           IN VARCHAR2
    ) IS
        v_tipo       facturas.tipo_documento%type;
        v_estado     facturas.estado%type;
        v_o_tipo     facturas.tipo_documento%type;
        v_o_estado   facturas.estado%type;
        v_o_total    number;
        v_lineas     number;
        v_pedidas    number;
        v_halladas   number;
        v_max        number;
        v_cred       number;
        v_cantidad   number;
        v_prod       varchar2(200);
        v_total_cred number;
        v_total_nuevo number;
    BEGIN
        -- 1. La nota
        BEGIN
            SELECT tipo_documento, estado INTO v_tipo, v_estado
              FROM facturas WHERE id_factura = p_id_factura;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                raise_application_error(-20047, 'La nota no existe.');
        END;

        IF NVL(UPPER(v_tipo), 'FAC') <> 'NC' THEN
            raise_application_error(-20047,
                'Solo una nota de credito puede traer lineas de la factura que acredita.');
        END IF;

        IF UPPER(v_estado) IN ('PAGADA', 'ANULADA', 'FACTURADO') THEN
            raise_application_error(-20002,
                'No se puede modificar el detalle de una nota en estado '
                || UPPER(v_estado) || ': es un documento cerrado.');
        END IF;

        SELECT COUNT(*) INTO v_lineas FROM facturas_det WHERE id_factura = p_id_factura;
        IF v_lineas > 0 THEN
            raise_application_error(-20045,
                'La nota ya tiene ' || v_lineas
                || ' linea(s): borralas antes de traer las de la factura.');
        END IF;

        -- 2. La factura que acredita
        IF p_id_factura_origen IS NULL THEN
            raise_application_error(-20047,
                'La nota no tiene factura de origen: elige la factura que acredita.');
        END IF;

        BEGIN
            SELECT tipo_documento, estado, monto_total
              INTO v_o_tipo, v_o_estado, v_o_total
              FROM facturas WHERE id_factura = p_id_factura_origen;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                raise_application_error(-20047, 'La factura que acredita no existe.');
        END;

        IF NVL(UPPER(v_o_tipo), 'X') <> 'FAC' OR UPPER(v_o_estado) = 'ANULADA' THEN
            raise_application_error(-20047,
                'La factura que acredita no es una factura de venta vigente.');
        END IF;

        SELECT COUNT(*) INTO v_halladas FROM facturas_det WHERE id_factura = p_id_factura_origen;
        IF v_halladas = 0 THEN
            raise_application_error(-20047,
                'La factura que acredita no tiene lineas: no hay nada que acreditar.');
        END IF;

        -- 3. La lista de lineas marcadas
        IF p_id_detalles IS NULL OR TRIM(p_id_detalles) IS NULL THEN
            raise_application_error(-20046, 'No has marcado ninguna linea para acreditar.');
        END IF;

        SELECT COUNT(DISTINCT TRIM(REGEXP_SUBSTR(p_id_detalles, '[^,]+', 1, LEVEL)))
          INTO v_pedidas
          FROM dual
         CONNECT BY LEVEL <= REGEXP_COUNT(p_id_detalles, ',') + 1;

        IF v_pedidas = 0 THEN
            raise_application_error(-20046, 'No has marcado ninguna linea para acreditar.');
        END IF;

        SELECT COUNT(*) INTO v_halladas
          FROM facturas_det d
         WHERE d.id_factura = p_id_factura_origen
           AND INSTR(',' || p_id_detalles || ',', ',' || d.id_detalle || ',') > 0;

        IF v_halladas <> v_pedidas THEN
            raise_application_error(-20047,
                'Alguna de las lineas marcadas no es de la factura que acredita.');
        END IF;

        -- 4. Tope por linea: no acreditar mas cantidad de la facturada
        FOR r IN (SELECT d.id_detalle, d.cantidad,
                         NVL(d.codigo_producto, SUBSTR(d.descripcion, 1, 60)) AS producto,
                         NVL((SELECT SUM(x.cantidad)
                                FROM facturas_det x
                                JOIN facturas f ON f.id_factura = x.id_factura
                               WHERE x.id_detalle_origen = d.id_detalle
                                 AND f.tipo_documento = 'NC'
                                 AND f.estado <> 'ANULADA'
                                 AND f.id_factura <> p_id_factura), 0) AS ya_acreditado
                    FROM facturas_det d
                   WHERE d.id_factura = p_id_factura_origen
                     AND INSTR(',' || p_id_detalles || ',', ',' || d.id_detalle || ',') > 0)
        LOOP
            IF r.ya_acreditado + r.cantidad > r.cantidad + 0.0001 THEN
                raise_application_error(-20048,
                    'La linea ' || r.producto || ' ya tiene ' || r.ya_acreditado
                    || ' acreditada(s) de ' || r.cantidad
                    || ': no se puede acreditar mas de lo facturado.');
            END IF;
        END LOOP;

        -- 5. Tope total: las notas de credito no pueden pasar la factura
        SELECT NVL(SUM(d.monto_total_linea), 0) INTO v_total_nuevo
          FROM facturas_det d
         WHERE d.id_factura = p_id_factura_origen
           AND INSTR(',' || p_id_detalles || ',', ',' || d.id_detalle || ',') > 0;

        SELECT NVL(SUM(f.monto_total), 0) INTO v_total_cred
          FROM facturas f
         WHERE f.tipo_documento = 'NC'
           AND f.estado <> 'ANULADA'
           AND f.id_factura_origen = p_id_factura_origen
           AND f.id_factura <> p_id_factura;

        IF v_total_cred + v_total_nuevo > v_o_total + 0.01 THEN
            raise_application_error(-20049,
                'La nota deja el total acreditado en ' || TO_CHAR(v_total_cred + v_total_nuevo, 'FM999G999G990D00')
                || ' y la factura que acredita vale ' || TO_CHAR(v_o_total, 'FM999G999G990D00')
                || '. No se puede acreditar mas de lo facturado.');
        END IF;

        -- 6. Copia fiel de las lineas marcadas
        SELECT NVL(MAX(num_linea), 0) INTO v_max FROM facturas_det WHERE id_factura = p_id_factura;

        INSERT INTO facturas_det (
            id_factura, num_linea, id_producto, codigo_producto, descripcion,
            cantidad, precio_unitario, porcentaje_descuento, monto_descuento,
            id_impuesto, porcentaje_impuesto, monto_impuesto, subtotal_linea,
            monto_total_linea, tasa_cambio_aplicada, subtotal_bs, total_bs,
            creado_por, id_detalle_origen
        )
        SELECT
            p_id_factura,
            v_max + ROW_NUMBER() OVER (ORDER BY d.id_detalle),
            d.id_producto,
            d.codigo_producto,
            d.descripcion,
            d.cantidad,
            d.precio_unitario,
            NVL(d.porcentaje_descuento, 0),
            NVL(d.monto_descuento, 0),
            d.id_impuesto,
            NVL(d.porcentaje_impuesto, 0),
            NVL(d.monto_impuesto, 0),
            NVL(d.subtotal_linea, 0),
            NVL(d.monto_total_linea, 0),
            d.tasa_cambio_aplicada,
            NVL(d.subtotal_bs, 0),
            NVL(d.total_bs, 0),
            p_usuario,
            d.id_detalle
          FROM facturas_det d
         WHERE d.id_factura = p_id_factura_origen
           AND INSTR(',' || p_id_detalles || ',', ',' || d.id_detalle || ',') > 0;
    END copiar_lineas_de_factura;

END pkg_factura_detalle;
/