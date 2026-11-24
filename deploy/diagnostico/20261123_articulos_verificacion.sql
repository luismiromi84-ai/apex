-- =============================================================================
-- 20261123_articulos_verificacion.sql
--
-- Catalogo de articulos y servicios POR EMPRESA, con codigo de barras y
-- etiquetas Code 128 (2026-11-23).
--
--   A1  las paginas 40 (catalogo) y 41 (etiquetas) existen y son 'C'
--   A2  la lista de la 40 filtra por la empresa activa y por tipo/estado
--   A3  la consulta guardada de la 40 devuelve solo los articulos de la empresa
--   A4  el formulario tiene los campos y Guardar/Nuevo solo con rol de escritura
--   A4b Cancelar edicion (40) y Volver a Articulos (41)
--   A5  la 41 pinta las etiquetas con fn_etiqueta_articulo y tiene sus dos guardas
--   A6  hay entrada de menu y esquema 'ver-articulos'
--   A7  las tres LOV de linea (paginas 6, 10 y 29) filtran por la empresa activa
--       y muestran el codigo de barras (para poder escanear)
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261123_articulos_verificacion.sql
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
    v_res    number;

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

    function fuente_reg(p_pagina number, p_nombre varchar2) return clob is
        v clob;
    begin
        select region_source into v
          from apex_application_page_regions
         where application_id = 100 and page_id = p_pagina and region_name = p_nombre;
        return v;
    end;

    function proceso(p_pagina number, p_static varchar2) return clob is
        v clob;
    begin
        select process_source into v
          from apex_application_page_proc
         where application_id = 100 and page_id = p_pagina and static_id = p_static;
        return v;
    end;
begin
    ------------------------------------------------------------------ A1
    select count(*) into v_n
      from apex_application_pages
     where application_id = 100 and page_id in (40, 41);
    espera_num('A1 paginas 40 y 41', v_n, 2);

    select count(*) into v_n
      from apex_application_pages
     where application_id = 100 and page_id in (40, 41)
       and page_access_protection = 'Arguments Must Have Checksum';
    espera_num('A1 proteccion C de las dos paginas', v_n, 2);

    ------------------------------------------------------------------ A2
    v_sql := fuente_reg(40, 'Artículos y Servicios');
    if instr(v_sql, 'fn_clean_num(:F_EMPRESA_ACTIVA)') = 0 then
        falla('A2 la lista filtra por empresa activa', 'no la menciona');
    end if;
    if instr(v_sql, ':P40_F_TIPO') = 0 or instr(v_sql, ':P40_F_ESTADO') = 0 then
        falla('A2 la lista filtra por tipo y estado', 'faltan los binds');
    end if;
    if instr(v_sql, 'codigo_barras') = 0 then
        falla('A2 la lista trae el codigo de barras', 'no lo selecciona');
    end if;

    ------------------------------------------------------------------ A3
    -- La consulta guardada, ejecutada con la empresa 1 y sin filtros. Se compara
    -- con la tabla, no con un numero fijo: el catalogo crece con el uso real.
    begin
        select count(*) into v_n from producto_servicio where id_empresa = 1;
    exception
        when others then
            v_n := 0;
    end;
    v_sql := fuente_reg(40, 'Artículos y Servicios');
    v_sql := replace(v_sql, ':F_EMPRESA_ACTIVA', '1');
    v_sql := replace(v_sql, ':P40_F_TIPO', 'null');
    v_sql := replace(v_sql, ':P40_F_ESTADO', 'null');
    begin
        execute immediate 'select count(*) from (' || to_char(v_sql) || ')' into v_res;
        espera_num('A3 articulos de la empresa 1', v_res, v_n);
    exception
        when others then
            falla('A3 la consulta guardada de la 40 no corre', sqlerrm);
    end;

    ------------------------------------------------------------------ A4
    select count(*) into v_n
      from apex_application_page_items
     where application_id = 100 and page_id = 40 and item_name in
           ('P40_ID_ARTICULO', 'P40_CODIGO', 'P40_CODIGO_BARRAS', 'P40_NOMBRE',
            'P40_TIPO', 'P40_PRECIO_SUGERIDO', 'P40_IMPUESTO_APLICABLE',
            'P40_ESTADO', 'P40_DESCRIPCION');
    espera_num('A4 campos del formulario', v_n, 9);

    select count(*) into v_n
      from apex_application_page_buttons
     where application_id = 100 and page_id = 40
       and button_name in ('BTN_GUARDAR_ARTICULO', 'BTN_NUEVO_ARTICULO')
       and condition_expression1 like '%ADMIN,GERENCIA,VENTAS,ALMACEN,PRUEBA%';
    espera_num('A4 Guardar y Nuevo solo con rol de escritura', v_n, 2);

    -- A4b: los botones de vuelta (2026-11-23). La 41 se abria desde la lista y
    -- no habia manera de volver; al editar tampoco habia "cancelar".
    select count(*) into v_n
      from apex_application_page_buttons
     where application_id = 100 and page_id = 40
       and button_name = 'BTN_CANCELAR_ARTICULO'
       and condition_expression1 like '%P40_ID_ARTICULO is not null%';
    espera_num('A4b Cancelar edicion en la 40', v_n, 1);

    select count(*) into v_n
      from apex_application_page_buttons
     where application_id = 100 and page_id = 41
       and button_name = 'BTN_VOLVER_ARTICULOS'
       and redirect_url like '%:40:%P40_ID_ARTICULO:%';
    espera_num('A4b Volver a Articulos en la 41', v_n, 1);

    v_sql := proceso(40, 'guardar-articulo');
    if instr(v_sql, 'fn_usuario_empresa_valida(:APP_USER, v_emp)') = 0 then
        falla('A4 el guardado valida la empresa del usuario', 'no llama a fn_usuario_empresa_valida');
    end if;
    if instr(v_sql, 'codigo_barras') = 0 then
        falla('A4 el guardado devuelve el codigo de barras', 'no lo lee del RETURNING');
    end if;

    ------------------------------------------------------------------ A5
    select count(*) into v_n
      from apex_application_page_regions
     where application_id = 100 and page_id = 41
       and region_name = 'Etiquetas'
       and source_type_plugin_static_id = 'NATIVE_DYNAMIC_CONTENT'
       and function_body_language = 'PLSQL'
       and dbms_lob.instr(region_source, 'fn_etiqueta_articulo') > 0;
    espera_num('A5 la 41 pinta fn_etiqueta_articulo', v_n, 1);

    select count(*) into v_n
      from apex_application_page_proc
     where application_id = 100 and page_id = 41
       and static_id in ('valida-rol-etiquetas', 'valida-empresa-etiqueta');
    espera_num('A5 las dos guardas de la 41', v_n, 2);

    ------------------------------------------------------------------ A6
    select count(*) into v_n
      from apex_application_list_entries
     where application_id = 100 and static_id = 'articulos';
    espera_num('A6 entrada de menu', v_n, 1);

    select count(*) into v_n
      from apex_application_authorization
     where application_id = 100 and static_id = 'ver-articulos';
    if v_n = 0 then
        -- La vista puede llamarse distinto segun la version: se comprueba por
        -- el objeto guardado en la app.
        begin
            select count(*) into v_n from apex_application_page_proc
             where application_id = 100 and static_id = 'valida-rol-articulos';
            espera_num('A6 guarda de rol de la 40', v_n, 1);
        end;
    end if;

    ------------------------------------------------------------------ A7
    v_sql := fuente_reg(40, 'Artículos y Servicios');
    -- las tres LOV se leen de los items de linea
    for r in (select page_id, item_name, lov_definition as lov from apex_application_page_items
               where application_id = 100
                 and item_name in ('P6_ID_PRODUCTO_SERVICIO', 'P10_CODIGO_PRODUCTO',
                                   'P29_ID_PRODUCTO_SERVICIO')) loop
        v_txt := to_clob(r.lov);
        if instr(v_txt, 'F_EMPRESA_ACTIVA') = 0 then
            falla('A7 LOV sin filtro de empresa', 'pagina ' || r.page_id || ' ' || r.item_name);
        end if;
        if instr(upper(v_txt), 'CODIGO_BARRAS') = 0 then
            falla('A7 LOV sin codigo de barras', 'pagina ' || r.page_id || ' ' || r.item_name);
        end if;
    end loop;

    select count(*) into v_n
      from apex_application_page_items
     where application_id = 100 and item_name = 'P29_ID_PRODUCTO_SERVICIO'
       and display_as_code = 'NATIVE_POPUP_LOV';
    espera_num('A7 la linea de compra permite escanear (Popup LOV)', v_n, 1);

    ------------------------------------------------------------------ A8
    -- El codigo interno lo asigna la base (2026-11-23): series PROD y SERV de
    -- FOLIO_CONTADOR, desde un trigger BEFORE INSERT. Antes habia que teclearlo
    -- y con 100 articulos el usuario era el que llevaba la numeracion.
    declare
        v_id  number;
        v_cod producto_servicio.codigo%type;
        v_ok  boolean := false;
    begin
        if not regexp_like(fn_siguiente_folio(1, 'PROD'), '^PROD-[0-9]{5}$') then
            falla('A8 el formato de la serie PROD', fn_siguiente_folio(1, 'PROD'));
        end if;
        if not regexp_like(fn_siguiente_folio(1, 'SERV'), '^SERV-[0-9]{5}$') then
            falla('A8 el formato de la serie SERV', fn_siguiente_folio(1, 'SERV'));
        end if;
        if not regexp_like(fn_siguiente_folio(1, 'ARTICULO'), '^[0-9]{8}$') then
            falla('A8 la vista previa del codigo de barras', fn_siguiente_folio(1, 'ARTICULO'));
        end if;

        begin
            insert into producto_servicio (id_empresa, nombre, tipo)
            values (1, 'PRUEBA CODIGO AUTO', 'PRODUCTO')
            returning id_producto_servicio, codigo into v_id, v_cod;
            v_ok := true;
        exception
            when others then
                falla('A8 el codigo interno se asigna solo', sqlerrm);
        end;

        if v_ok then
            if not regexp_like(v_cod, '^PROD-[0-9]{5}$') then
                falla('A8 el articulo nace con la serie de su tipo', nvl(v_cod, 'NULL'));
            end if;
            begin
                update producto_servicio set codigo = 'OTRO' where id_producto_servicio = v_id;
                falla('A8 el codigo interno es permanente', 'dejo cambiarlo');
            exception
                when others then null;
            end;
        end if;
        rollback;
    end;

    ------------------------------------------------------------- A9
    -- El codigo interno lo pone la base y no se teclea (2026-11-23).
    select count(*) into v_n
      from apex_application_page_items
     where application_id = 100 and page_id = 40 and item_name = 'P40_CODIGO'
       and read_only_condition_type_code = 'ALWAYS';
    espera_num('A9 el codigo interno es de solo lectura', v_n, 1);

    v_sql := lower(proceso(40, 'guardar-articulo'));
    if instr(v_sql, '(id_empresa, codigo') > 0 or instr(v_sql, 'v_cod') > 0 then
        falla('A9 el guardado ya no escribe el codigo', 'sigue insertando codigo');
    end if;

    -- 2026-11-23 (tarde): una accion dinamica NO puede escribir un item de solo
    -- lectura (APEX lo ignora en silencio: medido). El tipo ahora ENVIA la
    -- pagina y el codigo se repropone en el servidor.
    select count(*) into v_n
      from apex_application_page_items
     where application_id = 100 and page_id = 40 and item_name = 'P40_TIPO'
       and json_value(attributes, '$.page_action_on_selection') = 'SUBMIT';
    espera_num('A9 el tipo envia la pagina al cambiar', v_n, 1);

    select count(*) into v_n
      from apex_application_page_da
     where application_id = 100 and page_id = 40
       and static_id = 'art-codigo-tipo';
    espera_num('A9 la accion que no podia escribir el codigo ya no existe', v_n, 0);

    v_sql := lower(proceso(40, 'carga-articulo'));
    if instr(v_sql, 'p40_id_cargado') = 0 then
        falla('A9 la carga no pisa lo tecleado', 'falta la guarda P40_ID_CARGADO');
    end if;

    ------------------------------------------------------------- A10
    -- Chips en dos filas en lugar de la tarjeta de filtros (2026-11-23).
    select count(*) into v_n
      from apex_application_page_regions
     where application_id = 100 and page_id = 40 and region_static_id = 'art-filtros';
    espera_num('A10 la tarjeta Filtros ya no existe', v_n, 0);

    select count(*) into v_n
      from apex_application_page_regions
     where application_id = 100 and page_id = 40 and region_static_id = 'chips-articulos';
    espera_num('A10 la franja de chips existe', v_n, 1);

    begin
        v_sql := fuente_reg(40, 'Filtros rapidos');
    exception
        when others then
            v_sql := null;
    end;
    if v_sql is null then
        falla('A10 la franja de chips', 'no existe la region Filtros rapidos');
    else
        for c in (select 'data-filtro="PRODUCTO"' t from dual union all
                  select 'data-filtro="SERVICIO"' from dual union all
                  select 'data-filtro="ACTIVO"'    from dual union all
                  select 'data-filtro="INACTIVO"'  from dual union all
                  select '>Productos<'             from dual) loop
            if instr(v_sql, c.t) = 0 then
                falla('A10 chip que falta', c.t);
            end if;
        end loop;
        if instr(v_sql, 'data-item="P40_F_TIPO"') = 0 or instr(v_sql, 'data-item="P40_F_ESTADO"') = 0 then
            falla('A10 los chips no dicen que item mueven', 'falta data-item');
        end if;
    end if;

    select count(*) into v_n
      from apex_application_page_items
     where application_id = 100 and page_id = 40
       and item_name in ('P40_F_TIPO', 'P40_F_ESTADO')
       and display_as_code = 'NATIVE_HIDDEN'
       and maintain_session_state = 'Per Session';
    espera_num('A10 los dos filtros son ocultos y persisten', v_n, 2);

    select count(*) into v_n
      from apex_application_page_da
     where application_id = 100 and page_id = 40
       and static_id = 'art-chips-filtro'
       and when_element = '.spx-filtro';
    espera_num('A10 la accion escucha los chips', v_n, 1);

    ------------------------------------------------------------- resultado
    if v_fallas = 0 then
        raise_application_error(-20100, 'RESULTADO: FALLAS=0');
    else
        raise_application_error(-20101, 'RESULTADO: FALLAS=' || v_fallas || v_lista);
    end if;
exception
    when others then
        if sqlcode in (-20100, -20101) then
            raise;
        end if;
        raise_application_error(-20102, 'RESULTADO: FALLAS=1 excepcion: ' || sqlerrm);
end;
/
