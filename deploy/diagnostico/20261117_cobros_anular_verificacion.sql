-- =============================================================================
-- 20261117_cobros_anular_verificacion.sql
--
-- Anular y conciliar cobros; la factura con cobros vivos no se anula (2026-11-17):
--   A1  anular el unico cobro devuelve la factura a TIMBRADA y el saldo completo
--   A2  anular uno de dos deja la factura en PARCIAL
--   A3  anular dos veces -> -20095
--   A4  anular una factura con cobros ACTIVOS -> -20091 (y el mensaje nombra los recibos)
--   A5  anular el cobro y despues la factura si funciona
--   A6  conciliar guarda referencia y fecha
--   A7  un recibo anulado no cuenta para el saldo
--   A8  el resumen de retencion de la cabecera se limpia al anular el cobro
--   A9  el tope de una NC se compara contra el TOTAL de la factura (no contra el saldo)
--
-- Todo el DML va dentro de un SAVEPOINT y se revierte.
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261117_cobros_anular_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

begin
    begin execute immediate 'drop table tmp_cobanu_fallas purge'; exception when others then null; end;
end;
/

create table tmp_cobanu_fallas (caso varchar2(300))
/

declare
    type t_lista is table of varchar2(300);
    v_fallas t_lista := t_lista();
    v_msg    varchar2(300);
    v_cli    number;
    v_fac    number;
    v_rec    number;
    v_rec2   number;
    v_estado varchar2(20);
    v_n      number;
    v_ref    varchar2(60);
    v_fecha  date;
    v_paso   varchar2(20) := 'inicio';

    procedure falla(p_texto varchar2) is
    begin
        v_fallas.extend;
        v_fallas(v_fallas.last) := substrb(p_texto, 1, 300);
    end;

    function nueva_factura(p_total number, p_pct_ret number default 0) return number is
        v_id number;
    begin
        insert into facturas (id_empresa, id_cliente, tipo_documento, folio_factura,
                              cod_moneda, tipo_cambio, fecha_emision, subtotal,
                              monto_impuesto, monto_total, estado, creado_por,
                              porcentaje_retencion, retencion_iva_bs)
        values (1, v_cli, 'FAC',
                'ANU-ZZ-' || to_char(sysdate, 'HH24MISS') || '-' || lpad(round(dbms_random.value(1, 99999)), 5, '0'),
                'VES', 1, sysdate, p_total, 0, p_total, 'TIMBRADA', 'test',
                p_pct_ret, 0)
        returning id_factura into v_id;
        return v_id;
    end;

    procedure cobra(p_factura number, p_monto number, p_ret number default 0,
                    p_comp varchar2 default null, p_rec out number) is
    begin
        pkg_cobros.prc_registrar_cobro(
            p_id_factura => p_factura, p_fecha => sysdate, p_id_forma_pago => null,
            p_cod_moneda => 'VES', p_monto => p_monto, p_retencion_iva_bs => p_ret,
            p_nro_comprobante => p_comp, p_usuario => 'ADMIN', p_id_recibo => p_rec);
    end;
begin
    savepoint sp_cobanu;

    select min(id_cliente) into v_cli from clientes where id_empresa = 1;

    -- A1: se cobra todo y se anula el unico cobro
    v_paso := 'A1';
    v_fac := nueva_factura(100);
    cobra(v_fac, 100, 0, null, v_rec);
    pkg_cobros.prc_anular_cobro(v_rec, 'ADMIN');
    select estado into v_estado from facturas where id_factura = v_fac;
    if v_estado <> 'TIMBRADA' then falla('A1: la factura quedo ' || v_estado || ' en vez de TIMBRADA'); end if;
    if fn_saldo_factura(v_fac) <> 100 then
        falla('A1: el saldo quedo ' || fn_saldo_factura(v_fac) || ' en vez de 100');
    end if;

    -- A3: no se anula dos veces
    v_paso := 'A3';
    begin
        pkg_cobros.prc_anular_cobro(v_rec, 'ADMIN');
        falla('A3: dejo anular dos veces el mismo recibo');
    exception
        when others then
            if sqlcode <> -20095 then falla('A3: codigo ' || sqlcode || ' en vez de -20095'); end if;
    end;

    -- A2: dos cobros, se anula uno -> PARCIAL
    v_paso := 'A2';
    v_fac := nueva_factura(100);
    cobra(v_fac, 40, 0, null, v_rec);
    cobra(v_fac, 60, 0, null, v_rec2);
    select estado into v_estado from facturas where id_factura = v_fac;
    if v_estado <> 'PAGADA' then falla('A2: con dos cobros completos quedo ' || v_estado); end if;
    pkg_cobros.prc_anular_cobro(v_rec2, 'ADMIN');
    select estado into v_estado from facturas where id_factura = v_fac;
    if v_estado <> 'PARCIAL' then falla('A2: al anular uno quedo ' || v_estado || ' en vez de PARCIAL'); end if;
    if fn_saldo_factura(v_fac) <> 60 then
        falla('A2: el saldo quedo ' || fn_saldo_factura(v_fac) || ' en vez de 60');
    end if;

    -- A4 / A5: la factura con cobros vivos no se anula
    v_paso := 'A4';
    begin
        pkg_facturacion.prc_anular_factura(v_fac, null, 'ADMIN');
        falla('A4: dejo anular una factura con cobros vivos');
    exception
        when others then
            if sqlcode <> -20091 then
                falla('A4: codigo ' || sqlcode || ' en vez de -20091 (' || substrb(sqlerrm, 1, 90) || ')');
            end if;
    end;

    v_paso := 'A5';
    pkg_cobros.prc_anular_cobro(v_rec, 'ADMIN');
    pkg_facturacion.prc_anular_factura(v_fac, null, 'ADMIN');
    select estado into v_estado from facturas where id_factura = v_fac;
    if v_estado <> 'ANULADA' then falla('A5: sin cobros la factura no se anulo (' || v_estado || ')'); end if;

    -- A6: conciliar
    v_paso := 'A6';
    v_fac := nueva_factura(100);
    cobra(v_fac, 100, 0, null, v_rec);
    pkg_cobros.prc_conciliar(v_rec, 'TRF-8891', 'ADMIN');
    select conciliado, referencia, fecha_conciliacion into v_estado, v_ref, v_fecha
      from recibos where id_recibo = v_rec;
    if v_estado <> 'S' or v_ref <> 'TRF-8891' or v_fecha is null then
        falla('A6: conciliar dejo ' || v_estado || '/' || v_ref || '/' || to_char(v_fecha, 'DD/MM/YYYY'));
    end if;

    -- A7: el recibo anulado no cuenta
    v_paso := 'A7';
    pkg_cobros.prc_anular_cobro(v_rec, 'ADMIN');
    if fn_saldo_factura(v_fac) <> 100 then
        falla('A7: el recibo anulado sigue descontando (' || fn_saldo_factura(v_fac) || ')');
    end if;

    -- A8: el resumen de retencion se limpia con el ultimo cobro anulado
    v_paso := 'A8';
    v_fac := nueva_factura(116, 75);
    insert into facturas_det (id_factura, num_linea, descripcion, cantidad, precio_unitario,
                              id_impuesto, porcentaje_impuesto, monto_impuesto,
                              subtotal_linea, monto_total_linea, tasa_cambio_aplicada,
                              subtotal_bs, total_bs)
    values (v_fac, 1, 'Servicio', 1, 100,
            (select id_impuesto from impuestos
              where cod_pais = 'VE' and cod_impuesto = 'IVA_GEN' and rownum = 1),
            16, 16, 100, 116, 1, 100, 116);
    cobra(v_fac, 116, 12, '20261100000088', v_rec);
    select nvl(retencion_iva_bs, 0), nvl(nro_comprobante_retencion, '#')
      into v_n, v_ref from facturas where id_factura = v_fac;
    if v_n <> 12 or v_ref <> '20261100000088' then
        falla('A8: la cabecera quedo ' || v_n || '/' || v_ref || ' y se esperaba 12/20261100000088');
    end if;
    pkg_cobros.prc_anular_cobro(v_rec, 'ADMIN');
    select nvl(retencion_iva_bs, 0), nvl(nro_comprobante_retencion, '#')
      into v_n, v_ref from facturas where id_factura = v_fac;
    if v_n <> 0 or v_ref <> '#' then
        falla('A8: al anular el cobro la cabecera sigue con ' || v_n || '/' || v_ref);
    end if;

    -- A9: el tope de la NC se compara contra el total, no contra el saldo
    v_paso := 'A9';
    v_fac := nueva_factura(100);
    cobra(v_fac, 60, 0, null, v_rec);
    update facturas set estado = 'TIMBRADA' where id_factura = v_fac;
    declare
        v_nc number;
    begin
        -- una NC de 50 sobre una factura de 100 con 60 cobrados: valida
        insert into facturas (id_empresa, id_cliente, tipo_documento, folio_factura,
                              cod_moneda, tipo_cambio, fecha_emision, subtotal,
                              monto_impuesto, monto_total, estado, creado_por, id_factura_origen)
        values (1, v_cli, 'NC',
                'ANU-NC-' || lpad(round(dbms_random.value(1, 99999)), 5, '0'),
                'VES', 1, sysdate, 50, 0, 50, 'TIMBRADA', 'test', v_fac)
        returning id_factura into v_nc;
        if fn_saldo_factura(v_fac) <> -10 then
            falla('A9: con NC de 50 y 60 cobrados el saldo es ' || fn_saldo_factura(v_fac)
                  || ' y se esperaba -10 (a favor del cliente)');
        end if;
    end;

    v_paso := 'A10';
    -- A10: conciliar un cobro de otra empresa se rechaza (antes no comprobaba nada).
    v_fac := nueva_factura(100);
    cobra(v_fac, 100, 0, null, v_rec);
    update recibos set id_empresa = 2 where id_recibo = v_rec;
    begin
        pkg_cobros.prc_conciliar(v_rec, 'AJENA', 'ADMIN');
        falla('A10: dejo conciliar un cobro de otra empresa');
    exception
        when others then
            if sqlcode <> -20003 then falla('A10: codigo ' || sqlcode || ' en vez de -20003'); end if;
    end;
    update recibos set id_empresa = 1 where id_recibo = v_rec;

    v_paso := 'A11';
    -- A11: un cobro anulado no se concilia.
    pkg_cobros.prc_anular_cobro(v_rec, 'ADMIN');
    begin
        pkg_cobros.prc_conciliar(v_rec, 'X', 'ADMIN');
        falla('A11: dejo conciliar un cobro anulado');
    exception
        when others then
            if sqlcode <> -20095 then falla('A11: codigo ' || sqlcode || ' en vez de -20095'); end if;
    end;

    rollback to sp_cobanu;

    for i in 1 .. v_fallas.count loop
        insert into tmp_cobanu_fallas values (v_fallas(i));
    end loop;
exception
    when others then
        rollback to sp_cobanu;
        v_msg := substrb('A?: el caso revento en ' || v_paso || ': ' || sqlerrm, 1, 300);
        insert into tmp_cobanu_fallas values (v_msg);
end;
/

declare
    v_fallas number;
    v_lista  varchar2(3000);
begin
    select count(*) into v_fallas from tmp_cobanu_fallas;
    select substrb(listagg(caso, ' | ' on overflow truncate) within group (order by caso), 1, 3000)
      into v_lista from tmp_cobanu_fallas;
    execute immediate 'drop table tmp_cobanu_fallas purge';
    raise_application_error(-20100, substrb('RESULTADO: FALLAS=' || v_fallas || ' | ' || v_lista, 1, 3000));
end;
/
