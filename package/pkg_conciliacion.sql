-- =============================================================================
-- pkg_conciliacion (spec) - conciliacion bancaria (2026-11-25)
--
-- Errores: -20170 ya hay una conciliacion abierta para la cuenta ·
--          -20171 periodo invalido o que pisa un cierre anterior ·
--          -20172 la diferencia con el banco no es cero ·
--          -20173 cuenta o conciliacion de otra empresa / inexistente ·
--          -20174 la conciliacion no esta ABIERTA.
-- =============================================================================

create or replace package pkg_conciliacion as

    -- Importe de un movimiento expresado en la moneda de la cuenta.
    function fn_importe(p_monto in number, p_moneda in varchar2, p_tc in number,
                        p_fecha in date, p_moneda_cuenta in varchar2) return number;

    -- Abre la conciliacion de una cuenta para un periodo. El saldo inicial es el
    -- saldo segun el banco del ultimo cierre de esa cuenta (0 si es la primera).
    function fn_abrir(p_id_cuenta in number, p_desde in date, p_hasta in date,
                      p_usuario in varchar2) return number;

    -- Marca o desmarca movimientos: JSON [{"t":"R"|"P","id":n,"ok":1|0}, ...].
    -- R = cobro (recibo, entrada), P = pago (salida).
    procedure prc_marcar(p_id_conciliacion in number, p_json in clob, p_usuario in varchar2);

    -- Saldo segun el sistema: saldo inicial + entradas marcadas - salidas marcadas.
    function fn_saldo_sistema(p_id_conciliacion in number) return number;

    -- Cierra si el saldo segun el banco cuadra con el del sistema (diferencia 0).
    procedure prc_cerrar(p_id_conciliacion in number, p_saldo_banco in number, p_usuario in varchar2);

    -- Anula una conciliacion abierta y desmarca sus movimientos.
    procedure prc_anular(p_id_conciliacion in number, p_usuario in varchar2);

end pkg_conciliacion;
/
