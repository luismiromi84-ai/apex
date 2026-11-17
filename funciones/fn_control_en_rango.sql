-- =============================================================================
-- fn_control_en_rango.sql
--
-- Valida y normaliza un N° de Control tecleado a mano contra el rango de la
-- providencia SENIAT que la empresa tiene en EMPRESA_FISCAL (CONTROL_DESDE ..
-- CONTROL_HSTA). Sirve para que una factura no pueda llevar un control fuera
-- de rango ni con otra forma.
--
-- Devuelve el control tal como se tecleo (sin espacios sobrantes). Si la
-- empresa no tiene rango configurado no valida nada y lo devuelve igual: el
-- control manual sigue siendo posible.
-- =============================================================================

create or replace function fn_control_en_rango (
    p_id_empresa in number,
    p_control    in varchar2
) return varchar2 is
    v_desde empresa_fiscal.control_desde%type;
    v_hasta empresa_fiscal.control_hasta%type;
    v_pref  varchar2(30);
    v_num   number;
    v_d     number;
    v_h     number;
    v_txt   varchar2(60) := trim(p_control);
begin
    begin
        select control_desde, control_hasta
          into v_desde, v_hasta
          from empresa_fiscal
         where id_empresa = p_id_empresa;
    exception
        when no_data_found then
            return v_txt;
    end;

    if v_desde is null or v_hasta is null or v_txt is null then
        return v_txt;
    end if;

    v_pref := substr(v_desde, 1, length(v_desde) - length(regexp_substr(v_desde, '[0-9]+$')));
    v_d    := to_number(regexp_substr(v_desde, '[0-9]+$'));
    v_h    := to_number(regexp_substr(v_hasta, '[0-9]+$'));

    if nvl(length(v_pref), 0) > 0
       and substr(v_txt, 1, length(v_pref)) <> v_pref then        raise_application_error(-20063,
            'El numero de control debe empezar por ' || v_pref ||
            ' (rango de la providencia: ' || v_desde || ' a ' || v_hasta || ').');
    end if;

    if not regexp_like(substr(v_txt, nvl(length(v_pref), 0) + 1), '^[0-9]+$') then
        raise_application_error(-20063,
            'El numero de control debe tener la forma ' || v_desde || '.');
    end if;

    v_num := to_number(substr(v_txt, nvl(length(v_pref), 0) + 1));

    if v_num < v_d or v_num > v_h then
        raise_application_error(-20063,
            'El numero de control ' || v_txt || ' esta fuera del rango de la providencia ('
            || v_desde || ' a ' || v_hasta || ').');
    end if;

    return v_txt;
end;
/
