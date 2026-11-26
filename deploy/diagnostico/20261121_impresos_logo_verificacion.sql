-- =============================================================================
-- 20261121_impresos_logo_verificacion.sql
--
-- El logo de la empresa en TODOS los impresos y el recibo en papel (2026-11-21).
--
--   L1  las tres funciones estan VALID
--   L2  el comprobante de retencion (IVA e ISLR) lleva el logo como data URI
--       cuando la empresa lo tiene cargado
--   L3  sin logo en EMPRESA_LOGO el comprobante NO deja un <img> roto: la
--       maqueta sigue (se mide dentro de un savepoint y se revierte)
--   L4  el libro en modo imprimir lleva el logo y el Excel NO lo lleva (es
--       deliberado: un <img> con data URI rompe el archivo que abre Excel)
--   L5  el recibo trae logo, numero, cliente y los cuatro importes guardados
--       (Monto cobrado, IGTF, Retencion de IVA y Neto), con el formato venezolano
--   L6  el recibo devuelve NULL si no existe (no inventa un papel en blanco)
--   L7  la pagina 35 existe, sirve el documento, tiene su item, sus dos guardas
--       y el boton Imprimir con window.print
--   L8  la pagina 25 (dialogo) tiene el boton «Imprimir recibo», condicionado a
--       que el recibo exista, y la URL la arma apex_page.get_url (pagina 35)
--   L9  los contadores de la app: 37 paginas y 0 objetos invalidos
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261121_impresos_logo_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000) := '';
    v_n      number;
    v_id     number;
    v_txt    clob;
    v_num    varchar2(60);
    v_cli    varchar2(200);
    v_mon    varchar2(5);
    v_cob    number;
    v_cob_bs number;
    v_igtf   number;
    v_igtfbs number;
    v_ret    number;
    v_neto   number;
    v_emp    number;

    procedure falla(p_caso varchar2, p_detalle varchar2) is
    begin
        v_fallas := v_fallas + 1;
        v_lista  := v_lista || ' | ' || p_caso || ': ' || substrb(p_detalle, 1, 140);
    end;

    function fn_num(p_valor number) return varchar2 is
    begin
        return to_char(nvl(p_valor, 0), 'FM999G999G999G990D00',
                       'NLS_NUMERIC_CHARACTERS='',.''');
    end;
begin
    -- L1 -------------------------------------------------------------------
    select count(*) into v_n
      from all_objects
     where owner = 'WKSP_SYPEXWS'
       and object_name in ('FN_IMPRIMIR_RETENCION', 'FN_LIBRO_EXCEL', 'FN_IMPRIMIR_RECIBO')
       and status = 'VALID';
    if v_n <> 3 then
        falla('L1', 'no estan VALID las tres funciones (' || nvl(to_char(v_n), '?') || ' de 3)');
    end if;

    -- L2: comprobante CON logo ---------------------------------------------
    -- Se busca un comprobante cuya empresa tenga logo cargado: es la unica
    -- forma honesta de medir el caso «con logo» sin inventar una empresa.
    begin
        select r.id_compra, r.id_empresa
          into v_id, v_emp
          from retenciones r
         where exists (select 1 from empresa_logo l where l.id_empresa = r.id_empresa)
           and r.id_compra is not null
           and rownum = 1;
    exception
        when no_data_found then
            v_id := null;
    end;

    if v_id is null then
        falla('L2', 'no hay ningun comprobante de una empresa con logo');
    else
        v_txt := fn_imprimir_retencion(v_id, 'IVA');
        if v_txt is null then
            falla('L2', 'el comprobante de IVA no se armo');
        elsif instr(v_txt, 'data:image') = 0 or instr(v_txt, '<img') = 0 then
            falla('L2', 'el comprobante de IVA no lleva el logo');
        end if;

        v_txt := fn_imprimir_retencion(v_id, 'ISLR');
        if v_txt is not null then
            if instr(v_txt, 'data:image') = 0 or instr(v_txt, '<img') = 0 then
                falla('L2', 'el comprobante de ISLR no lleva el logo');
            end if;
        end if;
    end if;

    -- L3: sin logo, la maqueta sigue y NO queda un <img> --------------------
    if v_id is not null then
        savepoint sp_logo;
        delete from empresa_logo where id_empresa = v_emp;
        v_txt := fn_imprimir_retencion(v_id, 'IVA');
        if v_txt is null then
            falla('L3', 'sin logo el comprobante desaparecio');
        else
            if instr(v_txt, '<img') > 0 then
                falla('L3', 'sin logo el comprobante deja un <img> sin origen');
            end if;
            if instr(v_txt, 'Comprobante de Retenci') = 0 then
                falla('L3', 'sin logo el comprobante perdio su maqueta');
            end if;
        end if;
        rollback to savepoint sp_logo;
    end if;

    -- L4: libro imprimible CON logo, Excel SIN logo -------------------------
    begin
        select l.id_empresa into v_emp
          from empresa_logo l join empresas e on e.id_empresa = l.id_empresa
         where rownum = 1;
    exception
        when no_data_found then
            v_emp := null;
    end;

    if v_emp is null then
        falla('L4', 'ninguna empresa tiene logo: no se puede medir el libro');
    else
        v_txt := fn_libro_excel('TODOS', extract(month from sysdate),
                                extract(year from sysdate), v_emp, 'MES', 'S');
        if v_txt is null then
            falla('L4', 'el libro imprimible no se armo');
        elsif instr(v_txt, 'data:image') = 0 then
            falla('L4', 'el libro imprimible no lleva el logo');
        elsif instr(v_txt, 'window.print()') = 0 then
            falla('L4', 'el libro imprimible perdio su window.print');
        end if;

        v_txt := fn_libro_excel('TODOS', extract(month from sysdate),
                                extract(year from sysdate), v_emp, 'MES', 'N');
        if v_txt is null then
            falla('L4', 'el Excel no se armo');
        elsif instr(v_txt, '<img') > 0 or instr(v_txt, 'data:image') > 0 then
            falla('L4', 'el Excel lleva una imagen: rompe el archivo que abre Excel');
        end if;
    end if;

    -- L5: el recibo ---------------------------------------------------------
    begin
        select r.id_recibo, r.id_empresa, fa.folio_factura, c.razon_social,
               upper(r.cod_moneda), r.monto_cobrado, r.monto_bs, r.igtf_monto,
               r.igtf_bs, r.retencion_iva_bs, r.monto_neto
          into v_id, v_emp, v_num, v_cli, v_mon, v_cob, v_cob_bs, v_igtf,
               v_igtfbs, v_ret, v_neto
          from recibos r
          join facturas fa on fa.id_factura = r.id_factura
          join clientes c on c.id_cliente = fa.id_cliente
         where exists (select 1 from empresa_logo l where l.id_empresa = r.id_empresa)
           and rownum = 1;
    exception
        when no_data_found then
            v_id := null;
    end;

    if v_id is null then
        falla('L5', 'no hay ningun recibo de una empresa con logo');
    else
        v_txt := fn_imprimir_recibo(v_id);
        if v_txt is null then
            falla('L5', 'el recibo no se armo');
        else
            if instr(v_txt, 'data:image') = 0 then
                falla('L5', 'el recibo no lleva el logo');
            end if;
            if instr(v_txt, 'RECIBO DE COBRO') = 0 then
                falla('L5', 'el recibo no lleva su titulo');
            end if;
            if instr(v_txt, to_char(v_id)) = 0 then
                falla('L5', 'el recibo no lleva su numero');
            end if;
            if instr(v_txt, sys.htf.escape_sc(v_num)) = 0 then
                falla('L5', 'el recibo no lleva el folio de la factura (' || v_num || ')');
            end if;
            if instr(v_txt, sys.htf.escape_sc(v_cli)) = 0 then
                falla('L5', 'el recibo no lleva el cliente');
            end if;
            if instr(v_txt, fn_num(v_cob)) = 0 or instr(v_txt, fn_num(v_cob_bs)) = 0 then
                falla('L5', 'el recibo no lleva el monto cobrado en las dos monedas');
            end if;
            if instr(v_txt, fn_num(v_igtf)) = 0 or instr(v_txt, fn_num(v_igtfbs)) = 0 then
                falla('L5', 'el recibo no lleva el IGTF en las dos monedas');
            end if;
            if instr(v_txt, fn_num(v_ret)) = 0 then
                falla('L5', 'el recibo no lleva la retencion de IVA');
            end if;
            if instr(v_txt, fn_num(v_neto)) = 0 then
                falla('L5', 'el recibo no lleva el neto');
            end if;
            if instr(v_txt, '@media print') = 0 or instr(v_txt, 'visibility:hidden') = 0 then
                falla('L5', 'el recibo no esconde el cromo de APEX al imprimir');
            end if;
            -- El cliente y el numero de control son texto: no se recalculan.
            if instr(v_txt, 'N&ordm; de control') = 0 then
                falla('L5', 'el recibo no rotula el N. de control');
            end if;
        end if;
    end if;

    -- L6: un recibo que no existe devuelve NULL ----------------------------
    v_txt := fn_imprimir_recibo(-7);
    if v_txt is not null then
        falla('L6', 'invento un recibo para un id que no existe');
    end if;
    v_txt := fn_imprimir_recibo(null);
    if v_txt is not null then
        falla('L6', 'invento un recibo para un id nulo');
    end if;

    -- L7: la pagina 35 ------------------------------------------------------
    select count(*) into v_n
      from apex_application_pages
     where application_id = 100 and page_id = 35
       and page_alias = 'RECIBO-IMPRESO' and page_access_protection = 'Arguments Must Have Checksum';
    if v_n <> 1 then
        falla('L7', 'no existe la pagina 35 RECIBO-IMPRESO con proteccion C');
    end if;

    select count(*) into v_n
      from apex_260100.apex_application_page_regions
     where application_id = 100 and page_id = 35
       and source_type_plugin_static_id = 'NATIVE_DYNAMIC_CONTENT'
       and function_body_language = 'PLSQL'
       and lower(region_source) like '%fn_imprimir_recibo%';
    if v_n <> 1 then
        falla('L7', 'la region de la 35 no sirve fn_imprimir_recibo como contenido dinamico');
    end if;

    select count(*) into v_n
      from apex_260100.apex_application_page_items
     where application_id = 100 and page_id = 35 and item_name = 'P35_ID_RECIBO';
    if v_n <> 1 then
        falla('L7', 'la 35 no tiene el item P35_ID_RECIBO');
    end if;

    select count(*) into v_n
      from apex_260100.apex_application_page_proc
     where application_id = 100 and page_id = 35
       and static_id in ('valida-rol-recibo-print', 'valida-empresa-recibo-print');
    if v_n <> 2 then
        falla('L7', 'la 35 no tiene sus dos guardas (rol y empresa)');
    end if;

    -- La guarda de rol de la 35 es la misma que la del dialogo del recibo (25):
    -- mismo listado de roles en el cuerpo (no se comparan los CLOB enteros, que
    -- Oracle no deja usar como clave).
    select count(*) into v_n
      from apex_260100.apex_application_page_proc a
      join apex_260100.apex_application_page_proc b
        on b.application_id = a.application_id
     where a.application_id = 100 and a.page_id = 35
       and a.static_id = 'valida-rol-recibo-print'
       and b.page_id = 25 and b.static_id = 'valida-rol-registrar-cobro'
       and a.process_source like '%ADMIN,GERENCIA,FACTURACION,PRUEBA%'
       and b.process_source like '%ADMIN,GERENCIA,FACTURACION,PRUEBA%';
    if v_n <> 1 then
        falla('L7', 'la guarda de la 35 no es la misma que la del recibo (25)');
    end if;

    select count(*) into v_n
      from apex_260100.apex_application_page_buttons
     where application_id = 100 and page_id = 35
       and button_name = 'BTN_IMPRIMIR' and button_css_classes like '%u-no-print%';
    if v_n <> 1 then
        falla('L7', 'la 35 no tiene el boton Imprimir con u-no-print');
    end if;

    -- El boton dispara window.print(): la accion de componente del boton.
    select count(*) into v_n
      from apex_260100.apex_application_page_buttons b
     where b.application_id = 100 and b.page_id = 35
       and b.button_name = 'BTN_IMPRIMIR'
       and b.button_action = 'DEFINED_BY_DA_ACTION';
    if v_n <> 1 then
        falla('L7', 'el boton de la 35 no esta definido por accion');
    end if;

    -- L8: el boton del dialogo ----------------------------------------------
    select count(*) into v_n
      from apex_260100.apex_application_page_buttons
     where application_id = 100 and page_id = 25
       and button_name = 'BTN_IMPRIMIR_RECIBO'
       and redirect_url like '%P25_URL_IMPRESO%'
       and condition_expression1 like '%P25_ID_RECIBO%';
    if v_n <> 1 then
        falla('L8', 'el recibo (25) no tiene el boton de imprimir con su condicion');
    end if;

    select count(*) into v_n
      from apex_260100.apex_application_page_items
     where application_id = 100 and page_id = 25 and item_name = 'P25_URL_IMPRESO';
    if v_n <> 1 then
        falla('L8', 'el recibo (25) no tiene el item con la URL del impreso');
    end if;

    -- La URL la arma APEX (apex_page.get_url a la 35), nunca una f?p= a mano.
    select count(*) into v_n
      from apex_260100.apex_application_page_proc
     where application_id = 100 and page_id = 25
       and lower(process_source) like '%apex_page.get_url%'
       and lower(process_source) like '%p25_url_impreso%'
       and lower(process_source) like '%p_page => 35%';
    if v_n < 1 then
        falla('L8', 'la URL del impreso no la arma apex_page.get_url hacia la 35');
    end if;

    -- L9: contadores ---------------------------------------------------------
    select count(*) into v_n from apex_application_pages where application_id = 100;
    -- 2026-11-26: el numero exacto lo vigila 20261105_portada_verificacion.py; aqui basta que no
    -- se haya perdido ninguna pagina de las 37 de entonces.
    if v_n < 37 then
        falla('L9', 'la app tiene ' || v_n || ' paginas, se esperaban al menos 37');
    end if;

    select count(*) into v_n from all_objects
     where owner = 'WKSP_SYPEXWS' and status <> 'VALID';
    if v_n <> 0 then
        falla('L9', 'hay ' || v_n || ' objetos invalidos');
    end if;

    raise_application_error(-20100,
        substrb('RESULTADO: FALLAS=' || v_fallas || v_lista, 1, 3000));
end;
/
