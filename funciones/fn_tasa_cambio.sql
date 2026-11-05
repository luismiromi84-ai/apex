-- =============================================================================
-- fn_tasa_cambio.sql
--
-- Devuelve la tasa de una moneda contra USD para una fecha.
--
-- Reglas:
--   * USD siempre 1.
--   * VES/BS siempre 1: es la regla del sistema (los montos en bolivares se
--     manejan contra el dolar como si fueran 1:1 en esta version). Si esa regla
--     cambia, se cambia aqui y en un solo sitio.
--   * Fecha nula devuelve NULL (no hay fecha contra la que buscar).
--   * Si no hay tasa para la moneda en esa fecha, LANZA -20060. Antes devolvia
--     1 en silencio, que es peor que fallar: guardaba bolivares o pesos como si
--     fueran dolares y el error solo se veia en el total.
--   * Antes cualquier error terminaba en "return 1" (un WHEN OTHERS que se
--     tragaba todo). Ahora el error se propaga.
-- =============================================================================

create or replace function fn_tasa_cambio (
    p_fecha         in date,
    p_moneda_origen in varchar2 default 'USD'
) return number is
    v_moneda varchar2(10) := upper(trim(p_moneda_origen));
    v_tasa   number;
begin
    if v_moneda is null or v_moneda = 'USD' then
        return 1;
    end if;

    if v_moneda in ('VES', 'BS') then
        return 1;
    end if;

    if p_fecha is null then
        return null;
    end if;

    select max(tasa_cambio) keep (dense_rank last order by fecha_vigencia asc)
      into v_tasa
      from tipo_cambio
     where moneda_origen = v_moneda
       and fecha_vigencia <= trunc(p_fecha);

    if v_tasa is null then
        raise_application_error(-20060,
            'No hay tasa de cambio para ' || v_moneda || ' al '
            || to_char(p_fecha, 'DD/MM/YYYY')
            || '. Registrala antes de guardar el documento.');
    end if;

    return v_tasa;
end fn_tasa_cambio;
/
