-- =============================================================================
-- 20261123_imprimir_compra_verificacion.sql
--
-- La FACTURA DE COMPRA en papel (2026-11-23): fn_imprimir_compra + pagina 39.
-- Era el ultimo documento del modulo de compras sin papel propio: la pagina 31
-- imprime el COMPROBANTE DE RETENCION, no la factura del proveedor.
--
-- El papel es el registro del documento que emitio el PROVEEDOR: lo dice en una
-- nota, para que nadie lo confunda con una factura nuestra. Lleva el estado
-- (Pendiente / Procesada / Abonada / Pagada / Anulada), las lineas, los totales
-- en la moneda del documento y en bolivares, el IGTF CONGELADO en la compra y
-- los numeros de comprobante de retencion (IVA e ISLR) cuando ya se emitieron.
--
--   C1  la funcion existe y esta VALID
--   C2  con una compra procesada arma el documento: titulo, folio del proveedor,
--       razon social, RIF, N. de control, total y la nota de que es del proveedor
--   C3  trae todas las lineas (descripcion, cantidad, precio, IVA, total)
--   C4  los comprobantes EMITIDOS salen con su numero; un BORRADOR no inventa
--       numeros de comprobante
--   C5  el IGTF es el CONGELADO en COMPRAS.IGTF_BS (no se recalcula) y lo suma
--       al neto a pagar
--   C6  devuelve NULL para un id nulo o inexistente (no inventa un papel)
--   C7  la pagina 39: region dinamica con la funcion, item oculto, boton
--       Imprimir con su accion, y las dos guardas (rol y empresa)
--   C8  la pagina 28 tiene el boton que abre la 39 con la compra, con su rol
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261123_imprimir_compra_verificacion.sql
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
    v_txt    varchar2(32767);
    v_c      clob;
    v_prov   number;
    v_comp   number;
    v_tasa   number;
    v_total  number;
    v_folio  varchar2(60);
    v_razon  varchar2(200);
    v_nc     number;
    v_nr     number;
    v_num_iva  varchar2(30);
    v_num_islr varchar2(30);
    v_nls    varchar2(40) := 'NLS_NUMERIC_CHARACTERS='',.''';

    procedure falla(p_caso varchar2, p_detalle varchar2) is
    begin
        v_fallas := v_fallas + 1;
        v_lista  := v_lista || ' | ' || p_caso || ': ' || substrb(p_detalle, 1, 150);
    end;

    -- La funcion se llama por SQL dinamico: asi esta verificacion compila (y da
    -- un ROJO legible) cuando la funcion todavia no existe.
    function documento(p_id number) return clob is
        v clob;
    begin
        execute immediate 'begin :1 := fn_imprimir_compra(:2); end;'
            using out v, in p_id;
        return v;
    end;
begin
    ------------------------------------------------------------------ C1
    begin
        select count(*) into v_n from all_objects
         where owner = 'WKSP_SYPEXWS' and object_name = 'FN_IMPRIMIR_COMPRA'
           and object_type = 'FUNCTION' and status = 'VALID';
        if v_n <> 1 then
            falla('C1', 'fn_imprimir_compra no existe o no esta VALID');
        end if;
    exception
        when others then
            falla('C1', sqlerrm);
    end;

    ------------------------------------------------------------------ C2 / C3 / C4
    begin
        -- La primera compra procesada con lineas y con comprobante de IVA emitido.
        select min(c.id_compra) into v_id
          from compras c
         where c.estado in ('REGISTRADA', 'PARCIAL', 'PAGADA')
           and exists (select 1 from compras_det d where d.id_compra = c.id_compra)
           and exists (select 1 from retenciones r
                        where r.id_compra = c.id_compra
                          and r.tipo = 'IVA' and r.estado = 'EMITIDO');

        if v_id is null then
            falla('C2', 'no hay compra procesada con lineas y comprobante para medir');
        else
            select c.folio_factura, nvl(c.tipo_cambio, 1), nvl(c.monto_total, 0), c.id_proveedor
              into v_folio, v_tasa, v_total, v_prov
              from compras c where c.id_compra = v_id;

            select pr.razon_social into v_razon
              from proveedores pr where pr.id_proveedor = v_prov;

            select r.numero_comprobante into v_num_iva
              from retenciones r
             where r.id_compra = v_id and r.tipo = 'IVA' and r.estado = 'EMITIDO';

            v_html := documento(v_id);

            if v_html is null then
                falla('C2', 'la compra ' || v_id || ' no arma documento');
            else
                v_c := v_html;
                if instr(v_c, 'FACTURA DE COMPRA') = 0 then
                    falla('C2', 'el documento no se titula FACTURA DE COMPRA');
                end if;
                if instr(v_c, sys.htf.escape_sc(v_folio)) = 0 then
                    falla('C2', 'el documento no trae el folio del proveedor ' || v_folio);
                end if;
                if instr(v_c, sys.htf.escape_sc(v_razon)) = 0 then
                    falla('C2', 'el documento no trae el proveedor');
                end if;
                if instr(v_c, 'No sustituye al original') = 0 then
                    falla('C2', 'el documento no avisa de que es del proveedor');
                end if;
                if instr(v_c, to_char(v_total, 'FM999G999G999G990D00', v_nls)) = 0 then
                    falla('C2', 'el documento no trae el total ' || v_total);
                end if;

                -- C3: todas las lineas
                select count(*) into v_n from compras_det where id_compra = v_id;
                v_nc := 0;
                for r in (select d.descripcion from compras_det d
                           where d.id_compra = v_id order by d.num_linea) loop
                    if instr(v_c, sys.htf.escape_sc(r.descripcion)) = 0 then
                        v_nc := v_nc + 1;
                    end if;
                end loop;
                if v_nc > 0 then
                    falla('C3', v_nc || ' de ' || v_n || ' linea(s) no salen en el papel');
                end if;

                -- C4: el comprobante de IVA con su numero
                if instr(v_c, v_num_iva) = 0 then
                    falla('C4', 'no sale el numero del comprobante de IVA ' || v_num_iva);
                end if;
            end if;
        end if;
    exception
        when others then
            falla('C2', sqlerrm);
    end;

    ------------------------------------------------------------------ C4 (borrador)
    begin
        savepoint sp_borr;
        select min(id_proveedor) into v_prov from proveedores where id_empresa = 1;
        insert into compras (id_empresa, id_proveedor, tipo_documento, folio_factura,
                             fecha_emision, cod_moneda, tipo_cambio, monto_total,
                             estado)
        values (1, v_prov, 'FAC', 'IMP-BORR-1', sysdate, 'USD', 900, 116, 'BORRADOR')
        returning id_compra into v_comp;

        insert into compras_det (id_compra, num_linea, descripcion, cantidad,
                                 precio_unitario, porcentaje_impuesto, monto_impuesto,
                                 subtotal_linea, total_linea, tasa_cambio_aplicada,
                                 subtotal_bs, total_bs)
        values (v_comp, 1, 'Servicio pendiente de procesar', 2, 50, 16, 16, 100, 116,
                900, 90000, 104400);

        v_html := documento(v_comp);
        v_c  := v_html;
        if v_c is null then
            falla('C4', 'un borrador no arma documento');
        else
            if instr(upper(v_c), 'PENDIENTE') = 0 then
                falla('C4', 'el borrador no dice que esta Pendiente');
            end if;
            -- La retencion aun no existe: no se puede enseñar un comprobante.
            if instr(upper(v_c), '202611') > 0 then
                falla('C4', 'el borrador inventa un numero de comprobante');
            end if;
        end if;
        rollback to sp_borr;
    exception
        when others then
            rollback to sp_borr;
            falla('C4', sqlerrm);
    end;

    ------------------------------------------------------------------ C5
    begin
        savepoint sp_igtf;
        select min(id_proveedor) into v_prov from proveedores where id_empresa = 1;
        insert into compras (id_empresa, id_proveedor, tipo_documento, folio_factura,
                             fecha_emision, cod_moneda, tipo_cambio, monto_total,
                             igtf_bs, retencion_iva_bs, estado)
        values (1, v_prov, 'FAC', 'IMP-IGTF-1', sysdate, 'USD', 900, 116,
                123.45, 0, 'REGISTRADA')
        returning id_compra into v_comp;

        insert into compras_det (id_compra, num_linea, descripcion, cantidad,
                                 precio_unitario, porcentaje_impuesto, monto_impuesto,
                                 subtotal_linea, total_linea, tasa_cambio_aplicada,
                                 subtotal_bs, total_bs)
        values (v_comp, 1, 'Servicio con IGTF congelado', 2, 50, 16, 16, 100, 116,
                900, 90000, 104400);

        -- La empresa deja de ser SPE: con el calculo en vivo el IGTF seria 0.
        update empresas set es_spe = 'N' where id_empresa = 1;

        v_html := documento(v_comp);
        v_c  := v_html;
        if v_c is null then
            falla('C5', 'no arma documento para la compra con IGTF');
        else
            if instr(v_c, '123,45') = 0 then
                falla('C5', 'el papel no trae el IGTF congelado (123,45)');
            end if;
            -- neto en Bs = 116 x 900 + 123,45
            if instr(v_c, '104.523,45') = 0 then
                falla('C5', 'el neto a pagar no suma el IGTF (104.523,45)');
            end if;
        end if;
        rollback to sp_igtf;
    exception
        when others then
            rollback to sp_igtf;
            falla('C5', sqlerrm);
    end;

    ------------------------------------------------------------------ C6
    begin
        if documento(null) is not null then
            falla('C6', 'devuelve documento con un id nulo');
        end if;
        if documento(-987654) is not null then
            falla('C6', 'devuelve documento para una compra que no existe');
        end if;
    exception
        when others then
            falla('C6', sqlerrm);
    end;

    ------------------------------------------------------------------ C7
    begin
        select count(*) into v_n
          from apex_application_page_regions
         where application_id = 100 and page_id = 39
           and region_id = 43000000000001710
           and source_type_plugin_static_id = 'NATIVE_DYNAMIC_CONTENT'
           and function_body_language = 'PLSQL'
           and instr(upper(region_source), 'FN_IMPRIMIR_COMPRA') > 0;
        if v_n <> 1 then
            falla('C7', 'la pagina 39 no tiene la region con fn_imprimir_compra');
        end if;

        select count(*) into v_n from apex_application_page_items
         where application_id = 100 and page_id = 39 and item_name = 'P39_ID_COMPRA'
           and display_as_code = 'NATIVE_HIDDEN';
        if v_n <> 1 then
            falla('C7', 'falta el item oculto P39_ID_COMPRA');
        end if;

        select count(*) into v_n from apex_application_page_buttons
         where application_id = 100 and page_id = 39
           and static_id = 'btn-imprimir-compra'
           and button_action_code = 'DEFINED_BY_DA_ACTION';
        if v_n <> 1 then
            falla('C7', 'falta el boton Imprimir de la pagina 39');
        end if;

        select count(*) into v_n from apex_application_page_proc
         where application_id = 100 and page_id = 39
           and static_id in ('valida-rol-compra-print', 'valida-empresa-compra-print');
        if v_n <> 2 then
            falla('C7', 'faltan las dos guardas de la pagina 39 (' || v_n || ')');
        end if;

        select count(*) into v_n from apex_application_page_proc
         where application_id = 100 and page_id = 39
           and static_id = 'valida-empresa-compra-print'
           and instr(process_source, 'fn_usuario_empresa_valida') > 0;
        if v_n <> 1 then
            falla('C7', 'la guarda de empresa no usa fn_usuario_empresa_valida');
        end if;
    exception
        when others then
            falla('C7', sqlerrm);
    end;

    ------------------------------------------------------------------ C8
    begin
        select count(*) into v_n
          from apex_application_page_buttons
         where application_id = 100 and page_id = 28
           and static_id = 'btn-imprimir-compra-28'
           and instr(upper(redirect_url), ':39:') > 0
           and instr(upper(redirect_url), 'P39_ID_COMPRA') > 0
           and instr(condition_expression1, 'fn_tiene_rol') > 0;
        if v_n <> 1 then
            falla('C8', 'la pagina 28 no tiene el boton de imprimir la compra');
        end if;
    exception
        when others then
            falla('C8', sqlerrm);
    end;

    raise_application_error(-20100,
        substrb('RESULTADO: FALLAS=' || v_fallas || v_lista, 1, 3000));
end;
/
