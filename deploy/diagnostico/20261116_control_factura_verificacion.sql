-- =============================================================================
-- 20261116_control_factura_verificacion.sql
--
-- N° de Control de las facturas: sale del rango de EMPRESA_FISCAL y se consume
-- con un contador atomico; una factura no puede pasar del «hasta» ni llevar un
-- control fuera de rango. Se prueba con una empresa temporal (900250) y se
-- limpia al final.
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261116_control_factura_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

begin
    begin execute immediate 'drop table tmp_ctl_fallas purge'; exception when others then null; end;
end;
/

create table tmp_ctl_fallas (caso varchar2(300))
/

-- Preparacion: empresa, datos fiscales con rango y un cliente.
begin
    begin
        delete from usuario_empresa where id_empresa = 900250;
        commit;
    exception when others then null; end;
    begin
        delete from facturas_det where id_factura in (select id_factura from facturas where id_empresa = 900250);
        commit;
    exception when others then null; end;
    begin
        delete from facturas where id_empresa = 900250;
        commit;
    exception when others then null; end;
    begin
        delete from folio_contador where id_empresa = 900250;
        commit;
    exception when others then null; end;
    begin
        delete from empresa_fiscal where id_empresa = 900250;
        commit;
    exception when others then null; end;
    begin
        delete from clientes where id_empresa = 900250;
        commit;
    exception when others then null; end;
    begin
        delete from empresas where id_empresa = 900250;
        commit;
    exception when others then null; end;
end;
/

insert into empresas (id_empresa, nombre_empresa, cod_pais, tipo_ident_fiscal, rfc, estado)
values (900250, 'DIAG CONTROL', 'VE', 'RIF', 'J-90025000-1', 'ACTIVO')
/

insert into empresa_fiscal (id_empresa, control_desde, control_hasta, tipo_emision)
values (900250, '900-0001', '900-0004', 'FORMA_LIBRE')
/

insert into clientes (id_empresa, rif, razon_social, tipo_persona, cod_pais, estado)
values (900250, 'V-11111111', 'CLIENTE CONTROL', 'N', 'VE', 'ACTIVO')
/

commit
/

-- C1/C2: el contador entrega 0001 y luego 0002.
declare
    v_c varchar2(60);
begin
    v_c := fn_asignar_control(900250);
    if v_c <> '900-0001' then
        insert into tmp_ctl_fallas values (substrb('C1: el primer control fue ' || v_c, 1, 300));
    end if;
    v_c := fn_asignar_control(900250);
    if v_c <> '900-0002' then
        insert into tmp_ctl_fallas values (substrb('C2: el segundo control fue ' || v_c, 1, 300));
    end if;
end;
/

-- C3: un control tecleado dentro del rango se acepta.
declare
    v_c varchar2(60);
begin
    v_c := fn_control_en_rango(900250, '900-0003');
    if v_c <> '900-0003' then
        insert into tmp_ctl_fallas values (substrb('C3: no acepto 900-0003', 1, 300));
    end if;
end;
/

-- C4/C5: fuera de rango o con otro prefijo -> -20063.
declare
    v_ok  number := 0;
    v_msg varchar2(300);
begin
    begin
        v_ok := 1;
        v_ok := length(fn_control_en_rango(900250, '900-9999'));
        insert into tmp_ctl_fallas values (substrb('C4: acepto 900-9999 (fuera de rango)', 1, 300));
    exception
        when others then
            if sqlcode <> -20063 then
                v_msg := 'C4: codigo ' || sqlcode;
                insert into tmp_ctl_fallas values (substrb(v_msg, 1, 300));
            end if;
    end;
    begin
        v_ok := length(fn_control_en_rango(900250, 'XX-0002'));
        insert into tmp_ctl_fallas values (substrb('C5: acepto un prefijo ajeno', 1, 300));
    exception
        when others then
            if sqlcode <> -20063 then
                v_msg := 'C5: codigo ' || sqlcode;
                insert into tmp_ctl_fallas values (substrb(v_msg, 1, 300));
            end if;
    end;
end;
/

-- C6: una factura guardada SIN control recibe el siguiente (900-0003).
declare
    v_id  number := null;
    v_c   varchar2(60);
    v_cli number;
begin
    select min(id_cliente) into v_cli from clientes where id_empresa = 900250;
    pkg_facturacion.prc_guardar_factura(
        p_id_factura     => v_id,
        p_id_empresa     => 900250,
        p_folio_factura  => 'X',
        p_id_cliente     => v_cli,
        p_id_presupuesto => null,
        p_rfc_emisor     => 'J-90025000-1',
        p_rfc_receptor   => 'V-11111111',
        p_uuid_fiscal    => null,
        p_uso_cfdi       => null,
        p_forma_pago     => null,
        p_metodo_pago    => null,
        p_condicion_pago => null,
        p_fecha_emision  => to_char(sysdate, 'DD/MM/YYYY'),
        p_fecha_vencimiento => null,
        p_estado         => 'PENDIENTE',
        p_subtotal       => 100,
        p_monto_impuesto => 16,
        p_monto_total    => 116,
        p_observaciones  => 'prueba control',
        p_cod_moneda     => 'VES',
        p_tipo_cambio    => 1,
        p_usuario        => 'DIAG',
        p_tipo_documento => 'FAC',
        p_nro_control    => null
    );
    select nro_control into v_c from facturas where id_factura = v_id;
    if v_c <> '900-0003' then
        insert into tmp_ctl_fallas values (substrb('C6: la factura quedo con control ' || v_c, 1, 300));
    end if;
    commit;
end;
/

-- C7: una nota de credito NO consume el contador de control.
declare
    v_id     number := null;
    v_cli    number;
    v_origen number;
begin
    select min(id_cliente) into v_cli from clientes where id_empresa = 900250;
    select min(id_factura) into v_origen from facturas where id_empresa = 900250;
    pkg_facturacion.prc_guardar_factura(
        p_id_factura     => v_id,
        p_id_empresa     => 900250,
        p_folio_factura  => 'X',
        p_id_cliente     => v_cli,
        p_id_presupuesto => null,
        p_rfc_emisor     => 'J-90025000-1',
        p_rfc_receptor   => 'V-11111111',
        p_uuid_fiscal    => null,
        p_uso_cfdi       => null,
        p_forma_pago     => null,
        p_metodo_pago    => null,
        p_condicion_pago => null,
        p_fecha_emision  => to_char(sysdate, 'DD/MM/YYYY'),
        p_fecha_vencimiento => null,
        p_estado         => 'PENDIENTE',
        p_subtotal       => 10,
        p_monto_impuesto => 1.6,
        p_monto_total    => 11.6,
        p_observaciones  => 'nota de prueba',
        p_cod_moneda     => 'VES',
        p_tipo_cambio    => 1,
        p_usuario        => 'DIAG',
        p_tipo_documento => 'NC',
        p_nro_control    => null,
        p_id_factura_origen => v_origen
    );
    commit;
end;
/

insert into tmp_ctl_fallas
select substrb('C7: la nota consumio el contador de control (ultimo='
               || (select ultimo from folio_contador where id_empresa = 900250 and tipo = 'CONTROL') || ')', 1, 300)
  from dual
 where (select ultimo from folio_contador where id_empresa = 900250 and tipo = 'CONTROL') <> 3;
/

-- C8: se agota el rango (hasta 0004): la cuarta factura entra, la quinta no.
declare
    v_cli number;
    v_msg varchar2(300);
    procedure nueva is
        v_new number := null;
    begin
        pkg_facturacion.prc_guardar_factura(
            p_id_factura     => v_new,
            p_id_empresa     => 900250,
            p_folio_factura  => 'X',
            p_id_cliente     => v_cli,
            p_id_presupuesto => null,
            p_rfc_emisor     => 'J-90025000-1',
            p_rfc_receptor   => 'V-11111111',
            p_uuid_fiscal    => null,
            p_uso_cfdi       => null,
            p_forma_pago     => null,
            p_metodo_pago    => null,
            p_condicion_pago => null,
            p_fecha_emision  => to_char(sysdate, 'DD/MM/YYYY'),
            p_fecha_vencimiento => null,
            p_estado         => 'PENDIENTE',
            p_subtotal       => 100,
            p_monto_impuesto => 16,
            p_monto_total    => 116,
            p_observaciones  => 'prueba control',
            p_cod_moneda     => 'VES',
            p_tipo_cambio    => 1,
            p_usuario        => 'DIAG',
            p_tipo_documento => 'FAC',
            p_nro_control    => null
        );
    end;
begin
    select min(id_cliente) into v_cli from clientes where id_empresa = 900250;
    nueva;   -- 900-0004
    begin
        nueva;   -- ya no hay
        insert into tmp_ctl_fallas values (substrb('C8: paso del «hasta» sin error', 1, 300));
    exception
        when others then
            if sqlcode <> -20062 then
                v_msg := 'C8: codigo ' || sqlcode;
                insert into tmp_ctl_fallas values (substrb(v_msg, 1, 300));
            end if;
    end;
    rollback;
end;
/

-- C9: editar sin control conserva el que tenia.
declare
    v_id  number;
    v_c   varchar2(60);
    v_cli number;
begin
    select min(id_factura) into v_id from facturas where id_empresa = 900250 and tipo_documento = 'FAC';
    select min(id_cliente) into v_cli from clientes where id_empresa = 900250;
    pkg_facturacion.prc_guardar_factura(
        p_id_factura     => v_id,
        p_id_empresa     => 900250,
        p_folio_factura  => 'X',
        p_id_cliente     => v_cli,
        p_id_presupuesto => null,
        p_rfc_emisor     => 'J-90025000-1',
        p_rfc_receptor   => 'V-11111111',
        p_uuid_fiscal    => null,
        p_uso_cfdi       => null,
        p_forma_pago     => null,
        p_metodo_pago    => null,
        p_condicion_pago => null,
        p_fecha_emision  => to_char(sysdate, 'DD/MM/YYYY'),
        p_fecha_vencimiento => null,
        p_estado         => 'PENDIENTE',
        p_subtotal       => 100,
        p_monto_impuesto => 16,
        p_monto_total    => 116,
        p_observaciones  => 'prueba control editada',
        p_cod_moneda     => 'VES',
        p_tipo_cambio    => 1,
        p_usuario        => 'DIAG',
        p_tipo_documento => 'FAC',
        p_nro_control    => null
    );
    select nro_control into v_c from facturas where id_factura = v_id;
    if v_c <> '900-0003' then
        insert into tmp_ctl_fallas values (substrb('C9: al editar el control quedo en ' || v_c, 1, 300));
    end if;
    rollback;
end;
/

-- Limpieza.
begin
    begin delete from facturas_det where id_factura in (select id_factura from facturas where id_empresa = 900250); commit; exception when others then null; end;
    begin delete from facturas where id_empresa = 900250; commit; exception when others then null; end;
    begin delete from folio_contador where id_empresa = 900250; commit; exception when others then null; end;
    begin delete from empresa_fiscal where id_empresa = 900250; commit; exception when others then null; end;
    begin delete from clientes where id_empresa = 900250; commit; exception when others then null; end;
    begin delete from empresas where id_empresa = 900250; commit; exception when others then null; end;
end;
/

declare
    v_fallas number;
    v_lista  varchar2(2000);
begin
    select count(*) into v_fallas from tmp_ctl_fallas;
    select substrb(listagg(caso, ' | ' on overflow truncate) within group (order by caso), 1, 2000)
      into v_lista from tmp_ctl_fallas;
    execute immediate 'drop table tmp_ctl_fallas purge';
    raise_application_error(-20100, substrb('RESULTADO: FALLAS=' || v_fallas || ' | ' || v_lista, 1, 2000));
end;
/
