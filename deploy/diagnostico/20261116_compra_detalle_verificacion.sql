-- =============================================================================
-- 20261116_compra_detalle_verificacion.sql
--
-- Detalle de la compra (Task 5). Todo el DML va dentro de un SAVEPOINT.
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261116_compra_detalle_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

begin
    begin execute immediate 'drop table tmp_comp_det_fallas purge'; exception when others then null; end;
end;
/

create table tmp_comp_det_fallas (caso varchar2(300))
/

declare
    type t_lista is table of varchar2(300);
    v_fallas t_lista := t_lista();
    v_msg    varchar2(300);

    v_prov   number;
    v_usu    number;
    v_compra number;
    v_linea  number;
    v_linea2 number;
    v_nc     number;
    v_sub    number;
    v_imp    number;
    v_tot    number;
    v_base   number;
    v_tlinea number;
    v_origen number;

    procedure falla(p_texto varchar2) is
    begin
        v_fallas.extend;
        v_fallas(v_fallas.last) := substrb(p_texto, 1, 300);
    end;

    function nueva(p_tipo varchar2, p_folio varchar2, p_origen number) return number is
        v_id number;
    begin
        insert into compras (id_empresa, id_proveedor, tipo_documento, folio_factura,
                             fecha_emision, estado, porcentaje_retencion, id_compra_origen)
        values (1, v_prov, p_tipo, p_folio, sysdate, 'BORRADOR', 75, p_origen)
        returning id_compra into v_id;
        return v_id;
    end;
begin
    savepoint sp_det;

    insert into proveedores (id_empresa, rif, razon_social, cod_pais)
    values (1, 'J-TESTDET-1', 'Proveedor detalle', 'VE')
    returning id_proveedor into v_prov;

    insert into usuario (username, email, estado, id_empresa, password_hash)
    values ('test_det_uno', 'test_det@local', 'ACTIVO', 1, 'x')
    returning usuario_id into v_usu;

    v_compra := nueva('FAC', 'DET-1', null);

    -- D1 y D6: la linea se calcula dentro del paquete y la cabecera se recalcula.
    pkg_compra_detalle.guardar_detalle(
        p_id_detalle => v_linea, p_id_compra => v_compra, p_num_linea => null,
        p_id_producto_servicio => null, p_descripcion => 'Servicio',
        p_cantidad => 2, p_precio_unitario => 50,
        p_porcentaje_descuento => 10, p_monto_descuento => null,
        p_id_impuesto => 1, p_porcentaje_impuesto => 16, p_usuario => 'test_det_uno');

    select subtotal_linea, monto_descuento, monto_impuesto, total_linea
      into v_base, v_sub, v_imp, v_tlinea
      from compras_det where id_detalle = v_linea;
    if v_base <> 90 then falla('D6: subtotal_linea ' || v_base || ' en vez de 90'); end if;
    if v_sub <> 10 then falla('D6: descuento ' || v_sub || ' en vez de 10'); end if;
    if v_imp <> 14.4 then falla('D6: IVA ' || v_imp || ' en vez de 14.40'); end if;
    if v_tlinea <> 104.4 then falla('D6: total ' || v_tlinea || ' en vez de 104.40'); end if;

    select subtotal, monto_impuesto, monto_total into v_sub, v_imp, v_tot
      from compras where id_compra = v_compra;
    if v_sub <> 90 or v_imp <> 14.4 or v_tot <> 104.4 then
        falla('D1: cabecera ' || v_sub || '/' || v_imp || '/' || v_tot || ' en vez de 90/14.40/104.40');
    end if;

    -- D3 (parte 1): borrar una linea en BORRADOR recalcula.
    pkg_compra_detalle.guardar_detalle(
        p_id_detalle => v_linea2, p_id_compra => v_compra, p_num_linea => null,
        p_id_producto_servicio => null, p_descripcion => 'Otra',
        p_cantidad => 1, p_precio_unitario => 100,
        p_porcentaje_descuento => 0, p_monto_descuento => 0,
        p_id_impuesto => 1, p_porcentaje_impuesto => 16, p_usuario => 'test_det_uno');
    select monto_total into v_tot from compras where id_compra = v_compra;
    if v_tot <> 220.4 then falla('D1: con dos lineas el total es ' || v_tot || ' en vez de 220.40'); end if;

    pkg_compra_detalle.eliminar_detalle(p_id_detalle => v_linea2, p_usuario => 'test_det_uno');
    select monto_total into v_tot from compras where id_compra = v_compra;
    if v_tot <> 104.4 then falla('D3: tras borrar el total es ' || v_tot || ' en vez de 104.40'); end if;

    -- D4: copiar las lineas de una FAC a su NC.
    pkg_compras.prc_registrar_compra(p_id_compra => v_compra, p_usuario => 'test_det_uno');
    v_nc := nueva('NC', 'DET-NC-1', v_compra);
    pkg_compra_detalle.copiar_desde_compra(p_id_compra => v_nc, p_id_compra_origen => v_compra,
                                           p_usuario => 'test_det_uno');
    select count(*), count(id_detalle_origen) into v_sub, v_origen
      from compras_det where id_compra = v_nc;
    if v_sub <> 1 or v_origen <> 1 then
        falla('D4: la nota tiene ' || v_sub || ' lineas y ' || v_origen || ' con origen');
    end if;

    -- D5: copiar dos veces.
    begin
        pkg_compra_detalle.copiar_desde_compra(p_id_compra => v_nc, p_id_compra_origen => v_compra,
                                               p_usuario => 'test_det_uno');
        falla('D5: copio dos veces');
    exception
        when others then
            if sqlcode <> -20045 then falla('D5: codigo ' || sqlcode || ' en vez de -20045'); end if;
    end;

    -- D2 y D3 (parte 2): en REGISTRADA no se guarda ni se borra.
    begin
        pkg_compra_detalle.guardar_detalle(
            p_id_detalle => v_linea2, p_id_compra => v_compra, p_num_linea => 9,
            p_id_producto_servicio => null, p_descripcion => 'Tarde',
            p_cantidad => 1, p_precio_unitario => 10,
            p_porcentaje_descuento => 0, p_monto_descuento => 0,
            p_id_impuesto => 1, p_porcentaje_impuesto => 16, p_usuario => 'test_det_uno');
        falla('D2: guardo una linea en una compra registrada');
    exception
        when others then
            if sqlcode <> -20083 then falla('D2: codigo ' || sqlcode || ' en vez de -20083'); end if;
    end;

    begin
        pkg_compra_detalle.eliminar_detalle(p_id_detalle => v_linea, p_usuario => 'test_det_uno');
        falla('D3: borro una linea de una compra registrada');
    exception
        when others then
            if sqlcode <> -20083 then falla('D3: codigo ' || sqlcode || ' en vez de -20083'); end if;
    end;

    rollback to sp_det;

    for i in 1 .. v_fallas.count loop
        insert into tmp_comp_det_fallas values (v_fallas(i));
    end loop;
exception
    when others then
        rollback to sp_det;
        v_msg := substrb('D?: el caso revento: ' || sqlerrm, 1, 300);
        insert into tmp_comp_det_fallas values (v_msg);
end;
/

declare
    v_fallas number;
    v_lista  varchar2(3000);
begin
    select count(*) into v_fallas from tmp_comp_det_fallas;
    select substrb(listagg(caso, ' | ' on overflow truncate) within group (order by caso), 1, 3000)
      into v_lista from tmp_comp_det_fallas;
    execute immediate 'drop table tmp_comp_det_fallas purge';
    raise_application_error(-20100, substrb('RESULTADO: FALLAS=' || v_fallas || ' | ' || v_lista, 1, 3000));
end;
/
