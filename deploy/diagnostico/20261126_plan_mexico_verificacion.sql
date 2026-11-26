-- =============================================================================
-- 20261126_plan_mexico_verificacion.sql
--
-- Borrador del plan de cuentas de Mexico con el codigo agrupador del SAT (Anexo 24 RMF 2024):
--   M1 instalar el plan en una empresa de Mexico copia las 80 cuentas, todas con su codigo
--      agrupador del SAT y marcadas «Revisar» (origen SYNPEX)
--   M2 la subcuenta de la caja hereda el agrupador de su grupo (101.01)
--   M3 los conceptos apuntan a las cuentas del SAT: IVA de la venta -> 209.01 (trasladado no
--      cobrado), IVA de la compra -> 119.01, proveedores -> 201.01, diferencial -> 702.01
--   M4 el estado de resultados incluye la clase 7: una venta de 100 y una utilidad cambiaria de 10
--      dan utilidad 110; el balance general cuadra
--
-- Empresa temporal 900282 (MX) y usuario temporal; se purga al final.
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261126_plan_mexico_verificacion.sql
-- FALLAS=0 = EXITO (el runner sale con codigo 1 aunque sea verde: se lee el mensaje).
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

begin
    begin execute immediate 'drop table tmp_mx_fallas purge'; exception when others then null; end;
end;
/

create table tmp_mx_fallas (caso varchar2(400))
/

begin
    begin pkg_contabilidad.prc_purgar_prueba(900282); commit; exception when others then null; end;
    for r in (select usuario_id from usuario where upper(username) = 'DIAG.MX') loop
        delete from usuario_empresa where usuario_id = r.usuario_id; commit;
        delete from usuario where usuario_id = r.usuario_id; commit;
    end loop;
    begin delete from cuentas_fondos where id_empresa = 900282; commit; exception when others then null; end;
    begin delete from usuario_empresa where id_empresa = 900282; commit; exception when others then null; end;
    begin delete from empresas where id_empresa = 900282; commit; exception when others then null; end;
end;
/

insert into empresas (id_empresa, nombre_empresa, cod_pais, tipo_ident_fiscal, rfc, estado)
values (900282, 'DIAG MEXICO', 'MX', 'RFC', 'DIA900282AB1', 'ACTIVO')
/

insert into cuentas_fondos (id_empresa, nombre, tipo, cod_moneda, es_principal, estado, creado_por)
values (900282, 'Caja principal', 'CAJA', 'MXN', 'S', 'ACTIVO', 'DIAG')
/

commit
/

insert into usuario (username, email, password_hash, estado, id_empresa, rol_id, debe_cambiar_clave, reintentos_fallidos)
values ('diag.mx', 'diag.mx@synpex.local', 'x', 'ACTIVO', 900282,
        (select id_rol from syn_roles where codigo_rol = 'ADMIN'), 'N', 0)
/

commit
/

declare
    U   constant varchar2(20) := 'diag.mx';
    E   constant number := 900282;
    v_n number; v_s number; v_r number;
    v_txt varchar2(400);
    v_id  number;
    v_x   clob;

    procedure falla(p varchar2) is
    begin
        insert into tmp_mx_fallas values (substr(p, 1, 400));
        commit;
    end falla;

    function sat(p_concepto varchar2) return varchar2 is
        v varchar2(20);
    begin
        select c.codigo_agrupador_sat into v from ctb_mapeo m join ctb_cuentas c on c.id_cuenta_ctb = m.id_cuenta_ctb
         where m.id_empresa = E and m.concepto = p_concepto;
        return v;
    exception when no_data_found then return '(sin concepto)';
    end sat;
begin
    -- M1
    v_n := pkg_contabilidad.fn_instalar_plan(E, U);
    commit;
    select count(*), count(codigo_agrupador_sat), count(case when origen = 'SYNPEX' then 1 end)
      into v_n, v_s, v_r
      from ctb_cuentas where id_empresa = E and origen <> 'EMPRESA';
    if v_n <> 80 or v_s <> 80 or v_r <> 80 then
        falla('M1 plan de Mexico: cuentas=' || v_n || ' con agrupador=' || v_s || ' revisar=' || v_r);
    end if;
    -- M2
    select count(*) into v_n from cuentas_fondos f join ctb_cuentas c on c.id_cuenta_ctb = f.id_cuenta_ctb
     where f.id_empresa = E and f.tipo = 'CAJA' and c.codigo_agrupador_sat = '101.01' and c.codigo like '1.1.01.%';
    if v_n <> 1 then
        falla('M2 la subcuenta de la caja no hereda el agrupador 101.01');
    end if;
    -- M3
    if sat('IVA_DEBITO') <> '209.01' or sat('IVA_CREDITO') <> '119.01' or sat('CXP') <> '201.01'
       or sat('DIFERENCIAL_CAMBIARIO') <> '702.01' or sat('CXC') <> '105.01' then
        falla('M3 conceptos: IVA_DEBITO=' || sat('IVA_DEBITO') || ' IVA_CREDITO=' || sat('IVA_CREDITO')
              || ' CXP=' || sat('CXP') || ' DIFERENCIAL=' || sat('DIFERENCIAL_CAMBIARIO'));
    end if;
    -- M4: venta 100 + IVA 16 y utilidad cambiaria 10 cobrada en caja
    v_id := null;
    pkg_contabilidad.prc_guardar_asiento(v_id, E, date '2026-06-10', 'Venta',
        '[{"id":' || pkg_contabilidad.fn_cuenta(E, 'CXC') || ',"debe":116,"haber":0},{"id":'
        || pkg_contabilidad.fn_cuenta(E, 'VENTAS') || ',"debe":0,"haber":100},{"id":'
        || pkg_contabilidad.fn_cuenta(E, 'IVA_DEBITO') || ',"debe":0,"haber":16}]', U);
    pkg_contabilidad.prc_confirmar(v_id, U);
    select id_cuenta_ctb into v_n from cuentas_fondos where id_empresa = E and tipo = 'CAJA';
    v_id := null;
    pkg_contabilidad.prc_guardar_asiento(v_id, E, date '2026-06-12', 'Utilidad cambiaria',
        '[{"id":' || v_n || ',"debe":10,"haber":0},{"id":'
        || pkg_contabilidad.fn_cuenta(E, 'DIFERENCIAL_CAMBIARIO') || ',"debe":0,"haber":10}]', U);
    pkg_contabilidad.prc_confirmar(v_id, U);
    commit;
    v_x := fn_ctb_libro('RESULTADOS', date '2026-01-01', date '2026-12-31', null, E, 'XLS');
    if instr(v_x, 'RESULTADO INTEGRAL DE FINANCIAMIENTO') = 0
       or instr(v_x, '<td style="mso-number-format:''#\,##0\.00'';font-weight:bold">110</td></tr>') = 0 then
        falla('M4 el estado de resultados no suma la clase 7 (se esperaba utilidad 110)');
    end if;
    v_x := fn_ctb_libro('SITUACION', date '2026-01-01', date '2026-12-31', null, E, 'XLS');
    if instr(v_x, 'Cuadra: activo') = 0 then
        falla('M4 el balance general de Mexico no cuadra');
    end if;
exception
    when others then
        v_txt := substr(sqlerrm, 1, 300);
        rollback;
        falla('error inesperado: ' || v_txt || ' ' || substr(dbms_utility.format_error_backtrace, 1, 90));
end;
/

begin
    pkg_contabilidad.prc_purgar_prueba(900282);
    commit;
    delete from cuentas_fondos where id_empresa = 900282;
    commit;
    for r in (select usuario_id from usuario where upper(username) = 'DIAG.MX') loop
        delete from usuario_empresa where usuario_id = r.usuario_id; commit;
        delete from usuario where usuario_id = r.usuario_id; commit;
    end loop;
    delete from usuario_empresa where id_empresa = 900282;
    commit;
    delete from empresas where id_empresa = 900282;
    commit;
end;
/

declare
    v_n   number;
    v_txt varchar2(4000);
begin
    select count(*) into v_n from tmp_mx_fallas;
    for r in (select caso from tmp_mx_fallas) loop
        v_txt := substr(v_txt || ' | ' || r.caso, 1, 3500);
    end loop;
    execute immediate 'drop table tmp_mx_fallas purge';
    raise_application_error(-20100, 'RESULTADO: FALLAS=' || v_n || v_txt);
end;
/
