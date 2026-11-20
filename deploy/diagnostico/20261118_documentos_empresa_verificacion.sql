-- =============================================================================
-- 20261118_documentos_empresa_verificacion.sql
--
-- El documento no se puede mover a otra empresa (revisión del 2026-11-18):
--   D1  actualizar un presupuesto de una empresa ajena da -20003 y NO lo toca
--   D2  actualizar una factura de una empresa ajena da -20003 y NO la toca
--   D3  un cliente de otra empresa da -20029 (presupuesto)
--   D4  un cliente de otra empresa da -20029 (factura)
--   D5  el caso legítimo sigue funcionando (documento propio, cliente propio)
--   D6  los ítems ocultos de empresa no son obligatorios (APEX no bloquea el guardado)
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261118_documentos_empresa_verificacion.sql
-- FALLAS=0 = EXITO (el runner sale con 1 a propósito: -20100).
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

begin
    begin execute immediate 'drop table tmp_docmix_fallas purge'; exception when others then null; end;
end;
/

create table tmp_docmix_fallas (caso varchar2(300))
/

declare
    v_user      varchar2(50);
    v_emp_user  number;
    v_emp_otra  number;
    v_idp       number;
    v_idf       number;
    v_cli_otra  number;
    v_cli_prop  number;
    v_est_antes varchar2(20);
    v_tot_antes number;
    v_est_desp  varchar2(20);
    v_tot_desp  number;
    v_cod       number;
    v_id        number;
    v_n         number;
    v_folio     varchar2(30);
    v_fac_ini   number;
    v_ctl_ini   number;
    v_pres_ini  number;
    v_nc_ini    number;
    v_nd_ini    number;

    procedure falla(p varchar2) is
    begin
        insert into tmp_docmix_fallas values (substrb(p, 1, 300));
    end;
begin
    -- Un usuario ACTIVO con empresa, y una empresa que NO es suya con documentos.
    select min(u.username) into v_user
      from usuario u
     where u.estado in ('ACTIVO', 'A', '1')
       and exists (select 1 from usuario_empresa ue where ue.usuario_id = u.usuario_id);
    if v_user is null then
        falla('PRE: no hay usuario con empresa');
        return;
    end if;

    select min(ue.id_empresa) into v_emp_user
      from usuario_empresa ue
      join usuario u on u.usuario_id = ue.usuario_id
     where upper(u.username) = upper(v_user);

    -- Los contadores de folio de esa empresa, tal como estan: los casos de abajo
    -- crean documentos con folio y los borran, y el commit de D5 los dejaba por
    -- delante (hueco en la numeracion fiscal). Se restauran al final.
    select nvl(max(case when tipo = 'FAC'          then ultimo end), 0),
           nvl(max(case when tipo = 'CONTROL'      then ultimo end), 0),
           nvl(max(case when tipo = 'PRESUPUESTO' then ultimo end), 0),
           nvl(max(case when tipo = 'NC'           then ultimo end), 0),
           nvl(max(case when tipo = 'ND'           then ultimo end), 0)
      into v_fac_ini, v_ctl_ini, v_pres_ini, v_nc_ini, v_nd_ini
      from folio_contador
     where id_empresa = v_emp_user;

    select min(p.id_empresa) into v_emp_otra
      from presupuestos p
     where p.id_empresa not in (select ue.id_empresa from usuario_empresa ue
                                 join usuario u on u.usuario_id = ue.usuario_id
                                where upper(u.username) = upper(v_user));
    if v_emp_otra is null then
        falla('PRE: no hay una empresa ajena con presupuestos (carga el fixture)');
        return;
    end if;

    select min(p.id_presupuesto) into v_idp from presupuestos p where p.id_empresa = v_emp_otra;
    select min(f.id_factura) into v_idf from facturas f where f.id_empresa = v_emp_otra;
    select min(c.id_cliente) into v_cli_otra from clientes c where c.id_empresa = v_emp_otra;
    select min(c.id_cliente) into v_cli_prop from clientes c where c.id_empresa = v_emp_user;

    apex_application.g_user := v_user;

    -- D1: mover/actualizar un presupuesto ajeno
    select estado, total into v_est_antes, v_tot_antes from presupuestos where id_presupuesto = v_idp;
    v_cod := 0;
    v_id  := v_idp;
    begin
        pkg_presupuestos.prc_guardar_presupuesto(
            p_id_presupuesto    => v_id,
            p_id_empresa        => v_emp_user,
            p_id_cliente        => v_cli_prop,
            p_folio             => 'X-1',
            p_cod_moneda        => 'VES',
            p_fecha_vencimiento => null,
            p_fecha_emision     => sysdate,
            p_tipo_cambio       => 1,
            p_estado            => 'PENDIENTE',
            p_observaciones     => null,
            p_usuario           => v_user);
    exception
        when others then v_cod := sqlcode;
    end;
    select estado, total into v_est_desp, v_tot_desp from presupuestos where id_presupuesto = v_idp;
    if v_cod <> -20003 then
        falla('D1: actualizar un presupuesto ajeno devolvio ' || v_cod || ' (se esperaba -20003)');
    end if;
    if v_est_desp <> v_est_antes or nvl(v_tot_desp, -1) <> nvl(v_tot_antes, -2) then
        falla('D1: el presupuesto ajeno CAMBIO (estado ' || v_est_desp || ', total ' || v_tot_desp || ')');
    end if;

    -- D2: actualizar una factura ajena
    if v_idf is not null then
        select folio_factura, estado into v_folio, v_est_antes from facturas where id_factura = v_idf;
        v_cod := 0;
        begin
            pkg_facturacion.prc_actualizar(
                p_id_factura      => v_idf,
                p_id_empresa      => v_emp_user,
                p_folio_factura   => v_folio,
                p_id_cliente      => v_cli_prop,
                p_id_presupuesto  => null,
                p_rfc_emisor      => null,
                p_rfc_receptor    => null,
                p_uuid_fiscal     => null,
                p_uso_cfdi        => null,
                p_forma_pago      => null,
                p_metodo_pago     => null,
                p_condicion_pago  => null,
                p_fecha_emision   => to_char(sysdate, 'DD/MM/YYYY'),
                p_fecha_vencimiento => null,
                p_estado          => 'PENDIENTE',
                p_subtotal        => 1,
                p_monto_impuesto  => 0,
                p_monto_total     => 1,
                p_observaciones   => null,
                p_cod_moneda      => 'VES',
                p_tipo_cambio     => 1);
        exception
            when others then v_cod := sqlcode;
        end;
        select estado into v_est_desp from facturas where id_factura = v_idf;
        if v_cod <> -20003 then
            falla('D2: actualizar una factura ajena devolvio ' || v_cod || ' (se esperaba -20003)');
        end if;
        if v_est_desp <> v_est_antes then
            falla('D2: la factura ajena CAMBIO de estado a ' || v_est_desp);
        end if;
    end if;

    -- D3: cliente de otra empresa en un presupuesto propio
    if v_cli_otra is not null and v_cli_prop is not null then
        v_cod := 0;
        v_id  := null;
        begin
            pkg_presupuestos.prc_guardar_presupuesto(
                p_id_presupuesto    => v_id,
                p_id_empresa        => v_emp_user,
                p_id_cliente        => v_cli_otra,
                p_folio             => 'X-2',
                p_cod_moneda        => 'VES',
                p_fecha_vencimiento => null,
                p_fecha_emision     => sysdate,
                p_tipo_cambio       => 1,
                p_estado            => 'PENDIENTE',
                p_observaciones     => null,
                p_usuario           => v_user);
        exception
            when others then v_cod := sqlcode;
        end;
        if v_cod <> -20029 then
            falla('D3: un cliente de otra empresa devolvio ' || v_cod || ' (se esperaba -20029)');
        end if;

        -- D4: lo mismo en la factura
        v_cod := 0;
        v_id  := null;
        begin
            pkg_facturacion.prc_guardar_factura(
                p_id_factura      => v_id,
                p_id_empresa      => v_emp_user,
                p_folio_factura   => 'X-3',
                p_id_cliente      => v_cli_otra,
                p_id_presupuesto  => null,
                p_rfc_emisor      => null,
                p_rfc_receptor    => null,
                p_uuid_fiscal     => null,
                p_uso_cfdi        => null,
                p_forma_pago      => null,
                p_metodo_pago     => null,
                p_condicion_pago  => null,
                p_fecha_emision   => to_char(sysdate, 'DD/MM/YYYY'),
                p_fecha_vencimiento => null,
                p_estado          => 'PENDIENTE',
                p_subtotal        => 1,
                p_monto_impuesto  => 0,
                p_monto_total     => 1,
                p_observaciones   => null,
                p_cod_moneda      => 'VES',
                p_tipo_cambio     => 1,
                p_usuario         => v_user);
        exception
            when others then v_cod := sqlcode;
        end;
        if v_cod <> -20029 then
            falla('D4: un cliente de otra empresa en la factura devolvio ' || v_cod || ' (se esperaba -20029)');
        end if;
    end if;

    -- D5: el caso legítimo. Se crea un presupuesto con cliente propio y se borra.
    v_cod := 0;
    v_id  := null;
    begin
        pkg_presupuestos.prc_guardar_presupuesto(
            p_id_presupuesto    => v_id,
            p_id_empresa        => v_emp_user,
            p_id_cliente        => v_cli_prop,
            p_folio             => 'X-4',
            p_cod_moneda        => 'VES',
            p_fecha_vencimiento => null,
            p_fecha_emision     => sysdate,
            p_tipo_cambio       => 1,
            p_estado            => 'PENDIENTE',
            p_observaciones     => null,
            p_usuario           => v_user);
    exception
        when others then v_cod := sqlcode;
    end;
    if v_cod <> 0 then
        falla('D5: el alta legitima devolvio ' || v_cod);
    else
        delete from presupuestos where id_presupuesto = v_id;
        commit;
    end if;

    -- D6: los ítems ocultos de empresa, sin ser obligatorios
    select count(*) into v_n
      from apex_application_page_items
     where application_id = 100
       and item_name in ('P7_ID_EMPRESA', 'P9_ID_EMPRESA', 'P13_ID_EMPRESA')
       and is_required = 'Yes';
    if v_n > 0 then
        falla('D6: ' || v_n || ' item(s) de empresa ocultos siguen siendo obligatorios');
    end if;

    -- Los casos de esta verificacion dan de alta documentos con folio del contador
    -- y los borran; el commit de D5 dejaba los contadores POR DELANTE (un hueco en
    -- la numeracion fiscal, que es justo lo que vigila 20261118_folios_verificacion).
    -- Se devuelven al valor que tenian al empezar (medido: subian FAC, CONTROL y
    -- PRESUPUESTO en 1 cada corrida).
    update folio_contador set ultimo = v_fac_ini  where id_empresa = v_emp_user and tipo = 'FAC';
    update folio_contador set ultimo = v_ctl_ini  where id_empresa = v_emp_user and tipo = 'CONTROL';
    update folio_contador set ultimo = v_pres_ini where id_empresa = v_emp_user and tipo = 'PRESUPUESTO';
    update folio_contador set ultimo = v_nc_ini   where id_empresa = v_emp_user and tipo = 'NC';
    update folio_contador set ultimo = v_nd_ini   where id_empresa = v_emp_user and tipo = 'ND';
    commit;
end;
/

declare
    v_fallas number;
    v_lista  varchar2(3000);
begin
    select count(*) into v_fallas from tmp_docmix_fallas;
    select substrb(listagg(caso, ' | ' on overflow truncate) within group (order by caso), 1, 3000)
      into v_lista from tmp_docmix_fallas;
    execute immediate 'drop table tmp_docmix_fallas purge';
    raise_application_error(-20100, substrb('RESULTADO: FALLAS=' || v_fallas || ' | ' || v_lista, 1, 3000));
end;
/
