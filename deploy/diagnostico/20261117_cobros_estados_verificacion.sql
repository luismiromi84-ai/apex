-- =============================================================================
-- 20261117_cobros_estados_verificacion.sql
--
-- Estados de la factura con cobros (2026-11-17):
--   E1  fn_factura_editable cierra PARCIAL igual que PAGADA
--   E2  la matriz de transiciones: los retrocesos por cobro anulado se permiten y
--       los que falsean el documento se siguen prohibiendo
--   E3  el trigger real acepta PAGADA->PARCIAL y rechaza PAGADA->PENDIENTE (-20070)
--
-- Todo el DML va dentro de un SAVEPOINT y se revierte.
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261117_cobros_estados_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

begin
    begin execute immediate 'drop table tmp_cobest_fallas purge'; exception when others then null; end;
end;
/

create table tmp_cobest_fallas (caso varchar2(300))
/

declare
    type t_lista is table of varchar2(300);
    v_fallas t_lista := t_lista();
    v_msg    varchar2(300);
    v_cli    number;
    v_fac    number;
    v_ok     boolean;
    v_code   number;

    procedure falla(p_texto varchar2) is
    begin
        v_fallas.extend;
        v_fallas(v_fallas.last) := substrb(p_texto, 1, 300);
    end;

    procedure exige(p_antes varchar2, p_despues varchar2, p_esperado boolean) is
    begin
        v_ok := fn_transicion_estado_valida('FACTURA', p_antes, p_despues);
        if v_ok <> p_esperado then
            falla('E2: ' || p_antes || '->' || p_despues
                  || case when p_esperado then ' deberia permitirse' else ' deberia prohibirse' end);
        end if;
    end;

    function nueva_factura(p_estado varchar2) return number is
        v_id number;
    begin
        insert into facturas (id_empresa, id_cliente, tipo_documento, folio_factura,
                              cod_moneda, tipo_cambio, fecha_emision, subtotal,
                              monto_impuesto, monto_total, estado, creado_por)
        values (1, v_cli, 'FAC',
                'EST-ZZ-' || to_char(sysdate, 'HH24MISS') || '-' || lpad(round(dbms_random.value(1, 99999)), 5, '0'),
                'VES', 1, sysdate, 100, 0, 100, p_estado, 'test')
        returning id_factura into v_id;
        return v_id;
    end;
begin
    savepoint sp_cobest;

    select min(id_cliente) into v_cli from clientes where id_empresa = 1;

    -- E1: qué se puede editar
    if fn_factura_editable(nueva_factura('PAGADA')) then
        falla('E1: una factura PAGADA sigue editable');
    end if;
    if fn_factura_editable(nueva_factura('PARCIAL')) then
        falla('E1: una factura PARCIAL sigue editable');
    end if;
    if fn_factura_editable(nueva_factura('ANULADA')) then
        falla('E1: una factura ANULADA sigue editable');
    end if;
    if not fn_factura_editable(nueva_factura('PENDIENTE')) then
        falla('E1: una factura PENDIENTE deberia ser editable');
    end if;
    if not fn_factura_editable(nueva_factura('TIMBRADA')) then
        falla('E1: una factura TIMBRADA deberia ser editable');
    end if;
    if not fn_factura_editable(null) or not fn_factura_editable(-1) then
        falla('E1: el alta (id nulo o inexistente) deberia ser editable');
    end if;

    -- E2: la matriz
    exige('TIMBRADA', 'PARCIAL',  true);
    exige('TIMBRADA', 'PAGADA',   true);
    exige('PARCIAL',  'PAGADA',   true);
    exige('PARCIAL',  'TIMBRADA', true);
    exige('PARCIAL',  'ANULADA',  true);
    exige('PAGADA',   'PARCIAL',  true);
    exige('PAGADA',   'TIMBRADA', true);
    exige('PAGADA',   'ANULADA',  true);
    exige('ANULADA',  'TIMBRADA', false);
    exige('ANULADA',  'PARCIAL',  false);
    exige('ANULADA',  'PAGADA',   false);
    exige('PAGADA',   'PENDIENTE', false);

    -- E3: el trigger real
    v_fac := nueva_factura('PAGADA');
    begin
        update facturas set estado = 'PARCIAL' where id_factura = v_fac;
        if sql%rowcount <> 1 then falla('E3: la factura de prueba no se actualizo'); end if;
    exception
        when others then
            falla('E3: el trigger no dejo pasar PAGADA->PARCIAL: ' || substrb(sqlerrm, 1, 120));
    end;

    v_fac := nueva_factura('PAGADA');
    begin
        update facturas set estado = 'PENDIENTE' where id_factura = v_fac;
        falla('E3: el trigger acepto PAGADA->PENDIENTE');
    exception
        when others then
            if sqlcode <> -20070 then falla('E3: codigo ' || sqlcode || ' en vez de -20070'); end if;
    end;

    rollback to sp_cobest;

    for i in 1 .. v_fallas.count loop
        insert into tmp_cobest_fallas values (v_fallas(i));
    end loop;
exception
    when others then
        rollback to sp_cobest;
        v_msg := substrb('E?: el caso revento: ' || sqlerrm, 1, 300);
        insert into tmp_cobest_fallas values (v_msg);
end;
/

declare
    v_fallas number;
    v_lista  varchar2(3000);
begin
    select count(*) into v_fallas from tmp_cobest_fallas;
    select substrb(listagg(caso, ' | ' on overflow truncate) within group (order by caso), 1, 3000)
      into v_lista from tmp_cobest_fallas;
    execute immediate 'drop table tmp_cobest_fallas purge';
    raise_application_error(-20100, substrb('RESULTADO: FALLAS=' || v_fallas || ' | ' || v_lista, 1, 3000));
end;
/
