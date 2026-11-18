-- =============================================================================
-- fn_formato_rif.sql
--
-- Deja un RIF venezolano con el formato del SENIAT: J-12345678-9.
-- Entrada: cualquier cosa ('J123456789', 'J-171403189', ' j-171403189 ').
-- Si no tiene la forma letra + 9 dígitos (un RFC mexicano, los datos de relleno
-- 'EMP123456789', un RIF con letra de empresa) devuelve el valor sin espacios.
--
-- Es solo presentación: no valida ni cambia nada en la base por sí sola.
-- =============================================================================

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
