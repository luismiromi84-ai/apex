-- =============================================================================
-- 20261106_mensajes_errores.sql
--
-- Objetivo: que el usuario no vea jerga tecnica ni errores duplicados.
--
-- Que hace:
--   1. En los packages, los errores de negocio (-20999..-20000) se propagan tal
--      cual. Antes, seis manejadores WHEN OTHERS los reetiquetaban: el trigger
--      de transiciones lanzaba -20070 y el usuario veia
--      «Error en pkg_facturacion.prc_anular_factura: ORA-20070: ...», y al
--      borrar una linea de una factura PAGADA el mensaje salia duplicado
--      («ORA-20002: ORA-20002: ...»).
--   2. Los errores inesperados dejan un mensaje limpio al usuario y el detalle
--      tecnico (SQLERRM y backtrace) en SYN_ERROR_LOG, via prc_log_error.
--   3. Los mensajes de los dos triggers de transiciones ya no mencionan
--      CLIENT_INFO = SYPEX_FORZAR_ESTADO: eso es una escotilla de operacion,
--      no algo que se le diga a quien esta usando facturacion. La escotilla
--      sigue igual y esta documentada en AGENTS.md.
--
-- Afecta a: 4 package bodies y 2 triggers. Ningun cambio de spec, ninguna
--           tabla, ningun dato.
--
-- Idempotente: todo son create or replace.
--
-- Ejecutar:
--   python deploy/conexion/importar_export.py deploy/migrations/20261106_mensajes_errores.sql
--
-- Verificacion:
--   deploy/diagnostico/20261106_mensajes_verificacion.sql
--
-- REVERSA:
--   volver a compilar los bodies y los triggers de la version anterior
--   (git checkout <commit> -- package_bodies/ trigger/ y el
--   20261105_transiciones_estado.sql).
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;
/

-- ---------------------------------------------------------------------------
-- package_bodies/pkg_facturacion.sql
-- ---------------------------------------------------------------------------

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

-- ---------------------------------------------------------------------------
-- package_bodies/pkg_presupuestos.sql
-- ---------------------------------------------------------------------------

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
    BEGIN
    -- Seguridad: la empresa debe pertenecer al usuario de la sesion APEX
    if apex_application.g_user is not null
       and not fn_usuario_empresa_valida(apex_application.g_user, p_id_empresa) then
        raise_application_error(-20003, 'No tiene acceso a la empresa indicada.');
    end if;

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

-- ---------------------------------------------------------------------------
-- package_bodies/pkg_presupuesto_detalle.sql
-- ---------------------------------------------------------------------------

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

-- ---------------------------------------------------------------------------
-- package_bodies/pkg_factura_detalle.sql
-- ---------------------------------------------------------------------------

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

END pkg_factura_detalle;
/

-- ---------------------------------------------------------------------------
-- trigger/trg_valida_estado_presupuesto.sql
-- ---------------------------------------------------------------------------

-- =============================================================================
-- trg_valida_estado_presupuesto.sql
--
-- Impide los retrocesos de estado que no tienen sentido. La regla vive en
-- fn_transicion_estado_valida.
-- =============================================================================

create or replace trigger trg_valida_estado_presupuesto
    before update of estado on presupuestos
    for each row
begin
    if not fn_transicion_estado_valida('PRESUPUESTO', :old.estado, :new.estado) then
        raise_application_error(-20070,
            'No se puede pasar un presupuesto de ' || :old.estado
            || ' a ' || :new.estado
            || '. Un presupuesto CANCELADO ya no se mueve, y uno FACTURADO solo vuelve a APROBADO (anulando la factura).');
    end if;
end;
/

-- ---------------------------------------------------------------------------
-- trigger/trg_valida_estado_factura.sql
-- ---------------------------------------------------------------------------

-- =============================================================================
-- trg_valida_estado_factura.sql
--
-- Impide los retrocesos de estado que no tienen sentido. La regla vive en
-- fn_transicion_estado_valida.
-- =============================================================================

create or replace trigger trg_valida_estado_factura
    before update of estado on facturas
    for each row
begin
    if not fn_transicion_estado_valida('FACTURA', :old.estado, :new.estado) then
        raise_application_error(-20070,
            'No se puede pasar una factura de ' || :old.estado
            || ' a ' || :new.estado
            || '. Una factura ANULADA ya no se mueve, y una PAGADA solo puede pasar a ANULADA.');
    end if;
end;
/

declare
    v_errores number;
begin
    dbms_utility.compile_schema('WKSP_SYPEXWS', false);

    select count(*) into v_errores
      from all_objects
     where owner = 'WKSP_SYPEXWS' and status <> 'VALID'
       and object_type in ('FUNCTION', 'PROCEDURE', 'PACKAGE', 'PACKAGE BODY',
                           'TRIGGER', 'VIEW');

    if v_errores > 0 then
        raise_application_error(-20100, 'Quedaron ' || v_errores
            || ' objetos INVALID despues de la migracion.');
    end if;
end;
/
