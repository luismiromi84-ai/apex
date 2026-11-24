-- =============================================================================
-- 20261122_rif_mayus_chips_islr_verificacion.sql
--
-- Dos pedidos del dueno el 2026-11-22:
--
--   A) El RIF se guarda en MAYUSCULAS. El de clientes (21) y proveedores (23) ya
--      se normalizaba; el que quedo en minusculas fue el de la IMPRENTA
--      (empresa_fiscal.imprenta_rif = 'j-85462139-7') y el de la empresa (19).
--   B) Chips de filtro rapido en «Conceptos de ISLR» (34), como los de Facturas
--      de Compras: Todos / Activos / Inactivos.
--
--   A1  el guardado de la empresa (19) pasa el RIF a mayusculas
--   A2  el guardado de los datos fiscales pasa el RIF de la imprenta a mayusculas
--   A3  no queda ningun RIF en minusculas en la base (clientes, proveedores,
--       empresas y datos fiscales)
--   A4  clientes (21) y proveedores (23) siguen normalizando
--   C1  la 34 tiene la region de chips con los tres y su data-filtro
--   C2  P34_FILTRO es oculto, persiste y nace en TODOS
--   C3  la consulta guardada del informe filtra por P34_FILTRO y el informe lo
--       manda en su refresco
--   C4  el clic de los chips refresca la lista
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261122_rif_mayus_chips_islr_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000) := '';
    v_src    clob;
    v_txt    varchar2(32767);
    v_n      number;

    procedure falla(p_caso varchar2, p_detalle varchar2) is
    begin
        v_fallas := v_fallas + 1;
        v_lista  := v_lista || ' | ' || p_caso || ': ' || substrb(p_detalle, 1, 170);
    end;
begin
    ------------------------------------------------------------------ A1
    begin
        select count(*) into v_n
          from apex_application_page_proc
         where application_id = 100 and page_id = 19
           and static_id = 'guardar-empresa'
           and instr(upper(process_source), 'UPPER(TRIM(:P19_RFC))') > 0;
        if v_n <> 1 then
            falla('A1', 'el guardado de la empresa no pasa el RIF a mayusculas');
        end if;
    exception
        when others then
            falla('A1', sqlerrm);
    end;

    ------------------------------------------------------------------ A2
    begin
        select count(*) into v_n
          from apex_application_page_proc
         where application_id = 100 and page_id = 19
           and static_id = 'guardar-datos-fiscales-admin'
           and instr(upper(process_source), 'UPPER(TRIM(:P19F_IMPRENTA_RIF))') > 0;
        if v_n <> 1 then
            falla('A2', 'el guardado fiscal no pasa el RIF de la imprenta a mayusculas');
        end if;
    exception
        when others then
            falla('A2', sqlerrm);
    end;

    ------------------------------------------------------------------ A3
    begin
        select count(*) into v_n from clientes where rif <> upper(rif);
        if v_n <> 0 then
            falla('A3', 'hay ' || v_n || ' clientes con el RIF en minusculas');
        end if;
        select count(*) into v_n from proveedores where rif <> upper(rif);
        if v_n <> 0 then
            falla('A3', 'hay ' || v_n || ' proveedores con el RIF en minusculas');
        end if;
        select count(*) into v_n from empresas where rfc <> upper(rfc);
        if v_n <> 0 then
            falla('A3', 'hay ' || v_n || ' empresas con el RIF/RFC en minusculas');
        end if;
        select count(*) into v_n from empresa_fiscal
         where imprenta_rif <> upper(imprenta_rif);
        if v_n <> 0 then
            falla('A3', 'hay ' || v_n || ' datos fiscales con el RIF de la imprenta en minusculas');
        end if;
    exception
        when others then
            falla('A3', sqlerrm);
    end;

    ------------------------------------------------------------------ A4
    begin
        select count(*) into v_n
          from apex_application_page_proc
         where application_id = 100 and page_id = 21
           and static_id = 'guardar-cliente'
           and instr(upper(process_source), 'UPPER(TRIM(:P21_RIF))') > 0;
        if v_n <> 1 then
            falla('A4', 'el guardado del cliente perdio la normalizacion del RIF');
        end if;
        select count(*) into v_n
          from apex_application_page_proc
         where application_id = 100 and page_id = 23
           and static_id = 'guardar-proveedor'
           and instr(upper(process_source), 'UPPER(TRIM(:P23_RIF))') > 0;
        if v_n <> 1 then
            falla('A4', 'el guardado del proveedor perdio la normalizacion del RIF');
        end if;
    exception
        when others then
            falla('A4', sqlerrm);
    end;

    ------------------------------------------------------------------ C1
    begin
        select region_source into v_src
          from apex_application_page_regions
         where application_id = 100 and page_id = 34
           and region_id = 43000000000001695;
        v_txt := v_src;
        for c in (select column_value as f from table(sys.odcivarchar2list(
                      'data-filtro="TODOS"', 'data-filtro="ACTIVOS"',
                      'data-filtro="INACTIVOS"', 'spx-filtro'))) loop
            if instr(v_txt, c.f) = 0 then
                falla('C1', 'falta en los chips: ' || c.f);
            end if;
        end loop;
    exception
        when others then
            falla('C1', sqlerrm);
    end;

    ------------------------------------------------------------------ C2
    begin
        select count(*) into v_n
          from apex_application_page_items
         where application_id = 100 and page_id = 34
           and item_name = 'P34_FILTRO'
           and display_as_code = 'NATIVE_HIDDEN'
           and nvl(maintain_session_state, 'Y') in ('Y', 'Yes', 'Per Session')
           and instr(upper(nvl(item_default, ' ')), 'TODOS') > 0;
        if v_n <> 1 then
            falla('C2', 'P34_FILTRO no es un oculto persistente que nace en TODOS');
        end if;
    exception
        when others then
            falla('C2', sqlerrm);
    end;

    ------------------------------------------------------------------ C3
    begin
        select region_source into v_src
          from apex_application_page_regions
         where application_id = 100 and page_id = 34
           and region_id = 43000000000001471;
        v_txt := v_src;
        if instr(v_txt, ':P34_FILTRO') = 0 then
            falla('C3', 'la consulta de la lista no filtra por P34_FILTRO');
        end if;
        if instr(upper(v_txt), 'INACTIVOS') = 0 then
            falla('C3', 'la consulta no distingue INACTIVOS');
        end if;

        select count(*) into v_n
          from apex_application_page_regions
         where application_id = 100 and page_id = 34
           and region_id = 43000000000001471
           and ajax_items_to_submit = 'P34_FILTRO';
        if v_n <> 1 then
            falla('C3', 'el informe no manda P34_FILTRO en su refresco');
        end if;
    exception
        when others then
            falla('C3', sqlerrm);
    end;

    ------------------------------------------------------------------ C4
    begin
        select count(*) into v_n
          from apex_application_page_da
         where application_id = 100 and page_id = 34
           and when_element = '.spx-filtro'
           and when_event_internal_name = 'click';
        if v_n <> 1 then
            falla('C4', 'no hay accion de clic sobre los chips');
        end if;

        select count(*) into v_n
          from apex_application_page_da_acts a
          join apex_application_page_da e on e.dynamic_action_id = a.dynamic_action_id
         where a.application_id = 100 and e.page_id = 34
           and instr(a.attributes, 'R43000000000001471') > 0;
        if v_n < 1 then
            falla('C4', 'el clic de los chips no refresca la lista');
        end if;
    exception
        when others then
            falla('C4', sqlerrm);
    end;

    ------------------------------------------------------------------ C5
    -- Pestanas de la 34 (2026-11-23): lista y formulario, como Administracion.
    begin
        select count(*) into v_n
          from apex_application_page_regions
         where application_id = 100 and page_id = 34
           and region_static_id = 'islr-selector'
           and source_type_plugin_static_id = 'NATIVE_DISPLAY_SELECTOR';
        if v_n <> 1 then
            falla('C5', 'no existe el selector de regiones');
        end if;

        select count(*) into v_n
          from apex_application_page_regions
         where application_id = 100 and page_id = 34
           and region_static_id in ('islr-lista', 'islr-form')
           and display_region_selector = 'Yes';
        if v_n <> 2 then
            falla('C5', 'la lista y el formulario no estan en el selector');
        end if;

        select count(*) into v_n
          from apex_application_page_regions
         where application_id = 100 and page_id = 34
           and region_static_id = 'islr-acciones';
        if v_n <> 0 then
            falla('C5', 'la region Acciones sigue existiendo');
        end if;

        select count(*) into v_n
          from apex_application_page_buttons
         where application_id = 100 and page_id = 34
           and button_name in ('BTN_GUARDAR_CONCEPTO', 'BTN_NUEVO_CONCEPTO', 'BTN_VOLVER')
           and region_id = 43000000000001483;
        if v_n <> 3 then
            falla('C5', 'los botones no estan dentro del formulario');
        end if;

        select count(*) into v_n
          from apex_application_page_items
         where application_id = 100 and page_id = 34
           and item_name = 'P34_TAB'
           and region_id = 43000000000001483;
        if v_n <> 1 then
            falla('C5', 'falta P34_TAB en el formulario');
        end if;

        select count(*) into v_n
          from apex_application_page_ir_col
         where application_id = 100 and page_id = 34
           and column_alias = 'ID_CONCEPTO'
           and instr(column_link, 'P34_TAB') > 0;
        if v_n <> 1 then
            falla('C5', 'el enlace Editar no abre la pestana del formulario');
        end if;
    exception
        when others then
            falla('C5', sqlerrm);
    end;

    raise_application_error(-20100,
        substrb('RESULTADO: FALLAS=' || v_fallas || v_lista, 1, 3000));
end;
/
