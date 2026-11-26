-- =============================================================================
-- pkg_cobros.sql (especificacion)
--
-- Cobros de las facturas (2026-11-17). Un recibo es un cobro: puede ser el total
-- o un abono. El saldo lo lleva fn_saldo_factura, no se guarda.
--
-- El IGTF se calcula aqui, no en la factura: solo si la empresa es SPE y el cobro
-- es en moneda extranjera, sobre la parte cobrada (nunca sobre el total de la
-- factura) y con la alicuota configurada en IMPUESTOS.
--
-- El IGTF no es ingreso: MONTO_NETO es el dinero que entra al banco y el IGTF se
-- guarda aparte (impuesto por enterar).
-- =============================================================================

create or replace package pkg_cobros as

    -- Lo que la pantalla propone antes de guardar: el 3 % (o lo que diga la
    -- configuracion) del monto si el cobro es en divisas y la empresa es SPE.
    function fn_igtf_sugerido (
        p_id_factura in number,
        p_cod_moneda in varchar2,
        p_monto      in number
    ) return number;

    -- Lo que la pantalla propone como retencion de IVA: el porcentaje de la
    -- factura prorrateado a la parte que se esta cobrando. p_cod_moneda es la
    -- moneda del cobro: el monto se lleva antes a la moneda de la factura.
    function fn_retencion_sugerida (
        p_id_factura in number,
        p_monto      in number,
        p_cod_moneda in varchar2 default null
    ) return number;

    -- Registra un cobro. p_tasa es bolivares por unidad de la moneda del cobro;
    -- si no llega se toma la del dia. p_aplica_igtf permite forzar S/N (para los
    -- pagos en divisas que la ley exceptua); si llega nulo se decide solo.
    procedure prc_registrar_cobro (
        p_id_factura     in  number,
        p_fecha          in  date,
        p_id_forma_pago  in  number,
        p_cod_moneda     in  varchar2,
        p_monto          in  number,
        p_tasa           in  number   default null,
        p_retencion_iva_bs in number default 0,
        p_nro_comprobante  in varchar2 default null,
        p_referencia     in  varchar2 default null,
        p_aplica_igtf    in  varchar2 default null,
        p_usuario        in  varchar2,
        p_id_recibo      out number,
        p_id_cuenta      in  number   default null   -- caja/banco destino (2026-11-25)
    );

    -- Anula un cobro (no se borra: queda el rastro) y devuelve la factura a
    -- TIMBRADA o PARCIAL segun lo que quede cobrado.
    procedure prc_anular_cobro (
        p_id_recibo in number,
        p_usuario   in varchar2
    );

    -- Marca el cobro como conciliado con el ingreso bancario.
    procedure prc_conciliar (
        p_id_recibo   in number,
        p_referencia  in varchar2,
        p_usuario     in varchar2 default null
    );

end pkg_cobros;
/
