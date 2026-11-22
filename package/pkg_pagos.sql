-- =============================================================================
-- pkg_pagos.sql
--
-- Pagos a proveedores (2026-11-21). Espejo de pkg_cobros del lado del dinero que
-- sale: cabecera (PAGOS) + reparto a facturas de compra (PAGOS_DETALLE).
--
-- Reglas que viven aqui (no en la pantalla):
--   - Un pago se aplica a varias compras y una compra se cancela con varios pagos.
--   - Un pago SIN aplicaciones es un anticipo: su monto queda como saldo a favor.
--   - Lo aplicado nunca supera el saldo de la compra ni el monto del pago.
--   - Nada se borra: se anula, y al anularse las compras vuelven a estar pendientes.
--   - Un pago conciliado no se anula ni recibe aplicaciones sin desmarcarlo.
--
-- El saldo de la compra sale de fn_saldo_compra (formula unica del sistema).
-- =============================================================================

create or replace package pkg_pagos as

    -- Registra un pago con su reparto, en una sola transaccion.
    -- p_aplicaciones es JSON: [{"id_compra":123,"monto":895.00}, ...] y puede
    -- llegar nulo (anticipo). El monto de cada aplicacion va en la MONEDA DE LA
    -- COMPRA. La forma que devuelve fn_reparto_sugerido, asi que la pantalla lo
    -- reenvia tal cual.
    procedure prc_registrar_pago (
        p_id_proveedor   in  number,
        p_fecha          in  date,
        p_moneda         in  varchar2,
        p_tasa           in  number,
        p_monto          in  number,
        p_id_forma_pago  in  number   default null,
        p_referencia     in  varchar2 default null,
        p_observaciones  in  varchar2 default null,
        p_aplicaciones   in  varchar2 default null,
        p_usuario        in  varchar2,
        p_id_pago        out number
    );

    -- Anula el pago (no lo borra) y devuelve sus compras a pendientes.
    procedure prc_anular_pago (
        p_id_pago in number,
        p_usuario in varchar2
    );

    -- Marca o desmarca la conciliacion bancaria.
    procedure prc_conciliar (
        p_id_pago    in number,
        p_conciliado in char,
        p_usuario    in varchar2
    );

    -- Aplica el saldo a favor de un pago ya guardado a una compra nueva.
    procedure prc_aplicar_saldo (
        p_id_pago   in number,
        p_id_compra in number,
        p_monto     in number,
        p_usuario   in varchar2
    );

    -- Recalcula el estado de una compra segun su saldo (lo llama pkg_compras al
    -- registrar o anular una nota de credito o debito).
    procedure prc_recalcular_compra (
        p_id_compra in number
    );

    -- Propuesta de reparto (no escribe nada): FIFO por fecha de emision, sin
    -- pasarse de cada saldo. Devuelve el mismo JSON que come prc_registrar_pago.
    function fn_reparto_sugerido (
        p_id_proveedor in number,
        p_moneda       in varchar2,
        p_tasa         in number,
        p_monto        in number
    ) return varchar2;

    -- Deuda viva del proveedor (suma de saldos pendientes), en la moneda pedida.
    function fn_saldo_proveedor (
        p_id_proveedor in number,
        p_moneda       in varchar2
    ) return number;

    -- Saldo a favor disponible (pagos activos menos lo aplicado), en la moneda pedida.
    function fn_saldo_favor_proveedor (
        p_id_proveedor in number,
        p_moneda       in varchar2
    ) return number;

end pkg_pagos;
/
