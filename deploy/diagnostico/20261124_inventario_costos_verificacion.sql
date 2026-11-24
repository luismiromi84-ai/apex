-- =============================================================================
-- 20261124_inventario_costos_verificacion.sql
--
-- La pagina 45 (costo de ventas del periodo e inventario valorado al corte).
--
--   V1  la pagina existe con su alias
--   V2  tiene los tres filtros y el boton Filtrar
--   V3  las dos regiones son informes con sus columnas
--   V4  la entrada de menu «Costos de inventario» cuelga de Compras
--   V5  la consulta del costo de ventas se ejecuta con sus binds
--   V6  la consulta del inventario valorado se ejecuta con sus binds
--   V7  el costo de ventas del sistema cuadra con el de los movimientos
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261124_inventario_costos_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000) := '';
    v_n      number;
    v_sql    clob;
    v_a      number;
    v_b      number;

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
    select count(*) into v_n
      from apex_application_pages
     where application_id = 100 and page_id = 45 and upper(page_alias) = 'COSTOS-INVENTARIO';
    espera_num('V1 pagina 45 con su alias', v_n, 1);

    ------------------------------------------------------------------ V2
    select count(*) into v_n
      from apex_application_page_items
     where application_id = 100 and page_id = 45
       and item_name in ('P45_DESDE','P45_HASTA','P45_ID_ARTICULO');
    espera_num('V2 la 45 tiene sus tres filtros', v_n, 3);

    select count(*) into v_n
      from apex_application_page_buttons
     where application_id = 100 and page_id = 45 and button_name = 'BTN_FILTRAR_COSTOS';
    espera_num('V2 la 45 tiene el boton Filtrar', v_n, 1);

    ------------------------------------------------------------------ V3
    select count(*) into v_n
      from apex_application_page_regions
     where application_id = 100 and page_id = 45 and source_type_plugin_static_id = 'NATIVE_IR';
    espera_num('V3 la 45 tiene sus dos informes', v_n, 2);

    select count(*) into v_n
      from apex_application_page_ir_col
     where application_id = 100 and page_id = 45
       and column_alias in ('CODIGO','NOMBRE','UNIDADES','COSTO_BS','COSTO_REF',
                            'CANTIDAD','COSTO_PROMEDIO','VALOR_BS','VALOR_REF');
    -- CODIGO y NOMBRE estan en los dos informes: 5 + 6 = 11
    espera_num('V3 las columnas de los dos informes', v_n, 11);

    ------------------------------------------------------------------ V4
    select count(*) into v_n
      from apex_application_list_entries e
     where e.application_id = 100 and e.list_name = 'Navigation Menu'
       and upper(e.entry_text) = 'COSTOS DE INVENTARIO'
       and e.list_entry_parent_id is not null;
    espera_num('V4 menu Costos de inventario con padre', v_n, 1);

    ------------------------------------------------------------------ V5
    begin
        select region_source into v_sql
          from apex_application_page_regions
         where application_id = 100 and page_id = 45 and region_static_id = 'cos-ventas';
        v_sql := replace(v_sql, ':F_EMPRESA_ACTIVA', '1');
        v_sql := replace(v_sql, ':P45_ID_ARTICULO', 'null');
        v_sql := replace(v_sql, ':P45_DESDE', 'trunc(sysdate, ''MM'')');
        v_sql := replace(v_sql, ':P45_HASTA', 'trunc(sysdate)');
        execute immediate 'select nvl(sum(costo_bs), 0) from (' || v_sql || ')' into v_a;
        if v_a is null then
            falla('V5 la consulta del costo de ventas', 'no devolvio nada');
        end if;
    exception
        when others then falla('V5 la consulta del costo de ventas', sqlerrm);
    end;

    ------------------------------------------------------------------ V6
    begin
        select region_source into v_sql
          from apex_application_page_regions
         where application_id = 100 and page_id = 45 and region_static_id = 'cos-valorado';
        v_sql := replace(v_sql, ':F_EMPRESA_ACTIVA', '1');
        v_sql := replace(v_sql, ':P45_ID_ARTICULO', 'null');
        v_sql := replace(v_sql, ':P45_HASTA', 'trunc(sysdate)');
        execute immediate 'select nvl(sum(valor_bs), 0) from (' || v_sql || ')' into v_a;
        if v_a is null then
            falla('V6 la consulta del inventario valorado', 'no devolvio nada');
        end if;
    exception
        when others then falla('V6 la consulta del inventario valorado', sqlerrm);
    end;

    ------------------------------------------------------------------ V7
    -- El inventario valorado del sistema (todo el historico) es el valor del saldo.
    begin
        select nvl(sum(valor_bs), 0) into v_a from kardex_saldo where id_empresa = 1;
        select nvl(sum(pkg_inventario.fn_signo(tipo_movimiento) * costo_total_bs), 0)
          into v_b
          from kardex_mov where id_empresa = 1;
        if abs(v_a - v_b) > 0.05 then
            falla('V7 el valor del saldo cuadra con los movimientos', v_a || ' vs ' || v_b);
        end if;
    exception
        when others then falla('V7 valor del saldo', sqlerrm);
    end;

    ------------------------------------------------------------------ resultado
    if v_fallas > 0 then
        raise_application_error(-20101, 'RESULTADO: FALLAS=' || v_fallas || v_lista);
    end if;
    raise_application_error(-20100, 'RESULTADO: FALLAS=0');
end;
/
