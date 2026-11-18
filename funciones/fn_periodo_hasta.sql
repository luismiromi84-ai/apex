-- =============================================================================
-- funciones/fn_periodo_hasta.sql
--
-- Fin (EXCLUSIVO) del período del Libro de compras y ventas (2026-11-18).
--
--   p_periodo = 'MES'  -> 01/(mm+1)/aaaa  (todo el mes)
--   p_periodo = 'Q1'   -> 16/mm/aaaa      (1 al 15)
--   p_periodo = 'Q2'   -> 01/(mm+1)/aaaa  (16 al último día)
--
-- Se usa como "fecha_emision < fn_periodo_hasta(...)".
-- =============================================================================

create or replace function fn_periodo_hasta (
    p_mes     in number,
    p_anio    in number,
    p_periodo in varchar2 default 'MES'
) return date is
    v_mes  number := nvl(p_mes,  extract(month from sysdate));
    v_anio number := nvl(p_anio, extract(year  from sysdate));
begin
    if upper(nvl(p_periodo, 'MES')) = 'Q1' then
        return to_date('16/' || lpad(v_mes, 2, '0') || '/' || v_anio, 'DD/MM/YYYY');
    end if;
    return add_months(to_date('01/' || lpad(v_mes, 2, '0') || '/' || v_anio, 'DD/MM/YYYY'), 1);
end fn_periodo_hasta;
/
