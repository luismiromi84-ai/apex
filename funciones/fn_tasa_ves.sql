-- =============================================================================
-- fn_tasa_ves.sql
--
-- Devuelve cuantos BOLIVARES vale UNA unidad de la moneda, a una fecha.
-- Es la tasa que se guarda en `tipo_cambio` y en `presupuestos.tipo_cambio` /
-- `facturas.tipo_cambio`, y la que usa facturacion para los montos en Bs
-- (`subtotal_linea * tasa_cambio`).
--
-- Reglas:
--   * VES/BS devuelve 1 (un bolivar son 1 bolivar).
--   * USD, MXN, EUR... devuelven la ultima `tasa_cambio` con
--     moneda_destino = 'VES' y tipo_tasa = 'REAL' con fecha_vigencia <= fecha.
--   * Si no hay tasa, devuelve NULL (no miente con un 1). Quien llama decide.
--
-- OJO: no confundir con fn_tasa_cambio, que fue escrita como factor A USD y
-- devuelve 1 para USD. La tabla guarda bolivares por unidad, no factor a USD.
-- =============================================================================

create or replace function fn_tasa_ves (
    p_fecha  in date,
    p_moneda in varchar2 default 'USD'
) return number is
    v_moneda varchar2(10) := upper(trim(p_moneda));
    v_tasa   number;
begin
    if v_moneda is null or v_moneda in ('VES', 'BS') then
        return 1;
    end if;

    select max(tasa_cambio) keep (dense_rank last order by fecha_vigencia)
      into v_tasa
      from tipo_cambio
     where moneda_origen = v_moneda
       and moneda_destino = 'VES'
       and tipo_tasa = 'REAL'
       and fecha_vigencia <= nvl(p_fecha, sysdate);

    return v_tasa;
end fn_tasa_ves;
/
