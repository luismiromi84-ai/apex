-- =============================================================================
-- 20261124_p6_ora01722_verificacion.sql
--
-- El Popup LOV entrega su TEXTO y Oracle no puede convertirlo a numero.
--
-- Lo que reporto el dueno (captura): al abrir «Detalle de Presupuesto» (linea de
-- presupuesto, pagina 6) salio el aviso
--     «No se ha podido convertir el valor de cadena que contiene '-' en un numero:»
-- No era JavaScript: es un ORA-01722 del servidor, en la accion dinamica
-- CARGAR_DATOS_PRODUCTO (peticion PLUGIN), que hacia
--     WHERE p.id_producto_servicio = :P6_ID_PRODUCTO_SERVICIO
-- y recibio el texto del LOV. El log lo dice sin ambiguedad:
--     ORA-03302: (Detalles de ORA-01722) valor de cadena no valido:
--                -- Seleccione Producto/Servicio --
--
-- Casos:
--   L0 ningún ítem guarda el texto del LOV en LOV_NULL_VALUE (era la causa: el valor
--      del ítem pasaba a ser «-- Seleccione ... --»)
--   L1 la accion de la 6 no falla cuando el LOV trae su texto (y devuelve 0 filas)
--   L2 la accion de la 6 sigue trayendo el articulo cuando el id es real
--   L3 los filtros de articulo del Kardex (43) y de Costos (45) no fallan con su texto
--   L4 el JS de la 6 toma el % del impuesto de la opcion ELEGIDA, no de todas
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261124_p6_ora01722_verificacion.sql
-- FALLAS=0 = EXITO. El runner termina con codigo 1 aunque sea verde: se lee el mensaje.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_fallas  number := 0;
    v_lista   varchar2(3000) := '';
    v_n       number;
    v_sql     varchar2(32767);
    v_sql2    varchar2(32767);
    v_js      varchar2(32767);
    v_null6   varchar2(200);
    v_null43  varchar2(200);
    v_art     number;

    procedure falla(p_caso varchar2, p_detalle varchar2) is
    begin
        v_fallas := v_fallas + 1;
        v_lista  := v_lista || ' | ' || p_caso || ': ' || p_detalle;
    end;
begin
    -- ------------------------------------------------------------------ L0
    select count(*) into v_n
      from apex_260100.apex_application_page_items
     where application_id = 100 and lov_null_value is not null;
    if v_n > 0 then
        falla('L0', 'hay ' || v_n || ' items con el texto del LOV en LOV_NULL_VALUE (el item enviaria el texto como valor)');
    end if;

    -- ------------------------------------------------------------------ L1
    select lov_null_text into v_null6
      from apex_260100.apex_application_page_items
     where application_id = 100 and page_id = 6 and item_name = 'P6_ID_PRODUCTO_SERVICIO';

    select json_value(attributes, '$.sql_query') into v_sql
      from apex_260100.apex_application_page_da_acts
     where application_id = 100 and page_id = 6 and dynamic_action_name = 'CARGAR_DATOS_PRODUCTO'
       and json_value(attributes, '$.sql_query') is not null;

    v_sql2 := replace(v_sql, ':F_EMPRESA_ACTIVA', '1');
    v_sql2 := replace(v_sql2, ':P6_ID_PRODUCTO_SERVICIO', '''' || v_null6 || '''');

    begin
        execute immediate 'select count(*) from (' || v_sql2 || ')' into v_n;
        if v_n <> 0 then
            falla('L1', 'con el texto del LOV devuelve ' || v_n || ' filas (se esperaba 0)');
        end if;
    exception
        when others then
            falla('L1', 'el SQL de CARGAR_DATOS_PRODUCTO revienta con el texto del LOV -> ' || sqlerrm);
    end;

    -- ------------------------------------------------------------------ L2
    select min(id_producto_servicio) into v_art
      from producto_servicio
     where id_empresa = 1 and nvl(estado, 'ACTIVO') = 'ACTIVO';

    if v_art is null then
        falla('L2', 'no hay articulos activos en la empresa 1 para probar el camino bueno');
    else
        v_sql2 := replace(v_sql, ':F_EMPRESA_ACTIVA', '1');
        v_sql2 := replace(v_sql2, ':P6_ID_PRODUCTO_SERVICIO', to_char(v_art));
        begin
            execute immediate 'select count(*) from (' || v_sql2 || ')' into v_n;
            if v_n <> 1 then
                falla('L2', 'con el articulo ' || v_art || ' devuelve ' || v_n || ' filas (se esperaba 1)');
            end if;
        exception
            when others then
                falla('L2', 'el camino bueno de la accion falla -> ' || sqlerrm);
        end;
    end if;

    -- ------------------------------------------------------------------ L3
    select lov_null_text into v_null43
      from apex_260100.apex_application_page_items
     where application_id = 100 and page_id = 43 and item_name = 'P43_ID_ARTICULO';

    select region_source into v_sql
      from apex_260100.apex_application_page_regions
     where application_id = 100 and page_id = 43 and region_name = 'Movimientos';
    v_sql := replace(v_sql, ':F_EMPRESA_ACTIVA', '1');
    v_sql := replace(v_sql, ':P43_DESDE', '''01/01/2026''');
    v_sql := replace(v_sql, ':P43_HASTA', '''31/12/2026''');
    v_sql := replace(v_sql, ':P43_TIPO', 'null');
    v_sql := replace(v_sql, ':P43_ID_ARTICULO', '''' || v_null43 || '''');
    begin
        execute immediate 'select count(*) from (' || v_sql || ')' into v_n;
    exception
        when others then
            falla('L3', 'el informe del Kardex (43) revienta con el texto del LOV -> ' || sqlerrm);
    end;

    for r in (select region_name, region_source
                from apex_260100.apex_application_page_regions
               where application_id = 100 and page_id = 45
                 and region_name in ('Costo de ventas del periodo', 'Inventario valorado al corte')) loop
        v_sql := replace(r.region_source, ':F_EMPRESA_ACTIVA', '1');
        v_sql := replace(v_sql, ':P45_DESDE', '''01/01/2026''');
        v_sql := replace(v_sql, ':P45_HASTA', '''31/12/2026''');
        v_sql := replace(v_sql, ':P45_ID_ARTICULO', '''' || v_null43 || '''');
        begin
            execute immediate 'select count(*) from (' || v_sql || ')' into v_n;
        exception
            when others then
                falla('L3', 'el informe «' || r.region_name || '» (45) revienta con el texto del LOV -> ' || sqlerrm);
        end;
    end loop;

    -- ------------------------------------------------------------------ L4
    select javascript_code into v_js
      from apex_260100.apex_application_pages
     where application_id = 100 and page_id = 6;

    if instr(v_js, 'option:selected') = 0 then
        falla('L4', 'el JS de la 6 no lee la opcion ELEGIDA del impuesto');
    end if;
    if instr(v_js, '$wrapper.text()') > 0 then
        falla('L4', 'el JS de la 6 sigue leyendo TODAS las opciones del Select List (deja 16 % en una linea en blanco)');
    end if;

    raise_application_error(-20100,
        substrb('RESULTADO: FALLAS=' || v_fallas || v_lista, 1, 3000));
end;
/
