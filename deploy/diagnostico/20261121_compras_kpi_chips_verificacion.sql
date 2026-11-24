-- =============================================================================
-- 20261121_compras_kpi_chips_verificacion.sql
--
-- La pagina 27 "Facturas de Compras" con el acabado de las paginas 5, 8, 20, 22
-- y 24: fila de indicadores, insignias de estado y chips de filtro rapido.
-- NO se toco ningun calculo, guarda, package ni proceso: esto solo vigila que lo
-- nuevo mida lo que dice y que lo de antes siga en su sitio.
--
--   K1  la fila de indicadores existe en la 27, es contenido dinamico PL/SQL y
--       va por encima del informe (secuencia 5 < 10)
--   K2  P27_FILTRO es un item oculto que PERSISTE (defecto TODOS) y el informe lo
--       manda en su refresh (ajax_items_to_submit): lo que no persiste no filtra
--   K3  la region de chips es ESTATICA (sin tipo de plugin) y trae los cuatro
--       chips con su data-filtro
--   K4  la accion del clic esta enganchada a .spx-filtro, escribe P27_FILTRO y
--       refresca la lista R43000000000001000
--   K5  la consulta guardada filtra de verdad: cada chip devuelve solo su estado
--       y la suma de los tres es el total
--   K6  los cuatro numeros del KPI son los de la base (empresa 1) y la empresa
--       sin compras pinta guiones, no ceros
--   K7  el CSS de la propia pagina tiene las tres insignias y las clases spx-
--   K8  las columnas, sus enlaces, el boton "Nueva compra" y la guarda de rol
--       siguen como estaban (desde el 2026-11-21 el informe trae ademas
--       Vencimiento y Saldo: cuentas por pagar)
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261121_compras_kpi_chips_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000) := '';
    v_txt    varchar2(32767);
    v_src    clob;
    v_html   clob;
    v_n      number;
    v_n2     number;
    v_tot    number;
    v_ret    number;
    v_bor    number;
    v_cnt    number;
    v_mal    number;
    v_esp    varchar2(60);

    procedure falla(p_caso varchar2, p_detalle varchar2) is
    begin
        v_fallas := v_fallas + 1;
        v_lista  := v_lista || ' | ' || p_caso || ': ' || substrb(p_detalle, 1, 160);
    end;

    function fuente(p_region number) return clob is
        v clob;
    begin
        select region_source into v
          from apex_application_page_regions
         where application_id = 100 and region_id = p_region;
        return v;
    end;

    -- El informe tal como esta guardado, sin el order by (para poder contarlo) y
    -- con el chip pedido. No es una copia a mano: se lee de APEX.
    function consulta(p_filtro varchar2) return clob is
        v  clob;
        vc varchar2(32767);
        p  number;
    begin
        v := fuente(43000000000001000);
        v := replace(v, ':F_EMPRESA_ACTIVA', '''1''');
        v := replace(v, ':P27_FILTRO', '''' || p_filtro || '''');
        vc := v;
        p  := instr(upper(vc), ' ORDER BY ');
        if p > 0 then
            vc := substr(vc, 1, p - 1);
        end if;
        return vc;
    end;

    procedure prueba_chip(p_chip varchar2, p_estado varchar2) is
        v_sql clob := consulta(p_chip);
    begin
        execute immediate 'select count(*), count(case when nvl(estado_cod, ''#'') <> '''
                          || p_estado || ''' then 1 end) from (' || v_sql || ')'
            into v_cnt, v_mal;
        if v_mal > 0 then
            falla('K5', 'el chip ' || p_chip || ' devuelve ' || v_mal || ' filas que no son ' || p_estado);
        end if;
        if p_estado is not null then
            select count(*) into v_n
              from compras
             where id_empresa = 1 and estado = p_estado;
            if v_cnt <> v_n then
                falla('K5', 'el chip ' || p_chip || ' devuelve ' || v_cnt || ' filas y la base dice ' || v_n);
            end if;
        end if;
    end;

begin
    ------------------------------------------------------------------ K1
    begin
        select count(*) into v_n
          from apex_application_page_regions
         where application_id = 100
           and region_id = 43000000000001560
           and page_id = 27
           and region_static_id = 'kpi-compras'
           and source_type_plugin_static_id = 'NATIVE_DYNAMIC_CONTENT'
           and function_body_language = 'PLSQL'
           and display_sequence = 5;
        if v_n <> 1 then
            falla('K1', 'la fila de indicadores no es contenido dinamico PL/SQL en la secuencia 5');
        end if;
        select count(*) into v_n2
          from apex_application_page_regions
         where application_id = 100 and page_id = 27
           and region_static_id = 'compras-lista' and display_sequence = 10;
        if v_n2 <> 1 then
            falla('K1', 'la lista no esta en la secuencia 10');
        end if;
    exception
        when others then
            falla('K1', sqlerrm);
    end;

    ------------------------------------------------------------------ K2
    begin
        select count(*) into v_n
          from apex_application_page_items
         where application_id = 100 and page_id = 27
           and item_name = 'P27_FILTRO'
           and display_as_code = 'NATIVE_HIDDEN'
           and item_default = 'TODOS'
           -- MAINTAIN_SESSION_STATE = 'Per Session' es lo que hace que el valor
           -- llegue al refresh. Con 'No' el combo volveria a Todos (paso en la 24).
           and maintain_session_state = 'Per Session';
        if v_n <> 1 then
            falla('K2', 'P27_FILTRO no es un item oculto persistente con defecto TODOS');
        end if;
        select count(*) into v_n
          from apex_application_page_regions
         where application_id = 100 and region_id = 43000000000001000
           and upper(nvl(ajax_items_to_submit, '#')) = 'P27_FILTRO';
        if v_n <> 1 then
            falla('K2', 'el informe no manda P27_FILTRO en ajax_items_to_submit');
        end if;
    exception
        when others then
            falla('K2', sqlerrm);
    end;

    ------------------------------------------------------------------ K3
    begin
        select count(*) into v_n
          from apex_application_page_regions
         where application_id = 100 and region_id = 43000000000001561
           and page_id = 27
           and region_static_id = 'chips-compras'
           -- Una region estatica NO lleva tipo de plugin: si lo lleva, la pagina
           -- muere con HTTP 400 (leccion del 2026-11-05).
           and source_type_plugin_static_id = 'NATIVE_STATIC'
           and display_sequence = 7;
        if v_n <> 1 then
            falla('K3', 'la region de chips no es estatica en la secuencia 7');
        end if;
        v_txt := fuente(43000000000001561);
        for c in (select column_value as chip from table(sys.odcivarchar2list(
                      'TODOS', 'PROCESADA', 'BORRADOR', 'ANULADA'))) loop
            if instr(v_txt, 'data-filtro="' || c.chip || '"') = 0 then
                falla('K3', 'falta el chip ' || c.chip);
            end if;
        end loop;
    exception
        when others then
            falla('K3', sqlerrm);
    end;

    ------------------------------------------------------------------ K4
    begin
        select count(*) into v_n
          from apex_application_page_da d
          join apex_application_page_da_acts a
            on a.application_id = d.application_id
           and a.dynamic_action_id = d.dynamic_action_id
         where d.application_id = 100 and d.page_id = 27
           and d.static_id = 'compras-filtro-rapido'
           and d.when_element = '.spx-filtro'
           and d.when_event_internal_name = 'click'
           and a.action_code = 'NATIVE_JAVASCRIPT_CODE'
           and instr(a.attributes, 'P27_FILTRO') > 0
           and instr(a.attributes, 'R43000000000001000') > 0;
        if v_n <> 1 then
            falla('K4', 'la accion del clic no escribe P27_FILTRO o no refresca la lista');
        end if;
    exception
        when others then
            falla('K4', sqlerrm);
    end;

    ------------------------------------------------------------------ K5
    begin
        prueba_chip('TODOS', null);
        prueba_chip('PROCESADA', 'REGISTRADA');
        prueba_chip('BORRADOR', 'BORRADOR');
        prueba_chip('ANULADA', 'ANULADA');

        execute immediate 'select count(*) from (' || consulta('TODOS') || ')' into v_cnt;
        select count(*) into v_n from compras where id_empresa = 1;
        if v_cnt <> v_n then
            falla('K5', 'TODOS devuelve ' || v_cnt || ' compras y la base tiene ' || v_n);
        end if;
    exception
        when others then
            falla('K5', 'no se pudo ejecutar la consulta guardada: ' || substrb(sqlerrm, 1, 120));
    end;

    ------------------------------------------------------------------ K6
    begin
        -- El fuente de la region, ejecutado como funcion: es la unica forma de
        -- comprobar que los cuatro numeros salen de la base y no de una copia.
        v_txt := fuente(43000000000001560);
        v_txt := trim(v_txt);
        if upper(substr(v_txt, 1, 7)) = 'DECLARE' then
            v_txt := substr(v_txt, 8);
        end if;
        v_txt := replace(v_txt, ':F_EMPRESA_ACTIVA', 'p_emp');

        begin
            execute immediate 'drop function tmp_kpi27';
        exception
            when others then
                null;
        end;
        execute immediate 'create or replace function tmp_kpi27(p_emp number) return clob is ' || v_txt;

        execute immediate 'select tmp_kpi27(1) from dual' into v_html;

        select count(*), nvl(sum(monto_total * nvl(tipo_cambio, 1)), 0),
               nvl(sum(retencion_iva_bs), 0)
          into v_n, v_tot, v_ret
          from compras
         where id_empresa = 1 and tipo_documento = 'FAC'
           and nvl(estado, '#') <> 'ANULADA'
           and trunc(fecha_emision, 'MM') = trunc(sysdate, 'MM');

        select count(*) into v_bor
          from compras
         where id_empresa = 1 and tipo_documento = 'FAC'
           and nvl(estado, '#') <> 'ANULADA' and estado = 'BORRADOR';

        if dbms_lob.instr(v_html, '<div class="spx-card-val">' || v_n || '</div>') = 0 then
            falla('K6', 'Compras del mes no es ' || v_n);
        end if;
        v_esp := to_char(v_tot, 'FM999G999G999G999G990D00', 'NLS_NUMERIC_CHARACTERS='',.''');
        if dbms_lob.instr(v_html, v_esp) = 0 then
            falla('K6', 'Total compras (Bs) no es ' || v_esp);
        end if;
        v_esp := to_char(v_ret, 'FM999G999G999G999G990D00', 'NLS_NUMERIC_CHARACTERS='',.''');
        if dbms_lob.instr(v_html, v_esp) = 0 then
            falla('K6', 'Retencion IVA (Bs) no es ' || v_esp);
        end if;
        if dbms_lob.instr(v_html, '<div class="spx-card-val">' || v_bor || '</div>') = 0 then
            falla('K6', 'Pendientes no es ' || v_bor);
        end if;

        -- Y la empresa sin compras pinta guiones, no ceros.
        execute immediate 'select tmp_kpi27(2) from dual' into v_html;
        if dbms_lob.instr(v_html, '&#8212;') = 0 then
            falla('K6', 'una empresa sin compras no pinta guiones');
        end if;

        execute immediate 'drop function tmp_kpi27';
    exception
        when others then
            begin
                execute immediate 'drop function tmp_kpi27';
            exception
                when others then
                    null;
            end;
            falla('K6', 'no se pudo ejecutar el KPI: ' || substrb(sqlerrm, 1, 120));
    end;

    ------------------------------------------------------------------ K7
    begin
        select inline_css into v_txt
          from apex_application_pages
         where application_id = 100 and page_id = 27;
        for c in (select column_value as cls from table(sys.odcivarchar2list(
                      '.status-BORRADOR', '.status-Pendiente', '.status-REGISTRADA', '.status-ANULADA',
                      '.status-badge', '.status-dot', '.spx-kpis', '.spx-card',
                      '.spx-filtros', '.spx-filtro', '.spx-card-val'))) loop
            if instr(v_txt, c.cls) = 0 then
                falla('K7', 'el CSS de la pagina 27 no tiene ' || c.cls);
            end if;
        end loop;
        -- La clase de cada insignia sale de la etiqueta que se lee.
        select count(*) into v_n
          from apex_application_page_ir_col
         where application_id = 100 and page_id = 27
           and column_alias = 'ESTADO'
           and instr(html_expression, 'status-#ESTADO#') > 0;
        if v_n <> 1 then
            falla('K7', 'la columna ESTADO no pinta status-#ESTADO#');
        end if;
    exception
        when others then
            falla('K7', sqlerrm);
    end;

    ------------------------------------------------------------------ K8
    begin
        -- Las columnas del informe por defecto, tal como estaban. Se mira el
        -- informe PUBLICO: APEX guarda una vista privada por usuario en cuanto
        -- alguien toca el informe, y esa no es la definicion de la app.
        select count(*) into v_n
          from apex_application_page_ir_rpt
         where application_id = 100 and page_id = 27
           and status = 'PUBLIC'
           and report_columns = 'ID_COMPRA:PROVEEDOR:RIF:TIPO_DOCUMENTO:FOLIO_FACTURA:NRO_CONTROL:'
              || 'FECHA_EMISION:FECHA_VENCIMIENTO:COD_MONEDA:MONTO_TOTAL:RETENCION_IVA_BS:SALDO:ESTADO:PAGAR';
        if v_n <> 1 then
            falla('K8', 'cambiaron las columnas del informe por defecto');
        end if;

        -- El enlace "Editar" sigue llevando a la compra (28).
        select count(*) into v_n
          from apex_application_page_ir_col
         where application_id = 100 and page_id = 27
           and column_alias = 'ID_COMPRA'
           and instr(column_link, ':28:') > 0;
        if v_n <> 1 then
            falla('K8', 'el enlace de Editar no lleva a la pagina 28');
        end if;

        -- El boton "Nueva compra" y su condicion.
        select count(*) into v_n
          from apex_application_page_buttons
         where application_id = 100 and page_id = 27
           and static_id = 'btn-nueva-compra'
           and instr(redirect_url, ':28:') > 0
           and instr(condition_expression1, 'ADMIN,GERENCIA,CONTABILIDAD,ALMACEN,PRUEBA') > 0;
        if v_n <> 1 then
            falla('K8', 'el boton Nueva compra cambio');
        end if;

        -- La guarda de rol de la pagina.
        select count(*) into v_n
          from apex_application_page_proc
         where application_id = 100 and page_id = 27
           and static_id = 'valida-rol-compras';
        if v_n <> 1 then
            falla('K8', 'falta la guarda valida-rol-compras');
        end if;
    exception
        when others then
            falla('K8', sqlerrm);
    end;

    raise_application_error(-20100,
        substrb('RESULTADO: FALLAS=' || v_fallas || v_lista, 1, 3000));
end;
/
