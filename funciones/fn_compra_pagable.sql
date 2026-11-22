-- =============================================================================
-- fn_compra_pagable.sql
--
-- 'S' si la compra se puede pagar hoy (2026-11-21): esta REGISTRADA o PARCIAL y
-- le queda saldo. Existe como funcion porque la condicion de un boton es una
-- expresion PL/SQL y NO admite subconsultas.
--
-- Un BORRADOR no se paga (no esta cerrado), una PAGADA tampoco (saldo cero) y una
-- ANULADA nunca.
-- =============================================================================

create or replace function fn_compra_pagable (
    p_id_compra in number
) return varchar2 is
    v_estado varchar2(20);
    v_tipo   varchar2(10);
begin
    if p_id_compra is null then
        return 'N';
    end if;

    begin
        select c.estado, nvl(c.tipo_documento, 'FAC')
          into v_estado, v_tipo
          from compras c
         where c.id_compra = p_id_compra;
    exception
        when no_data_found then
            return 'N';
    end;

    -- Una nota de credito o de debito NO se paga (2026-11-22): es un documento
    -- que ajusta a otra factura. Sin este filtro la pantalla de pagos la ofrecia
    -- como factura abierta y el dinero se aplicaba a la nota.
    if v_tipo <> 'FAC' then
        return 'N';
    end if;

    if v_estado not in ('REGISTRADA', 'PARCIAL') then
        return 'N';
    end if;

    if fn_saldo_compra(p_id_compra) <= 0.01 then
        return 'N';
    end if;

    return 'S';
end fn_compra_pagable;
/
