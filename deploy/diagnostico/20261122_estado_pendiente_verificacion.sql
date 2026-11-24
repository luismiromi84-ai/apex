-- =============================================================================
-- 20261122_estado_pendiente_verificacion.sql
--
-- La etiqueta visible del estado BORRADOR de la compra pasa a "Pendiente"
-- (pedido del dueno, 2026-11-22). El VALOR guardado no cambia: de BORRADOR
-- dependen las condiciones de las paginas 28/29, la emision de comprobantes y
-- el libro. Es el mismo patron que "Procesada" para REGISTRADA.
--
--   P1  fn_estado_compra: BORRADOR se lee "Pendiente" y los demas no cambian
--   P2  el modelo intacto: el CHECK sigue admitiendo BORRADOR y ninguna fila
--       guarda "Pendiente"
--   P3  el chip de la pagina 27 se lee "Pendiente" y sigue filtrando por
--       data-filtro="BORRADOR" (el valor de la base)
--   P4  la tarjeta del KPI se llama "Pendientes", no "En borrador"
--   P5  el CSS de la pagina 27 declara la insignia .status-Pendiente
--   P6  los mensajes de los packages ya no dicen "en BORRADOR" y dicen
--       "pendiente" (lo que ve el usuario al tocar una compra procesada)
--   P7  la lista (27) y la cabecera (28) siguen rotulando con fn_estado_compra
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261122_estado_pendiente_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000) := '';
    v_txt    varchar2(32767);
    v_src    clob;
    v_n      number;

    procedure falla(p_caso varchar2, p_detalle varchar2) is
    begin
        v_fallas := v_fallas + 1;
        v_lista  := v_lista || ' | ' || p_caso || ': ' || substrb(p_detalle, 1, 160);
    end;
begin
    ------------------------------------------------------------------ P1
    begin
        if fn_estado_compra('BORRADOR') <> 'Pendiente' then
            falla('P1', 'BORRADOR se lee ' || fn_estado_compra('BORRADOR'));
        end if;
        for c in (select 'REGISTRADA' est, 'Procesada' esp from dual union all
                  select 'PARCIAL', 'Abonada' from dual union all
                  select 'PAGADA', 'Pagada' from dual union all
                  select 'ANULADA', 'Anulada' from dual) loop
            if fn_estado_compra(c.est) <> c.esp then
                falla('P1', c.est || ' se lee ' || fn_estado_compra(c.est) || ' y deberia ser ' || c.esp);
            end if;
        end loop;
    exception
        when others then
            falla('P1', sqlerrm);
    end;

    ------------------------------------------------------------------ P2
    begin
        select count(*) into v_n
          from all_constraints
         where owner = 'WKSP_SYPEXWS'
           and table_name = 'COMPRAS'
           and constraint_name = 'CHK_COMPRAS_ESTADO'
           and search_condition_vc like '%BORRADOR%';
        if v_n <> 1 then
            falla('P2', 'el CHECK de COMPRAS ya no admite BORRADOR');
        end if;

        select count(*) into v_n from compras where upper(estado) = 'PENDIENTE';
        if v_n <> 0 then
            falla('P2', 'hay ' || v_n || ' compras guardadas con el valor PENDIENTE');
        end if;
    exception
        when others then
            falla('P2', sqlerrm);
    end;

    ------------------------------------------------------------------ P3
    begin
        select region_source into v_src
          from apex_application_page_regions
         where application_id = 100 and page_id = 27
           and region_id = 43000000000001561;
        v_txt := v_src;
        if instr(v_txt, 'data-filtro="BORRADOR"') = 0 then
            falla('P3', 'el chip dejo de filtrar por el valor BORRADOR');
        end if;
        if instr(v_txt, 'Pendiente') = 0 then
            falla('P3', 'el chip no se lee Pendiente');
        end if;
        if instr(v_txt, '>Borrador') > 0 then
            falla('P3', 'el chip todavia dice Borrador');
        end if;
    exception
        when others then
            falla('P3', sqlerrm);
    end;

    ------------------------------------------------------------------ P4
    begin
        select region_source into v_src
          from apex_application_page_regions
         where application_id = 100 and page_id = 27
           and region_id = 43000000000001560;
        v_txt := v_src;
        if instr(v_txt, 'Pendientes') = 0 then
            falla('P4', 'la tarjeta no se lee Pendientes');
        end if;
        if instr(v_txt, 'En borrador') > 0 then
            falla('P4', 'la tarjeta todavia dice En borrador');
        end if;
    exception
        when others then
            falla('P4', sqlerrm);
    end;

    ------------------------------------------------------------------ P5
    begin
        select inline_css into v_txt
          from apex_application_pages
         where application_id = 100 and page_id = 27;
        if instr(v_txt, '.status-Pendiente') = 0 then
            falla('P5', 'el CSS de la pagina 27 no tiene .status-Pendiente');
        end if;
        if instr(v_txt, '.status-BORRADOR') = 0 then
            falla('P5', 'se quito la clase .status-BORRADOR (rompe datos viejos en vuelo)');
        end if;
    exception
        when others then
            falla('P5', sqlerrm);
    end;

    ------------------------------------------------------------------ P6
    begin
        -- Los dos mensajes de pantalla que ve el usuario al tocar una compra ya
        -- procesada (proceso de la 28 y de la 29).
        select count(*) into v_n
          from apex_application_page_proc
         where application_id = 100 and page_id in (28, 29)
           and upper(process_source) like '%YA NO ESTA EN BORRADOR%';
        if v_n <> 0 then
            falla('P6', 'quedan ' || v_n || ' mensajes de pantalla que dicen en BORRADOR');
        end if;

        select count(*) into v_n
          from apex_application_page_proc
         where application_id = 100 and page_id in (28, 29)
           and upper(process_source) like '%YA NO ESTA EN ESTADO PENDIENTE%';
        if v_n < 2 then
            falla('P6', 'los mensajes de la 28/29 no dicen estado pendiente (' || v_n || ')');
        end if;
    exception
        when others then
            falla('P6', sqlerrm);
    end;

    ------------------------------------------------------------------ P7
    begin
        -- La lista rotula con la funcion (asi la insignia toma la clase nueva).
        select region_source into v_src
          from apex_application_page_regions
         where application_id = 100 and page_id = 27
           and region_id = 43000000000001000;
        v_txt := v_src;
        if instr(lower(v_txt), 'fn_estado_compra') = 0 then
            falla('P7', 'la lista de la 27 no usa fn_estado_compra');
        end if;

        -- La cabecera de la 28 publica la etiqueta en P28_ESTADO_TXT.
        select count(*) into v_n
          from apex_application_page_proc
         where application_id = 100 and page_id = 28
           and instr(lower(process_source), 'p28_estado_txt') > 0
           and instr(lower(process_source), 'fn_estado_compra') > 0;
        if v_n < 1 then
            falla('P7', 'la 28 ya no publica la etiqueta con fn_estado_compra');
        end if;
    exception
        when others then
            falla('P7', sqlerrm);
    end;

    raise_application_error(-20100,
        substrb('RESULTADO: FALLAS=' || v_fallas || v_lista, 1, 3000));
end;
/
