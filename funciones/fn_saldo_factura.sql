-- =============================================================================
-- fn_saldo_factura.sql
--
-- Saldo de una factura, en su propia moneda (2026-11-17).
--
--   saldo = total de la factura
--         - notas de credito timbradas que la acreditan
--         + notas de debito timbradas que la afectan
--         - la suma de los cobros ACTIVOS (su equivalente en la moneda de la factura)
--
-- Devuelve 0 si la factura no existe o esta ANULADA. Puede devolver un numero
-- negativo cuando se cobro de mas y despues se emitio una nota de credito: eso es
-- un saldo a favor del cliente (dinero a devolver) y se muestra tal cual, no se
-- recorta a cero.
--
-- El equivalente de cada cobro (RECIBOS.MONTO_FACTURA) lo guarda pkg_cobros con la
-- tasa del dia del cobro; aqui no se recalcula nada.
-- =============================================================================

create or replace function fn_saldo_factura (
    p_id_factura in number
) return number is
    v_total   number;
    v_estado  varchar2(20);
    v_notas   number;
    v_cobrado number;
begin
    if p_id_factura is null then
        return 0;
    end if;

    begin
        select f.monto_total, f.estado
          into v_total, v_estado
          from facturas f
         where f.id_factura = p_id_factura;
    exception
        when no_data_found then
            return 0;
    end;

    if v_estado = 'ANULADA' then
        return 0;
    end if;

    select nvl(sum(case f.tipo_documento
                     when 'NC' then -f.monto_total
                     when 'ND' then  f.monto_total
                     else 0
                   end), 0)
      into v_notas
      from facturas f
     where f.id_factura_origen = p_id_factura
       and f.tipo_documento in ('NC', 'ND')
       and f.estado = 'TIMBRADA';

    select nvl(sum(r.monto_factura), 0)
      into v_cobrado
      from recibos r
     where r.id_factura = p_id_factura
       and r.estado = 'ACTIVO';

    return round(v_total + v_notas - v_cobrado, 2);
end fn_saldo_factura;
/
