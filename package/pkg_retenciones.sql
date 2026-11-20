-- =============================================================================
-- package/pkg_retenciones.sql
--
-- Retencion de IVA e ISLR de las compras: calculo, numeracion y emision del
-- comprobante.
--
-- Reglas de IVA (spec 2026-11-16-libro-compras-ventas, decision 7):
--   * La base imponible son las lineas con IVA mayor que cero. Quedan fuera el
--     exento (0 %) y el IGTF (que es otro impuesto, no IVA).
--   * El IVA causado se lleva a bolivares con la tasa de la linea.
--   * El porcentaje es 75 % para proveedor domiciliado y 100 % para el de otro
--     pais; 0 % desactiva y NO consume numeracion.
--   * El numero es AAAAMM + 8 digitos, consecutivo por empresa y por mes de
--     EMISION; el periodo fiscal de la factura va en su propio campo.
--
-- Reglas de ISLR (spec 2026-11-19-retenciones-iva-islr, seccion 7.2):
--   * La base es el SUBTOTAL del documento (sin IVA y sin IGTF) llevado a
--     bolivares con la tasa del documento, por el BASE_PCT del concepto.
--   * retenido = base x tarifa / 100 - sustraendo_ut x UT, y 0 si da negativo.
--   * La UT sale de SYN_PARAMETROS.UT_ISLR (43,00 desde 2025); no esta clavada
--     en el codigo porque cuando el SENIAT la reajusta se edita ahi.
--
-- Emision (tarea 5 del spec): prc_emitir escribe la CABECERA en RETENCIONES con
-- una LINEA por alicuota en RETENCIONES_DET, y prc_emitir_islr escribe el segundo
-- comprobante. Los dos guardan en la linea la foto del calculo; la cabecera lleva
-- la suma de las lineas. Solo las FACTURAS emiten: la puerta la cierra
-- pkg_compras.prc_registrar_compra.
-- =============================================================================

create or replace package pkg_retenciones as

    function fn_aplica(p_id_proveedor in number) return boolean;

    function fn_porcentaje(p_id_proveedor in number) return number;

    function fn_siguiente_numero(p_id_empresa in number, p_fecha in date) return varchar2;

    function fn_base_imponible_bs(p_id_compra in number) return number;

    function fn_iva_causado_bs(p_id_compra in number) return number;

    function fn_retencion_bs(p_id_compra in number) return number;

    -- Valor de la unidad tributaria vigente, en bolivares (43 si el parametro
    -- falta o no es un numero).
    function fn_valor_ut return number;

    -- Base del ISLR en bolivares: subtotal del documento x base_pct / 100 x tasa.
    -- Devuelve 0 si la compra o el concepto no existen (la pantalla la llama
    -- antes de que la compra tenga concepto elegido).
    function fn_islr_base_bs(p_id_compra in number, p_id_concepto in number) return number;

    -- Sustraendo del concepto en bolivares (sustraendo_ut x UT, redondeado a 2).
    -- Es el mismo numero que resta fn_islr_retencion_bs, para que la emision del
    -- comprobante lo guarde en la linea sin recalcularlo por su cuenta.
    function fn_islr_sustraendo_bs(p_id_concepto in number) return number;

    -- ISLR retenido en bolivares, con el piso en 0.
    function fn_islr_retencion_bs(p_id_compra in number, p_id_concepto in number) return number;

    procedure prc_emitir(p_id_compra in number, p_id_retencion out number, p_usuario in varchar2);

    -- Comprobante de ISLR de la compra, con una linea que guarda la foto del
    -- calculo. NO emite ni consume numero si la compra no tiene concepto de ISLR o
    -- si el retenido es 0 (por debajo del sustraendo).
    procedure prc_emitir_islr(p_id_compra in number, p_id_retencion out number, p_usuario in varchar2);

    -- Anula los comprobantes de la compra (los dos tipos), conservando su numero.
    procedure prc_anular(p_id_compra in number, p_usuario in varchar2);

end pkg_retenciones;
/
