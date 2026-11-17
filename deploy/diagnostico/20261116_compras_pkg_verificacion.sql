-- =============================================================================
-- 20261116_compras_pkg_verificacion.sql
--
-- Cabecera de compras (Task 4): estados, duplicados, retencion al registrar.
-- Todo el DML va dentro de un SAVEPOINT y se revierte.
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261116_compras_pkg_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

begin
    begin execute immediate 'drop table tmp_comp_pkg_fallas purge'; exception when others then null; end;
end;
/

create table tmp_comp_pkg_fallas (caso varchar2(300))
/

declare
    type t_lista is table of varchar2(300);
    v_fallas t_lista := t_lista();
    v_msg    varchar2(300);

    v_prov   number;
    v_prov2  number;
    v_usu2   number;
    v_usu1   number;
    v_c      number;
    v_c2     number;
    v_estado varchar2(20);
    v_folio  varchar2(50);
    v_ctrl   varchar2(30);
    v_pct    number;
    v_ret    number;
    v_num    varchar2(14);

    procedure falla(p_texto varchar2) is
    begin
        v_fallas.extend;
        v_fallas(v_fallas.last) := substrb(p_texto, 1, 300);
    end;

    procedure espera_error is
    begin
        null;
    end;
begin
    savepoint sp_pkg;

    insert into proveedores (id_empresa, rif, razon_social, cod_pais)
    values (1, 'J-TESTPKG-1', 'Proveedor uno', 'VE')
    returning id_proveedor into v_prov;

    insert into proveedores (id_empresa, rif, razon_social, cod_pais)
    values (2, 'J-TESTPKG-2', 'Proveedor de la empresa dos', 'MX')
    returning id_proveedor into v_prov2;

    -- Usuario de la empresa 2 para probar la guarda de empresa.
    insert into usuario (username, email, estado, id_empresa, password_hash)
    values ('test_pkg_otra', 'test_pkg@local', 'ACTIVO', 2, 'x')
    returning usuario_id into v_usu2;

    insert into usuario (username, email, estado, id_empresa, password_hash)
    values ('test_pkg_uno', 'test_pkg1@local', 'ACTIVO', 1, 'x')
    returning usuario_id into v_usu1;

    -- C1: alta nueva en BORRADOR con folio y control del proveedor.
    pkg_compras.prc_guardar_compra(
        p_id_compra => v_c, p_id_empresa => 1, p_id_proveedor => v_prov,
        p_tipo_documento => 'FAC', p_folio_factura => 'PKG-1',
        p_nro_control => '00-999', p_fecha_emision => sysdate,
        p_cod_moneda => 'VES', p_tipo_cambio => 1,
        p_porcentaje_retencion => null, p_id_compra_origen => null,
        p_observaciones => 'prueba', p_usuario => 'test_pkg_uno');

    select estado, folio_factura, nro_control, porcentaje_retencion
      into v_estado, v_folio, v_ctrl, v_pct
      from compras where id_compra = v_c;
    if v_estado <> 'BORRADOR' or v_folio <> 'PKG-1' or v_ctrl <> '00-999' or v_pct <> 75 then
        falla('C1: alta ' || v_estado || '/' || v_folio || '/' || v_ctrl || '/' || v_pct);
    end if;

    -- C2: el mismo folio del mismo proveedor y tipo no entra; con NC si entra.
    begin
        pkg_compras.prc_guardar_compra(
            p_id_compra => v_c2, p_id_empresa => 1, p_id_proveedor => v_prov,
            p_tipo_documento => 'FAC', p_folio_factura => 'PKG-1',
            p_nro_control => null, p_fecha_emision => sysdate,
            p_cod_moneda => 'VES', p_tipo_cambio => 1,
            p_porcentaje_retencion => null, p_id_compra_origen => null,
            p_observaciones => null, p_usuario => 'test_pkg_uno');
        falla('C2: el folio repetido no fallo');
    exception
        when others then
            if sqlcode <> -20080 then falla('C2: codigo ' || sqlcode || ' en vez de -20080'); end if;
    end;

    pkg_compras.prc_guardar_compra(
        p_id_compra => v_c2, p_id_empresa => 1, p_id_proveedor => v_prov,
        p_tipo_documento => 'NC', p_folio_factura => 'PKG-1',
        p_nro_control => null, p_fecha_emision => sysdate,
        p_cod_moneda => 'VES', p_tipo_cambio => 1,
        p_porcentaje_retencion => null, p_id_compra_origen => v_c,
        p_observaciones => null, p_usuario => 'test_pkg_uno');
    if v_c2 is null then falla('C2: la nota con el mismo folio no entro'); end if;

    -- C3: proveedor de otra empresa.
    begin
        pkg_compras.prc_guardar_compra(
            p_id_compra => v_c2, p_id_empresa => 1, p_id_proveedor => v_prov2,
            p_tipo_documento => 'FAC', p_folio_factura => 'PKG-9',
            p_nro_control => null, p_fecha_emision => sysdate,
            p_cod_moneda => 'VES', p_tipo_cambio => 1,
            p_porcentaje_retencion => null, p_id_compra_origen => null,
            p_observaciones => null, p_usuario => 'test_pkg_uno');
        falla('C3: el proveedor ajeno no fallo');
    exception
        when others then
            if sqlcode <> -20084 then falla('C3: codigo ' || sqlcode || ' en vez de -20084'); end if;
    end;

    -- C4: registrar sin lineas.
    begin
        pkg_compras.prc_registrar_compra(p_id_compra => v_c, p_usuario => 'test_pkg_uno');
        falla('C4: registro una compra sin lineas');
    exception
        when others then
            if sqlcode <> -20085 then falla('C4: codigo ' || sqlcode || ' en vez de -20085'); end if;
    end;

    -- C5: con lineas al 16 % queda REGISTRADA y con comprobante.
    insert into compras_det (id_compra, num_linea, descripcion, cantidad, precio_unitario,
                             id_impuesto, porcentaje_impuesto, monto_impuesto,
                             subtotal_linea, total_linea, tasa_cambio_aplicada, subtotal_bs, total_bs)
    values (v_c, 1, 'Servicio', 1, 1000, 1, 16, 160, 1000, 1160, 1, 1000, 1160);

    pkg_compras.prc_registrar_compra(p_id_compra => v_c, p_usuario => 'test_pkg_uno');

    select estado into v_estado from compras where id_compra = v_c;
    if v_estado <> 'REGISTRADA' then falla('C5: estado ' || v_estado); end if;

    select count(*) into v_ret from retenciones_iva where id_compra = v_c;
    if v_ret <> 1 then
        falla('C5: no se creo el comprobante');
    else
        select numero_comprobante, iva_retenido_bs into v_num, v_ret
          from retenciones_iva where id_compra = v_c;
        if length(v_num) <> 14 then falla('C5: numero ' || v_num); end if;
        if v_ret <> 120 then falla('C5: retenido ' || v_ret || ' en vez de 120'); end if;
    end if;

    -- C6: porcentaje 0 -> REGISTRADA y sin comprobante.
    pkg_compras.prc_guardar_compra(
        p_id_compra => v_c2, p_id_empresa => 1, p_id_proveedor => v_prov,
        p_tipo_documento => 'FAC', p_folio_factura => 'PKG-2',
        p_nro_control => null, p_fecha_emision => sysdate,
        p_cod_moneda => 'VES', p_tipo_cambio => 1,
        p_porcentaje_retencion => 0, p_id_compra_origen => null,
        p_observaciones => null, p_usuario => 'test_pkg_uno');
    insert into compras_det (id_compra, num_linea, descripcion, cantidad, precio_unitario,
                             id_impuesto, porcentaje_impuesto, monto_impuesto,
                             subtotal_linea, total_linea, tasa_cambio_aplicada, subtotal_bs, total_bs)
    values (v_c2, 1, 'Servicio', 1, 1000, 1, 16, 160, 1000, 1160, 1, 1000, 1160);
    pkg_compras.prc_registrar_compra(p_id_compra => v_c2, p_usuario => 'test_pkg_uno');
    select count(*) into v_ret from retenciones_iva where id_compra = v_c2;
    if v_ret <> 0 then falla('C6: creo comprobante con retencion 0'); end if;

    -- C7: editar una REGISTRADA.
    begin
        pkg_compras.prc_guardar_compra(
            p_id_compra => v_c2, p_id_empresa => 1, p_id_proveedor => v_prov,
            p_tipo_documento => 'FAC', p_folio_factura => 'PKG-2',
            p_nro_control => null, p_fecha_emision => sysdate,
            p_cod_moneda => 'VES', p_tipo_cambio => 1,
            p_porcentaje_retencion => 0, p_id_compra_origen => null,
            p_observaciones => 'cambio', p_usuario => 'test_pkg_uno');
        falla('C7: edito una compra registrada');
    exception
        when others then
            if sqlcode <> -20083 then falla('C7: codigo ' || sqlcode || ' en vez de -20083'); end if;
    end;

    -- C8: anular deja ANULADA y anula el comprobante.
    pkg_compras.prc_anular_compra(p_id_compra => v_c, p_usuario => 'test_pkg_uno');
    select estado into v_estado from compras where id_compra = v_c;
    if v_estado <> 'ANULADA' then falla('C8: estado ' || v_estado); end if;
    select count(*) into v_ret from retenciones_iva where id_compra = v_c and estado = 'ANULADO';
    if v_ret <> 1 then falla('C8: el comprobante no quedo anulado'); end if;

    -- C9: moneda extranjera con tasa 1 (invalida).
    begin
        pkg_compras.prc_guardar_compra(
            p_id_compra => v_c2, p_id_empresa => 1, p_id_proveedor => v_prov,
            p_tipo_documento => 'FAC', p_folio_factura => 'PKG-3',
            p_nro_control => null, p_fecha_emision => sysdate,
            p_cod_moneda => 'USD', p_tipo_cambio => 1,
            p_porcentaje_retencion => null, p_id_compra_origen => null,
            p_observaciones => null, p_usuario => 'test_pkg_uno');
        falla('C9: acepto USD con tasa 1');
    exception
        when others then
            if sqlcode <> -20061 then falla('C9: codigo ' || sqlcode || ' en vez de -20061'); end if;
    end;

    -- C10: usuario de otra empresa.
    begin
        pkg_compras.prc_guardar_compra(
            p_id_compra => v_c2, p_id_empresa => 1, p_id_proveedor => v_prov,
            p_tipo_documento => 'FAC', p_folio_factura => 'PKG-4',
            p_nro_control => null, p_fecha_emision => sysdate,
            p_cod_moneda => 'VES', p_tipo_cambio => 1,
            p_porcentaje_retencion => null, p_id_compra_origen => null,
            p_observaciones => null, p_usuario => 'test_pkg_otra');
        falla('C10: un usuario de otra empresa pudo guardar');
    exception
        when others then
            if sqlcode <> -20003 then falla('C10: codigo ' || sqlcode || ' en vez de -20003'); end if;
    end;

    rollback to sp_pkg;

    for i in 1 .. v_fallas.count loop
        insert into tmp_comp_pkg_fallas values (v_fallas(i));
    end loop;
exception
    when others then
        rollback to sp_pkg;
        v_msg := substrb('C?: el caso revento: ' || sqlerrm, 1, 300);
        insert into tmp_comp_pkg_fallas values (v_msg);
end;
/

declare
    v_fallas number;
    v_lista  varchar2(3000);
begin
    select count(*) into v_fallas from tmp_comp_pkg_fallas;
    select substrb(listagg(caso, ' | ' on overflow truncate) within group (order by caso), 1, 3000)
      into v_lista from tmp_comp_pkg_fallas;
    execute immediate 'drop table tmp_comp_pkg_fallas purge';
    raise_application_error(-20100, substrb('RESULTADO: FALLAS=' || v_fallas || ' | ' || v_lista, 1, 3000));
end;
/
