-- =============================================================================
-- 20261109_tasa_fecha_referencia.sql
--
-- fn_validar_tasa_documento gana un cuarto parametro opcional:
--   p_fecha_referencia DATE DEFAULT NULL
--
-- Por que: la nota de credito revierte una factura emitida otro dia. Por el
-- principio de correlacion (providencias de facturacion del SENIAT) la nota lleva
-- la tasa y la alicuota de la factura que corrige, no las del dia en que se emite.
-- Con este parametro la validacion compara la tasa contra la tabla TIPO_CAMBIO en
-- la fecha de la factura original.
--
-- Sin el parametro el comportamiento es exactamente el de antes: se compara
-- contra p_fecha. Los presupuestos y las facturas normales no cambian.
--
-- Idempotente: es un create or replace.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

create or replace function fn_validar_tasa_documento (
    p_moneda in varchar2,
    p_fecha  in date,
    p_tasa   in number,
    p_fecha_referencia in date default null
) return number is
    v_moneda varchar2(10) := upper(trim(p_moneda));
    v_fecha  date := nvl(p_fecha, sysdate);
    v_ref    date := nvl(p_fecha_referencia, nvl(p_fecha, sysdate));
    v_tabla  number;
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

begin
  dbms_utility.compile_schema('WKSP_SYPEXWS', false);
end;
/

select count(*) as invalidos from all_objects where owner = 'WKSP_SYPEXWS' and status <> 'VALID'
/
