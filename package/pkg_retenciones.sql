-- =============================================================================
-- package/pkg_retenciones.sql
--
-- Retencion de IVA de las compras: calculo, numeracion y emision del comprobante.
--
-- Reglas (spec 2026-11-16-libro-compras-ventas, decision 7):
--   * La base imponible son las lineas con IVA mayor que cero. Quedan fuera el
--     exento (0 %) y el IGTF (que es otro impuesto, no IVA).
--   * El IVA causado se lleva a bolivares con la tasa de la linea.
--   * El porcentaje es 75 % para proveedor domiciliado y 100 % para el de otro
--     pais; 0 % desactiva y NO consume numeracion.
--   * El numero es AAAAMM + 8 digitos, consecutivo por empresa y por mes de
--     EMISION; el periodo fiscal de la factura va en su propio campo.
-- =============================================================================

create or replace package pkg_retenciones as

    function fn_aplica(p_id_proveedor in number) return boolean;

    function fn_porcentaje(p_id_proveedor in number) return number;

    function fn_siguiente_numero(p_id_empresa in number, p_fecha in date) return varchar2;

    function fn_base_imponible_bs(p_id_compra in number) return number;

    function fn_iva_causado_bs(p_id_compra in number) return number;

    function fn_retencion_bs(p_id_compra in number) return number;

    procedure prc_emitir(p_id_compra in number, p_id_retencion out number, p_usuario in varchar2);

    procedure prc_anular(p_id_compra in number, p_usuario in varchar2);

end pkg_retenciones;
/
