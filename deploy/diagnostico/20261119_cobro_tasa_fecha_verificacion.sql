-- =============================================================================
-- 20261119_cobro_tasa_fecha_verificacion.sql
--
-- La tasa del cobro (pagina 25) tiene que ser la de la FECHA DEL COBRO y tiene
-- que verse en pantalla. Reportado por el dueno el 2026-11-18: cambio la fecha
-- al 18/11 y la tasa seguia vacia (con el «Neto en bolivares» de la tasa vieja).
--
-- Causas medidas:
--   * las tres acciones dinamicas de calculo NO devolvian P25_TIPO_CAMBIO: el
--     PL/SQL usaba la tasa internamente pero el item se quedaba vacio;
--   * no habia ninguna accion sobre P25_FECHA_COBRO, y las consultas de tasa
--     filtraban por trunc(sysdate): el dia elegido no servia para nada;
--   * P25_FECHA_COBRO se abria vacia (sin defecto) y, en bolivares, la tasa
--     tampoco se ponia en 1.
--
-- Casos:
--   T1 hay accion dinamica sobre el cambio de P25_FECHA_COBRO
--   T2 las cuatro acciones de calculo devuelven P25_TIPO_CAMBIO
--   T3 las acciones resuelven la tasa con la fecha del cobro (fn_tasa_ves)
--   T4 P25_FECHA_COBRO nace con la fecha de hoy
--   T5 el proceso de carga pone tasa 1 cuando el cobro es en bolivares
--   T6 fn_tasa_ves resuelve el 18/11 con la ultima publicada y 1 para VES
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261119_cobro_tasa_fecha_verificacion.sql
-- FALLAS=0 = EXITO (el runner sale con codigo 1 igual: el detalle va en -20100).
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000) := '';
    v_n      number;
    v_src    clob;
    v_ret    varchar2(4000);
    v_tasa   number;
    v_esp    number;

    procedure falla(p_caso varchar2, p_detalle varchar2) is
    begin
        v_fallas := v_fallas + 1;
        v_lista  := v_lista || ' | ' || p_caso || ': ' || p_detalle;
    end;
begin
    -- T1: accion dinamica al cambiar la fecha
    select count(*) into v_n
      from apex_260100.apex_application_page_da
     where application_id = 100 and page_id = 25
       and when_element = 'P25_FECHA_COBRO'
       and when_event_name = 'Change';
    if v_n = 0 then
        falla('T1', 'no hay accion dinamica sobre el cambio de P25_FECHA_COBRO');
    end if;

    -- T2: P25_TIPO_CAMBIO viaja de vuelta en las cuatro acciones de calculo
    select count(*) into v_n
      from apex_260100.apex_application_page_da_acts
     where application_id = 100 and page_id = 25
       and static_id in ('calcula-cobro-factura', 'calcula-cobro-monto',
                         'calcula-cobro-moneda', 'calcula-cobro-fecha')
       and instr(json_value(attributes, '$.items_to_return'), 'P25_TIPO_CAMBIO') > 0;
    if v_n <> 4 then
        falla('T2', 'las acciones que devuelven la tasa son ' || v_n || ' de 4');
    end if;

    -- T3: la tasa se resuelve con la fecha del cobro (fn_tasa_ves) y ya no con la
    -- consulta escrita a mano que filtraba por trunc(sysdate).
    select count(*) into v_n
      from apex_260100.apex_application_page_da_acts
     where application_id = 100 and page_id = 25
       and static_id in ('calcula-cobro-factura', 'calcula-cobro-monto',
                         'calcula-cobro-moneda', 'calcula-cobro-fecha')
       and instr(upper(attributes), 'FN_TASA_VES') > 0
       and instr(upper(attributes), 'P25_FECHA_COBRO') > 0
       and instr(upper(attributes), 'FECHA_VIGENCIA < TRUNC(SYSDATE)') = 0;
    if v_n <> 4 then
        falla('T3', 'las acciones que usan la fecha del cobro son ' || v_n || ' de 4');
    end if;

    -- T4: la fecha del cobro nace con la de hoy
    select count(*) into v_n
      from apex_260100.apex_application_page_items
     where application_id = 100 and page_id = 25
       and item_name = 'P25_FECHA_COBRO'
       and item_default_type = 'SQL_QUERY'
       and instr(upper(item_default), 'SYSDATE') > 0;
    if v_n = 0 then
        falla('T4', 'P25_FECHA_COBRO no tiene por defecto la fecha de hoy');
    end if;

    -- T5: en bolivares la tasa es 1 y tambien se muestra
    select process_source into v_src
      from apex_260100.apex_application_page_proc
     where application_id = 100 and page_id = 25 and static_id = 'sugiere-moneda-cobro';
    if instr(upper(to_char(v_src)), 'FN_TASA_VES') = 0 then
        falla('T5', 'el proceso de carga no resuelve la tasa con fn_tasa_ves');
    end if;
    if instr(upper(to_char(v_src)), '''P25_TIPO_CAMBIO''') = 0 then
        falla('T5', 'el proceso de carga no escribe P25_TIPO_CAMBIO');
    end if;

    -- T6: el 18/11 no tiene fila propia: manda la ultima publicada.
    -- El valor esperado se lee de la TABLA, no se escribe a mano: la tasa del dia
    -- cambia (el 19/11 el 18/11 ya tenia 916,6477 y la prueba fallaba por el
    -- dato, no por la regla).
    begin
        select max(tasa_cambio) keep (dense_rank last order by fecha_vigencia)
          into v_esp
          from tipo_cambio
         where moneda_origen = 'USD' and moneda_destino = 'VES'
           and tipo_tasa = 'REAL'
           and fecha_vigencia <= to_date('18/11/2026', 'DD/MM/YYYY');
    exception
        when no_data_found then v_esp := null;
    end;
    v_tasa := fn_tasa_ves(to_date('18/11/2026', 'DD/MM/YYYY'), 'USD');
    if v_esp is null then
        falla('T6', 'no hay tasa USD->VES publicada hasta el 18/11/2026');
    elsif v_tasa is null or abs(v_tasa - v_esp) > 0.000001 then
        falla('T6', 'fn_tasa_ves al 18/11 devolvio ' || nvl(to_char(v_tasa), '(nulo)')
                    || ' en vez de la ultima publicada (' || v_esp || ')');
    end if;
    if fn_tasa_ves(to_date('18/11/2026', 'DD/MM/YYYY'), 'VES') <> 1 then
        falla('T6', 'fn_tasa_ves en bolivares no devuelve 1');
    end if;

    -- T7: la tasa que se ve es la que se guarda. Con mascara de 2 decimales el
    -- campo enseñaba 915,75 y se guardaba 915,75, mientras los netos se habian
    -- calculado con 915,7476. Las paginas 7 y 9 no llevan mascara.
    select count(*) into v_n
      from apex_260100.apex_application_page_items
     where application_id = 100 and page_id = 25 and item_name = 'P25_TIPO_CAMBIO'
       and (format_mask is null or instr(format_mask, 'D0000') > 0);
    if v_n = 0 then
        falla('T7', 'P25_TIPO_CAMBIO redondea la tasa al mostrarla');
    end if;

    raise_application_error(-20100, substrb('RESULTADO: FALLAS=' || v_fallas || v_lista, 1, 3000));
end;
/
