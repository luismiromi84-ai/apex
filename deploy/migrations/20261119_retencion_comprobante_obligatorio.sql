-- =============================================================================
-- 20261119_retencion_comprobante_obligatorio.sql
--
-- El comprobante de retencion del cliente NO es obligatorio al emitir.
--
-- HISTORIA - esta migracion nacio el 2026-11-19 para hacer OBLIGATORIO el
-- comprobante (lanzaba -20064).
--
-- REGLA VIGENTE - el comprobante no se exige al emitir. En Venezuela lo emite el
-- cliente DESPUES de recibir la factura, asi que en el momento de guardar todavia
-- no existe. Lo que queda:
--   * el FORMATO se valida cuando llega un numero (-20081, 14 digitos);
--   * el numero se guarda cuando llega y el NVL del UPDATE conserva el que ya
--     tuviera la factura;
--   * el IVA retenido (RETENCION_IVA_BS) se sigue calculando y guardando igual;
--   * se puede registrar DESPUES de emitir con prc_registrar_comprobante_retencion
--     (2026-11-20).
--
-- Se regenero el 2026-11-20 con la spec y el body canonicos finales, para que
-- repetir esta migracion no deje el paquete sin el procedimiento nuevo. Es
-- idempotente.
--
-- Contenido - spec y body de pkg_facturacion, sacados de los canonicos
-- (package/pkg_facturacion.sql y package_bodies/pkg_facturacion.sql). La spec va
-- PRIMERO - al reves el body queda INVALID con PLS-00323.
--
-- Reversa - recompilar spec y body de la version anterior. No toca datos.
--
-- Verificacion - deploy/diagnostico/20261119_redondeo_retencion_verificacion.sql
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

create or replace PACKAGE pkg_facturacion AS
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
        p_usuario           IN VARCHAR2,
        p_tipo_documento    IN VARCHAR2 DEFAULT 'FAC',
        p_nro_control       IN VARCHAR2 DEFAULT NULL,
        p_id_factura_origen IN NUMBER   DEFAULT NULL
    );

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
        p_tipo_cambio       IN NUMBER,
        p_tipo_documento    IN VARCHAR2 DEFAULT 'FAC',
        p_nro_control       IN VARCHAR2 DEFAULT NULL,
        p_id_factura_origen IN NUMBER   DEFAULT NULL
    );

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
    );

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
        p_usuario            IN VARCHAR2,
        p_tipo_documento     IN VARCHAR2 DEFAULT 'FAC',
        p_nro_control        IN VARCHAR2 DEFAULT NULL,
        p_id_factura_origen  IN NUMBER   DEFAULT NULL,
        -- Fecha de la factura que se acredita: la nota lleva la tasa de ESE dia
        -- (correlacion). Se pasa tal cual a fn_validar_tasa_documento.
        p_fecha_referencia   IN DATE     DEFAULT NULL,
        p_porcentaje_retencion        IN NUMBER   DEFAULT NULL,
        p_nro_comprobante_retencion   IN VARCHAR2 DEFAULT NULL
    );

    PROCEDURE prc_anular_factura (
        p_id_factura     IN NUMBER,
        p_id_presupuesto IN NUMBER,
        p_usuario        IN VARCHAR2
    );

    PROCEDURE prc_procesar_factura (
        p_id_factura IN NUMBER,
        p_usuario    IN VARCHAR2
    );

    -- Comprobante de retencion del cliente (2026-11-20). En Venezuela lo emite
    -- el cliente DESPUES de recibir la factura, cuando el documento ya esta
    -- TIMBRADA/PARCIAL/PAGADA y por tanto cerrado para fn_factura_editable. Este
    -- procedimiento es la unica via para dejar constancia del numero sin tocar
    -- el documento: no cambia estado, importes ni retencion_iva_bs.
    PROCEDURE prc_registrar_comprobante_retencion (
        p_id_factura IN NUMBER,
        p_nro        IN VARCHAR2,
        p_usuario    IN VARCHAR2
    );
END pkg_facturacion;
/

create or replace PACKAGE BODY pkg_facturacion AS

    ---------------------------------------------------------------------------
    -- El saldo de la factura cambia cuando se procesa o se anula una NOTA sobre
    -- ella; su estado tiene que decirlo: PAGADA si no queda saldo, TIMBRADA si no
    -- hay cobros y vuelve a haber saldo, PARCIAL si hay cobros parciales. Es un
    -- recalculo del SISTEMA, no del usuario, asi que al revertir un PAGADA usa la
    -- escotilla del trigger de transiciones (SYPEX_FORZAR_ESTADO).
    ---------------------------------------------------------------------------
    PROCEDURE actualiza_estado_origen (p_id_factura IN NUMBER, p_usuario IN VARCHAR2) IS
        v_estado facturas.estado%TYPE;
        v_saldo  NUMBER;
        v_cobros NUMBER;
        v_nuevo  facturas.estado%TYPE;
    BEGIN
        IF p_id_factura IS NULL THEN RETURN; END IF;

        BEGIN
            SELECT UPPER(estado) INTO v_estado FROM facturas WHERE id_factura = p_id_factura;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN RETURN;
        END;
        IF v_estado = 'ANULADA' THEN RETURN; END IF;

        v_saldo := NVL(fn_saldo_factura(p_id_factura), 0);
        SELECT COUNT(*) INTO v_cobros
          FROM recibos
         WHERE id_factura = p_id_factura AND estado = 'ACTIVO';

        v_nuevo := CASE WHEN v_saldo <= 0.01 THEN 'PAGADA'
                        WHEN v_cobros = 0      THEN 'TIMBRADA'
                        ELSE 'PARCIAL' END;
        IF v_nuevo = v_estado THEN RETURN; END IF;

        dbms_application_info.set_client_info('SYPEX_FORZAR_ESTADO');
        UPDATE facturas SET
               estado             = v_nuevo,
               fecha_modificacion = SYSDATE,
               modificado_por     = NVL(p_usuario, v('APP_USER'))
         WHERE id_factura = p_id_factura;
        dbms_application_info.set_client_info(NULL);
    END actualiza_estado_origen;

    -- Si el documento es una nota con factura de origen, recalcula el estado de esa
    -- factura. Nunca tumba la operacion: es un remate, no el objetivo del proceso.
    PROCEDURE remata_origen (p_id_factura IN NUMBER, p_usuario IN VARCHAR2) IS
        v_origen NUMBER;
    BEGIN
        BEGIN
            SELECT id_factura_origen INTO v_origen
              FROM facturas WHERE id_factura = p_id_factura;
        EXCEPTION
            WHEN OTHERS THEN RETURN;
        END;
        IF v_origen IS NOT NULL THEN
            actualiza_estado_origen(v_origen, p_usuario);
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            NULL;
    END remata_origen;

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
        p_usuario           IN VARCHAR2,
        p_tipo_documento    IN VARCHAR2 DEFAULT 'FAC',
        p_nro_control       IN VARCHAR2 DEFAULT NULL,
        p_id_factura_origen IN NUMBER DEFAULT NULL
    ) IS
    BEGIN
        -- El cliente tiene que ser de la MISMA empresa que la factura.
        if p_id_cliente is not null then
            declare
                v_hay number;
            begin
                select count(*) into v_hay
                  from clientes c
                 where c.id_cliente = p_id_cliente
                   and c.id_empresa = p_id_empresa;
                if v_hay = 0 then
                    raise_application_error(-20029,
                        'El cliente no es de la empresa de la factura.');
                end if;
            end;
        end if;

        INSERT INTO facturas (
            id_empresa, folio_factura, id_cliente, id_presupuesto, rfc_emisor, 
            rfc_receptor, uuid_fiscal, uso_cfdi, forma_pago, metodo_pago, 
            condicion_pago, creado_por,
            fecha_emision, fecha_vencimiento, estado, subtotal, monto_impuesto, 
            monto_total, observaciones, cod_moneda, tipo_cambio, tipo_documento,
            nro_control, id_factura_origen
        ) VALUES (
            p_id_empresa, p_folio_factura, p_id_cliente, p_id_presupuesto, p_rfc_emisor,
            p_rfc_receptor, p_uuid_fiscal, p_uso_cfdi, p_forma_pago, p_metodo_pago,
            p_condicion_pago, p_usuario,
            CASE WHEN p_fecha_emision IS NOT NULL THEN TO_DATE(p_fecha_emision, 'DD/MM/YYYY') ELSE SYSDATE END,
            CASE WHEN p_fecha_vencimiento IS NOT NULL THEN TO_DATE(p_fecha_vencimiento, 'DD/MM/YYYY') ELSE NULL END,
            NVL(p_estado, 'PENDIENTE'), p_subtotal, p_monto_impuesto,
            p_monto_total, p_observaciones, NVL(p_cod_moneda, 'USD'), p_tipo_cambio,
            NVL(UPPER(TRIM(p_tipo_documento)), 'FAC'),
            p_nro_control, p_id_factura_origen
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
        p_tipo_cambio       IN NUMBER,
        p_tipo_documento    IN VARCHAR2 DEFAULT 'FAC',
        p_nro_control       IN VARCHAR2 DEFAULT NULL,
        p_id_factura_origen IN NUMBER DEFAULT NULL
    ) IS
        v_folio  facturas.folio_factura%type;
        v_estado facturas.estado%type;
    BEGIN
        -- Seguridad: la factura existente tiene que ser de una empresa del usuario. Sin esto
        -- un POST con un id ajeno la reescribiria y le cambiaria la empresa.
        if apex_application.g_user is not null
           and not fn_factura_propio(p_id_factura, apex_application.g_user) then
            raise_application_error(-20003,
                'Esa factura no es de una empresa suya: no se puede modificar.');
        end if;

        -- El cliente tiene que ser de la MISMA empresa que la factura.
        if p_id_cliente is not null then
            declare
                v_hay number;
            begin
                select count(*) into v_hay
                  from clientes c
                 where c.id_cliente = p_id_cliente
                   and c.id_empresa = p_id_empresa;
                if v_hay = 0 then
                    raise_application_error(-20029,
                        'El cliente no es de la empresa de la factura.');
                end if;
            end;
        end if;

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
            tipo_documento     = NVL(UPPER(TRIM(p_tipo_documento)), 'FAC'),
            nro_control        = p_nro_control,
            id_factura_origen  = p_id_factura_origen,
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
        p_usuario            IN VARCHAR2,
        p_tipo_documento     IN VARCHAR2 DEFAULT 'FAC',
        p_nro_control        IN VARCHAR2 DEFAULT NULL,
        p_id_factura_origen  IN NUMBER DEFAULT NULL,
        p_fecha_referencia   IN DATE DEFAULT NULL,
        p_porcentaje_retencion       IN NUMBER DEFAULT NULL,
        p_nro_comprobante_retencion  IN VARCHAR2 DEFAULT NULL
    ) AS
        v_tipo_cambio    NUMBER;
        v_tipo_doc       VARCHAR2(10) := NVL(UPPER(TRIM(p_tipo_documento)), 'FAC');
        v_folio          VARCHAR2(50);
        v_subtotal       NUMBER;
        v_monto_impuesto NUMBER;
        v_monto_total    NUMBER;
        v_id_empresa     NUMBER := NVL(p_id_empresa, 1);
        v_existe         NUMBER := 0;
        v_fecha          DATE;
        v_nro_control    VARCHAR2(60);
        v_pct_retencion  NUMBER;
        v_ret_bs         NUMBER;
    BEGIN
    -- Seguridad: la empresa debe pertenecer al usuario de la sesion APEX
    if apex_application.g_user is not null
       and not fn_usuario_empresa_valida(apex_application.g_user, p_id_empresa) then
        raise_application_error(-20003, 'No tiene acceso a la empresa indicada.');
    end if;

        -- La tasa llega ya como numero: no se pasa por fn_clean_num (TO_CHAR + el
        -- validador de texto anulaba las tasas de 6 decimales, como 47,910741, y
        -- el INSERT moria con ORA-01400 en TIPO_CAMBIO).
        v_tipo_cambio    := p_tipo_cambio;
        v_subtotal       := fn_clean_num(TO_CHAR(p_subtotal));
        v_monto_impuesto := fn_clean_num(TO_CHAR(p_monto_impuesto));
        v_monto_total    := fn_clean_num(TO_CHAR(p_monto_total));

        -- Editar sin tocar la tasa conserva la que ya tenia el documento; una
        -- tasa nueva (o una alta) se valida en fn_validar_tasa_documento.
        IF (v_tipo_cambio IS NULL OR v_tipo_cambio <= 0)
           AND p_id_factura IS NOT NULL AND p_id_factura > 0 THEN
            SELECT MAX(tipo_cambio)
              INTO v_tipo_cambio
              FROM facturas 
             WHERE id_factura = p_id_factura;
        END IF;

        BEGIN
            v_fecha := TO_DATE(p_fecha_emision, 'DD/MM/YYYY');
        EXCEPTION
            WHEN OTHERS THEN
                v_fecha := SYSDATE;
        END;

        IF v_fecha IS NULL THEN
            v_fecha := SYSDATE;
        END IF;

        v_tipo_cambio := fn_validar_tasa_documento(p_cod_moneda, v_fecha, v_tipo_cambio,
                                                   p_fecha_referencia);

        -- Tope de la nota de credito: la suma de las notas de credito no anuladas
        -- de esa factura (sin contar esta) mas el total de esta no puede pasar el
        -- total de la factura que acredita.
        IF v_tipo_doc = 'NC' AND p_id_factura_origen IS NOT NULL THEN
            DECLARE
                v_origen_total NUMBER;
                v_ya_credito   NUMBER;
            BEGIN
                SELECT monto_total INTO v_origen_total
                  FROM facturas WHERE id_factura = p_id_factura_origen;

                SELECT NVL(SUM(f.monto_total), 0) INTO v_ya_credito
                  FROM facturas f
                 WHERE f.tipo_documento = 'NC'
                   AND f.estado <> 'ANULADA'
                   AND f.id_factura_origen = p_id_factura_origen
                   AND f.id_factura <> NVL(p_id_factura, 0);

                IF v_ya_credito + v_monto_total > v_origen_total + 0.01 THEN
                    raise_application_error(-20049,
                        'La nota deja el total acreditado en '
                        || TO_CHAR(v_ya_credito + v_monto_total, 'FM999G999G990D00')
                        || ' y la factura que acredita vale '
                        || TO_CHAR(v_origen_total, 'FM999G999G990D00')
                        || '. No se puede acreditar mas de lo facturado.');
                END IF;
            END;
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

        -- Numero de control: en las facturas sale del rango de la providencia
        -- (EMPRESA_FISCAL). Si se teclea, se valida contra el rango; si no, se
        -- asigna el siguiente y se consume el contador atomico. Las notas llevan
        -- el que se teclee (cada serie de notas se controla aparte).
        IF v_tipo_doc = 'FAC' THEN
            IF p_nro_control IS NOT NULL THEN
                v_nro_control := fn_control_en_rango(v_id_empresa, p_nro_control);
            ELSIF v_existe > 0 THEN
                SELECT nro_control INTO v_nro_control
                  FROM facturas WHERE id_factura = p_id_factura;
            ELSE
                v_nro_control := fn_asignar_control(v_id_empresa);
            END IF;
        ELSE
            v_nro_control := p_nro_control;
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
                p_tipo_cambio       => v_tipo_cambio,
                p_tipo_documento    => v_tipo_doc,
                p_nro_control       => v_nro_control,
                p_id_factura_origen => p_id_factura_origen
            );
        ELSE
            p_id_factura := NULL;
            -- El folio lo asigna el contador de la empresa por tipo de documento
            -- (FAC / NC / ND): el que trae la pagina es solo vista previa.
            v_folio := fn_asignar_folio(v_id_empresa, v_tipo_doc);
            prc_insertar(
                p_id_factura        => p_id_factura,
                p_id_empresa        => v_id_empresa,
                p_folio_factura     => v_folio,
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
                p_usuario           => p_usuario,
                p_tipo_documento    => v_tipo_doc,
                p_nro_control       => v_nro_control,
                p_id_factura_origen => p_id_factura_origen
            );
        END IF;

        -- Retencion de IVA del cliente (2026-11-16). El porcentaje sale del
        -- cliente si la pagina no manda uno; el monto se guarda en bolivares
        -- porque es lo que se declara y lo que dice el comprobante del cliente.
        BEGIN
            IF p_porcentaje_retencion IS NULL THEN
                SELECT CASE WHEN NVL(es_agente_retencion, 'N') = 'S'
                            THEN NVL(porcentaje_retencion, 75) ELSE 0 END
                  INTO v_pct_retencion
                  FROM clientes WHERE id_cliente = p_id_cliente;
            ELSE
                v_pct_retencion := p_porcentaje_retencion;
            END IF;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_pct_retencion := 0;
        END;

        IF v_pct_retencion IS NULL OR v_pct_retencion < 0 OR v_pct_retencion > 100 THEN
            raise_application_error(-20082,
                'El porcentaje de retencion debe estar entre 0 y 100.');
        END IF;

        IF p_nro_comprobante_retencion IS NOT NULL
           AND NOT REGEXP_LIKE(TRIM(p_nro_comprobante_retencion), '^[0-9]{14}$') THEN
            raise_application_error(-20081,
                'El comprobante de retencion del cliente debe tener 14 digitos (AAAAMM + 8).');
        END IF;

        -- El comprobante de retencion NO es obligatorio al emitir: en Venezuela lo
        -- emite el cliente DESPUES de recibir la factura, asi que en el momento de
        -- guardar todavia no existe. Se valida el formato si viene (-20081) y se
        -- guarda cuando llegue; el NVL del UPDATE conserva el que ya tuviera.
        -- El monto se calcula sobre el IVA (sin IGTF) y del detalle real, no del
        -- monto_impuesto que manda la pantalla: en un alta la cabecera llega en 0
        -- porque los totales los pone el detalle (pagina 10).
        v_ret_bs := fn_iva_retenido_bs(p_id_factura, v_pct_retencion, v_tipo_cambio);

        UPDATE facturas SET porcentaje_retencion = v_pct_retencion,
               retencion_iva_bs = v_ret_bs,
               nro_comprobante_retencion = NVL(p_nro_comprobante_retencion, nro_comprobante_retencion)
         WHERE id_factura = p_id_factura;

    EXCEPTION
        WHEN DUP_VAL_ON_INDEX THEN
            RAISE_APPLICATION_ERROR(-20022,
                'El folio ' || nvl(v_folio, p_folio_factura) || ' ya existe para esta empresa. Elige otro numero.');
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
        v_folio          VARCHAR2(30);
        v_cobros         NUMBER;
    BEGIN
        -- Con dinero cobrado no se anula el documento: el cobro queda colgando de
        -- una factura muerta y el arqueo no cuadra. Primero se anulan los cobros
        -- (misma regla que «anula la factura antes de cancelar el presupuesto»).
        SELECT folio_factura,
               (SELECT COUNT(*) FROM recibos r
                 WHERE r.id_factura = v_id_factura AND r.estado = 'ACTIVO')
          INTO v_folio, v_cobros
          FROM facturas
         WHERE id_factura = v_id_factura;

        IF v_cobros > 0 THEN
            RAISE_APPLICATION_ERROR(-20091,
                'La factura ' || v_folio || ' tiene ' || v_cobros
                || CASE WHEN v_cobros = 1 THEN ' cobro registrado' ELSE ' cobros registrados' END
                || ': anula primero los cobros y despues la factura.');
        END IF;

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

        -- Al anular una nota, la factura que acreditaba recupera su saldo.
        remata_origen(v_id_factura, p_usuario);
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

        -- Si lo procesado es una nota, la factura que acredita cambia de saldo.
        remata_origen(v_id_factura, p_usuario);
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

--------------------------------------------------------------------------------
-- 7. COMPROBANTE DE RETENCION DEL CLIENTE (DOCUMENTO YA EMITIDO)
--------------------------------------------------------------------------------
    -- El comprobante llega dias despues de emitir la factura, cuando ya esta
    -- TIMBRADA/PARCIAL/PAGADA y fn_factura_editable la cierra. Esto NO es una
    -- edicion del documento: solo se anota el numero en su columna. No se toca
    -- el estado, los importes ni RETENCION_IVA_BS (que ya se calculo al emitir).
    PROCEDURE prc_registrar_comprobante_retencion (
        p_id_factura IN NUMBER,
        p_nro        IN VARCHAR2,
        p_usuario    IN VARCHAR2
    ) IS
        v_id_factura NUMBER := fn_clean_num(TO_CHAR(p_id_factura));
        v_empresa    NUMBER;
        v_folio      VARCHAR2(30);
        v_estado     VARCHAR2(20);
    BEGIN
        BEGIN
            SELECT id_empresa, folio_factura, UPPER(estado)
              INTO v_empresa, v_folio, v_estado
              FROM facturas
             WHERE id_factura = v_id_factura;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                raise_application_error(-20085,
                    'La factura ' || p_id_factura || ' no existe.');
        END;

        -- Seguridad primero: sin esto un POST con un id ajeno escribiria el
        -- comprobante en la factura de otra empresa.
        IF NOT fn_usuario_empresa_valida(p_usuario, v_empresa) THEN
            raise_application_error(-20003,
                'No tiene acceso a la empresa indicada.');
        END IF;

        -- Una factura anulada no admite papeles: su comprobante ya no respalda nada.
        IF v_estado = 'ANULADA' THEN
            raise_application_error(-20024,
                'La factura ' || v_folio || ' esta ANULADA: '
                || 'no se puede registrar un comprobante de retencion.');
        END IF;

        IF TRIM(p_nro) IS NULL
           OR NOT REGEXP_LIKE(TRIM(p_nro), '^[0-9]{14}$') THEN
            raise_application_error(-20081,
                'El comprobante de retencion del cliente debe tener 14 digitos (AAAAMM + 8).');
        END IF;

        UPDATE facturas set nro_comprobante_retencion = TRIM(p_nro),
               modificado_por            = p_usuario,
               fecha_modificacion        = SYSTIMESTAMP
         WHERE id_factura = v_id_factura;
    END prc_registrar_comprobante_retencion;

END pkg_facturacion;
/

-- =============================================================================
-- Validacion - el paquete tiene que quedar VALID. Si algo quedo INVALID se dice
-- aqui y no en la cara del usuario al guardar una factura.
-- =============================================================================

begin
    dbms_utility.compile_schema('WKSP_SYPEXWS', false);
end;
/

declare
    v_n number;
begin
    select count(*) into v_n
      from all_objects
     where owner = 'WKSP_SYPEXWS' and object_name = 'PKG_FACTURACION'
       and object_type = 'PACKAGE' and status = 'VALID';
    if v_n <> 1 then
        raise_application_error(-20120, 'la spec de PKG_FACTURACION quedo INVALID');
    end if;

    select count(*) into v_n
      from all_objects
     where owner = 'WKSP_SYPEXWS' and object_name = 'PKG_FACTURACION'
       and object_type = 'PACKAGE BODY' and status = 'VALID';
    if v_n <> 1 then
        raise_application_error(-20120, 'el body de PKG_FACTURACION quedo INVALID');
    end if;

    select count(*) into v_n
      from all_source
     where owner = 'WKSP_SYPEXWS' and name = 'PKG_FACTURACION'
       and type = 'PACKAGE BODY'
       and upper(text) like '%PRC_REGISTRAR_COMPROBANTE_RETENCION%';
    if v_n = 0 then
        raise_application_error(-20120,
            'el body no tiene prc_registrar_comprobante_retencion');
    end if;
end;
/
