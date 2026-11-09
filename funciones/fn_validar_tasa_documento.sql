-- =============================================================================
-- fn_validar_tasa_documento.sql
--
-- Valida y normaliza el tipo de cambio de un documento (presupuesto o factura)
-- antes de guardarlo. Devuelve la tasa que hay que guardar.
--
-- La tasa se guarda, como en todo el sistema, en BOLIVARES POR UNIDAD de la
-- moneda del documento: USD->VES 896,12 · MXN->VES 47,91 · VES = 1. NO es un
-- factor a dolares. De ahi salieron los 29 presupuestos y 23 facturas en USD con
-- tipo_cambio = 1 que hubo que recalcular el 2026-11-06.
--
-- Reglas:
--   * VES/BS: devuelve 1. La tasa no se pregunta.
--   * Moneda extranjera sin tasa (nula o <= 0): lanza -20061 y, si la tabla la
--     tiene, dice cual es la del dia.
--   * Moneda extranjera con tasa 1: lanza -20061. Un 1 deja los montos en
--     bolivares iguales a los de la moneda y es siempre un error de tecleo.
--   * Moneda extranjera con tasa fuera de 0,5x a 2x de la de la tabla: lanza
--     -20061. Atrapa el caso tipico de usar la tasa de otra moneda (la de USD en
--     un documento en MXN, por ejemplo). Si la tabla no tiene tasa para esa
--     fecha no se compara: solo se exige que sea mayor que cero.
--
-- Ojo: por eso hay que llamarla despues de resolver la tasa (si el usuario dejo
-- la casilla vacia en una edicion, primero se toma la que ya tenia el documento).
--
-- p_fecha_referencia (2026-11-09): las notas de credito revierten una factura
-- emitida otro dia y llevan la tasa de ESA factura. Con el parametro, la
-- comparacion contra TIPO_CAMBIO se hace con la fecha de la factura original.
-- Sin el, el comportamiento es el de siempre (se compara contra p_fecha).
-- =============================================================================

create or replace function fn_validar_tasa_documento (
    p_moneda in varchar2,
    p_fecha  in date,
    p_tasa   in number,
    -- Fecha contra la que se compara la tasa de la tabla. Sirve para las notas de
    -- credito: la nota revierte una factura emitida otro dia y tiene que llevar la
    -- tasa de ESA factura, no la de hoy. Sin el parametro se usa p_fecha.
    p_fecha_referencia in date default null
) return number is
    v_moneda varchar2(10) := upper(trim(p_moneda));
    v_fecha  date := nvl(p_fecha, sysdate);
    v_ref    date := nvl(p_fecha_referencia, nvl(p_fecha, sysdate));
    v_tabla  number;
    -- Formato de la tasa en los mensajes: punto decimal, independiente del NLS.
    v_fmt    constant varchar2(40) := 'FM999G999G990D999999';
    v_nls    constant varchar2(40) := 'NLS_NUMERIC_CHARACTERS=''.,''';
begin
    if v_moneda is null or v_moneda in ('VES', 'BS') then
        return 1;
    end if;

    v_tabla := fn_tasa_ves(v_ref, v_moneda);

    if p_tasa is null or p_tasa <= 0 then
        raise_application_error(-20061,
            'Falta el tipo de cambio de un documento en ' || v_moneda || '.'
            || case
                 when v_tabla is not null then
                      ' La tasa del ' || to_char(v_ref, 'DD/MM/YYYY') || ' es '
                      || to_char(v_tabla, v_fmt, v_nls) || ' bolivares por ' || v_moneda || '.'
                 else ''
               end
            || ' Sin tasa no se puede calcular el equivalente en bolivares.');
    end if;

    if p_tasa = 1 then
        raise_application_error(-20061,
            'El tipo de cambio de un documento en ' || v_moneda
            || ' no puede ser 1: se guarda en bolivares por unidad. Con 1 los montos en '
            || 'bolivares quedarian iguales a los de ' || v_moneda || '.');
    end if;

    if v_tabla is not null and (p_tasa < v_tabla * 0.5 or p_tasa > v_tabla * 2) then
        raise_application_error(-20061,
            'El tipo de cambio ' || to_char(p_tasa, v_fmt, v_nls)
            || ' no cuadra con la tasa del ' || to_char(v_ref, 'DD/MM/YYYY')
            || ' (' || to_char(v_tabla, v_fmt, v_nls) || ' bolivares por ' || v_moneda
            || '). Revisa la moneda y la tasa.');
    end if;

    return p_tasa;
end fn_validar_tasa_documento;
/
