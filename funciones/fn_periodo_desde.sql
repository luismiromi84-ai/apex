-- =============================================================================
-- funciones/fn_periodo_desde.sql
--
-- Inicio del período del Libro de compras y ventas (página 18): mes completo o
-- una de las dos quincenas (2026-11-18).
--
--   p_periodo = 'MES'  -> 01/mm/aaaa
--   p_periodo = 'Q1'   -> 01/mm/aaaa
--   p_periodo = 'Q2'   -> 16/mm/aaaa
--
-- El final del rango lo da fn_periodo_hasta (fin exclusivo).
-- Si el mes o el año llegan nulos se usa el mes actual, para que una pantalla
-- sin filtros no reviente.
-- =============================================================================

create or replace function fn_periodo_desde (
    p_mes     in number,
    p_anio    in number,
    p_periodo in varchar2 default 'MES'
) return date is
    v_mes  number := nvl(p_mes,  extract(month from sysdate));
    v_anio number := nvl(p_anio, extract(year  from sysdate));
begin
    if upper(nvl(p_periodo, 'MES')) = 'Q2' then
        return to_date('16/' || lpad(v_mes, 2, '0') || '/' || v_anio, 'DD/MM/YYYY');
    end if;
    return to_date('01/' || lpad(v_mes, 2, '0') || '/' || v_anio, 'DD/MM/YYYY');
end fn_periodo_desde;
/
