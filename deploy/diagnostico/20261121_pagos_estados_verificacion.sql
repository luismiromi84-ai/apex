-- =============================================================================
-- 20261121_pagos_estados_verificacion.sql
--
-- Cobrar una compra no puede romper lo que ya funcionaba (2026-11-21). Al añadir
-- PARCIAL y PAGADA, cuatro sitios daban por hecho que "registrada" era el ultimo
-- estado:
--
--   E1  fn_estado_compra etiqueta los cinco estados (Abonada y Pagada son nuevas)
--   E2  los chips de la lista de compras (27) tienen Abonada y Pagada, y la
--       consulta los filtra
--   E3  el boton «Imprimir comprobante» de la compra (28) se pinta tambien en una
--       compra abonada o pagada (un comprobante ya emitido se tiene que reimprimir)
--   E4  pkg_retenciones ya no rechaza por estado una compra abonada o pagada (lo
--       unico que la frena es que ya tenga su comprobante)
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261121_pagos_estados_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000) := '';
    v_num    number;
    v_txt    clob;
    v_txt2   varchar2(4000);
    v_emp    number;
    v_prov   number;
    v_user   varchar2(100);
    v_prod   number;
    v_imp    number;
    v_compra number;
    v_det    number;
    v_pago   number;
    v_folio  number;

    procedure falla(p_caso varchar2, p_detalle varchar2) is
    begin
        v_fallas := v_fallas + 1;
        v_lista  := v_lista || ' | ' || p_caso || ': ' || p_detalle;
    end;

    procedure espera_txt(p_caso varchar2, p_valor varchar2, p_esperado varchar2, p_que varchar2) is
    begin
        if p_valor is null or p_valor <> p_esperado then
            falla(p_caso, p_que || ' = ' || nvl(p_valor, 'NULL')
                        || ' (esperado ' || p_esperado || ')');
        end if;
    end;

begin
    -- E1: las cinco etiquetas --------------------------------------------------
    espera_txt('E1', fn_estado_compra('BORRADOR'), 'Borrador', 'etiqueta de BORRADOR');
    espera_txt('E1', fn_estado_compra('REGISTRADA'), 'Procesada', 'etiqueta de REGISTRADA');
    espera_txt('E1', fn_estado_compra('PARCIAL'), 'Abonada', 'etiqueta de PARCIAL');
    espera_txt('E1', fn_estado_compra('PAGADA'), 'Pagada', 'etiqueta de PAGADA');
    espera_txt('E1', fn_estado_compra('ANULADA'), 'Anulada', 'etiqueta de ANULADA');

    -- E2: los chips de la 27 ---------------------------------------------------
    select count(*) into v_num
      from apex_260100.apex_application_page_regions
     where application_id = 100 and page_id = 27 and region_static_id = 'chips-compras';
    if v_num = 1 then
        select region_source into v_txt
          from apex_260100.apex_application_page_regions
         where application_id = 100 and page_id = 27 and region_static_id = 'chips-compras';
        v_txt2 := dbms_lob.substr(v_txt, 4000, 1);
        if instr(v_txt2, 'ABONADA') = 0 then
            falla('E2', 'el chip Abonada no esta en la region de filtros');
        end if;
        if instr(v_txt2, 'PAGADA') = 0 then
            falla('E2', 'el chip Pagada no esta en la region de filtros');
        end if;
    else
        falla('E2', 'no encontre la region chips-compras de la pagina 27');
    end if;

    select count(*) into v_num
      from apex_260100.apex_application_page_regions
     where application_id = 100 and page_id = 27 and region_static_id = 'compras-lista';
    if v_num = 1 then
        select region_source into v_txt
          from apex_260100.apex_application_page_regions
         where application_id = 100 and page_id = 27 and region_static_id = 'compras-lista';
        v_txt2 := dbms_lob.substr(v_txt, 8000, 1);
        if instr(v_txt2, '''ABONADA''') = 0 or instr(v_txt2, '''PAGADA''') = 0 then
            falla('E2', 'la consulta de la lista no filtra por ABONADA y PAGADA');
        end if;
    else
        falla('E2', 'no encontre la region compras-lista de la pagina 27');
    end if;

    -- E3: el boton de imprimir comprobante -------------------------------------
    select count(*) into v_num
      from apex_260100.apex_application_page_buttons
     where application_id = 100 and page_id = 28
       and button_name = 'BTN_IMPRIMIR_RETENCION'
       and instr(condition_expression1, '''PARCIAL''') > 0
       and instr(condition_expression1, '''PAGADA''') > 0;
    if v_num <> 1 then
        falla('E3', 'el boton Imprimir comprobante no admite PARCIAL/PAGADA');
    end if;

    -- E4: el paquete ya no rechaza por estado ----------------------------------
    select min(e.id_empresa) into v_emp from empresas e where e.cod_pais = 'VE';

    select min(u.username) into v_user
      from usuario u join usuario_empresa ue on ue.usuario_id = u.usuario_id
     where ue.id_empresa = v_emp;

    select min(p.id_proveedor) into v_prov from proveedores p where p.id_empresa = v_emp;
    select min(ps.id_producto_servicio) into v_prod from producto_servicio ps;
    select min(i.id_impuesto) into v_imp
      from impuestos i
     where i.cod_pais = 'VE' and nvl(i.aplica_en, 'LINEA') = 'LINEA' and i.porcentage = 16;

    if v_emp is not null and v_prov is not null and v_user is not null
       and v_prod is not null and v_imp is not null then

        savepoint sp_est;

        select nvl(max(id_compra), 0) + 1 into v_folio from compras;

        insert into compras (id_empresa, id_proveedor, tipo_documento, folio_factura, fecha_emision,
                             cod_moneda, tipo_cambio, estado)
        values (v_emp, v_prov, 'FAC', 'VERIF-E-' || v_folio, date '2026-11-21', 'VES', 1, 'BORRADOR')
        returning id_compra into v_compra;

        pkg_compra_detalle.guardar_detalle(v_det, v_compra, 1, v_prod, 'Verif estados',
                                           1, 100, 0, 0, v_imp, 16, v_user);
        pkg_compras.prc_registrar_compra(v_compra, v_user);

        pkg_pagos.prc_registrar_pago(
            p_id_proveedor => v_prov, p_fecha => date '2026-11-21', p_moneda => 'VES',
            p_tasa => 1, p_monto => 10, p_id_forma_pago => null,
            p_aplicaciones => '[{"id_compra":' || v_compra || ',"monto":10}]',
            p_usuario => v_user, p_id_pago => v_pago);

        select estado into v_txt2 from compras where id_compra = v_compra;
        espera_txt('E4', v_txt2, 'PARCIAL', 'estado de la compra abonada');

        begin
            pkg_retenciones.prc_emitir(v_compra, v_num, v_user);
            -- si no falla es que emitio otro comprobante: tambien vale como
            -- "no rechazo por estado", pero lo normal es que ya tuviera uno
            null;
        exception
            when others then
                if sqlcode = -20083 and instr(sqlerrm, 'Solo se emite comprobante') > 0 then
                    falla('E4', 'el paquete sigue rechazando una compra PARCIAL por estado');
                end if;
        end;

        update compras set estado = 'PAGADA' where id_compra = v_compra;

        begin
            pkg_retenciones.prc_emitir(v_compra, v_num, v_user);
            null;
        exception
            when others then
                if sqlcode = -20083 and instr(sqlerrm, 'Solo se emite comprobante') > 0 then
                    falla('E4', 'el paquete sigue rechazando una compra PAGADA por estado');
                end if;
        end;

        rollback to sp_est;
    end if;

    raise_application_error(-20100,
        substrb('RESULTADO: FALLAS=' || v_fallas || v_lista, 1, 3000));
end;
/
