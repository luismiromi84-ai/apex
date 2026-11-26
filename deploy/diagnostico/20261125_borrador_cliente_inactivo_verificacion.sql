-- =============================================================================
-- 20261125_borrador_cliente_inactivo_verificacion.sql
--
-- Tarea 3 de la revision funcional (2026-11-25):
--   B1 anular un BORRADOR (PENDIENTE) lo deja ANULADO y NO crea nota de credito
--   B2 el borrador anulado conserva su folio y su N° de control
--   B3 guardar una FACTURA a un cliente INACTIVO se rechaza (-20068)
--   B4 emitir (procesar) un borrador de un cliente que paso a INACTIVO se rechaza (-20068)
--   B5 una NOTA de credito a un cliente INACTIVO si se permite (para anular sus facturas)
--
-- Empresa temporal 900260 con rango de control; se limpia al final.
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261125_borrador_cliente_inactivo_verificacion.sql
-- FALLAS=0 = EXITO (el runner sale con codigo 1 aunque sea verde: se lee el mensaje).
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

begin
    begin execute immediate 'drop table tmp_bci_fallas purge'; exception when others then null; end;
end;
/

create table tmp_bci_fallas (caso varchar2(400))
/

begin
    begin delete from facturas_det where id_factura in (select id_factura from facturas where id_empresa = 900260); commit; exception when others then null; end;
    begin delete from facturas where id_empresa = 900260; commit; exception when others then null; end;
    begin delete from folio_contador where id_empresa = 900260; commit; exception when others then null; end;
    begin delete from empresa_fiscal where id_empresa = 900260; commit; exception when others then null; end;
    begin delete from clientes where id_empresa = 900260; commit; exception when others then null; end;
    begin delete from empresas where id_empresa = 900260; commit; exception when others then null; end;
end;
/

insert into empresas (id_empresa, nombre_empresa, cod_pais, tipo_ident_fiscal, rfc, estado)
values (900260, 'DIAG BORRADOR', 'VE', 'RIF', 'J-90026000-1', 'ACTIVO')
/

insert into empresa_fiscal (id_empresa, control_desde, control_hasta, tipo_emision)
values (900260, '00-000001', '00-000100', 'FORMA_LIBRE')
/

insert into clientes (id_empresa, rif, razon_social, tipo_persona, cod_pais, estado)
values (900260, 'V-11111111', 'CLIENTE ACTIVO', 'N', 'VE', 'ACTIVO')
/

insert into clientes (id_empresa, rif, razon_social, tipo_persona, cod_pais, estado)
values (900260, 'V-22222222', 'CLIENTE INACTIVO', 'N', 'VE', 'INACTIVO')
/

commit
/

declare
    v_act   number;
    v_ina   number;
    v_id    number;
    v_nc    number;
    v_folio varchar2(30);
    v_ctrl  varchar2(30);
    v_est   varchar2(20);
    v_n     number;

    procedure falla(p varchar2) is
    begin
        insert into tmp_bci_fallas values (substrb(p, 1, 400));
        commit;
    end;

    procedure guarda(p_id in out number, p_cli number, p_tipo varchar2, p_origen number default null) is
    begin
        pkg_facturacion.prc_guardar_factura(
            p_id_factura => p_id, p_id_empresa => 900260, p_folio_factura => 'X',
            p_id_cliente => p_cli, p_id_presupuesto => null, p_rfc_emisor => 'J-90026000-1',
            p_rfc_receptor => null, p_uuid_fiscal => null, p_uso_cfdi => null,
            p_forma_pago => null, p_metodo_pago => null, p_condicion_pago => null,
            p_fecha_emision => to_char(sysdate, 'DD/MM/YYYY'), p_fecha_vencimiento => null,
            p_estado => 'PENDIENTE', p_subtotal => 0, p_monto_impuesto => 0, p_monto_total => 0,
            p_observaciones => 'prueba borrador', p_cod_moneda => 'VES', p_tipo_cambio => 1,
            p_usuario => 'DIAG', p_tipo_documento => p_tipo, p_nro_control => null,
            p_id_factura_origen => p_origen);
    end;
begin
    select id_cliente into v_act from clientes where id_empresa = 900260 and estado = 'ACTIVO';
    select id_cliente into v_ina from clientes where id_empresa = 900260 and estado = 'INACTIVO';

    -- B1/B2: borrador anulado sin nota
    v_id := null;
    guarda(v_id, v_act, 'FAC');
    select folio_factura, nro_control into v_folio, v_ctrl from facturas where id_factura = v_id;
    v_nc := -1;
    prc_anular_factura_nc(p_id_factura => v_id, p_id_nc => v_nc, p_usuario => 'DIAG');
    select estado into v_est from facturas where id_factura = v_id;
    select count(*) into v_n from facturas where id_empresa = 900260 and tipo_documento = 'NC';
    if v_est <> 'ANULADA' or v_nc is not null or v_n <> 0 then
        falla('B1: borrador anulado -> estado ' || v_est || ', id_nc ' || nvl(to_char(v_nc), 'NULL')
              || ', notas creadas ' || v_n);
    end if;
    select count(*) into v_n from facturas
     where id_factura = v_id and folio_factura = v_folio and nro_control = v_ctrl and v_ctrl is not null;
    if v_n <> 1 then
        falla('B2: el borrador anulado perdio folio o control (' || v_folio || ' / ' || nvl(v_ctrl, 'NULL') || ')');
    end if;
    commit;

    -- B3: factura a cliente inactivo
    begin
        v_id := null;
        guarda(v_id, v_ina, 'FAC');
        falla('B3: se guardo una factura a un cliente INACTIVO');
        rollback;
    exception when others then
        if sqlcode <> -20068 then falla('B3: codigo ' || sqlcode || ' ' || substr(sqlerrm, 1, 200)); end if;
        rollback;
    end;

    -- B4: un borrador del cliente activo pasa a inactivo y se intenta emitir
    v_id := null;
    guarda(v_id, v_act, 'FAC');
    commit;
    update clientes set estado = 'INACTIVO' where id_cliente = v_act;
    commit;
    begin
        pkg_facturacion.prc_procesar_factura(p_id_factura => v_id, p_usuario => 'DIAG');
        falla('B4: se emitio una factura de un cliente INACTIVO');
        rollback;
    exception when others then
        if sqlcode <> -20068 then falla('B4: codigo ' || sqlcode || ' ' || substr(sqlerrm, 1, 200)); end if;
        rollback;
    end;

    -- B5: una nota a ese cliente inactivo si se permite
    begin
        v_nc := null;
        guarda(v_nc, v_act, 'NC', v_id);
        rollback;
    exception when others then
        falla('B5: no se pudo crear una nota a un cliente INACTIVO: ' || sqlcode || ' ' || substr(sqlerrm, 1, 200));
        rollback;
    end;
end;
/

begin
    begin delete from facturas_det where id_factura in (select id_factura from facturas where id_empresa = 900260); commit; exception when others then null; end;
    begin delete from facturas where id_empresa = 900260; commit; exception when others then null; end;
    begin delete from folio_contador where id_empresa = 900260; commit; exception when others then null; end;
    begin delete from empresa_fiscal where id_empresa = 900260; commit; exception when others then null; end;
    begin delete from clientes where id_empresa = 900260; commit; exception when others then null; end;
    begin delete from empresas where id_empresa = 900260; commit; exception when others then null; end;
end;
/

declare
    v_fallas number;
    v_lista  varchar2(2000);
begin
    select count(*) into v_fallas from tmp_bci_fallas;
    select substrb(listagg(caso, ' | ' on overflow truncate) within group (order by caso), 1, 2000)
      into v_lista from tmp_bci_fallas;
    execute immediate 'drop table tmp_bci_fallas purge';
    raise_application_error(-20100, substrb('RESULTADO: FALLAS=' || v_fallas || ' | ' || v_lista, 1, 2000));
end;
/
