-- =============================================================================
-- 20261106_tasa_obligatoria_documentos.sql
--
-- El tipo de cambio de un presupuesto o una factura deja de ser opcional y deja
-- de poder ser 1. Se guarda en BOLIVARES POR UNIDAD de la moneda del documento
-- (USD->VES 896,12 · MXN->VES 47,91 · VES = 1).
--
-- Lo que estaba mal:
--   * pkg_facturacion.prc_guardar_factura hacia `if v_tipo_cambio <= 0 then
--     v_tipo_cambio := 1`, o sea se inventaba la tasa. De ahi los 29
--     presupuestos y 23 facturas en USD con tipo_cambio = 1.
--   * Ademas pasaba la tasa por fn_clean_num(TO_CHAR(tasa)) y la mascara de
--     TO_NUMBER solo admitia 4 decimales: una tasa de 6 (47,910741) volvia NULL
--     y el INSERT moria con ORA-01400 en TIPO_CAMBIO.
--   * pkg_presupuestos la guardaba tal cual, sin mirar si venia nula (la columna
--     es NOT NULL, asi que el usuario veia "No se pudo guardar el presupuesto").
--
-- Ahora las dos llaman a fn_validar_tasa_documento:
--   * VES/BS -> 1.
--   * sin tasa -> -20061 diciendo cual es la del dia.
--   * tasa 1 en moneda extranjera -> -20061.
--   * fuera de 0,5x..2x de la de la tabla -> -20061 (atrapa la tasa de otra
--     moneda).
--
-- fn_clean_num: la mascara pasa de 4 a 10 decimales.
--
-- Los documentos ya guardados no se tocan: la validacion es al guardar.
--
-- Reversa: recompilar los dos bodies y fn_clean_num del repo anterior
-- (`git checkout <commit> -- package_bodies/pkg_facturacion.sql`...) y borrar
-- fn_validar_tasa_documento.
--
-- Validacion:
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261106_tasa_obligatoria_verificacion.sql
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

-- La misma tasa se guarda en presupuestos y en facturas con 6 decimales.
-- fn_tasa_ves y TIPO_CAMBIO devuelven 6, y con TIPO_CAMBIO(12,4) una tasa como
-- 47,910741 se guardaba como 47,9107.
-- Va a (14,6) y no a (12,6): Oracle no deja aumentar la escala sin aumentar la
-- precision (ORA-01440), porque 12,4 -> 12,6 le quita digitos enteros.
alter table facturas modify tipo_cambio number(14,6)
/

-- =============================================================================
-- fn_clean_num.sql
--
-- Convierte texto en numero aceptando formato latino (1.234,56) y estandar
-- (1234.56).
--
-- Cambio del 2026-11-05: antes borraba los caracteres que no eran numero con un
-- REGEXP_REPLACE, asi que "12,5x" se convertia en 12,5 y el error desaparecia.
-- Ahora se valida la cadena completa: si no es un numero, devuelve NULL. Un NULL
-- revienta en una columna obligatoria y se ve; un 12,5 silencioso no.
--
-- Reglas:
--   * NULL o cadena vacia -> 0 (una casilla vacia significa cero, no error).
--   * Numero valido -> su valor.
--   * Cualquier otra cosa -> NULL. NO se recorta ni se convierte a 0.
--
-- Cambio del 2026-11-06: la mascara de TO_NUMBER tenia 4 decimales y las tasas
-- de cambio tienen 6 (MXN->VES 47,910741). Una tasa de 6 decimales devolvia
-- NULL, y en `prc_guardar_factura` eso terminaba en ORA-01400 al insertar
-- `TIPO_CAMBIO`. Ahora la mascara admite 10 decimales.
--
-- Ojo: los llamadores que hacian nvl(fn_clean_num(x), 0) siguen dando cero; los
-- que no, ahora reciben NULL y fallan de forma visible.
-- =============================================================================

create or replace FUNCTION fn_clean_num (p_val IN VARCHAR2)
RETURN NUMBER IS
    l_limpio VARCHAR2(100);
BEGIN
    IF p_val IS NULL OR TRIM(p_val) IS NULL THEN
        RETURN 0;
    END IF;

    l_limpio := TRIM(p_val);

    -- Solo digitos, separadores y signo. Si aparece cualquier otra cosa
    -- (letras, simbolos de moneda, basura), no es un numero.
    IF NOT REGEXP_LIKE(l_limpio, '^[-+]?[0-9]+([.,][0-9]+)*$')
       AND NOT REGEXP_LIKE(l_limpio, '^[-+]?[.,][0-9]+$') THEN
        RETURN NULL;
    END IF;

    -- Formato latino: si tiene coma y punto, el que este mas a la derecha es el
    -- decimal y el otro el separador de miles.
    IF INSTR(l_limpio, ',') > 0 AND INSTR(l_limpio, '.') > 0 THEN
        IF INSTR(l_limpio, ',') > INSTR(l_limpio, '.') THEN
            l_limpio := REPLACE(l_limpio, '.', '');
            l_limpio := REPLACE(l_limpio, ',', '.');
        ELSE
            l_limpio := REPLACE(l_limpio, ',', '');
        END IF;
    ELSIF INSTR(l_limpio, ',') > 0 THEN
        l_limpio := REPLACE(l_limpio, ',', '.');
    END IF;

    IF l_limpio IN ('.', '-', '+', '-.', '+.') THEN
        RETURN NULL;
    END IF;

    -- El signo + no lo acepta la mascara de TO_NUMBER.
    IF SUBSTR(l_limpio, 1, 1) = '+' THEN
        l_limpio := SUBSTR(l_limpio, 2);
    END IF;

    RETURN TO_NUMBER(l_limpio, 'FM999999999999999999.9999999999', 'NLS_NUMERIC_CHARACTERS=''.,''');

EXCEPTION
    WHEN OTHERS THEN
        -- Cadena con pinta de numero pero que no convierte: es invalida, no cero.
        RETURN NULL;
END fn_clean_num;
/

-- =============================================================================
-- fn_validar_tasa_documento.sql
--
-- Valida y normaliza el tipo de cambio de un documento (presupuesto o factura)
-- antes de guardarlo. Devuelve la tasa que hay que guardar.
--
-- La tasa se guarda, como en todo el sistema, en BOLIVARES POR UNIDAD de la
-- moneda del documento: USD->VES 896,12 Â· MXN->VES 47,91 Â· VES = 1. NO es un
-- factor a dolares. De ahi salieron los 29 presupuestos y 23 facturas en USD con
-- tipo_cambio = 1 que hubo que recalcular el 2026-11-06.
--
-- Reglas:
--   * VES/BS: devuelve 1. La tasa no se pregunta.
--   * Moneda extranjera sin tasa (nula o <= 0): lanza -20061 y, si la tabla la
--     tiene, dice cual es la del dia.
--   * Moneda extranjera con tasa 1: lanza -20061. Un 1 deja los montos en
--     bolivares iguales a los de la moneda y es siempre un error de tecleo.
--   * Moneda extranjera con tasa fuera de 0,5x a 2x de la de la tabla: lanza
--     -20061. Atrapa el caso tipico de usar la tasa de otra moneda (la de USD en
--     un documento en MXN, por ejemplo). Si la tabla no tiene tasa para esa
--     fecha no se compara: solo se exige que sea mayor que cero.
--
-- Ojo: por eso hay que llamarla despues de resolver la tasa (si el usuario dejo
-- la casilla vacia en una edicion, primero se toma la que ya tenia el documento).
-- =============================================================================

create or replace function fn_validar_tasa_documento (
    p_moneda in varchar2,
    p_fecha  in date,
    p_tasa   in number
) return number is
    v_moneda varchar2(10) := upper(trim(p_moneda));
    v_fecha  date := nvl(p_fecha, sysdate);
    v_tabla  number;
    -- Formato de la tasa en los mensajes: punto decimal, independiente del NLS.
    v_fmt    constant varchar2(40) := 'FM999G999G990D999999';
    v_nls    constant varchar2(40) := 'NLS_NUMERIC_CHARACTERS=''.,''';
begin
    if v_moneda is null or v_moneda in ('VES', 'BS') then
        return 1;
    end if;

    v_tabla := fn_tasa_ves(v_fecha, v_moneda);

    if p_tasa is null or p_tasa <= 0 then
        raise_application_error(-20061,
            'Falta el tipo de cambio de un documento en ' || v_moneda || '.'
            || case
                 when v_tabla is not null then
                      ' La tasa del ' || to_char(v_fecha, 'DD/MM/YYYY') || ' es '
                      || to_char(v_tabla, v_fmt, v_nls) || ' bolivares por ' || v_moneda || '.'
                 else ''
               end
            || ' Sin tasa no se puede calcular el equivalente en bolivares.');
    end if;

    if p_tasa = 1 then
        raise_application_error(-20061,
            'El tipo de cambio de un documento en ' || v_moneda
            || ' no puede ser 1: se guarda en bolivares por unidad. Con 1 los montos en '
            || 'bolivares quedarian iguales a los de ' || v_moneda || '.');
    end if;

    if v_tabla is not null and (p_tasa < v_tabla * 0.5 or p_tasa > v_tabla * 2) then
        raise_application_error(-20061,
            'El tipo de cambio ' || to_char(p_tasa, v_fmt, v_nls)
            || ' no cuadra con la tasa del ' || to_char(v_fecha, 'DD/MM/YYYY')
            || ' (' || to_char(v_tabla, v_fmt, v_nls) || ' bolivares por ' || v_moneda
            || '). Revisa la moneda y la tasa.');
    end if;

    return p_tasa;
end fn_validar_tasa_documento;
/

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
                'El presupuesto ' || v_folio || ' estÃ¡ ' || v_estado
                || ': no se puede modificar un documento cerrado. '
                || 'Crea uno nuevo.');
        END IF;

        IF p_id_presupuesto IS NOT NULL THEN
            -- ActualizaciÃ³n (Incluye MODIFICADO_POR)
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
            -- InserciÃ³n (Incluye CREADO_POR y opcionalmente MODIFICADO_POR)
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
    -- PROCEDIMIENTO: Procesar Presupuesto (Desde la vista de detalles / botÃ³n APEX)
    ----------------------------------------------------------------------------
    PROCEDURE prc_procesar_presupuesto (
        p_id_presupuesto    IN     NUMBER,
        p_usuario           IN     VARCHAR2,
        p_nuevo_estado      OUT    VARCHAR2,
        p_nuevas_obs        OUT    VARCHAR2
    ) IS
        v_estado_actual     VARCHAR2(50);
    BEGIN
        -- Consultamos el estado actual para definir la transiciÃ³n de estado lÃ³gica
        SELECT estado 
          INTO v_estado_actual 
          FROM presupuestos 
         WHERE id_presupuesto = p_id_presupuesto;

        -- Definimos la regla de negocio para el procesamiento:
        -- Si estÃ¡ PENDIENTE, al procesarlo pasa a ENVIADO (puedes ajustarlo segÃºn tu flujo: APROBADO, etc.)
        IF v_estado_actual IN ('PENDIENTE', 'APROBADO') THEN
            p_nuevo_estado := 'ENVIADO';
        ELSE
            -- Si ya se encuentra en otro estado, puedes mantenerlo o avanzar segÃºn convenga
            p_nuevo_estado := v_estado_actual; 
        END IF;

        -- Actualizamos el estado, la auditorÃ­a de modificaciÃ³n y agregamos una nota opcional en observaciones
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
        -- Actualizamos el estado a CANCELADO, registramos quiÃ©n modificÃ³ y concatenamos la observaciÃ³n
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
create or replace PACKAGE BODY pkg_facturacion AS

--------------------------------------------------------------------------------
-- 1. IMPLEMENTACIÃ“N DE INSERCIÃ“N
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
-- 2. IMPLEMENTACIÃ“N DE ACTUALIZACIÃ“N
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
                'La factura ' || v_folio || ' estÃ¡ ' || v_estado
                || ': no se puede modificar un documento cerrado. '
                || 'AnÃºlala y emite otra.');
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
-- 3. PROCESAR PRESUPUESTO (CON RECÃLCULO POR TASA DEL DÃA)
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
                        -- Buscar la tasa vigente exacta para la fecha de emisiÃ³n[cite: 4]
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
                                -- Si no existe exacta, buscar la mÃ¡s reciente anterior o igual[cite: 4]
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

                -- Calcular el factor de proporciÃ³n entre la tasa nueva y la vieja
                v_factor := v_tasa / v_tasa_presupuesto;

                -- 3. Cargar datos principales aplicando el factor de conversiÃ³n
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

                -- 4. Reconstruir el detalle de la factura aplicando tambiÃ©n el factor a las lÃ­neas.
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
        v_fecha          DATE;
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

        v_tipo_cambio := fn_validar_tasa_documento(p_cod_moneda, v_fecha, v_tipo_cambio);

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
-- 5. IMPLEMENTACIÃ“N DE ANULACIÃ“N DE FACTURA
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
            -- le enseÃ±a jerga al usuario y le oculta el motivo (el trigger de
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
-- 6. IMPLEMENTACIÃ“N DE PROCESAR / TIMBRAR FACTURA
--------------------------------------------------------------------------------
   --------------------------------------------------------------------------------
-- 6. IMPLEMENTACIÃ“N DE PROCESAR / TIMBRAR FACTURA
--------------------------------------------------------------------------------
    PROCEDURE prc_procesar_factura (
        p_id_factura IN NUMBER,
        p_usuario    IN VARCHAR2
    ) IS
        v_id_factura     NUMBER := fn_clean_num(TO_CHAR(p_id_factura));
        v_id_presupuesto NUMBER;
    BEGIN
        IF v_id_factura IS NULL OR v_id_factura <= 0 THEN
            raise_application_error(-20002, 'Error: El ID de la factura es nulo o invÃ¡lido.');
        END IF;

        UPDATE facturas SET
               estado             = 'TIMBRADA',
               fecha_modificacion = SYSDATE,
               MODIFICADO_POR     = NVL(p_usuario, v('APP_USER'))
         WHERE id_factura         = v_id_factura;

        IF SQL%ROWCOUNT = 0 THEN
            raise_application_error(-20003, 'No se encontrÃ³ la factura con ID: ' || v_id_factura);
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
-- Recompila el esquema: los bodies nuevos pueden dejar dependientes en INVALID.
begin
    dbms_utility.compile_schema('WKSP_SYPEXWS', false);
end;
/