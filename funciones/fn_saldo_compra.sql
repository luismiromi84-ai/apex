-- =============================================================================
-- fn_saldo_compra.sql
--
-- Saldo por pagar de una compra, en su moneda (2026-11-21):
--
--   saldo = fn_importe_compra - suma de lo aplicado por pagos ACTIVOS
--
-- Lo aplicado vive en PAGOS_DETALLE.MONTO_APLICADO, ya en la moneda de la compra,
-- asi que aqui no se convierte nada. Un pago ANULADO no cuenta (no se borra: se
-- anula, y al anularse sus compras vuelven a estar pendientes).
--
-- Puede devolver un numero negativo solo si una nota de credito llega DESPUES de
-- haber pagado: es informacion (el proveedor queda debiendo) y no se recorta.
-- Un pago nunca puede dejarlo negativo: pkg_pagos lo rechaza.
-- =============================================================================

create or replace function fn_saldo_compra (
    p_id_compra in number
) return number is
    v_importe  number;
    v_aplicado number;
begin
    if p_id_compra is null then
        return 0;
    end if;

    v_importe := fn_importe_compra(p_id_compra);

    select nvl(sum(d.monto_aplicado), 0)
      into v_aplicado
      from pagos_detalle d
      join pagos p on p.id_pago = d.id_pago
     where d.id_compra = p_id_compra
       and p.estado = 'ACTIVO';

    return round(v_importe - v_aplicado, 2);
end fn_saldo_compra;
/
