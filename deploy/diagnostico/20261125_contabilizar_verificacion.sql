-- =============================================================================
-- 20261125_contabilizar_verificacion.sql
--
-- Contabilidad, fase 4: «Contabilizar periodo» sobre los documentos REALES de cada empresa de
-- Venezuela, dentro de una transaccion que se revierte al final (no deja nada):
--   L1 el lote no da errores (facturas, notas, cobros, compras, retenciones, pagos, kardex)
--   L2 todo asiento automatico queda CONFIRMADO y cuadrado
--   L3 el saldo de cuentas por cobrar = facturas y notas de debito procesadas - notas de credito
--      - lo aplicado por los cobros activos (todo a la tasa de cada factura)
--   L4 el saldo de inventario = el valor del kardex (las entradas de compra, por la compra)
--   L5 el balance de comprobacion cuadra
--   L6 repetir el lote no crea ni reversa nada
--   L7 un asiento automatico no se reversa a mano (-20186)
--
-- Mes: el actual. Usuario temporal con acceso a las empresas; se borra al final.
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261125_contabilizar_verificacion.sql
-- FALLAS=0 = EXITO (el runner sale con codigo 1 aunque sea verde: se lee el mensaje).
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

begin
    begin execute immediate 'drop table tmp_lote_fallas purge'; exception when others then null; end;
end;
/

create table tmp_lote_fallas (caso varchar2(1000), info varchar2(1) default 'N')
/

begin
    for r in (select usuario_id from usuario where upper(username) = 'DIAG.LOTE') loop
        delete from usuario_empresa where usuario_id = r.usuario_id; commit;
        delete from usuario where usuario_id = r.usuario_id; commit;
    end loop;
end;
/

insert into usuario (username, email, password_hash, estado, id_empresa, rol_id, debe_cambiar_clave, reintentos_fallidos)
values ('diag.lote', 'diag.lote@synpex.local', 'x', 'ACTIVO', 1,
        (select id_rol from syn_roles where codigo_rol = 'ADMIN'), 'N', 0)
/

commit
/

insert into usuario_empresa (usuario_id, id_empresa)
select u.usuario_id, e.id_empresa from usuario u cross join empresas e
 where u.username = 'diag.lote' and e.cod_pais = 'VE' and e.id_empresa < 900000
   and not exists (select 1 from usuario_empresa x where x.usuario_id = u.usuario_id and x.id_empresa = e.id_empresa)
/

commit
/

declare
    U      constant varchar2(20) := 'diag.lote';
    v_anio number := extract(year from sysdate);
    v_mes  number := extract(month from sysdate);
    v_fin  date := last_day(trunc(sysdate));
    v_cre  number; v_rev number; v_err number; v_det varchar2(4000);
    v_cre2 number; v_rev2 number; v_err2 number; v_det2 varchar2(4000);
    v_n    number;
    v_a    number;
    v_b    number;
    v_aut  number;
    type t_txt is table of varchar2(1000);
    v_out  t_txt := t_txt();

    procedure anota(p varchar2, p_info varchar2 default 'N') is
    begin
        v_out.extend;
        v_out(v_out.count) := p_info || substr(p, 1, 990);
    end anota;

    function saldo(p_emp number, p_concepto varchar2) return number is
        v number;
    begin
        select nvl(sum(d.debe - d.haber), 0) into v
          from ctb_asiento_det d join ctb_asientos a on a.id_asiento = d.id_asiento
         where a.id_empresa = p_emp and a.estado in ('CONFIRMADO', 'REVERSADO') and a.fecha <= v_fin
           and d.id_cuenta_ctb = pkg_contabilidad.fn_cuenta(p_emp, p_concepto);
        return v;
    end saldo;
begin
    for e in (select id_empresa from empresas where cod_pais = 'VE' and id_empresa < 900000 order by 1) loop
        begin
            select count(*) into v_n from ctb_cuentas where id_empresa = e.id_empresa;
            if v_n = 0 then
                v_n := pkg_contabilidad.fn_instalar_plan(e.id_empresa, U);
            end if;
            pkg_contabilidad.prc_contabilizar_periodo(e.id_empresa, v_anio, v_mes, U, v_cre, v_rev, v_err, v_det);
            select count(*) into v_aut from ctb_asientos where id_empresa = e.id_empresa and origen = 'AUTOMATICO';
            anota('Empresa ' || e.id_empresa || ': ' || v_cre || ' asientos, ' || v_rev || ' reversos, ' || v_err || ' errores', 'S');

            -- L1
            if v_err > 0 then
                anota('L1 empresa ' || e.id_empresa || ' con errores: ' || v_det);
            end if;
            -- L2
            select count(*) into v_n from ctb_asientos
             where id_empresa = e.id_empresa and origen = 'AUTOMATICO'
               and (estado <> 'CONFIRMADO' or total_debe <> total_haber or total_debe <= 0);
            if v_n > 0 then
                anota('L2 empresa ' || e.id_empresa || ': ' || v_n || ' asientos automaticos sin confirmar o descuadrados');
            end if;
            -- L3
            select nvl(sum(case when f.tipo_documento = 'NC' then -1 else 1 end
                           * (round(abs(f.subtotal) * nvl(nullif(f.tipo_cambio, 0), 1), 2)
                              + round(abs(f.monto_impuesto) * nvl(nullif(f.tipo_cambio, 0), 1), 2))), 0)
              into v_a
              from facturas f
             where f.id_empresa = e.id_empresa and trunc(f.fecha_emision) <= v_fin
               and f.tipo_documento in ('FAC', 'ND', 'NC') and f.estado <> 'PENDIENTE'
               and not (f.estado = 'ANULADA' and f.nro_control is null);
            select nvl(sum(round(r.monto_factura * nvl(nullif(f.tipo_cambio, 0), 1), 2)), 0) into v_b
              from recibos r join facturas f on f.id_factura = r.id_factura
             where r.id_empresa = e.id_empresa and r.estado = 'ACTIVO' and trunc(r.fecha_cobro) <= v_fin;
            if v_aut > 0 and abs(saldo(e.id_empresa, 'CXC') - (v_a - v_b)) > 0.01 then
                anota('L3 empresa ' || e.id_empresa || ': cuentas por cobrar ' || saldo(e.id_empresa, 'CXC')
                      || ', esperado ' || (v_a - v_b));
            end if;
            -- L4
            select nvl(sum(pkg_inventario.fn_signo(m.tipo_movimiento) * m.costo_total_bs), 0) into v_a
              from kardex_mov m
             where m.id_empresa = e.id_empresa and trunc(m.fecha_movimiento) <= v_fin
               and (m.doc_tipo <> 'COMPRA'
                    or exists (select 1 from compras c where c.id_compra = m.id_doc and c.estado not in ('BORRADOR', 'ANULADA')));
            if v_aut > 0 and abs(saldo(e.id_empresa, 'INVENTARIO') - v_a) > 0.05 then
                anota('L4 empresa ' || e.id_empresa || ': inventario contable ' || saldo(e.id_empresa, 'INVENTARIO')
                      || ', kardex ' || round(v_a, 2));
            end if;
            -- L5
            select nvl(sum(d.debe), 0), nvl(sum(d.haber), 0) into v_a, v_b
              from ctb_asiento_det d join ctb_asientos a on a.id_asiento = d.id_asiento
             where a.id_empresa = e.id_empresa and a.estado in ('CONFIRMADO', 'REVERSADO');
            if v_a <> v_b then
                anota('L5 empresa ' || e.id_empresa || ': el balance no cuadra (' || v_a || ' / ' || v_b || ')');
            end if;
            -- L6
            pkg_contabilidad.prc_contabilizar_periodo(e.id_empresa, v_anio, v_mes, U, v_cre2, v_rev2, v_err2, v_det2);
            if v_cre2 <> 0 or v_rev2 <> 0 then
                anota('L6 empresa ' || e.id_empresa || ': la segunda pasada creo ' || v_cre2 || ' y reverso ' || v_rev2);
            end if;
            -- L7
            select max(id_asiento) into v_n from ctb_asientos
             where id_empresa = e.id_empresa and origen = 'AUTOMATICO' and estado = 'CONFIRMADO';
            if v_n is not null then
                begin
                    v_a := pkg_contabilidad.fn_reversar(v_n, 'a mano', U);
                    anota('L7 empresa ' || e.id_empresa || ': se pudo reversar a mano un asiento automatico');
                exception
                    when others then
                        if sqlcode <> -20186 then
                            anota('L7 empresa ' || e.id_empresa || ': ' || sqlerrm);
                        end if;
                end;
            end if;
        exception
            when others then
                anota('empresa ' || e.id_empresa || ' error inesperado: ' || sqlerrm || ' '
                      || substr(dbms_utility.format_error_backtrace, 1, 200));
        end;
        rollback;   -- no deja nada de la prueba
    end loop;
    for i in 1 .. v_out.count loop
        insert into tmp_lote_fallas (caso, info) values (substr(v_out(i), 2), substr(v_out(i), 1, 1));
    end loop;
    commit;
end;
/

begin
    for r in (select usuario_id from usuario where upper(username) = 'DIAG.LOTE') loop
        delete from usuario_empresa where usuario_id = r.usuario_id; commit;
        delete from usuario where usuario_id = r.usuario_id; commit;
    end loop;
end;
/

declare
    v_n   number;
    v_txt varchar2(4000);
begin
    select count(*) into v_n from tmp_lote_fallas where info = 'N';
    for r in (select caso, info from tmp_lote_fallas order by info desc) loop
        v_txt := substr(v_txt || ' | ' || r.caso, 1, 3800);
    end loop;
    execute immediate 'drop table tmp_lote_fallas purge';
    raise_application_error(-20100, 'RESULTADO: FALLAS=' || v_n || v_txt);
end;
/
