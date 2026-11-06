create or replace PACKAGE BODY pkg_facturacion AS

--------------------------------------------------------------------------------
-- 1. IMPLEMENTACIÓN DE INSERCIÓN
--------------------------------------------------------------------------------
    PROCEDURE prc_insertar (
        p_id_factura        IN OUT NUMBER,
        p_id_empresa        IN NUMBER,
        p_folio_factura     IN VARCHAR2,
        p_id_cliente        IN NUMBER,
        p_id_presupuesto    IN NUMBER,
        p_rfc_emisor        IN VARCHAR2,
        p_rfc_receptor      IN VARCHAR2,
        p_uuid_fiscal       IN VARCHAR2,
        p_uso_cfdi          IN VARCHAR2,
        p_forma_pago        IN VARCHAR2,
        p_metodo_pago       IN VARCHAR2,
        p_condicion_pago    IN VARCHAR2,
        p_fecha_emision     IN VARCHAR2,
        p_fecha_vencimiento IN VARCHAR2,
        p_estado            IN VARCHAR2,
        p_subtotal          IN NUMBER,
        p_monto_impuesto    IN NUMBER,
        p_monto_total       IN NUMBER,
        p_observaciones     IN VARCHAR2,
        p_cod_moneda        IN VARCHAR2,
        p_tipo_cambio       IN NUMBER,
        p_usuario           IN VARCHAR2
    ) IS
    BEGIN
        INSERT INTO facturas (
            id_empresa, folio_factura, id_cliente, id_presupuesto, rfc_emisor, 
            rfc_receptor, uuid_fiscal, uso_cfdi, forma_pago, metodo_pago, 
            condicion_pago, creado_por,
            fecha_emision, fecha_vencimiento, estado, subtotal, monto_impuesto, 
            monto_total, observaciones, cod_moneda, tipo_cambio
        ) VALUES (
            p_id_empresa, p_folio_factura, p_id_cliente, p_id_presupuesto, p_rfc_emisor,
            p_rfc_receptor, p_uuid_fiscal, p_uso_cfdi, p_forma_pago, p_metodo_pago,
            p_condicion_pago, p_usuario,
            CASE WHEN p_fecha_emision IS NOT NULL THEN TO_DATE(p_fecha_emision, 'DD/MM/YYYY') ELSE SYSDATE END,
            CASE WHEN p_fecha_vencimiento IS NOT NULL THEN TO_DATE(p_fecha_vencimiento, 'DD/MM/YYYY') ELSE NULL END,
            NVL(p_estado, 'PENDIENTE'), p_subtotal, p_monto_impuesto,
            p_monto_total, p_observaciones, NVL(p_cod_moneda, 'USD'), p_tipo_cambio
        ) RETURN id_factura INTO p_id_factura;
    END prc_insertar;

--------------------------------------------------------------------------------
-- 2. IMPLEMENTACIÓN DE ACTUALIZACIÓN
--------------------------------------------------------------------------------
    PROCEDURE prc_actualizar (
        p_id_factura        IN NUMBER,
        p_id_empresa        IN NUMBER,
        p_folio_factura     IN VARCHAR2,
        p_id_cliente        IN NUMBER,
        p_id_presupuesto    IN NUMBER,
        p_rfc_emisor        IN VARCHAR2,
        p_rfc_receptor      IN VARCHAR2,
        p_uuid_fiscal       IN VARCHAR2,
        p_uso_cfdi          IN VARCHAR2,
        p_forma_pago        IN VARCHAR2,
        p_metodo_pago       IN VARCHAR2,
        p_condicion_pago    IN VARCHAR2,
        p_fecha_emision     IN VARCHAR2,
        p_fecha_vencimiento IN VARCHAR2,
        p_estado            IN VARCHAR2,
        p_subtotal          IN NUMBER,
        p_monto_impuesto    IN NUMBER,
        p_monto_total       IN NUMBER,
        p_observaciones     IN VARCHAR2,
        p_cod_moneda        IN VARCHAR2,
        p_tipo_cambio       IN NUMBER
    ) IS
        v_folio  facturas.folio_factura%type;
        v_estado facturas.estado%type;
    BEGIN
        -- Un documento cerrado no se edita: PAGADA y ANULADA son estados finales.
        -- Para corregirlo hay que anular la factura y emitir otra.
        IF NOT fn_factura_editable(p_id_factura) THEN
            SELECT folio_factura, UPPER(estado)
              INTO v_folio, v_estado
              FROM facturas
             WHERE id_factura = p_id_factura;

            raise_application_error(-20024,
                'La factura ' || v_folio || ' está ' || v_estado
                || ': no se puede modificar un documento cerrado. '
                || 'Anúlala y emite otra.');
        END IF;

        UPDATE facturas SET
            id_empresa         = p_id_empresa,
            folio_factura      = p_folio_factura,
            id_cliente         = p_id_cliente,
            id_presupuesto     = p_id_presupuesto,
            rfc_emisor         = p_rfc_emisor,
            rfc_receptor       = p_rfc_receptor,
            uuid_fiscal        = p_uuid_fiscal,
            uso_cfdi           = p_uso_cfdi,
            forma_pago         = p_forma_pago,
            metodo_pago        = p_metodo_pago,
            condicion_pago     = p_condicion_pago,
            fecha_emision      = CASE WHEN p_fecha_emision IS NOT NULL THEN TO_DATE(p_fecha_emision, 'DD/MM/YYYY') ELSE SYSDATE END,
            fecha_vencimiento  = CASE WHEN p_fecha_vencimiento IS NOT NULL THEN TO_DATE(p_fecha_vencimiento, 'DD/MM/YYYY') ELSE NULL END,
            estado             = NVL(p_estado, 'PENDIENTE'),
            subtotal           = p_subtotal,
            monto_impuesto     = p_monto_impuesto,
            monto_total        = p_monto_total,
            observaciones      = p_observaciones,
            cod_moneda         = NVL(p_cod_moneda, 'USD'),
            tipo_cambio        = p_tipo_cambio
        WHERE id_factura = p_id_factura;
    END prc_actualizar;

--------------------------------------------------------------------------------
-- 3. PROCESAR PRESUPUESTO (CON RECÁLCULO POR TASA DEL DÍA)
--------------------------------------------------------------------------------
  PROCEDURE prc_procesar_presupuesto_factura (
        p_id_presupuesto_str IN VARCHAR2,
        p_fecha_emision_str  IN VARCHAR2,
        p_id_factura         IN NUMBER,
        p_es_vencido         OUT VARCHAR2,
        p_id_empresa         OUT VARCHAR2,
        p_id_cliente         OUT VARCHAR2,
        p_subtotal           OUT VARCHAR2,
        p_monto_impuesto     OUT VARCHAR2,
        p_monto_total        OUT VARCHAR2,
        p_cod_moneda         OUT VARCHAR2,
        p_tipo_cambio        OUT VARCHAR2,
        p_observaciones      OUT VARCHAR2
    ) AS
        v_id_presupuesto     NUMBER;
        v_fecha_emision      DATE;
        v_vencimiento        DATE;
        v_tasa               NUMBER(14,6) := 1;
        v_tasa_presupuesto   NUMBER(14,6) := 1;
        v_factor             NUMBER(14,6) := 1;
    BEGIN
        p_es_vencido := 'N';
        v_id_presupuesto := TO_NUMBER(REGEXP_SUBSTR(p_id_presupuesto_str, '^[0-9]+') DEFAULT NULL ON CONVERSION ERROR);

        IF v_id_presupuesto IS NOT NULL THEN
            IF p_fecha_emision_str IS NULL THEN
                v_fecha_emision := TRUNC(SYSDATE);
            ELSE
                v_fecha_emision := TO_DATE(SUBSTR(p_fecha_emision_str, 1, 10) DEFAULT NULL ON CONVERSION ERROR, 'DD/MM/YYYY');
                IF v_fecha_emision IS NULL THEN
                    v_fecha_emision := TRUNC(SYSDATE);
                END IF;
            END IF;

            -- 1. Validar fecha de vencimiento del presupuesto
            SELECT fecha_vencimiento
              INTO v_vencimiento
              FROM presupuestos
             WHERE id_presupuesto = v_id_presupuesto;

            IF TRUNC(v_vencimiento) < TRUNC(v_fecha_emision) THEN
                p_es_vencido := 'Y';
                p_id_empresa := NULL;
                p_id_cliente := NULL;
                p_subtotal := NULL;
                p_monto_impuesto := NULL;
                p_monto_total := NULL;
                p_cod_moneda := NULL;
                p_tipo_cambio := NULL;
                p_observaciones := NULL;
            ELSE
                -- 2. Obtener moneda y tasa original del presupuesto para calcular la diferencia
                SELECT p.cod_moneda, NVL(p.tipo_cambio, 1)
                  INTO p_cod_moneda, v_tasa_presupuesto
                  FROM presupuestos p
                 WHERE p.id_presupuesto = v_id_presupuesto;

                IF v_tasa_presupuesto <= 0 THEN v_tasa_presupuesto := 1; END IF;

                IF p_cod_moneda IN ('VES', 'BS') THEN
                    v_tasa := 1;
                ELSE
                    BEGIN
                        -- Buscar la tasa vigente exacta para la fecha de emisión[cite: 4]
                        SELECT tasa_cambio  
                          INTO v_tasa  
                          FROM tipo_cambio  
                         WHERE moneda_origen = p_cod_moneda  
                           AND moneda_destino = 'VES'
                           AND tipo_tasa = 'REAL'
                           AND fecha_vigencia = v_fecha_emision;
                    EXCEPTION
                        WHEN NO_DATA_FOUND THEN
                            BEGIN
                                -- Si no existe exacta, buscar la más reciente anterior o igual[cite: 4]
                                SELECT tasa_cambio  
                                  INTO v_tasa  
                                  FROM (SELECT tasa_cambio  
                                          FROM tipo_cambio  
                                         WHERE moneda_origen = p_cod_moneda  
                                           AND moneda_destino = 'VES'
                                           AND tipo_tasa = 'REAL'
                                           AND fecha_vigencia <= v_fecha_emision  
                                         ORDER BY fecha_vigencia DESC)
                                 WHERE ROWNUM = 1;
                            EXCEPTION
                                WHEN OTHERS THEN v_tasa := v_tasa_presupuesto; 
                            END;
                        WHEN OTHERS THEN 
                            v_tasa := v_tasa_presupuesto;
                    END;
                END IF;

                -- Calcular el factor de proporción entre la tasa nueva y la vieja
                v_factor := v_tasa / v_tasa_presupuesto;

                -- 3. Cargar datos principales aplicando el factor de conversión
                SELECT TO_CHAR(p.id_empresa),
                       TO_CHAR(p.id_cliente),
                       TO_CHAR(p.subtotal * v_factor, 'FM9999999990.00'),
                       TO_CHAR(p.impuesto_iva * v_factor, 'FM9999999990.00'),
                       TO_CHAR(p.total * v_factor, 'FM9999999990.00'),
                       p.cod_moneda,
                       TO_CHAR(v_tasa, 'FM9999999990.0000'),
                       p.observaciones
                  INTO p_id_empresa,
                       p_id_cliente,
                       p_subtotal,
                       p_monto_impuesto,
                       p_monto_total,
                       p_cod_moneda,
                       p_tipo_cambio,
                       p_observaciones
                  FROM presupuestos p
                 WHERE p.id_presupuesto = v_id_presupuesto;

                -- 4. Reconstruir el detalle de la factura aplicando también el factor a las líneas.
                --    El INSERT vive en PKG_FACTURA_DETALLE: un solo package escribe en FACTURAS_DET.
                IF p_id_factura IS NOT NULL THEN
                    pkg_factura_detalle.reemplazar_desde_presupuesto(
                        p_id_factura     => p_id_factura,
                        p_id_presupuesto => v_id_presupuesto,
                        p_factor         => v_factor,
                        p_tasa_cambio    => v_tasa,
                        p_usuario        => v('APP_USER'));
                END IF;
            END IF;
        ELSE
            p_id_empresa := NULL;
            p_id_cliente := NULL;
            p_subtotal := NULL;
            p_monto_impuesto := NULL;
            p_monto_total := NULL;
            p_cod_moneda := NULL;
            p_tipo_cambio := NULL;
            p_observaciones := NULL;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            p_es_vencido := 'N';
    END prc_procesar_presupuesto_factura;

--------------------------------------------------------------------------------
-- 4. ORQUESTADOR DE GUARDADO
--------------------------------------------------------------------------------
    PROCEDURE prc_guardar_factura (
        p_id_factura         IN OUT NUMBER,
        p_id_empresa         IN NUMBER,
        p_folio_factura      IN VARCHAR2,
        p_id_cliente         IN NUMBER,
        p_id_presupuesto     IN NUMBER,
        p_rfc_emisor         IN VARCHAR2,
        p_rfc_receptor       IN VARCHAR2,
        p_uuid_fiscal        IN VARCHAR2,
        p_uso_cfdi           IN VARCHAR2,
        p_forma_pago         IN VARCHAR2,
        p_metodo_pago        IN VARCHAR2,
        p_condicion_pago     IN VARCHAR2,
        p_fecha_emision      IN VARCHAR2,
        p_fecha_vencimiento  IN VARCHAR2,
        p_estado             IN VARCHAR2,
        p_subtotal           IN NUMBER,       
        p_monto_impuesto     IN NUMBER,       
        p_monto_total        IN NUMBER,       
        p_observaciones      IN VARCHAR2,
        p_cod_moneda         IN VARCHAR2,
        p_tipo_cambio        IN NUMBER,       
        p_usuario            IN VARCHAR2
    ) AS
        v_tipo_cambio    NUMBER;
        v_subtotal       NUMBER;
        v_monto_impuesto NUMBER;
        v_monto_total    NUMBER;
        v_id_empresa     NUMBER := NVL(p_id_empresa, 1);
        v_existe         NUMBER := 0;
    BEGIN
    -- Seguridad: la empresa debe pertenecer al usuario de la sesion APEX
    if apex_application.g_user is not null
       and not fn_usuario_empresa_valida(apex_application.g_user, p_id_empresa) then
        raise_application_error(-20003, 'No tiene acceso a la empresa indicada.');
    end if;

        v_tipo_cambio    := fn_clean_num(TO_CHAR(p_tipo_cambio));
        v_subtotal       := fn_clean_num(TO_CHAR(p_subtotal));
        v_monto_impuesto := fn_clean_num(TO_CHAR(p_monto_impuesto));
        v_monto_total    := fn_clean_num(TO_CHAR(p_monto_total));

        IF v_tipo_cambio <= 0 AND p_id_factura IS NOT NULL AND p_id_factura > 0 THEN
            SELECT NVL(MAX(tipo_cambio), 1)
              INTO v_tipo_cambio
              FROM facturas 
             WHERE id_factura = p_id_factura;
        END IF;

        IF v_tipo_cambio <= 0 THEN
            v_tipo_cambio := 1;
        END IF;

        IF v_id_empresa <= 0 THEN
            v_id_empresa := 1;
        END IF;

        IF p_id_factura IS NOT NULL AND p_id_factura > 0 THEN
            SELECT COUNT(1) 
              INTO v_existe 
              FROM facturas 
             WHERE id_factura = p_id_factura;
        END IF;  

        IF v_existe > 0 THEN
            prc_actualizar(
                p_id_factura        => p_id_factura,
                p_id_empresa        => v_id_empresa,
                p_folio_factura     => p_folio_factura,
                p_id_cliente        => p_id_cliente,
                p_id_presupuesto    => p_id_presupuesto,
                p_rfc_emisor        => p_rfc_emisor,
                p_rfc_receptor      => p_rfc_receptor,
                p_uuid_fiscal       => p_uuid_fiscal,
                p_uso_cfdi          => p_uso_cfdi,
                p_forma_pago        => p_forma_pago,
                p_metodo_pago       => p_metodo_pago,
                p_condicion_pago    => p_condicion_pago,
                p_fecha_emision     => p_fecha_emision,
                p_fecha_vencimiento => p_fecha_vencimiento,
                p_estado            => p_estado,
                p_subtotal          => v_subtotal,
                p_monto_impuesto    => v_monto_impuesto,
                p_monto_total       => v_monto_total,
                p_observaciones     => p_observaciones,
                p_cod_moneda        => p_cod_moneda,
                p_tipo_cambio       => v_tipo_cambio
            );
        ELSE
            p_id_factura := NULL;
            prc_insertar(
                p_id_factura        => p_id_factura,
                p_id_empresa        => v_id_empresa,
                p_folio_factura     => p_folio_factura,
                p_id_cliente        => p_id_cliente,
                p_id_presupuesto    => p_id_presupuesto,
                p_rfc_emisor        => p_rfc_emisor,
                p_rfc_receptor      => p_rfc_receptor,
                p_uuid_fiscal       => p_uuid_fiscal,
                p_uso_cfdi          => p_uso_cfdi,
                p_forma_pago        => p_forma_pago,
                p_metodo_pago       => p_metodo_pago,
                p_condicion_pago    => p_condicion_pago,
                p_fecha_emision     => p_fecha_emision,
                p_fecha_vencimiento => p_fecha_vencimiento,
                p_estado            => p_estado,
                p_subtotal          => v_subtotal,
                p_monto_impuesto    => v_monto_impuesto,
                p_monto_total       => v_monto_total,
                p_observaciones     => p_observaciones,
                p_cod_moneda        => p_cod_moneda,
                p_tipo_cambio       => v_tipo_cambio,
                p_usuario           => p_usuario
            );
        END IF;

    EXCEPTION
        WHEN DUP_VAL_ON_INDEX THEN
            RAISE_APPLICATION_ERROR(-20022,
                'El folio ' || p_folio_factura || ' ya existe para esta empresa. Elige otro numero.');
    END prc_guardar_factura;

--------------------------------------------------------------------------------
-- 5. IMPLEMENTACIÓN DE ANULACIÓN DE FACTURA
--------------------------------------------------------------------------------
    PROCEDURE prc_anular_factura (
        p_id_factura     IN NUMBER,
        p_id_presupuesto IN NUMBER,
        p_usuario        IN VARCHAR2
    ) IS
        v_id_factura     NUMBER := fn_clean_num(TO_CHAR(p_id_factura));
        v_id_presupuesto NUMBER := fn_clean_num(TO_CHAR(p_id_presupuesto));
    BEGIN
        UPDATE facturas SET
               estado             = 'ANULADA',
               observaciones      = observaciones || ' [ANULADA EL ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI') || ']',
               MODIFICADO_POR     = NVL(p_usuario, v('APP_USER')),
               fecha_modificacion = SYSDATE
         WHERE id_factura         = v_id_factura;

        IF v_id_presupuesto IS NOT NULL AND v_id_presupuesto > 0 THEN
            UPDATE presupuestos SET
                   estado             = 'APROBADO',
                   fecha_modificacion = SYSDATE,
                   MODIFICADO_POR     = NVL(p_usuario, v('APP_USER'))
             WHERE id_presupuesto     = v_id_presupuesto;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            -- Los errores de negocio (-20xxx) se propagan tal cual: envolverlos
            -- le enseña jerga al usuario y le oculta el motivo (el trigger de
            -- transiciones lanza -20070, por ejemplo).
            IF SQLCODE BETWEEN -20999 AND -20000 THEN
                RAISE;
            END IF;
            -- Sin ROLLBACK: el error se propaga y la transaccion la decide quien
            -- llama (APEX revierte su proceso). El detalle tecnico va al log.
            prc_log_error(
                p_usuario   => nvl(v('APP_USER'), 'SISTEMA'),
                p_codigo    => 'ORA-' || lpad(to_char(abs(SQLCODE)), 5, '0'),
                p_mensaje   => 'No se pudo anular la factura',
                p_detalle   => SQLERRM,
                p_sentencia => dbms_utility.format_error_backtrace);
            raise_application_error(-20001,
                'No se pudo anular la factura. Avisa al administrador.');
    END prc_anular_factura;

--------------------------------------------------------------------------------
-- 6. IMPLEMENTACIÓN DE PROCESAR / TIMBRAR FACTURA
--------------------------------------------------------------------------------
   --------------------------------------------------------------------------------
-- 6. IMPLEMENTACIÓN DE PROCESAR / TIMBRAR FACTURA
--------------------------------------------------------------------------------
    PROCEDURE prc_procesar_factura (
        p_id_factura IN NUMBER,
        p_usuario    IN VARCHAR2
    ) IS
        v_id_factura     NUMBER := fn_clean_num(TO_CHAR(p_id_factura));
        v_id_presupuesto NUMBER;
    BEGIN
        IF v_id_factura IS NULL OR v_id_factura <= 0 THEN
            raise_application_error(-20002, 'Error: El ID de la factura es nulo o inválido.');
        END IF;

        UPDATE facturas SET
               estado             = 'TIMBRADA',
               fecha_modificacion = SYSDATE,
               MODIFICADO_POR     = NVL(p_usuario, v('APP_USER'))
         WHERE id_factura         = v_id_factura;

        IF SQL%ROWCOUNT = 0 THEN
            raise_application_error(-20003, 'No se encontró la factura con ID: ' || v_id_factura);
        END IF;

        BEGIN
            SELECT id_presupuesto
              INTO v_id_presupuesto
              FROM facturas
             WHERE id_factura = v_id_factura;
        EXCEPTION
            WHEN OTHERS THEN
                v_id_presupuesto := NULL;
        END; -- <--- CORREGIDO: Era END IF;, debe ser END;

        IF v_id_presupuesto IS NOT NULL AND v_id_presupuesto > 0 THEN
            UPDATE presupuestos SET
                   estado             = 'FACTURADO',
                   fecha_modificacion = SYSDATE,
                   MODIFICADO_POR     = NVL(p_usuario, v('APP_USER'))
             WHERE id_presupuesto     = v_id_presupuesto;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            -- Sin ROLLBACK, igual que en prc_anular_factura, y con los errores
            -- de negocio propagados tal cual.
            IF SQLCODE BETWEEN -20999 AND -20000 THEN
                RAISE;
            END IF;
            prc_log_error(
                p_usuario   => nvl(v('APP_USER'), 'SISTEMA'),
                p_codigo    => 'ORA-' || lpad(to_char(abs(SQLCODE)), 5, '0'),
                p_mensaje   => 'No se pudo procesar la factura',
                p_detalle   => SQLERRM,
                p_sentencia => dbms_utility.format_error_backtrace);
            raise_application_error(-20003,
                'No se pudo procesar la factura. Avisa al administrador.');
    END prc_procesar_factura;
END pkg_facturacion;
/