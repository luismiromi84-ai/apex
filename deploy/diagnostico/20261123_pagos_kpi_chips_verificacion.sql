-- =============================================================================
-- 20261123_pagos_kpi_chips_verificacion.sql
--
-- La lista de Pagos (36) al estandar de las demas listas (2026-11-23). Era la
-- unica que quedaba sin filtros, sin indicadores y con el conciliado en texto
-- crudo: se veia distinta de Recibos (24), Compras (27), Clientes (20) y
-- Proveedores (22).
--
--   K1  la pagina tiene Filtros (10), Indicadores (15) y la lista (20), en ese orden
--   K2  los cinco filtros existen y PERSISTEN (un item que se envia la pagina y
--       no persiste se descarta y el combo vuelve a Todos: el fallo de la 24)
--   K3  la region de indicadores es contenido dinamico PLSQL con su static_id
--   K4  ejecutando su fuente GUARDADA: cuatro tarjetas con los numeros del mes,
--       y GUIONES (no ceros) cuando la empresa no tiene pagos
--   K5  la consulta guardada filtra de verdad: los cinco binds y el resultado
--       coincide con el SQL directo en cuatro combinaciones
--   K6  estado EMITIDO con insignia y conciliado con chip (clase oculta, fuera
--       del informe por defecto), y el CSS de las dos en la propia pagina
--   K7  una accion de cambio por filtro (cinco), con su apex.submit
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261123_pagos_kpi_chips_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000) := '';
    v_n      number;
    v_src    clob;
    v_sql    clob;
    v_html   clob;
    v_css    clob;
    v_esp    varchar2(60);
    v_obt    number;
    v_dir    number;

    procedure falla(p_caso varchar2, p_detalle varchar2) is
    begin
        v_fallas := v_fallas + 1;
        v_lista  := v_lista || ' | ' || p_caso || ': ' || substrb(p_detalle, 1, 160);
    end;

    function cuenta(p_sql clob) return number is
        v number;
    begin
        execute immediate 'select count(*) from (' || p_sql || ')' into v;
        return v;
    end;

    -- Ejecuta la fuente GUARDADA de la region de indicadores y devuelve su HTML.
    function indicadores(p_empresa number) return clob is
        v_src2 clob;
        v_out  clob;
    begin
        select region_source into v_src2
          from apex_application_page_regions
         where application_id = 100 and page_id = 36 and region_id = 43000000000001726;
        v_src2 := replace(v_src2, ':F_EMPRESA_ACTIVA', to_char(p_empresa));
        -- La fuente termina en RETURN v_html; se cambia por la asignacion al bind
        -- y se ejecuta como bloque anonimo (patron de 20261122_igtf_resumen_p28).
        v_src2 := replace(v_src2, 'return v_html;', ':o := v_html;');
        execute immediate 'declare v_o clob; begin ' || v_src2 || ' end;'
            using out v_out;
        return v_out;
    end;
begin
    ------------------------------------------------------------------ K1
    begin
        select count(*) into v_n
          from apex_application_page_regions
         where application_id = 100 and page_id = 36
           and region_id = 43000000000001720
           and display_sequence = 10;
        if v_n <> 1 then
            falla('K1', 'no hay region Filtros en secuencia 10');
        end if;

        select count(*) into v_n
          from apex_application_page_regions
         where application_id = 100 and page_id = 36
           and region_id = 43000000000001726
           and display_sequence = 15;
        if v_n <> 1 then
            falla('K1', 'no hay region de indicadores en secuencia 15');
        end if;

        select count(*) into v_n
          from apex_application_page_regions
         where application_id = 100 and page_id = 36
           and region_id = 43000000000001570
           and display_sequence = 20;
        if v_n <> 1 then
            falla('K1', 'la lista no quedo en secuencia 20 (debajo de los indicadores)');
        end if;
    exception
        when others then
            falla('K1', sqlerrm);
    end;

    ------------------------------------------------------------------ K2
    begin
        for c in (select column_value as t from table(sys.odcivarchar2list(
                      'P36_DESDE', 'P36_HASTA', 'P36_ESTADO', 'P36_CONCILIADO',
                      'P36_BUSCAR'))) loop
            select count(*) into v_n
              from apex_application_page_items
             where application_id = 100 and page_id = 36 and item_name = c.t
               and region_id = 43000000000001720
               and maintain_session_state = 'Per Session';
            if v_n <> 1 then
                falla('K2', c.t || ' no existe en Filtros o no persiste');
            end if;
        end loop;

        select count(*) into v_n
          from apex_application_page_items
         where application_id = 100 and page_id = 36
           and item_name = 'P36_CONCILIADO'
           and lov_definition like '%Sí;SI%';
        if v_n <> 1 then
            falla('K2', 'el filtro de conciliado no ofrece Sí/No');
        end if;
    exception
        when others then
            falla('K2', sqlerrm);
    end;

    ------------------------------------------------------------------ K3
    begin
        select count(*) into v_n
          from apex_application_page_regions
         where application_id = 100 and page_id = 36
           and region_id = 43000000000001726
           and region_static_id = 'kpi-pagos'
           and source_type_plugin_static_id = 'NATIVE_DYNAMIC_CONTENT'
           and function_body_language = 'PLSQL';
        if v_n <> 1 then
            falla('K3', 'los indicadores no son contenido dinamico PLSQL con static_id kpi-pagos');
        end if;
    exception
        when others then
            falla('K3', sqlerrm);
    end;

    ------------------------------------------------------------------ K4
    begin
        v_html := indicadores(1);
        if v_html is null then
            falla('K4', 'la region no devuelve nada para la empresa 1');
        else
            for c in (select column_value as t from table(sys.odcivarchar2list(
                          'Pagos del mes', 'Pagado (Bs)', 'IGTF (Bs)',
                          'Sin conciliar'))) loop
                if instr(v_html, c.t) = 0 then
                    falla('K4', 'falta la tarjeta: ' || c.t);
                end if;
            end loop;

            -- El importe del mes, con la MISMA cuenta y la MISMA mascara.
            select to_char(nvl(sum(case when estado = 'ACTIVO'
                                         and trunc(fecha_pago, 'MM') = trunc(sysdate, 'MM')
                                        then nvl(monto_bs, monto * nvl(tipo_cambio, 1)) end), 0),
                           'FM999G999G999G999G990D00', 'NLS_NUMERIC_CHARACTERS='',.''')
              into v_esp
              from pagos where id_empresa = 1;
            if instr(v_html, v_esp) = 0 then
                falla('K4', 'no sale el pagado del mes ' || v_esp);
            end if;

            -- Y con una empresa SIN pagos: guiones, no ceros.
            v_html := indicadores(2);
            if instr(v_html, '&#8212;') = 0 then
                falla('K4', 'una empresa sin pagos no pinta guiones');
            end if;
        end if;
    exception
        when others then
            falla('K4', sqlerrm);
    end;

    ------------------------------------------------------------------ K5
    begin
        select region_source into v_src
          from apex_application_page_regions
         where application_id = 100 and page_id = 36
           and region_id = 43000000000001570;

        for c in (select column_value as t from table(sys.odcivarchar2list(
                      ':P36_DESDE', ':P36_HASTA', ':P36_ESTADO', ':P36_CONCILIADO'))) loop
            if instr(v_src, c.t) = 0 then
                falla('K5', 'la consulta no filtra por ' || c.t);
            end if;
        end loop;

        -- Sin filtros: todas las filas de la empresa activa.
        v_sql := replace(v_src, ':F_EMPRESA_ACTIVA', '1');
        v_sql := replace(v_sql, ':P36_DESDE', 'null');
        v_sql := replace(v_sql, ':P36_HASTA', 'null');
        v_sql := replace(v_sql, ':P36_ESTADO', 'null');
        v_sql := replace(v_sql, ':P36_CONCILIADO', 'null');
        v_sql := replace(v_sql, ':P36_BUSCAR', 'null');
        v_obt := cuenta(v_sql);
        select count(*) into v_dir from pagos where id_empresa = 1;
        if v_obt <> v_dir then
            falla('K5', 'sin filtros devuelve ' || v_obt || ' y hay ' || v_dir);
        end if;

        -- Conciliado = NO: la consulta y el SQL directo tienen que coincidir.
        v_sql := replace(v_src, ':F_EMPRESA_ACTIVA', '1');
        v_sql := replace(v_sql, ':P36_DESDE', 'null');
        v_sql := replace(v_sql, ':P36_HASTA', 'null');
        v_sql := replace(v_sql, ':P36_ESTADO', 'null');
        v_sql := replace(v_sql, ':P36_CONCILIADO', '''NO''');
        v_sql := replace(v_sql, ':P36_BUSCAR', 'null');
        v_obt := cuenta(v_sql);
        select count(*) into v_dir from pagos
         where id_empresa = 1 and conciliado = 'N';
        if v_obt <> v_dir then
            falla('K5', 'el filtro Conciliado=No devuelve ' || v_obt || ' y hay ' || v_dir);
        end if;

        -- Estado = ANULADO (la empresa 1 no tiene pagos anulados).
        v_sql := replace(v_src, ':F_EMPRESA_ACTIVA', '1');
        v_sql := replace(v_sql, ':P36_DESDE', 'null');
        v_sql := replace(v_sql, ':P36_HASTA', 'null');
        v_sql := replace(v_sql, ':P36_ESTADO', '''ANULADO''');
        v_sql := replace(v_sql, ':P36_CONCILIADO', 'null');
        v_sql := replace(v_sql, ':P36_BUSCAR', 'null');
        v_obt := cuenta(v_sql);
        select count(*) into v_dir from pagos
         where id_empresa = 1 and estado = 'ANULADO';
        if v_obt <> v_dir then
            falla('K5', 'el filtro Estado=Anulados devuelve ' || v_obt || ' y hay ' || v_dir);
        end if;

        -- Buscar por el proveedor que SI tiene un pago.
        begin
            select min(pr.razon_social) into v_esp
              from pagos p join proveedores pr on pr.id_proveedor = p.id_proveedor
             where p.id_empresa = 1;
        exception when others then v_esp := null;
        end;
        if v_esp is not null then
            v_sql := replace(v_src, ':F_EMPRESA_ACTIVA', '1');
            v_sql := replace(v_sql, ':P36_DESDE', 'null');
            v_sql := replace(v_sql, ':P36_HASTA', 'null');
            v_sql := replace(v_sql, ':P36_ESTADO', 'null');
            v_sql := replace(v_sql, ':P36_CONCILIADO', 'null');
            v_sql := replace(v_sql, ':P36_BUSCAR', '''' || v_esp || '''');
            v_obt := cuenta(v_sql);
            if v_obt < 1 then
                falla('K5', 'buscar por ' || v_esp || ' no devuelve su pago');
            end if;
        end if;
    exception
        when others then
            falla('K5', sqlerrm);
    end;

    ------------------------------------------------------------------ K6
    begin
        select count(*) into v_n
          from apex_application_page_ir_col
         where application_id = 100 and region_id = 43000000000001570
           and column_alias = 'CONCILIADO'
           and html_expression like '%spx-chip%CONCILIADO_CLASE%';
        if v_n <> 1 then
            falla('K6', 'el conciliado no se pinta con el chip y su clase');
        end if;

        select count(*) into v_n
          from apex_application_page_ir_col
         where application_id = 100 and region_id = 43000000000001570
           and column_alias = 'CONCILIADO_CLASE';
        if v_n <> 1 then
            falla('K6', 'no esta declarada CONCILIADO_CLASE');
        end if;

        select count(*) into v_n
          from apex_application_page_ir_rpt
         where application_id = 100 and region_id = 43000000000001570
           and report_columns like '%CONCILIADO_CLASE%';
        if v_n <> 0 then
            falla('K6', 'CONCILIADO_CLASE no debe salir en el informe por defecto');
        end if;

        select count(*) into v_n
          from apex_application_page_ir_col
         where application_id = 100 and region_id = 43000000000001570
           and column_alias = 'ESTADO'
           and html_expression like '%status-badge%';
        if v_n <> 1 then
            falla('K6', 'el estado no se pinta con insignia');
        end if;

        select inline_css into v_css
          from apex_application_pages
         where application_id = 100 and page_id = 36;
        if instr(v_css, '.status-EMITIDO') = 0 then
            falla('K6', 'falta el CSS de la insignia EMITIDO');
        end if;
        if instr(v_css, '.spx-chip--Si') = 0 then
            falla('K6', 'falta el CSS del chip de conciliado');
        end if;
    exception
        when others then
            falla('K6', sqlerrm);
    end;

    ------------------------------------------------------------------ K7
    begin
        select count(*) into v_n
          from apex_application_page_da
         where application_id = 100 and page_id = 36
           and when_element in ('P36_DESDE', 'P36_HASTA', 'P36_ESTADO',
                                      'P36_CONCILIADO', 'P36_BUSCAR')
           and when_event_internal_name = 'change';
        if v_n <> 5 then
            falla('K7', 'hay ' || v_n || ' acciones de cambio para cinco filtros');
        end if;

        select count(*) into v_n
          from apex_application_page_da d
          join apex_application_page_da_acts a on a.dynamic_action_id = d.dynamic_action_id
         where d.application_id = 100 and d.page_id = 36
           and d.when_element like 'P36%'
           and instr(lower(a.attributes), 'aplicar') > 0;
        if v_n <> 5 then
            falla('K7', 'las acciones no envian la pagina con APLICAR (' || v_n || ')');
        end if;
    exception
        when others then
            falla('K7', sqlerrm);
    end;

    raise_application_error(-20100,
        substrb('RESULTADO: FALLAS=' || v_fallas || v_lista, 1, 3000));
end;
/
