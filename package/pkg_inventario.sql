-- =============================================================================
-- PKG_INVENTARIO — el unico escritor del kardex (2026-11-24)
--
-- Reglas que manda el diseno (documentacion/docs/superpowers/specs/
-- 2026-11-23-inventario-kardex-design.md):
--   * El movimiento es inmutable; se revierte con otro movimiento.
--   * El costo promedio ponderado (CPP) se aplica en la SALIDA y se congela.
--   * Doble valoracion: bolivares a la tasa del documento y la divisa a esa
--     misma tasa.
--   * No hace COMMIT: manda el documento que llama.
-- =============================================================================

create or replace package pkg_inventario as

    -- +1 si el tipo suma cantidad, -1 si la resta.
    function fn_signo(p_tipo in varchar2) return number;

    -- Cuanto hay y a que costo. 0 si el articulo no tiene saldo.
    function fn_disponible(p_id_empresa in number, p_id_producto in number) return number;
    function fn_cpp_bs(p_id_empresa in number, p_id_producto in number) return number;

    -- Si el documento (o una de sus lineas) ya movio inventario: el documento se
    -- mueve una vez y cada linea genera su propio movimiento.
    function fn_tiene_movimiento(p_doc_tipo in varchar2, p_id_doc in number,
                                 p_id_detalle in number default null) return boolean;

    -- Cuelga del documento: la compra registrada (o su nota) y la factura emitida
    -- (o su nota). Lo llaman pkg_compras y pkg_facturacion.
    procedure prc_desde_compra(p_id_compra in number, p_usuario in varchar2);
    procedure prc_desde_factura(p_id_factura in number, p_usuario in varchar2);

    -- Devuelve el documento a como estaba antes de mover inventario, con
    -- movimientos de reversa numerados (nunca borra). Idempotente.
    procedure prc_reversar(p_doc_tipo in varchar2, p_id_doc in number,
                           p_motivo in varchar2, p_usuario in varchar2);

    -- Ajuste manual y carga inicial del stock. El motivo es obligatorio y el
    -- SALDO_INICIAL solo se admite una vez por articulo (mientras no tenga
    -- movimientos).
    procedure prc_ajuste(p_id_empresa in number, p_id_producto in number, p_fecha in date,
                         p_tipo in varchar2, p_cantidad in number, p_costo_unit_bs in number,
                         p_moneda in varchar2, p_tasa in number, p_motivo in varchar2,
                         p_usuario in varchar2);

    -- El unico insert del kardex. p_costo_unit_bs nulo en una salida = CPP.
    procedure prc_movimiento(
        p_id_empresa    in number,
        p_id_producto   in number,
        p_fecha         in date,
        p_tipo          in varchar2,
        p_cantidad      in number,
        p_costo_unit_bs in number,
        p_tasa          in number,
        p_moneda        in varchar2,
        p_doc_tipo      in varchar2,
        p_id_doc        in number,
        p_id_detalle    in number,
        p_motivo        in varchar2,
        p_usuario       in varchar2,
        p_id_movimiento out number);

end pkg_inventario;
/
