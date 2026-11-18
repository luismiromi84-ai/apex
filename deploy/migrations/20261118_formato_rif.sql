-- =============================================================================
-- 20261118_formato_rif.sql
--
-- El RIF se guardaba de tres formas distintas ('J123456789', 'J-171403189',
-- 'j-171403189 ') y la pantalla y el papel lo enseñaban tal cual. Esta migración:
--
--   1. crea fn_formato_rif(valor), que devuelve J-12345678-9 cuando la forma es
--      letra + 9 dígitos y, si no, el valor sin espacios;
--   2. normaliza lo ya guardado: EMPRESAS.RFC, CLIENTES.RIF y
--      FACTURAS.RFC_EMISOR / RFC_RECEPTOR.
--
-- Reversa: los valores viejos se pueden recuperar de la copia de seguridad; el
-- cambio solo añade guiones (no toca dígitos).
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

create or replace function fn_formato_rif (p_valor in varchar2) return varchar2 is
    v_limpio varchar2(60);
begin
    if p_valor is null then
        return null;
    end if;

    v_limpio := replace(replace(upper(trim(p_valor)), '-', ''), ' ', '');

    if length(v_limpio) = 10
       and substr(v_limpio, 1, 1) in ('J', 'V', 'E', 'G', 'P', 'C')
       and regexp_like(substr(v_limpio, 2), '^[0-9]{9}$') then
        return substr(v_limpio, 1, 1) || '-' || substr(v_limpio, 2, 8) || '-'
               || substr(v_limpio, 10, 1);
    end if;

    return trim(p_valor);
end fn_formato_rif;
/

-- Empresas (RIF/RFC del emisor)
update empresas set rfc = fn_formato_rif(rfc)
 where rfc is not null and rfc <> fn_formato_rif(rfc)
/

-- Clientes
update clientes set rif = fn_formato_rif(rif)
 where rif is not null and rif <> fn_formato_rif(rif)
/

-- Facturas (lo que se copió al emitir)
update facturas set rfc_emisor = fn_formato_rif(rfc_emisor)
 where rfc_emisor is not null and rfc_emisor <> fn_formato_rif(rfc_emisor)
/

update facturas set rfc_receptor = fn_formato_rif(rfc_receptor)
 where rfc_receptor is not null and rfc_receptor <> fn_formato_rif(rfc_receptor)
/

commit
/

begin
    dbms_utility.compile_schema('WKSP_SYPEXWS', false);
end;
/

-- Validación: la función existe y hace lo que dice.
declare
    v_n number;
begin
    if fn_formato_rif('J123456789') <> 'J-12345678-9' then
        raise_application_error(-20104, 'fn_formato_rif no formatea J123456789');
    end if;
    if fn_formato_rif('J-171403189') <> 'J-17140318-9' then
        raise_application_error(-20104, 'fn_formato_rif no normaliza J-171403189');
    end if;
    if fn_formato_rif('MXE850101AB1') <> 'MXE850101AB1' then
        raise_application_error(-20104, 'fn_formato_rif toca un RFC mexicano');
    end if;
    if fn_formato_rif(' j-171403189 ') <> 'J-17140318-9' then
        raise_application_error(-20104, 'fn_formato_rif no recorta espacios');
    end if;

    select count(*) into v_n from all_objects
     where owner = 'WKSP_SYPEXWS' and object_name = 'FN_FORMATO_RIF' and status = 'VALID';
    if v_n <> 1 then
        raise_application_error(-20104, 'FN_FORMATO_RIF no quedo VALID');
    end if;
end;
/
