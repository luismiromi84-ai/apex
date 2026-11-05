-- =============================================================================
-- 20261105_transiciones_estado.sql
--
-- Dos cosas que quedaban de la semana 4.
--
-- 1. TRANSICIONES DE ESTADO EN LA BASE. Hasta hoy solo las miraba la UI: por
--    SQL se podia devolver una factura ANULADA a PENDIENTE o un presupuesto
--    CANCELADO a ENVIADO. Se anade FN_TRANSICION_ESTADO_VALIDA y dos triggers.
--    No se prohibe todo lo que no este en una lista (eso impediria corregir un
--    estado mal puesto): se prohiben los retrocesos que falsean el documento.
--    Escotilla para corregir a mano: CLIENT_INFO = 'SYPEX_FORZAR_ESTADO'.
--
-- 2. SIN ROLLBACK DENTRO DE LOS PACKAGES. PKG_FACTURACION hacia ROLLBACK en los
--    manejadores de error de prc_anular_factura y prc_procesar_factura. Eso
--    descarta lo que el llamador tuviera pendiente y le quita el control de la
--    transaccion. Ahora el error se propaga y decide quien llama (APEX ya
--    revierte su proceso). El COMMIT de las tasas vive donde debe: en
--    PRC_JOB_TASAS_BCV, que es el envoltorio del job con reintentos.
--
-- Afecta a: una funcion, dos triggers y el body de PKG_FACTURACION.
--
-- Idempotente: la funcion y los triggers se recrean.
--
-- Ejecutar:
--   python deploy/conexion/importar_export.py deploy/migrations/20261105_transiciones_estado.sql
--   (o compilar antes package_bodies/pkg_facturacion.sql si se cambia alli)
--
-- REVERSA:
--   drop trigger trg_valida_estado_presupuesto;
--   drop trigger trg_valida_estado_factura;
--   drop function fn_transicion_estado_valida;
--   y volver a compilar PKG_FACTURACION del commit anterior.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;
/

create or replace function fn_transicion_estado_valida (
    p_tabla   in varchar2,
    p_antes   in varchar2,
    p_despues in varchar2
) return boolean is
    v_antes   varchar2(30) := upper(trim(p_antes));
    v_despues varchar2(30) := upper(trim(p_despues));
    v_tabla   varchar2(30) := upper(trim(p_tabla));
begin
    if nvl(sys_context('userenv', 'client_info'), '#') = 'SYPEX_FORZAR_ESTADO' then
        return true;
    end if;

    if v_antes is null or v_despues is null or v_antes = v_despues then
        return true;
    end if;

    if v_tabla = 'PRESUPUESTO' then
        if v_antes = 'CANCELADO' then
            return false;
        end if;
        if v_antes = 'FACTURADO' and v_despues <> 'APROBADO' then
            return false;
        end if;
    elsif v_tabla = 'FACTURA' then
        if v_antes = 'ANULADA' then
            return false;
        end if;
        if v_antes = 'PAGADA' and v_despues <> 'ANULADA' then
            return false;
        end if;
    end if;

    return true;
end fn_transicion_estado_valida;
/

create or replace trigger trg_valida_estado_presupuesto
    before update of estado on presupuestos
    for each row
begin
    if not fn_transicion_estado_valida('PRESUPUESTO', :old.estado, :new.estado) then
        raise_application_error(-20070,
            'No se puede pasar un presupuesto de ' || :old.estado
            || ' a ' || :new.estado
            || '. Si es una correccion, hazlo con CLIENT_INFO = SYPEX_FORZAR_ESTADO.');
    end if;
end;
/

create or replace trigger trg_valida_estado_factura
    before update of estado on facturas
    for each row
begin
    if not fn_transicion_estado_valida('FACTURA', :old.estado, :new.estado) then
        raise_application_error(-20070,
            'No se puede pasar una factura de ' || :old.estado
            || ' a ' || :new.estado
            || '. Si es una correccion, hazlo con CLIENT_INFO = SYPEX_FORZAR_ESTADO.');
    end if;
end;
/

-- -----------------------------------------------------------------------------
-- Validaciones: cero filas en las tres
-- -----------------------------------------------------------------------------
select 'FALLA: falta FN_TRANSICION_ESTADO_VALIDA' as caso from dual
 where not exists (select 1 from all_objects
                    where owner='WKSP_SYPEXWS' and object_name='FN_TRANSICION_ESTADO_VALIDA'
                      and status='VALID');
/

select 'FALLA: ' || t || ' no existe o esta deshabilitado' as caso
  from (select 'TRG_VALIDA_ESTADO_PRESUPUESTO' t from dual union all
        select 'TRG_VALIDA_ESTADO_FACTURA'      from dual) d
 where not exists (select 1 from all_triggers
                    where owner='WKSP_SYPEXWS' and trigger_name = d.t
                      and status = 'ENABLED');
/

select 'FALLA: hay objetos invalidos' as caso
  from all_objects
 where owner='WKSP_SYPEXWS' and status <> 'VALID'
   and object_type in ('FUNCTION','PROCEDURE','PACKAGE','PACKAGE BODY','TRIGGER','VIEW');
/
