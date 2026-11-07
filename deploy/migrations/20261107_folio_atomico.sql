-- =============================================================================
-- 20261107_folio_atomico.sql
--
-- Folio por empresa y tipo de documento con contador atomico, en lugar del
-- max(folio)+1 que se calculaba en las paginas 7 y 9.
--
-- Por que: dos usuarios guardando a la vez calculaban el mismo numero; la base
-- aceptaba uno y el otro recibia ORA-20021 ("El folio N ya existe para esta
-- empresa"). El contador se incrementa con UPDATE ... RETURNING dentro de la
-- transaccion del guardado, asi que la fila queda bloqueada hasta el COMMIT y
-- el segundo usuario recibe el numero siguiente.
--
-- Series: PRESUPUESTO (1047), FAC (F-1041), NC (NC-1), ND (ND-1).
--
-- Que trae:
--   1. Tabla FOLIO_CONTADOR (si no existe).
--   2. Semilla desde los documentos actuales:
--        PRESUPUESTO -> max(folio) por empresa
--        FAC         -> max numero de TODAS las facturas (la serie F- es unica:
--                       las NC/ND historicas ocupan numeros de la misma)
--        NC / ND     -> 0, porque sus series son nuevas (NC-1, ND-1)
--   3. fn_asignar_folio y fn_siguiente_folio.
--   4. package pkg_facturacion (spec y body) y body de pkg_presupuestos.
--   5. Recompilacion del esquema.
--
-- Reversa: drop function fn_asignar_folio; drop function fn_siguiente_folio;
--          drop table folio_contador; y volver a compilar los packages de la
--          version anterior (git show <commit>:package_bodies/pkg_facturacion.sql).
--
-- Verificacion: deploy/diagnostico/20261107_folio_atomico_verificacion.sql
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;
/

-- 1. Tabla del contador (idempotente)
declare
    v_hay number;
begin
    -- Ojo: user_tables mira el usuario CONECTADO (ADMIN), no el current_schema,
    -- asi que con "alter session set current_schema" hay que preguntar a
    -- all_tables por CURRENT_SCHEMA o el chequeo miente y el create falla
    -- con ORA-00955.
    select count(*) into v_hay
      from all_tables
     where owner = sys_context('USERENV', 'CURRENT_SCHEMA')
       and table_name = 'FOLIO_CONTADOR';
    if v_hay = 0 then
        execute immediate q'~
CREATE TABLE "FOLIO_CONTADOR"
 (	"ID_EMPRESA" NUMBER NOT NULL ENABLE,
	"TIPO" VARCHAR2(20) NOT NULL ENABLE,
	"ULTIMO" NUMBER DEFAULT 0 NOT NULL ENABLE,
	 CONSTRAINT "PK_FOLIO_CONTADOR" PRIMARY KEY ("ID_EMPRESA", "TIPO")
  USING INDEX  ENABLE,
	 CONSTRAINT "CK_FOLIO_CONTADOR_TIPO" CHECK (tipo IN ('PRESUPUESTO', 'FAC', 'NC', 'ND')) ENABLE,
	 CONSTRAINT "FK_FOLIO_CONTADOR_EMPRESA" FOREIGN KEY ("ID_EMPRESA")
	  REFERENCES "EMPRESAS" ("ID_EMPRESA") ENABLE
  )~';
    end if;
end;
/

-- 2. Semilla de los contadores
merge into folio_contador c
using (select id_empresa, 'PRESUPUESTO' tipo, nvl(max(folio), 0) ultimo
         from presupuestos group by id_empresa) s
on (c.id_empresa = s.id_empresa and c.tipo = s.tipo)
when matched then update set c.ultimo = greatest(c.ultimo, s.ultimo)
when not matched then insert (c.id_empresa, c.tipo, c.ultimo)
     values (s.id_empresa, s.tipo, s.ultimo);
/

merge into folio_contador c
using (select id_empresa, 'FAC' tipo,
              nvl(max(to_number(regexp_substr(folio_factura, '[0-9]+$'))), 0) ultimo
         from facturas group by id_empresa) s
on (c.id_empresa = s.id_empresa and c.tipo = s.tipo)
when matched then update set c.ultimo = greatest(c.ultimo, s.ultimo)
when not matched then insert (c.id_empresa, c.tipo, c.ultimo)
     values (s.id_empresa, s.tipo, s.ultimo);
/

insert into folio_contador (id_empresa, tipo, ultimo)
select e.id_empresa, t.tipo, 0
  from empresas e cross join (select 'NC' tipo from dual union all select 'ND' from dual) t
 where not exists (select 1 from folio_contador c
                    where c.id_empresa = e.id_empresa and c.tipo = t.tipo);
/

commit;
/

-- 3. Funciones del contador
-- =============================================================================
-- fn_asignar_folio
--
-- Devuelve el siguiente folio de la empresa para el tipo indicado y deja el
-- contador incrementado, todo dentro de la transaccion del llamador (no hace
-- COMMIT).
--
-- Por que un UPDATE y no max(folio)+1: el UPDATE bloquea la fila del contador
-- hasta el COMMIT, asi que dos sesiones que guardan a la vez se serializan y la
-- segunda recibe el numero siguiente en vez de chocar con el UNIQUE y acabar en
-- ORA-20021.
--
-- Si la fila no existe todavia (primera factura de una empresa) se inserta con
-- 1; si dos sesiones lo intentan a la vez, la segunda recibe DUP_VAL_ON_INDEX y
-- reintenta el UPDATE.
--
-- Formatos: PRESUPUESTO -> '1047', FAC -> 'F-1041', NC -> 'NC-1', ND -> 'ND-1'.
--
-- Ojo al editar: el SET del UPDATE va en la misma linea que el UPDATE. El
-- runner de despliegue descarta toda linea que empiece por "set " y partiria
-- la sentencia (ORA-00971).
-- =============================================================================

create or replace function fn_asignar_folio (
    p_id_empresa in number,
    p_tipo       in varchar2
) return varchar2 is
    v_tipo varchar2(20) := upper(trim(p_tipo));
    v_num  number;
begin
    if p_id_empresa is null or v_tipo is null then
        raise_application_error(-20062,
            'No se puede asignar un folio sin empresa y tipo de documento.');
    end if;

    begin
        update folio_contador set ultimo = ultimo + 1
         where id_empresa = p_id_empresa
           and tipo       = v_tipo
        returning ultimo into v_num;
    exception
        when no_data_found then
            v_num := null;
    end;

    if v_num is null then
        begin
            insert into folio_contador (id_empresa, tipo, ultimo)
            values (p_id_empresa, v_tipo, 1)
            returning ultimo into v_num;
        exception
            when dup_val_on_index then
                update folio_contador set ultimo = ultimo + 1
                 where id_empresa = p_id_empresa
                   and tipo       = v_tipo
                returning ultimo into v_num;
        end;
    end if;

    return case v_tipo
             when 'PRESUPUESTO' then to_char(v_num)
             when 'FAC'         then 'F-'  || v_num
             when 'NC'          then 'NC-' || v_num
             when 'ND'          then 'ND-' || v_num
             else to_char(v_num)
           end;
end fn_asignar_folio;
/
-- =============================================================================
-- fn_siguiente_folio
--
-- El numero que se le muestra al usuario ANTES de guardar. Es solo una vista
-- previa: NO incrementa el contador y no bloquea nada, asi que si otro usuario
-- guarda primero el folio real sera distinto. El que manda es el que devuelve
-- fn_asignar_folio() al insertar.
-- =============================================================================

create or replace function fn_siguiente_folio (
    p_id_empresa in number,
    p_tipo       in varchar2
) return varchar2 is
    v_tipo varchar2(20) := upper(trim(p_tipo));
    v_num  number;
begin
    select nvl(max(ultimo), 0) + 1
      into v_num
      from folio_contador
     where id_empresa = p_id_empresa
       and tipo       = v_tipo;

    return case v_tipo
             when 'PRESUPUESTO' then to_char(v_num)
             when 'FAC'         then 'F-'  || v_num
             when 'NC'          then 'NC-' || v_num
             when 'ND'          then 'ND-' || v_num
             else to_char(v_num)
           end;
end fn_siguiente_folio;
/
-- 4a. pkg_facturacion: spec (agrega p_tipo_documento)
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
        p_tipo_documento    IN VARCHAR2 DEFAULT 'FAC'
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
        p_tipo_documento    IN VARCHAR2 DEFAULT 'FAC'
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
        p_tipo_documento     IN VARCHAR2 DEFAULT 'FAC'
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
END pkg_facturacion;
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
        p_tipo_documento    IN VARCHAR2 DEFAULT 'FAC'
    ) IS
    BEGIN
        INSERT INTO facturas (
            id_empresa, folio_factura, id_cliente, id_presupuesto, rfc_emisor, 
            rfc_receptor, uuid_fiscal, uso_cfdi, forma_pago, metodo_pago, 
            condicion_pago, creado_por,
            fecha_emision, fecha_vencimiento, estado, subtotal, monto_impuesto, 
            monto_total, observaciones, cod_moneda, tipo_cambio, tipo_documento
        ) VALUES (
            p_id_empresa, p_folio_factura, p_id_cliente, p_id_presupuesto, p_rfc_emisor,
            p_rfc_receptor, p_uuid_fiscal, p_uso_cfdi, p_forma_pago, p_metodo_pago,
            p_condicion_pago, p_usuario,
            CASE WHEN p_fecha_emision IS NOT NULL THEN TO_DATE(p_fecha_emision, 'DD/MM/YYYY') ELSE SYSDATE END,
            CASE WHEN p_fecha_vencimiento IS NOT NULL THEN TO_DATE(p_fecha_vencimiento, 'DD/MM/YYYY') ELSE NULL END,
            NVL(p_estado, 'PENDIENTE'), p_subtotal, p_monto_impuesto,
            p_monto_total, p_observaciones, NVL(p_cod_moneda, 'USD'), p_tipo_cambio,
            NVL(UPPER(TRIM(p_tipo_documento)), 'FAC')
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
        p_tipo_documento    IN VARCHAR2 DEFAULT 'FAC'
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
        p_tipo_documento     IN VARCHAR2 DEFAULT 'FAC'
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
                p_tipo_cambio       => v_tipo_cambio,
                p_tipo_documento    => v_tipo_doc
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
                p_tipo_documento    => v_tipo_doc
            );
        END IF;

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
-- 4b. pkg_presupuestos: body (folio del contador al insertar)
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
-- 5. Recompilacion del esquema
begin
    dbms_utility.compile_schema('WKSP_SYPEXWS', false);
end;
/
