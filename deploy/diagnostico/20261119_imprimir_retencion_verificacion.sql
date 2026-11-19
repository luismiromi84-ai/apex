-- =============================================================================
-- 20261119_imprimir_retencion_verificacion.sql
--
-- El comprobante de retencion en papel (2026-11-19):
--   V1 fn_imprimir_retencion esta VALID
--   V2 arma el documento con el numero, la base y el IVA retenido
--   V3 devuelve NULL si la compra no tiene comprobante (no inventa un papel)
--   V4 la pagina 31 lo sirve y tiene su guarda de rol
--   V5 la compra (28) tiene el boton para imprimirlo
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261119_imprimir_retencion_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000) := '';
    v_n      number;
    v_id     number;
    v_num    varchar2(14);
    v_base   number;
    v_ret    number;
    v_txt    clob;

    procedure falla(p_caso varchar2, p_detalle varchar2) is
    begin
        v_fallas := v_fallas + 1;
        v_lista  := v_lista || ' | ' || p_caso || ': ' || substrb(p_detalle, 1, 140);
    end;
begin
    -- V1
    select count(*) into v_n from all_objects
     where owner = 'WKSP_SYPEXWS' and object_name = 'FN_IMPRIMIR_RETENCION'
       and status = 'VALID';
    if v_n < 1 then
        falla('V1', 'fn_imprimir_retencion no esta VALID');
    end if;

    -- V2: con un comprobante real
    select id_compra, numero_comprobante, base_imponible_bs, iva_retenido_bs
      into v_id, v_num, v_base, v_ret
      from retenciones_iva
     where rownum = 1;

    v_txt := fn_imprimir_retencion(v_id);
    if v_txt is null then
        falla('V2', 'no armo el documento');
    else
        if instr(v_txt, v_num) = 0 then
            falla('V2', 'el documento no trae el numero ' || v_num);
        end if;
        if instr(v_txt, 'IVA retenido') = 0 then
            falla('V2', 'el documento no trae el IVA retenido');
        end if;
        if instr(v_txt, 'Base imponible') = 0 then
            falla('V2', 'el documento no trae la base imponible');
        end if;
    end if;

    -- V3: una compra sin comprobante devuelve NULL
    begin
        select min(id_compra) into v_n from compras
         where id_compra not in (select id_compra from retenciones_iva);
        if v_n is not null then
            v_txt := fn_imprimir_retencion(v_n);
            if v_txt is not null then
                falla('V3', 'invento un comprobante para una compra sin retencion');
            end if;
        end if;
    exception
        when no_data_found then null;
    end;

    -- V4: la pagina 31
    select count(*) into v_n
      from apex_260100.apex_application_page_regions
     where application_id = 100 and page_id = 31
       and source_type_plugin_static_id = 'NATIVE_DYNAMIC_CONTENT'
       and lower(region_source) like '%fn_imprimir_retencion%';
    if v_n <> 1 then
        falla('V4', 'la pagina 31 no sirve el comprobante');
    end if;

    select count(*) into v_n
      from apex_260100.apex_application_page_proc
     where application_id = 100 and page_id = 31
       and static_id = 'valida-rol-retencion-print';
    if v_n <> 1 then
        falla('V4', 'la pagina 31 no tiene su guarda de rol');
    end if;

    -- V5: el boton en la compra
    select count(*) into v_n
      from apex_260100.apex_application_page_buttons
     where application_id = 100 and page_id = 28
       and button_name = 'BTN_IMPRIMIR_RETENCION';
    if v_n <> 1 then
        falla('V5', 'la compra (28) no tiene el boton de imprimir');
    end if;

    raise_application_error(-20100,
        substrb('RESULTADO: FALLAS=' || v_fallas || v_lista, 1, 3000));
end;
/
