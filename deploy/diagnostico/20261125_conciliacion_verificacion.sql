-- =============================================================================
-- 20261125_conciliacion_verificacion.sql
--
-- Conciliacion bancaria (pkg_conciliacion), con una cuenta temporal de la empresa 1
-- y un cobro y un pago de prueba (referencia DIAG-CONC) que se borran al final:
--   C1 abrir: estado ABIERTA y saldo inicial 0 (primera conciliacion de la cuenta)
--   C2 no se abre otra mientras haya una abierta (-20170)
--   C3 marcar el cobro (100) y el pago (30 + IGTF 2): saldo segun el sistema 68
--   C4 cerrar con el banco en 80 no cuadra (-20172)
--   C5 cerrar con el banco en 68 la deja CERRADA con diferencia 0
--   C6 un periodo que pisa el cierre se rechaza (-20171); el siguiente nace con saldo inicial 68
--   C7 anular la abierta la deja ANULADA y desmarca sus movimientos
--   C8 fn_importe convierte a la moneda de la cuenta (10 USD a 900 = 9000 Bs)
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261125_conciliacion_verificacion.sql
-- FALLAS=0 = EXITO (el runner sale con codigo 1 aunque sea verde: se lee el mensaje).
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

begin
    begin execute immediate 'drop table tmp_cc_fallas purge'; exception when others then null; end;
end;
/

create table tmp_cc_fallas (caso varchar2(400))
/

begin
    update recibos set id_conciliacion = null where id_conciliacion in
        (select id_conciliacion from conciliaciones c join cuentas_fondos f on f.id_cuenta = c.id_cuenta
          where f.nombre = 'DIAG CONC'); commit;
    update pagos set id_conciliacion = null where id_conciliacion in
        (select id_conciliacion from conciliaciones c join cuentas_fondos f on f.id_cuenta = c.id_cuenta
          where f.nombre = 'DIAG CONC'); commit;
    delete from recibos where referencia = 'DIAG-CONC'; commit;
    delete from pagos where referencia = 'DIAG-CONC'; commit;
    delete from conciliaciones where id_cuenta in (select id_cuenta from cuentas_fondos where nombre = 'DIAG CONC'); commit;
    delete from cuentas_fondos where nombre = 'DIAG CONC'; commit;
    for r in (select usuario_id from usuario where upper(username) = 'DIAG.CONC') loop
        delete from usuario_empresa where usuario_id = r.usuario_id; commit;
        delete from usuario where usuario_id = r.usuario_id; commit;
    end loop;
end;
/

insert into usuario (username, email, password_hash, estado, id_empresa, rol_id, debe_cambiar_clave, reintentos_fallidos)
values ('diag.conc', 'diag.conc@synpex.local', 'x', 'ACTIVO', 1,
        (select id_rol from syn_roles where codigo_rol = 'ADMIN'), 'N', 0)
/

commit
/

insert into cuentas_fondos (id_empresa, nombre, tipo, banco, cod_moneda, es_principal, estado, creado_por)
values (1, 'DIAG CONC', 'BANCO', 'Banco DIAG', 'VES', 'N', 'ACTIVO', 'DIAG')
/

commit
/

insert into recibos (id_empresa, id_factura, fecha_cobro, cod_moneda, tipo_cambio, monto_cobrado, monto_bs,
                     monto_factura, aplica_igtf, igtf_monto, igtf_bs, retencion_iva_bs, monto_neto,
                     referencia, conciliado, estado, creado_por, id_cuenta)
select 1, (select max(id_factura) from facturas where id_empresa = 1), date '2026-10-10', 'VES', 1, 100, 100,
       100, 'N', 0, 0, 0, 100, 'DIAG-CONC', 'N', 'ACTIVO', 'DIAG',
       (select id_cuenta from cuentas_fondos where nombre = 'DIAG CONC')
  from dual
/

commit
/

insert into pagos (id_empresa, id_proveedor, fecha_pago, cod_moneda, tipo_cambio, monto, monto_bs,
                   referencia, aplica_igtf, igtf_monto, igtf_bs, estado, creado_por, id_cuenta)
select 1, (select max(id_proveedor) from proveedores where id_empresa = 1), date '2026-10-12', 'VES', 1, 30, 30,
       'DIAG-CONC', 'S', 2, 2, 'ACTIVO', 'DIAG',
       (select id_cuenta from cuentas_fondos where nombre = 'DIAG CONC')
  from dual
/

commit
/

declare
    v_cta  number;
    v_rec  number;
    v_pag  number;
    v_c    number;
    v_c2   number;
    v_n    number;
    v_s    number;
    v_est  varchar2(10);

    procedure falla(p varchar2) is
    begin
        insert into tmp_cc_fallas values (substrb(p, 1, 400));
        commit;
    end;
begin
    select id_cuenta into v_cta from cuentas_fondos where nombre = 'DIAG CONC';
    select id_recibo into v_rec from recibos where referencia = 'DIAG-CONC';
    select id_pago into v_pag from pagos where referencia = 'DIAG-CONC';

    -- C1
    v_c := pkg_conciliacion.fn_abrir(v_cta, date '2026-10-01', date '2026-10-31', 'diag.conc');
    commit;
    select estado, saldo_inicial into v_est, v_s from conciliaciones where id_conciliacion = v_c;
    if v_est <> 'ABIERTA' or v_s <> 0 then falla('C1: estado ' || v_est || ' saldo inicial ' || v_s); end if;

    -- C2
    begin
        v_c2 := pkg_conciliacion.fn_abrir(v_cta, date '2026-11-01', date '2026-11-30', 'diag.conc');
        falla('C2: se abrio una segunda conciliacion');
        rollback;
    exception when others then
        if sqlcode <> -20170 then falla('C2: codigo ' || sqlcode); end if;
        rollback;
    end;

    -- C3
    pkg_conciliacion.prc_marcar(v_c, '[{"t":"R","id":' || v_rec || ',"ok":1},{"t":"P","id":' || v_pag || ',"ok":1}]', 'diag.conc');
    commit;
    v_s := pkg_conciliacion.fn_saldo_sistema(v_c);
    if v_s <> 68 then falla('C3: saldo segun el sistema ' || v_s || ' (esperaba 68)'); end if;

    -- C4
    begin
        pkg_conciliacion.prc_cerrar(v_c, 80, 'diag.conc');
        falla('C4: cerro con una diferencia de 12');
        rollback;
    exception when others then
        if sqlcode <> -20172 then falla('C4: codigo ' || sqlcode); end if;
        rollback;
    end;

    -- C5
    pkg_conciliacion.prc_cerrar(v_c, 68, 'diag.conc');
    commit;
    select estado, diferencia into v_est, v_s from conciliaciones where id_conciliacion = v_c;
    if v_est <> 'CERRADA' or v_s <> 0 then falla('C5: estado ' || v_est || ' diferencia ' || v_s); end if;

    -- C6
    begin
        v_c2 := pkg_conciliacion.fn_abrir(v_cta, date '2026-10-15', date '2026-11-30', 'diag.conc');
        falla('C6: se abrio un periodo que pisa el cierre');
        rollback;
    exception when others then
        if sqlcode <> -20171 then falla('C6: codigo ' || sqlcode); end if;
        rollback;
    end;
    v_c2 := pkg_conciliacion.fn_abrir(v_cta, date '2026-11-01', date '2026-11-30', 'diag.conc');
    commit;
    select saldo_inicial into v_s from conciliaciones where id_conciliacion = v_c2;
    if v_s <> 68 then falla('C6: el siguiente periodo nacio con saldo inicial ' || v_s || ' (esperaba 68)'); end if;

    -- C7: se marca algo en la nueva y se anula
    update pagos set id_conciliacion = null, conciliado = 'N' where id_pago = v_pag;
    commit;
    pkg_conciliacion.prc_marcar(v_c2, '[{"t":"P","id":' || v_pag || ',"ok":1}]', 'diag.conc');
    pkg_conciliacion.prc_anular(v_c2, 'diag.conc');
    commit;
    select estado into v_est from conciliaciones where id_conciliacion = v_c2;
    select count(*) into v_n from pagos where id_pago = v_pag and id_conciliacion is null and conciliado = 'N';
    if v_est <> 'ANULADA' or v_n <> 1 then falla('C7: estado ' || v_est || ', pago desmarcado ' || v_n); end if;

    -- C8
    if pkg_conciliacion.fn_importe(10, 'USD', 900, date '2026-10-10', 'VES') <> 9000 then
        falla('C8: 10 USD a 900 dio ' || pkg_conciliacion.fn_importe(10, 'USD', 900, date '2026-10-10', 'VES'));
    end if;
end;
/

begin
    update recibos set id_conciliacion = null where referencia = 'DIAG-CONC'; commit;
    update pagos set id_conciliacion = null where referencia = 'DIAG-CONC'; commit;
    delete from recibos where referencia = 'DIAG-CONC'; commit;
    delete from pagos where referencia = 'DIAG-CONC'; commit;
    delete from conciliaciones where id_cuenta in (select id_cuenta from cuentas_fondos where nombre = 'DIAG CONC'); commit;
    delete from cuentas_fondos where nombre = 'DIAG CONC'; commit;
    for r in (select usuario_id from usuario where upper(username) = 'DIAG.CONC') loop
        delete from usuario_empresa where usuario_id = r.usuario_id; commit;
        delete from usuario where usuario_id = r.usuario_id; commit;
    end loop;
end;
/

declare
    v_fallas number;
    v_lista  varchar2(2000);
begin
    select count(*) into v_fallas from tmp_cc_fallas;
    select substrb(listagg(caso, ' | ' on overflow truncate) within group (order by caso), 1, 2000)
      into v_lista from tmp_cc_fallas;
    execute immediate 'drop table tmp_cc_fallas purge';
    raise_application_error(-20100, substrb('RESULTADO: FALLAS=' || v_fallas || ' | ' || v_lista, 1, 2000));
end;
/
