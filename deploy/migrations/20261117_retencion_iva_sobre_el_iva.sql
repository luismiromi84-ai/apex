-- =============================================================================
-- 20261117_retencion_iva_sobre_el_iva.sql
--
-- Retencion de IVA del cliente, corregida (2026-11-17). Idempotente.
--
-- Que arregla:
--   1. El monto retenido se calculaba sobre MONTO_IMPUESTO completo, que incluye
--      el IGTF 3 %. El IGTF NO se retiene: ahora se calcula sobre el IVA del
--      detalle, linea por linea, con su tasa.
--   2. En un alta la cabecera llega con monto_impuesto = 0 (los totales los pone
--      el detalle), asi que la retencion quedaba en 0 aunque el porcentaje
--      fuera 75. Ahora se calcula del detalle real.
--   3. El trigger de totales del detalle no recalculaba la retencion cuando
--      cambiaban las lineas (agregar una linea despues de crear la factura
--      dejaba el importe viejo).
--
-- Contenido: fn_iva_retenido_bs (nueva), trg_actualiza_totales_factura y el body
-- de pkg_facturacion. Al final compila el esquema.
--
-- Reversa: volver a la version anterior de los tres objetos. El trigger anterior
-- calculaba retencion_iva_bs con SUM(monto_impuesto) * tipo_cambio * pct / 100;
-- la funcion no existia. Los importes ya guardados no se tocan.
--
-- Verificacion: deploy/diagnostico/20261117_retencion_iva_verificacion.sql
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

-- =============================================================================
-- fn_iva_retenido_bs.sql
--
-- IVA retenido por el cliente, en bolivares, de una factura (2026-11-17).
--
-- La retencion de IVA se calcula sobre el **IVA**, no sobre el total de
-- impuestos: el IGTF 3 % no se retiene. Antes se usaba MONTO_IMPUESTO completo,
-- asi que un documento que mezclara IVA e IGTF retenia tambien el 3 % del IGTF.
--
-- Se calcula por linea, con la tasa aplicada a la linea (la misma que usan el
-- libro de ventas y el impreso) y sin mirar el porcentaje guardado en la
-- cabecera: el porcentaje se pasa como parametro para poder recalcular cuando
-- cambia. La tasa de respaldo tambien llega como parametro (ver nota abajo).
--
-- Se usa desde:
--   * trg_actualiza_totales_factura, cada vez que cambia el detalle;
--   * pkg_facturacion.prc_guardar_factura, al guardar la cabecera.
--
-- Devuelve 0 si no hay factura o el porcentaje es 0 o nulo.
-- =============================================================================

create or replace function fn_iva_retenido_bs (
    p_id_factura  in number,
    p_porcentaje  in number default null,
    p_tasa_defecto in number default 1
) return number is
    v_pct    number := nvl(p_porcentaje, 0);
    v_iva_bs number := 0;
begin
    if p_id_factura is null or v_pct <= 0 then
        return 0;
    end if;

    -- Ojo: aqui NO se puede leer FACTURAS. La funcion se llama desde el trigger
    -- de totales mientras esa misma cabecera se esta actualizando, y leerla da
    -- ORA-04091 (tabla mutante). La tasa de respaldo llega como parametro.
    select nvl(sum(case
                    when nvl(i.cod_impuesto, 'X') <> 'IGTF'
                     and nvl(d.porcentaje_impuesto, 0) > 0
                    then nvl(d.monto_impuesto, 0)
                         * nvl(d.tasa_cambio_aplicada, nvl(p_tasa_defecto, 1))
                    else 0
                   end), 0)
      into v_iva_bs
      from facturas_det d
      left join impuestos i on i.id_impuesto = d.id_impuesto
     where d.id_factura = p_id_factura;

    return round(v_iva_bs * v_pct / 100, 2);
end fn_iva_retenido_bs;
/

create or replace TRIGGER trg_actualiza_totales_factura
FOR INSERT OR UPDATE OR DELETE ON FACTURAS_DET
COMPOUND TRIGGER

    TYPE t_facturas IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
    g_facturas t_facturas;

    AFTER EACH ROW IS
    BEGIN
        IF DELETING THEN
            g_facturas(:OLD.id_factura) := :OLD.id_factura;
        ELSE
            g_facturas(:NEW.id_factura) := :NEW.id_factura;
        END IF;
    END AFTER EACH ROW;

    AFTER STATEMENT IS
        v_id NUMBER;
    BEGIN
        v_id := g_facturas.FIRST;
        WHILE v_id IS NOT NULL LOOP
            UPDATE facturas f SET
                   f.subtotal        = (SELECT NVL(SUM(subtotal_linea), 0) FROM facturas_det WHERE id_factura = v_id),
                   f.monto_impuesto  = (SELECT NVL(SUM(monto_impuesto), 0) FROM facturas_det WHERE id_factura = v_id),
                   f.monto_total     = (SELECT NVL(SUM(monto_total_linea), 0) FROM facturas_det WHERE id_factura = v_id),
                   -- La retencion de IVA se recalcula con el detalle, sobre el IVA
                   -- (sin el IGTF). El cliente puede fijar el porcentaje en la
                   -- cabecera o venir del maestro de clientes.
                   f.retencion_iva_bs = fn_iva_retenido_bs(v_id, f.porcentaje_retencion,
                                                           f.tipo_cambio),
                   f.fecha_modificacion = SYSTIMESTAMP,
                   f.modificado_por     = USER
             WHERE f.id_factura = v_id;

            v_id := g_facturas.NEXT(v_id);
        END LOOP;
    END AFTER STATEMENT;

END trg_actualiza_totales_factura;
/

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
        p_usuario           IN VARCHAR2,
        p_tipo_documento    IN VARCHAR2 DEFAULT 'FAC',
        p_nro_control       IN VARCHAR2 DEFAULT NULL,
        p_id_factura_origen IN NUMBER DEFAULT NULL
    ) IS
    BEGIN
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

prompt Compilando el esquema...
begin
    dbms_utility.compile_schema('WKSP_SYPEXWS', false);
end;
/

select count(*) as invalidos from all_objects
 where owner = 'WKSP_SYPEXWS' and status = 'INVALID';
