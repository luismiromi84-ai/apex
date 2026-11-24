-- =============================================================================
-- 20261122_pagar_proveedor_verificacion.sql
--
-- El atajo «Pagar» desde la lista de compras (27) y la ficha del proveedor (33)
-- con lo que se le debe y sus pagos (2026-11-22).
--
--   P1  la lista de compras trae «Pagar» por fila, con el enlace a la 37 y el
--       proveedor; la consulta tiene que devolver id_proveedor para el #...#
--   P2  «Pagar» esta en el informe POR DEFECTO
--   P3  la ficha tiene la region «Pagos al proveedor» sobre PAGOS
--   P4  los indicadores de la ficha calculan «Por pagar» con fn_saldo_compra
--   P5  la ficha tiene el boton «Pagar» que abre la 37 con el proveedor
--   P6  spxNum de la pagina 37 entiende «1.420,00» y «1,420.00»
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261122_pagar_proveedor_verificacion.sql
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
    ------------------------------------------------------------------ P1
    begin
        select region_source into v_src
          from apex_application_page_regions
         where application_id = 100 and page_id = 27
           and region_id = 43000000000001000;
        v_txt := v_src;
        if instr(lower(v_txt), 'c.id_proveedor') = 0 then
            falla('P1', 'la consulta de la lista no devuelve id_proveedor');
        end if;

        select count(*) into v_n
          from apex_application_page_ir_col
         where application_id = 100 and page_id = 27
           and column_alias = 'PAGAR'
           and instr(column_link, ':37:') > 0
           and instr(column_link, 'P37_ID_PROVEEDOR') > 0
           and instr(column_link, '#PAGAR#') > 0;
        if v_n <> 1 then
            falla('P1', 'no existe la columna Pagar con el enlace a la 37 y el proveedor');
        end if;
    exception
        when others then
            falla('P1', sqlerrm);
    end;

    ------------------------------------------------------------------ P2
    begin
        select count(*) into v_n
          from apex_application_page_ir_rpt
         where application_id = 100 and page_id = 27
           and status = 'PUBLIC'
           and instr(report_columns, ':PAGAR') > 0;
        if v_n <> 1 then
            falla('P2', 'Pagar no esta en el informe por defecto de la 27');
        end if;
    exception
        when others then
            falla('P2', sqlerrm);
    end;

    ------------------------------------------------------------------ P3
    begin
        select count(*) into v_n
          from apex_application_page_regions
         where application_id = 100 and page_id = 33
           and region_id = 43000000000001690
           and instr(upper(region_source), 'FROM PAGOS') > 0
           and instr(upper(region_source), 'P33_ID_PROVEEDOR') > 0;
        if v_n <> 1 then
            falla('P3', 'la ficha no tiene la region de pagos del proveedor');
        end if;
    exception
        when others then
            falla('P3', sqlerrm);
    end;

    ------------------------------------------------------------------ P4
    begin
        select region_source into v_src
          from apex_application_page_regions
         where application_id = 100 and page_id = 33
           and region_id = 43000000000001381;
        v_txt := v_src;
        if instr(lower(v_txt), 'fn_saldo_compra') = 0 then
            falla('P4', 'los indicadores de la ficha no calculan lo que se debe');
        end if;
        if instr(v_txt, 'Por pagar') = 0 then
            falla('P4', 'la ficha no tiene la tarjeta Por pagar');
        end if;
    exception
        when others then
            falla('P4', sqlerrm);
    end;

    ------------------------------------------------------------------ P5
    begin
        select count(*) into v_n
          from apex_application_page_buttons
         where application_id = 100 and page_id = 33
           and static_id = 'btn-pagar-proveedor'
           and instr(redirect_url, ':37:') > 0
           and instr(redirect_url, 'P37_ID_PROVEEDOR') > 0;
        if v_n <> 1 then
            falla('P5', 'la ficha no tiene el boton Pagar hacia la 37');
        end if;
    exception
        when others then
            falla('P5', sqlerrm);
    end;

    ------------------------------------------------------------------ P6
    begin
        select javascript_code into v_txt
          from apex_application_pages
         where application_id = 100 and page_id = 37;
        -- El parser nuevo mira la ultima coma y el ultimo punto; el viejo solo
        -- cambiaba la primera coma por un punto ("1.420,00" -> 1,42).
        if instr(v_txt, 'lastIndexOf') = 0 then
            falla('P6', 'spxNum de la 37 no distingue miles de decimales');
        end if;
    exception
        when others then
            falla('P6', sqlerrm);
    end;

    raise_application_error(-20100,
        substrb('RESULTADO: FALLAS=' || v_fallas || v_lista, 1, 3000));
end;
/
