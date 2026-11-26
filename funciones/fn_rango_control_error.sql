-- =============================================================================
-- fn_rango_control_error
--
-- ¿Es valido el rango de N° de control de la providencia? (2026-11-25)
-- Devuelve NULL si el rango sirve, o el motivo en texto si no. La usa el guardado
-- de «Datos fiscales» (pagina 19) antes de escribir EMPRESA_FISCAL.
--
-- Reglas (las mismas que usa fn_asignar_control para numerar):
--   * sin desde ni hasta: valido (la empresa no numera control, p. ej. Mexico);
--   * hacen falta los dos;
--   * los dos terminan en digitos;
--   * mismo prefijo (lo que va antes de los digitos, p. ej. «00-»);
--   * mismo numero de digitos (00-000001 / 00-010000, no 000001 / 0000010000);
--   * desde <= hasta.
-- =============================================================================

create or replace function fn_rango_control_error (
    p_desde in varchar2,
    p_hasta in varchar2
) return varchar2 is
    v_d     varchar2(60) := trim(p_desde);
    v_h     varchar2(60) := trim(p_hasta);
    v_dn    varchar2(60);
    v_hn    varchar2(60);
begin
    if v_d is null and v_h is null then
        return null;
    end if;
    if v_d is null or v_h is null then
        return 'Escribe el control "desde" y el "hasta" (los dos), por ejemplo 00-000001 y 00-010000.';
    end if;

    v_dn := regexp_substr(v_d, '[0-9]+$');
    v_hn := regexp_substr(v_h, '[0-9]+$');
    if v_dn is null or v_hn is null then
        return 'El control "desde" y el "hasta" deben terminar en numeros, por ejemplo 00-000001.';
    end if;

    if nvl(substr(v_d, 1, length(v_d) - length(v_dn)), '#') <> nvl(substr(v_h, 1, length(v_h) - length(v_hn)), '#') then
        return 'El control "desde" (' || v_d || ') y el "hasta" (' || v_h
            || ') deben tener el mismo prefijo, por ejemplo 00-000001 y 00-010000.';
    end if;

    if length(v_dn) <> length(v_hn) then
        return 'El control "desde" (' || v_d || ') y el "hasta" (' || v_h
            || ') deben tener la misma cantidad de digitos, por ejemplo 00-000001 y 00-010000.';
    end if;

    if to_number(v_dn) > to_number(v_hn) then
        return 'El control "desde" (' || v_d || ') no puede ser mayor que el "hasta" (' || v_h || ').';
    end if;

    return null;
end fn_rango_control_error;
/
