-- =============================================================================
-- 20261122_imprimir_pago_verificacion.sql
--
-- El COMPROBANTE DE PAGO en papel (2026-11-22): fn_imprimir_pago + pagina 38,
-- espejo del recibo de cobro (35) para el dinero que sale.
--
--   E1  la funcion existe y esta VALID
--   E2  con un pago de la base arma el documento: titulo, proveedor, la factura
--       aplicada y el total pagado
--   E3  devuelve NULL para un pago que no existe (no inventa un papel en blanco)
--   E4  la pagina 38: region de contenido dinamico con la funcion, item oculto,
--       boton Imprimir con su accion y las dos guardas (rol y empresa)
--   E5  el boton de la pagina 37 lleva a la 38 con el pago
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261122_imprimir_pago_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000) := '';
    v_n      number;
    v_id     number;
    v_html   clob;
    v_prov   varchar2(200);
    v_folio  varchar2(60);

    procedure falla(p_caso varchar2, p_detalle varchar2) is
    begin
        v_fallas := v_fallas + 1;
        v_lista  := v_lista || ' | ' || p_caso || ': ' || substrb(p_detalle, 1, 170);
    end;
begin
    ------------------------------------------------------------------ E1
    begin
        select count(*) into v_n from all_objects
         where owner = 'WKSP_SYPEXWS' and object_name = 'FN_IMPRIMIR_PAGO'
           and object_type = 'FUNCTION' and status = 'VALID';
        if v_n <> 1 then
            falla('E1', 'fn_imprimir_pago no existe o no esta VALID');
        end if;
    exception
        when others then
            falla('E1', sqlerrm);
    end;

    ------------------------------------------------------------------ E2
    begin
        select min(id_pago) into v_id from pagos;
        if v_id is null then
            falla('E2', 'no hay pagos en la base para medir el documento');
        else
            v_html := fn_imprimir_pago(v_id);

            select pr.razon_social into v_prov
              from pagos p join proveedores pr on pr.id_proveedor = p.id_proveedor
             where p.id_pago = v_id;

            select min(co.folio_factura) into v_folio
              from pagos_detalle d join compras co on co.id_compra = d.id_compra
             where d.id_pago = v_id;

            if v_html is null then
                falla('E2', 'el pago ' || v_id || ' no arma documento');
            else
                if instr(v_html, 'COMPROBANTE DE PAGO') = 0 then
                    falla('E2', 'el documento no dice COMPROBANTE DE PAGO');
                end if;
                if instr(v_html, sys.htf.escape_sc(v_prov)) = 0 then
                    falla('E2', 'el documento no trae el proveedor ' || v_prov);
                end if;
                if v_folio is not null and instr(v_html, v_folio) = 0 then
                    falla('E2', 'el documento no trae la factura aplicada ' || v_folio);
                end if;
                if instr(upper(v_html), 'TOTAL PAGADO') = 0 then
                    falla('E2', 'el documento no declara el total pagado');
                end if;
                if instr(upper(v_html), 'WINDOW.PRINT') > 0 then
                    falla('E2', 'el documento no debe traer el dialogo de impresion');
                end if;
            end if;
        end if;
    exception
        when others then
            falla('E2', sqlerrm);
    end;

    ------------------------------------------------------------------ E3
    begin
        if fn_imprimir_pago(-987654) is not null then
            falla('E3', 'devuelve un documento para un pago que no existe');
        end if;
    exception
        when others then
            falla('E3', sqlerrm);
    end;

    ------------------------------------------------------------------ E4
    begin
        select count(*) into v_n
          from apex_application_page_regions
         where application_id = 100 and page_id = 38
           and region_id = 43000000000001700
           and source_type_plugin_static_id = 'NATIVE_DYNAMIC_CONTENT'
           and function_body_language = 'PLSQL'
           and instr(upper(region_source), 'FN_IMPRIMIR_PAGO') > 0;
        if v_n <> 1 then
            falla('E4', 'la pagina 38 no tiene la region con fn_imprimir_pago');
        end if;

        select count(*) into v_n from apex_application_page_items
         where application_id = 100 and page_id = 38 and item_name = 'P38_ID_PAGO'
           and display_as_code = 'NATIVE_HIDDEN';
        if v_n <> 1 then
            falla('E4', 'falta el item oculto P38_ID_PAGO');
        end if;

        select count(*) into v_n from apex_application_page_buttons
         where application_id = 100 and page_id = 38
           and static_id = 'btn-imprimir-pago' and button_action_code = 'DEFINED_BY_DA_ACTION';
        if v_n <> 1 then
            falla('E4', 'falta el boton Imprimir');
        end if;

        select count(*) into v_n
          from apex_application_page_proc
         where application_id = 100 and page_id = 38
           and static_id in ('valida-rol-pago-print', 'valida-empresa-pago-print');
        if v_n <> 2 then
            falla('E4', 'faltan las dos guardas de la pagina 38 (' || v_n || ')');
        end if;

        select count(*) into v_n
          from apex_application_page_proc
         where application_id = 100 and page_id = 38
           and static_id = 'valida-empresa-pago-print'
           and instr(process_source, 'fn_usuario_empresa_valida') > 0;
        if v_n <> 1 then
            falla('E4', 'la guarda de empresa no usa fn_usuario_empresa_valida');
        end if;
    exception
        when others then
            falla('E4', sqlerrm);
    end;

    ------------------------------------------------------------------ E5
    begin
        select count(*) into v_n
          from apex_application_page_buttons
         where application_id = 100 and page_id = 37
           and static_id = 'btn-imprimir-pago-37'
           and instr(redirect_url, ':38:') > 0
           and instr(redirect_url, 'P38_ID_PAGO') > 0;
        if v_n <> 1 then
            falla('E5', 'la pagina 37 no tiene el boton que abre el comprobante');
        end if;
    exception
        when others then
            falla('E5', sqlerrm);
    end;

    raise_application_error(-20100,
        substrb('RESULTADO: FALLAS=' || v_fallas || v_lista, 1, 3000));
end;
/
