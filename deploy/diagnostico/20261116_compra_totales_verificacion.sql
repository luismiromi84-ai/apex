-- =============================================================================
-- 20261116_compra_totales_verificacion.sql
--
-- Totales de la compra por trigger (Task 2). Todo el DML va dentro de un
-- SAVEPOINT y se revierte: la base queda como estaba.
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261116_compra_totales_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

begin
    begin execute immediate 'drop table tmp_compra_tot_fallas purge'; exception when others then null; end;
end;
/

create table tmp_compra_tot_fallas (caso varchar2(300))
/

declare
    type t_lista is table of varchar2(300);
    v_fallas t_lista := t_lista();
    v_prov   number;
    v_compra number;
    v_sub    number;
    v_imp    number;
    v_tot    number;
    v_msg    varchar2(300);

    procedure falla(p_texto varchar2) is
    begin
        v_fallas.extend;
        v_fallas(v_fallas.last) := substrb(p_texto, 1, 300);
    end;

    procedure cuadra(p_caso varchar2, p_sub number, p_imp number, p_tot number) is
    begin
        select subtotal, monto_impuesto, monto_total
          into v_sub, v_imp, v_tot
          from compras where id_compra = v_compra;
        if nvl(v_sub, -1) <> p_sub or nvl(v_imp, -1) <> p_imp or nvl(v_tot, -1) <> p_tot then
            falla(p_caso || ': cabecera ' || nvl(v_sub, -1) || '/' || nvl(v_imp, -1) || '/' || nvl(v_tot, -1)
                  || ' en vez de ' || p_sub || '/' || p_imp || '/' || p_tot);
        end if;
    end;
begin
    savepoint sp_trg;

    insert into proveedores (id_empresa, rif, razon_social)
    values (1, 'J-TESTTRG-1', 'Proveedor de prueba trigger')
    returning id_proveedor into v_prov;

    insert into compras (id_empresa, id_proveedor, folio_factura, fecha_emision)
    values (1, v_prov, 'T-TRG-1', sysdate)
    returning id_compra into v_compra;

    -- T1: dos lineas al 16 % -> 150 / 24 / 174.
    insert into compras_det (id_compra, num_linea, descripcion, cantidad, precio_unitario,
                             porcentaje_impuesto, monto_impuesto, subtotal_linea, total_linea)
    values (v_compra, 1, 'Linea A', 1, 100, 16, 16, 100, 116);
    insert into compras_det (id_compra, num_linea, descripcion, cantidad, precio_unitario,
                             porcentaje_impuesto, monto_impuesto, subtotal_linea, total_linea)
    values (v_compra, 2, 'Linea B', 1, 50, 16, 8, 50, 58);
    cuadra('T1', 150, 24, 174);

    -- T2: cambiar la cantidad de la linea 1 recalcula.
    update compras_det set cantidad = 2, subtotal_linea = 200, monto_impuesto = 32, total_linea = 232
     where id_compra = v_compra and num_linea = 1;
    cuadra('T2', 250, 40, 290);

    -- T3: borrar la linea 2 recalcula.
    delete from compras_det where id_compra = v_compra and num_linea = 2;
    cuadra('T3', 200, 32, 232);

    -- T4: la cabecera confia en TOTAL_LINEA (descuento aplicado en la linea).
    insert into compras_det (id_compra, num_linea, descripcion, cantidad, precio_unitario,
                             porcentaje_descuento, monto_descuento,
                             porcentaje_impuesto, monto_impuesto, subtotal_linea, total_linea)
    values (v_compra, 3, 'Linea con descuento', 1, 100, 10, 10, 16, 16, 100, 106);
    cuadra('T4', 300, 48, 338);

    -- T5: sin lineas la cabecera queda en 0, no en nulo.
    delete from compras_det where id_compra = v_compra;
    cuadra('T5', 0, 0, 0);

    rollback to sp_trg;

    for i in 1 .. v_fallas.count loop
        insert into tmp_compra_tot_fallas values (v_fallas(i));
    end loop;
exception
    when others then
        rollback to sp_trg;
        v_msg := substrb('T?: el caso revento: ' || sqlerrm, 1, 300);
        insert into tmp_compra_tot_fallas values (v_msg);
end;
/

declare
    v_fallas number;
    v_lista  varchar2(3000);
begin
    select count(*) into v_fallas from tmp_compra_tot_fallas;
    select substrb(listagg(caso, ' | ' on overflow truncate) within group (order by caso), 1, 3000)
      into v_lista from tmp_compra_tot_fallas;
    execute immediate 'drop table tmp_compra_tot_fallas purge';
    raise_application_error(-20100, substrb('RESULTADO: FALLAS=' || v_fallas || ' | ' || v_lista, 1, 3000));
end;
/
