-- =============================================================================
-- fn_asignar_control.sql
--
-- Devuelve el siguiente N° de Control de la empresa a partir del rango de la
-- providencia (EMPRESA_FISCAL.CONTROL_DESDE .. CONTROL_HASTA) y lo consume con
-- un contador atomico en FOLIO_CONTADOR (tipo 'CONTROL'), igual que hace
-- fn_asignar_folio con los folios.
--
-- Formato: el prefijo y el ancho salen de CONTROL_DESDE ('00-000001' ->
-- prefijo '00-', ancho 6). Si la empresa no tiene rango configurado devuelve
-- NULL: la factura se queda con el control que se teclee, si lo hay.
-- =============================================================================

create or replace function fn_asignar_control (
    p_id_empresa in number
) return varchar2 is
    v_desde empresa_fiscal.control_desde%type;
    v_hasta empresa_fiscal.control_hasta%type;
    v_pref  varchar2(30);
    v_ancho pls_integer;
    v_d     number;
    v_h     number;
    v_n     number;
begin
    begin
        select control_desde, control_hasta
          into v_desde, v_hasta
          from empresa_fiscal
         where id_empresa = p_id_empresa;
    exception
        when no_data_found then
            return null;
    end;

    if v_desde is null or v_hasta is null then
        return null;
    end if;

    v_ancho := length(regexp_substr(v_desde, '[0-9]+$'));
    v_pref  := substr(v_desde, 1, length(v_desde) - v_ancho);
    v_d     := to_number(regexp_substr(v_desde, '[0-9]+$'));
    v_h     := to_number(regexp_substr(v_hasta, '[0-9]+$'));

    -- Fila del contador: la primera vez arranca en (desde - 1).
    begin
        insert into folio_contador (id_empresa, tipo, ultimo)
        select p_id_empresa, 'CONTROL', v_d - 1
          from dual
         where not exists (select 1 from folio_contador
                            where id_empresa = p_id_empresa and tipo = 'CONTROL');
    exception
        when dup_val_on_index then
            null;   -- otra sesion la creo a la vez
    end;

    update folio_contador set ultimo = ultimo + 1
     where id_empresa = p_id_empresa
       and tipo = 'CONTROL'
     returning ultimo into v_n;

    if v_n > v_h then
        raise_application_error(-20062,
            'El rango de control de la empresa esta agotado: llega hasta ' || v_hasta ||
            '. Actualiza la providencia en Datos fiscales.');
    end if;

    return v_pref || lpad(to_char(v_n), v_ancho, '0');
end;
/
