-- =============================================================================
-- pkg_contabilidad (spec) - contabilidad, fase 2 (2026-11-25)
--
-- Reglas firmadas con el contador (documentacion/CONTABILIDAD_ALCANCE.md):
--   * partida doble: un asiento solo se confirma si debe = haber (-20185)
--   * confirmado = inmutable; se corrige con un reverso (-20182, -20186)
--   * periodo cerrado no admite movimientos; lo que llega tarde va al siguiente periodo
--     abierto (fn_fecha_contable)
--   * cada empresa con su plan de cuentas, copiado de la plantilla de su pais
-- Errores -20180..-20199. Mensajes en ASCII.
-- =============================================================================

create or replace package pkg_contabilidad as

    -- Copia a la empresa la plantilla de su pais (cuentas y mapeo por concepto) y crea una
    -- subcuenta por cada caja o banco. Repetible: solo agrega lo que falta. Devuelve cuantas
    -- cuentas agrego.
    function fn_instalar_plan(p_id_empresa in number, p_usuario in varchar2) return number;

    -- Subcuenta contable de una caja o banco de CUENTAS_FONDOS (la crea si no existe).
    function fn_cuenta_fondo(p_id_cuenta in number, p_usuario in varchar2) return number;

    -- Cuenta asignada a un concepto (CXC, VENTAS, IVA_DEBITO...). -20181 si falta.
    function fn_cuenta(p_id_empresa in number, p_concepto in varchar2) return number;

    -- 'S' si el mes de la fecha esta abierto (un mes sin fila cuenta como abierto).
    function fn_periodo_abierto(p_id_empresa in number, p_fecha in date) return varchar2;

    -- La fecha si su mes esta abierto; si esta cerrado, el primer dia del siguiente mes
    -- abierto (regla del contador para anulaciones y documentos tardios).
    function fn_fecha_contable(p_id_empresa in number, p_fecha in date) return date;

    -- Crea una cuenta bajo su grupo (el grupo padre debe existir) o cambia el nombre y el
    -- estado de una existente. Un codigo que termina en punto es de grupo.
    procedure prc_guardar_cuenta(p_id_empresa in number, p_codigo in varchar2, p_nombre in varchar2,
                                 p_estado in varchar2, p_usuario in varchar2);

    -- Cambia la cuenta de un concepto. Los conceptos GRUPO_* llevan una cuenta de grupo; los
    -- demas, una que acepte movimiento.
    procedure prc_asignar_concepto(p_id_empresa in number, p_concepto in varchar2,
                                   p_id_cuenta_ctb in number, p_usuario in varchar2);

    -- Crea (p_id_asiento nulo) o reemplaza un asiento MANUAL en borrador.
    -- p_lineas: JSON [{"id": id_cuenta_ctb, "debe": 10, "haber": 0, "desc": "..."}, ...]
    procedure prc_guardar_asiento(p_id_asiento in out number,
                                  p_id_empresa in number,
                                  p_fecha      in date,
                                  p_concepto   in varchar2,
                                  p_lineas     in clob,
                                  p_usuario    in varchar2);

    -- Confirma: cuadra, periodo abierto y numero correlativo del mes.
    procedure prc_confirmar(p_id_asiento in number, p_usuario in varchar2);

    -- Reversa un asiento confirmado con otro de lineas invertidas, ya confirmado. Su fecha
    -- es p_fecha (o la del original) llevada al primer mes abierto. Devuelve el id nuevo.
    function fn_reversar(p_id_asiento in number, p_motivo in varchar2,
                         p_usuario in varchar2, p_fecha in date default null) return number;

    -- Borra un asiento en borrador.
    procedure prc_eliminar(p_id_asiento in number, p_usuario in varchar2);

    -- Cierra el mes (sin borradores pendientes) / lo reabre (si no hay uno posterior cerrado).
    procedure prc_cerrar_periodo(p_id_empresa in number, p_anio in number, p_mes in number,
                                 p_usuario in varchar2);
    procedure prc_reabrir_periodo(p_id_empresa in number, p_anio in number, p_mes in number,
                                  p_usuario in varchar2);

    -- Contabiliza el mes (fase 4): genera y confirma los asientos automaticos de las facturas,
    -- notas, cobros, compras, comprobantes de retencion, pagos y kardex con fecha hasta el fin del
    -- mes que aun no los tengan, y reversa los de documentos anulados. Lo que cae en un mes cerrado
    -- va al siguiente mes abierto. Repetible. Un documento que falla se anota y el lote sigue.
    procedure prc_contabilizar_periodo(p_id_empresa in number, p_anio in number, p_mes in number,
                                       p_usuario in varchar2, p_creados out number, p_reversos out number,
                                       p_errores out number, p_detalle out varchar2);

    -- Saldo pendiente de un concepto de pasivo (haber - debe) hasta una fecha.
    function fn_saldo_concepto(p_id_empresa in number, p_concepto in varchar2, p_hasta in date default null) return number;

    -- Cierre anual (fase 5): un asiento al 31/12 que salda los ingresos, costos y gastos del ano
    -- contra RESULTADO_EJERCICIO. Uno por ano (-20192); se rehace reversandolo.
    procedure prc_cierre_anual(p_id_empresa in number, p_anio in number, p_usuario in varchar2,
                               p_id_asiento out number);

    -- Pago al SENIAT de lo retenido o percibido: debita RET_IVA_PROVEEDORES, RET_ISLR_PROVEEDORES o
    -- IGTF_POR_ENTERAR y acredita el banco. No paga mas de lo pendiente a la fecha (-20193).
    procedure prc_pagar_seniat(p_id_empresa in number, p_concepto in varchar2, p_fecha in date,
                               p_id_cuenta in number, p_monto in number, p_referencia in varchar2,
                               p_usuario in varchar2, p_id_asiento out number);

    -- Solo pruebas: borra toda la contabilidad de una empresa del rango de fixtures
    -- (900000..900999), con commit entre pasos (DML paralelo de Autonomous DB, ORA-12839).
    -- Los triggers la dejan pasar mientras corre (fn_purgando).
    procedure prc_purgar_prueba(p_id_empresa in number);
    function fn_purgando return boolean;

end pkg_contabilidad;
/
