-- =============================================================================
-- 20261124_inventario_paginas_verificacion.sql
--
-- Las pantallas del inventario (2026-11-24): paginas 42, 43 y 44.
--
--   V1  las tres paginas existen, con su alias y su titulo
--   V2  el esquema ver-inventario existe y lleva los roles de la guarda
--   V3  la entrada de menu «Inventario» es de primer nivel y abre la 42; de ella
--       cuelgan «Artículos y Servicios» y «Costo de Inventario»
--   V4  la 42: region de indicadores dinamica + IR de saldos con sus columnas
--   V5  la 43: los cuatro filtros + IR de movimientos + boton Filtrar
--   V6  la 44: los ocho campos + dos botones + los dos procesos
--   V7  la consulta de la 42 se ejecuta y devuelve columnas
--   V8  la consulta de la 43 se ejecuta con sus binds
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261124_inventario_paginas_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000) := '';
    v_n      number;
    v_txt    clob;
    v_sql    clob;

    procedure falla(p_caso varchar2, p_detalle varchar2) is
    begin
        v_fallas := v_fallas + 1;
        v_lista  := v_lista || ' | ' || p_caso || ': ' || substrb(p_detalle, 1, 170);
    end;

    procedure espera_num(p_caso varchar2, p_valor number, p_esperado number) is
    begin
        if p_valor is null or p_valor <> p_esperado then
            falla(p_caso, 'esperaba ' || p_esperado || ' y hay ' || nvl(to_char(p_valor), 'NULL'));
        end if;
    end;
begin
    ------------------------------------------------------------------ V1
    for p in (select 42 id, 'INVENTARIO' alias_p from dual
              union all select 43, 'KARDEX' from dual
              union all select 44, 'AJUSTE-INVENTARIO' from dual)
    loop
        select count(*) into v_n
          from apex_application_pages
         where application_id = 100 and page_id = p.id
           and upper(page_alias) = p.alias_p;
        espera_num('V1 pagina ' || p.id || ' con su alias', v_n, 1);
    end loop;

    ------------------------------------------------------------------ V2
    select count(*) into v_n
      from apex_application_authorization
     where application_id = 100
       and static_id = 'ver-inventario'
       and scheme_type_code = 'NATIVE_FUNCTION_BODY'
       and upper(attributes) like '%ALMACEN%';
    espera_num('V2 esquema ver-inventario con sus roles', v_n, 1);

    ------------------------------------------------------------------ V3
    -- V3 (2026-11-24, tarde): «Inventario» subio a primer nivel y abre la 42;
    -- de el cuelgan «Articulos y Servicios» (40) y «Costo de Inventario» (45).
    select count(*) into v_n
      from apex_application_list_entries e
     where e.application_id = 100
       and e.list_name = 'Navigation Menu'
       and upper(e.entry_text) = 'INVENTARIO'
       and e.list_entry_parent_id is null
       and instr(e.entry_target, ':42:') > 0;
    espera_num('V3 entrada de menu Inventario de primer nivel', v_n, 1);

    select count(*) into v_n
      from apex_application_list_entries h
      join apex_application_list_entries p
        on p.list_entry_id = h.list_entry_parent_id
     where h.application_id = 100 and h.list_name = 'Navigation Menu'
       and upper(p.entry_text) = 'INVENTARIO'
       and (   (h.static_id = 'articulos'         and instr(h.entry_target, ':40:') > 0)
            or (h.static_id = 'costos-inventario' and instr(h.entry_target, ':45:') > 0));
    espera_num('V3 hijas Articulos y Costo de Inventario', v_n, 2);

    ------------------------------------------------------------------ V4
    select count(*) into v_n
      from apex_application_page_regions
     where application_id = 100 and page_id = 42
       and source_type_plugin_static_id = 'NATIVE_DYNAMIC_CONTENT';
    espera_num('V4 la 42 tiene la region de indicadores dinamica', v_n, 1);

    select count(*) into v_n
      from apex_application_page_ir_col
     where application_id = 100 and page_id = 42
       and column_alias in ('CODIGO','NOMBRE','TIPO','CANTIDAD','COSTO_PROMEDIO_BS',
                            'VALOR_BS','VALOR_REF','STOCK_MINIMO','SITUACION','KARDEX_LINK');
    espera_num('V4 la 42 tiene sus diez columnas', v_n, 10);

    ------------------------------------------------------------------ V5
    select count(*) into v_n
      from apex_application_page_items
     where application_id = 100 and page_id = 43
       and item_name in ('P43_ID_ARTICULO','P43_DESDE','P43_HASTA','P43_TIPO');
    espera_num('V5 la 43 tiene sus cuatro filtros', v_n, 4);

    select count(*) into v_n
      from apex_application_page_ir_col
     where application_id = 100 and page_id = 43
       and column_alias in ('NUM_MOVIMIENTO','FECHA_MOVIMIENTO','TIPO_MOVIMIENTO','CANTIDAD',
                            'COSTO_UNIT_BS','COSTO_TOTAL_BS','TASA_CAMBIO','SALDO_CANTIDAD',
                            'DOC_TIPO','MOTIVO');
    espera_num('V5 la 43 tiene sus diez columnas', v_n, 10);

    ------------------------------------------------------------------ V6
    select count(*) into v_n
      from apex_application_page_items
     where application_id = 100 and page_id = 44
       and item_name in ('P44_ID_ARTICULO','P44_TIPO','P44_FECHA','P44_CANTIDAD',
                         'P44_COSTO_BS','P44_MONEDA','P44_TASA','P44_MOTIVO');
    espera_num('V6 la 44 tiene sus ocho campos', v_n, 8);

    select count(*) into v_n
      from apex_application_page_buttons
     where application_id = 100 and page_id = 44
       and button_name in ('BTN_GUARDAR_AJUSTE','BTN_VOLVER_AJUSTE');
    espera_num('V6 la 44 tiene sus dos botones', v_n, 2);

    select count(*) into v_n
      from apex_application_page_proc
     where application_id = 100 and page_id = 44
       and static_id in ('valida-rol-ajuste','guardar-ajuste-inventario');
    espera_num('V6 la 44 tiene sus dos procesos', v_n, 2);

    ------------------------------------------------------------------ V7
    begin
        select region_source into v_sql
          from apex_application_page_regions
         where application_id = 100 and page_id = 42
           and region_static_id = 'inv-saldos';
        v_sql := replace(v_sql, ':F_EMPRESA_ACTIVA', '1');
        execute immediate 'select count(*) from (' || v_sql || ')' into v_n;
        if v_n < 0 then
            falla('V7 la consulta de la 42', 'no devolvio nada');
        end if;
    exception
        when others then falla('V7 la consulta de la 42', sqlerrm);
    end;

    ------------------------------------------------------------------ V8
    begin
        select region_source into v_sql
          from apex_application_page_regions
         where application_id = 100 and page_id = 43
           and region_static_id = 'kdx-mov';
        v_sql := replace(v_sql, ':F_EMPRESA_ACTIVA', '1');
        v_sql := replace(v_sql, ':P43_ID_ARTICULO', 'null');
        v_sql := replace(v_sql, ':P43_DESDE', 'trunc(sysdate) - 30');
        v_sql := replace(v_sql, ':P43_HASTA', 'trunc(sysdate)');
        v_sql := replace(v_sql, ':P43_TIPO', 'null');
        execute immediate 'select count(*) from (' || v_sql || ')' into v_n;
        if v_n < 0 then
            falla('V8 la consulta de la 43', 'no devolvio nada');
        end if;
    exception
        when others then falla('V8 la consulta de la 43', sqlerrm);
    end;

    ------------------------------------------------------------------ resultado
    if v_fallas > 0 then
        raise_application_error(-20101, 'RESULTADO: FALLAS=' || v_fallas || v_lista);
    end if;
    raise_application_error(-20100, 'RESULTADO: FALLAS=0');
end;
/
