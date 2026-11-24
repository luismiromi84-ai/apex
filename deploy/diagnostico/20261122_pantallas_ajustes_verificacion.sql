-- =============================================================================
-- 20261122_pantallas_ajustes_verificacion.sql
--
-- Tres ajustes pedidos por el dueno el 2026-11-22, despues de probar:
--
--   A) En el pago, las retenciones se muestran en la MONEDA DE LA FACTURA, con su
--      columna de IGTF y la formula del saldo escrita. Un total de 1.480 y un saldo
--      de 1.420 no son un diferencial cambiario: son 60 de retencion de IVA que se
--      guarda en bolivares y se pintaba al lado de importes en dolares.
--   B) Las pestanas «Datos fiscales» y «Logo» de la 19 trabajan sobre una sola
--      empresa resuelta (la que se edita o la activa de la barra), sin su propio
--      combo; antes, con varias empresas, salia todo en blanco.
--   C) La pagina 34 decia «Concepto guardado.» DOS veces (el cuerpo del proceso y
--      su atributo) y el aviso no se cerraba solo.
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261122_pantallas_ajustes_verificacion.sql
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
        select region_source into v_src
          from apex_application_page_regions
         where application_id = 100 and page_id = 37
           and region_id = 43000000000001591;
        v_txt := v_src;
        if instr(v_txt, 'v_iva_doc') = 0 or instr(v_txt, '/ v_tc_doc') = 0 then
            falla('A1', 'la tabla de facturas abiertas no pasa las retenciones a la moneda de la factura');
        end if;
        if instr(v_txt, 'v_igtf_doc') = 0 then
            falla('A1', 'la tabla de facturas abiertas no muestra el IGTF');
        end if;
        if instr(upper(v_txt), 'SENIAT') = 0 then
            falla('A1', 'no explica que la retencion de IVA se entera al SENIAT');
        end if;
    exception
        when others then
            falla('A1', sqlerrm);
    end;

    ------------------------------------------------------------------ A2
    begin
        select region_source into v_src
          from apex_application_page_regions
         where application_id = 100 and page_id = 37
           and region_id = 43000000000001680;
        v_txt := v_src;
        if instr(v_txt, 'v_iva') = 0 or instr(v_txt, '/ v_tc') = 0 then
            falla('A2', 'la tabla del pago registrado sigue con las retenciones en bolivares');
        end if;
        if instr(upper(v_txt), 'SENIAT') = 0 then
            falla('A2', 'la tabla del pago registrado no explica la retencion');
        end if;
    exception
        when others then
            falla('A2', sqlerrm);
    end;

    ------------------------------------------------------------------ B1
    begin
        select count(*) into v_n
          from apex_application_page_items
         where application_id = 100 and page_id = 19
           and item_name in ('P19F_ID_EMPRESA', 'P19L_ID_EMPRESA')
           and display_as_code = 'NATIVE_HIDDEN';
        if v_n <> 2 then
            falla('B1', 'los selectores de empresa de fiscal y logo no estan ocultos (' || v_n || ')');
        end if;

        -- El combo aparte era el «otro listado de empresa» que confundia.
        select count(*) into v_n
          from apex_application_page_items
         where application_id = 100 and page_id = 19
           and item_name in ('P19F_ID_EMPRESA', 'P19L_ID_EMPRESA')
           and lov_named_lov is not null;
        if v_n <> 0 then
            falla('B1', 'sigue habiendo un combo de empresa dentro de las pestanas');
        end if;
    exception
        when others then
            falla('B1', sqlerrm);
    end;

    ------------------------------------------------------------------ B2
    begin
        select count(*) into v_n
          from apex_application_page_items
         where application_id = 100 and page_id = 19
           and item_name in ('P19F_EMPRESA_NOMBRE', 'P19L_EMPRESA_NOMBRE')
           and display_as_code = 'NATIVE_DISPLAY_ONLY'
           and instr(attributes, 'send_on_page_submit') > 0;
        if v_n <> 2 then
            falla('B2', 'no se muestra el nombre de la empresa en las dos pestanas (' || v_n || ')');
        end if;
    exception
        when others then
            falla('B2', sqlerrm);
    end;

    ------------------------------------------------------------------ B3
    begin
        select count(*) into v_n
          from apex_application_page_proc
         where application_id = 100 and page_id = 19
           and static_id = 'fija-empresa-admin'
           and instr(process_source, 'F_EMPRESA_ACTIVA') > 0
           and instr(process_source, 'v_empresas_usuario') > 0;
        if v_n <> 1 then
            falla('B3', 'no existe el proceso que resuelve la empresa de administracion');
        end if;

        -- La carga fiscal ya no decide con «having count(*) = 1».
        select count(*) into v_n
          from apex_application_page_proc
         where application_id = 100 and page_id = 19
           and static_id = 'carga-datos-fiscales-admin'
           and instr(upper(process_source), 'HAVING COUNT(*) = 1') > 0;
        if v_n <> 0 then
            falla('B3', 'la carga fiscal todavia elige la empresa con having count(*) = 1');
        end if;

        -- Y la guarda de propiedad sigue.
        select count(*) into v_n
          from apex_application_page_proc
         where application_id = 100 and page_id = 19
           and static_id = 'carga-datos-fiscales-admin'
           and instr(process_source, 'fn_usuario_empresa_valida') > 0;
        if v_n <> 1 then
            falla('B3', 'la carga fiscal perdio la guarda de empresa');
        end if;
    exception
        when others then
            falla('B3', sqlerrm);
    end;

    ------------------------------------------------------------------ C1
    begin
        select count(*) into v_n
          from apex_application_page_proc
         where application_id = 100 and page_id = 34
           and instr(upper(process_source), 'G_PRINT_SUCCESS_MESSAGE') > 0;
        if v_n <> 0 then
            falla('C1', 'el proceso sigue publicando el mensaje a mano (sale dos veces)');
        end if;

        select count(*) into v_n
          from apex_application_page_proc
         where application_id = 100 and page_id = 34
           and success_message is not null and instr(success_message, 'Concepto guardado') > 0;
        if v_n <> 1 then
            falla('C1', 'el mensaje de exito del proceso se perdio');
        end if;
    exception
        when others then
            falla('C1', sqlerrm);
    end;

    ------------------------------------------------------------------ C2
    begin
        select javascript_code_onload into v_txt
          from apex_application_pages
         where application_id = 100 and page_id = 34;
        if v_txt is null or instr(v_txt, 't_Alert_Success') = 0 then
            falla('C2', 'la pagina 34 no cierra sola el aviso de guardado');
        end if;
    exception
        when others then
            falla('C2', sqlerrm);
    end;

    ------------------------------------------------------------------ C3
    begin
        select count(*) into v_n
          from apex_application_page_regions
         where application_id = 100 and page_id = 34
           and (instr(lower(region_source), 'nacional') > 0
                or instr(lower(region_source), 'no depende de la empresa') > 0);
        if v_n = 0 then
            falla('C3', 'la nota del catalogo no dice que es nacional (no depende de la empresa)');
        end if;
    exception
        when others then
            falla('C3', sqlerrm);
    end;

    raise_application_error(-20100,
        substrb('RESULTADO: FALLAS=' || v_fallas || v_lista, 1, 3000));
end;
/
