-- =============================================================================
-- 20261117_cobros_saldo_verificacion.sql
--
-- Saldo de la factura y alicuota del IGTF (2026-11-17):
--   S1  factura sin cobros -> saldo = total
--   S2  un recibo ACTIVO descuenta
--   S3  un recibo ANULADO no descuenta
--   S4  una NC timbrada reduce el saldo (una ND lo aumenta)
--   S5  factura ANULADA -> 0
--   S6  factura inexistente -> 0
--   S7  la alicuota sale de IMPUESTOS (VE 3, MX 0)
--   S8  la factura en USD cobrada en Bs usa el equivalente ya guardado
--
-- Todo el DML va dentro de un SAVEPOINT y se revierte.
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261117_cobros_saldo_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

begin
    begin execute immediate 'drop table tmp_cobsal_fallas purge'; exception when others then null; end;
end;
/

create table tmp_cobsal_fallas (caso varchar2(300))
/

declare
    type t_lista is table of varchar2(300);
    v_fallas t_lista := t_lista();
    v_msg    varchar2(300);
    v_saldo  number;
    v_n      number;
    v_cli    number;
    v_fac    number;
    v_nc     number;

    procedure falla(p_texto varchar2) is
    begin
        v_fallas.extend;
        v_fallas(v_fallas.last) := substrb(p_texto, 1, 300);
    end;

    function nueva_factura(p_estado varchar2, p_total number, p_moneda varchar2,
                           p_tipo_cambio number, p_tipo varchar2 default 'FAC',
                           p_origen number default null) return number is
        v_id number;
    begin
        insert into facturas (id_empresa, id_cliente, tipo_documento, folio_factura,
                              cod_moneda, tipo_cambio, fecha_emision, subtotal,
                              monto_impuesto, monto_total, estado, creado_por, id_factura_origen)
        values (1, v_cli, p_tipo, 'SAL-ZZ-' || to_char(sysdate, 'HH24MISS') || '-' || lpad(round(dbms_random.value(1, 99999)), 5, '0'),
                p_moneda, p_tipo_cambio, sysdate, p_total, 0, p_total, p_estado, 'test', p_origen)
        returning id_factura into v_id;
        return v_id;
    end;

    procedure recibo(p_factura number, p_monto_factura number, p_estado varchar2) is
    begin
        insert into recibos (id_empresa, id_factura, fecha_cobro, cod_moneda, tipo_cambio,
                             monto_cobrado, monto_bs, monto_factura, aplica_igtf, igtf_monto,
                             igtf_bs, retencion_iva_bs, monto_neto, conciliado, estado, creado_por)
        values (1, p_factura, sysdate, 'VES', 1, p_monto_factura, p_monto_factura,
                p_monto_factura, 'N', 0, 0, 0, p_monto_factura, 'N', p_estado, 'test');
    end;
begin
    savepoint sp_cobsal;

    select min(id_cliente) into v_cli from clientes where id_empresa = 1;

    -- S1
    v_fac := nueva_factura('TIMBRADA', 100, 'VES', 1);
    v_saldo := fn_saldo_factura(v_fac);
    if v_saldo <> 100 then falla('S1: saldo ' || v_saldo || ' en vez de 100'); end if;

    -- S2
    recibo(v_fac, 40, 'ACTIVO');
    v_saldo := fn_saldo_factura(v_fac);
    if v_saldo <> 60 then falla('S2: saldo ' || v_saldo || ' en vez de 60'); end if;

    -- S3
    recibo(v_fac, 10, 'ANULADO');
    v_saldo := fn_saldo_factura(v_fac);
    if v_saldo <> 60 then falla('S3: el recibo anulado descontó (' || v_saldo || ' en vez de 60)'); end if;

    -- S4: NC timbrada de 30 -> 30
    v_nc := nueva_factura('TIMBRADA', 30, 'VES', 1, 'NC', v_fac);
    v_saldo := fn_saldo_factura(v_fac);
    if v_saldo <> 30 then falla('S4: con NC el saldo es ' || v_saldo || ' en vez de 30'); end if;

    -- S4b: una NC no timbrada no cuenta
    update facturas set estado = 'PENDIENTE' where id_factura = v_nc;
    v_saldo := fn_saldo_factura(v_fac);
    if v_saldo <> 60 then falla('S4b: una NC sin timbrar descontó (' || v_saldo || ')'); end if;
    update facturas set estado = 'TIMBRADA' where id_factura = v_nc;

    -- S5 / S6
    v_fac := nueva_factura('ANULADA', 100, 'VES', 1);
    v_saldo := fn_saldo_factura(v_fac);
    if v_saldo <> 0 then falla('S5: una factura anulada tiene saldo ' || v_saldo); end if;

    v_saldo := fn_saldo_factura(-1);
    if v_saldo <> 0 then falla('S6: una factura inexistente devuelve ' || v_saldo); end if;

    -- S7: la alicuota es configuracion
    v_n := fn_alicuota_igtf(1);
    if v_n <> 3 then falla('S7: la alicuota de la empresa 1 es ' || v_n || ' en vez de 3'); end if;
    v_n := fn_alicuota_igtf(2);
    if v_n <> 0 then falla('S7: la empresa 2 (Mexico) tiene IGTF ' || v_n || ' y deberia ser 0'); end if;

    -- S8: el equivalente en la moneda de la factura es el que se guarda
    v_fac := nueva_factura('TIMBRADA', 100, 'USD', 900);
    recibo(v_fac, 100, 'ACTIVO');
    v_saldo := fn_saldo_factura(v_fac);
    if v_saldo <> 0 then falla('S8: la factura en USD con su equivalente cobrado deja saldo ' || v_saldo); end if;

    rollback to sp_cobsal;

    for i in 1 .. v_fallas.count loop
        insert into tmp_cobsal_fallas values (v_fallas(i));
    end loop;
exception
    when others then
        rollback to sp_cobsal;
        v_msg := substrb('S?: el caso revento: ' || sqlerrm, 1, 300);
        insert into tmp_cobsal_fallas values (v_msg);
end;
/

declare
    v_fallas number;
    v_lista  varchar2(3000);
begin
    select count(*) into v_fallas from tmp_cobsal_fallas;
    select substrb(listagg(caso, ' | ' on overflow truncate) within group (order by caso), 1, 3000)
      into v_lista from tmp_cobsal_fallas;
    execute immediate 'drop table tmp_cobsal_fallas purge';
    raise_application_error(-20100, substrb('RESULTADO: FALLAS=' || v_fallas || ' | ' || v_lista, 1, 3000));
end;
/
