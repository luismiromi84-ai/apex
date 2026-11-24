-- =============================================================================
-- 20261124_inventario_factura_verificacion.sql
--
-- La factura emitida saca del kardex (2026-11-24):
--
--   F1  una FAC de 3 unidades PROCESADA deja el saldo en 7 y el movimiento con
--       el CPP vigente (12,000000), no con el precio de venta
--   F2  una factura en BORRADOR (PENDIENTE) no mueve nada
--   F3  una NC de 2 unidades procesada ENTRA al costo de la salida original
--   F3b una ND de 1 unidad procesada SALE al CPP vigente
--
-- El saldo de partida se crea con un ajuste de entrada: 10 unidades a 12,00.
-- Todo dentro de un savepoint: rollback al final.
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261124_inventario_factura_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000) := '';
    v_prod   number;
    v_cli    number;
    v_mov    number;
    v_fac    number;
    v_det    number;
    v_nc     number;
    v_detnc  number;
    v_nd     number;
    v_n      number;
    v_cant   number;
    v_cpp    number;
    v_unit   number;

    procedure falla(p_caso varchar2, p_detalle varchar2) is
    begin
        v_fallas := v_fallas + 1;
        v_lista  := v_lista || ' | ' || p_caso || ': ' || substrb(p_detalle, 1, 170);
    end;

    procedure espera_num(p_caso varchar2, p_valor number, p_esperado number, p_tol number default 0.001) is
    begin
        if p_valor is null or abs(p_valor - p_esperado) > p_tol then
            falla(p_caso, 'esperaba ' || p_esperado || ' y hay ' || nvl(to_char(p_valor), 'NULL'));
        end if;
    end;

    procedure crea_factura(p_tipo varchar2, p_origen number, p_id out number) is
    begin
        insert into facturas (id_empresa, id_cliente, tipo_documento, folio_factura,
                              cod_moneda, tipo_cambio, fecha_emision, estado,
                              porcentaje_retencion, id_factura_origen)
        values (1, v_cli, p_tipo,
                p_tipo || '-INV-' || to_char(systimestamp, 'HH24MISSFF3'),
                'VES', 1, trunc(sysdate), 'PENDIENTE', 0, p_origen)
        returning id_factura into p_id;
    end;

    procedure crea_linea(p_factura number, p_num number, p_cant number, p_precio number,
                         p_origen number, p_id out number) is
    begin
        insert into facturas_det (id_factura, num_linea, id_producto, descripcion, cantidad,
                                  precio_unitario, porcentaje_impuesto, monto_impuesto,
                                  subtotal_linea, monto_total_linea, tasa_cambio_aplicada,
                                  subtotal_bs, total_bs, id_detalle_origen)
        values (p_factura, p_num, v_prod, 'Linea de prueba', p_cant,
                p_precio, 0, 0,
                round(p_cant * p_precio, 2), round(p_cant * p_precio, 2), 1,
                round(p_cant * p_precio, 2), round(p_cant * p_precio, 2), p_origen)
        returning id_detalle into p_id;
    end;
begin
    savepoint factura;
    v_cli := null;
    select min(id_cliente) into v_cli from clientes where id_empresa = 1 and nvl(estado, 'ACTIVO') = 'ACTIVO';
    if v_cli is null then
        falla('F0 hace falta un cliente de la empresa 1', 'no hay');
        raise_application_error(-20101, 'RESULTADO: FALLAS=' || v_fallas || v_lista);
    end if;

    insert into producto_servicio (id_empresa, nombre, tipo, precio_sugerido, impuesto_aplicable, estado)
    values (1, 'INV FACTURA ' || to_char(systimestamp, 'HH24MISSFF3'), 'PRODUCTO', 30, 0, 'ACTIVO')
    returning id_producto_servicio into v_prod;

    -- Saldo de partida: 10 unidades a 12,00 Bs.
    pkg_inventario.prc_movimiento(
        p_id_empresa => 1, p_id_producto => v_prod, p_fecha => trunc(sysdate),
        p_tipo => 'AJUSTE_ENTRADA', p_cantidad => 10, p_costo_unit_bs => 12,
        p_tasa => 1, p_moneda => 'VES', p_doc_tipo => 'AJUSTE', p_id_doc => null,
        p_id_detalle => null, p_motivo => 'saldo de partida', p_usuario => 'admin',
        p_id_movimiento => v_mov);

    ---------------------------------------------------------------- F2 + F1
    crea_factura('FAC', null, v_fac);
    crea_linea(v_fac, 1, 3, 30, null, v_det);

    select nvl(pkg_inventario.fn_disponible(1, v_prod), 0) into v_cant from dual;
    espera_num('F2 el borrador no mueve', v_cant, 10);

    pkg_facturacion.prc_procesar_factura(v_fac, 'admin');

    select nvl(pkg_inventario.fn_disponible(1, v_prod), 0) into v_cant from dual;
    espera_num('F1 la factura emitida descuenta', v_cant, 7);

    begin
        select costo_unit_bs into v_unit
          from kardex_mov
         where doc_tipo = 'FACTURA' and id_doc = v_fac and tipo_movimiento = 'SALIDA_FACTURA';
        espera_num('F1 la salida va al CPP, no al precio de venta', v_unit, 12, 0.000001);
    exception
        when no_data_found then
            falla('F1 no hay movimiento de salida', 'falta');
    end;

    ---------------------------------------------------------------- F3 (NC)
    crea_factura('NC', v_fac, v_nc);
    crea_linea(v_nc, 1, 2, 30, v_det, v_detnc);
    pkg_facturacion.prc_procesar_factura(v_nc, 'admin');

    select nvl(pkg_inventario.fn_disponible(1, v_prod), 0) into v_cant from dual;
    espera_num('F3 la NC devuelve 2', v_cant, 9);

    begin
        select costo_unit_bs into v_unit
          from kardex_mov
         where doc_tipo = 'FACTURA' and id_doc = v_nc and tipo_movimiento = 'ENTRADA_NC_CLIENTE';
        espera_num('F3 la NC entra al costo de la venta original', v_unit, 12, 0.000001);
    exception
        when no_data_found then
            falla('F3 no hay movimiento de la NC', 'falta');
    end;

    ---------------------------------------------------------------- F3b (ND)
    crea_factura('ND', v_fac, v_nd);
    crea_linea(v_nd, 1, 1, 30, null, v_detnc);
    pkg_facturacion.prc_procesar_factura(v_nd, 'admin');

    select nvl(pkg_inventario.fn_disponible(1, v_prod), 0) into v_cant from dual;
    espera_num('F3b la ND descuenta 1', v_cant, 8);

    begin
        select costo_unit_bs into v_unit
          from kardex_mov
         where doc_tipo = 'FACTURA' and id_doc = v_nd and tipo_movimiento = 'SALIDA_ND_CLIENTE';
        espera_num('F3b la ND sale al CPP', v_unit, 12, 0.000001);
    exception
        when no_data_found then
            falla('F3b no hay movimiento de la ND', 'falta');
    end;


    ---------------------------------------------------------------- F4 (NC pendiente)
    -- Anular la factura cuando su NC esta PENDIENTE: la NC devolvera el stock al
    -- procesarse, asi que la anulacion no puede devolverlo tambien.
    begin
        declare
            v_f  number;
            v_n  number;
            v_d  number;
            v_m  number;
            v_q  number;
        begin
            pkg_inventario.prc_movimiento(1, v_prod, trunc(sysdate), 'AJUSTE_ENTRADA', 5, 12,
                                          1, 'VES', 'AJUSTE', null, null, 'partida F4', 'admin', v_m);
            crea_factura('FAC', null, v_f);
            crea_linea(v_f, 1, 2, 30, null, v_d);
            pkg_facturacion.prc_procesar_factura(v_f, 'admin');
            crea_factura('NC', v_f, v_n);
            crea_linea(v_n, 1, 2, 30, v_d, v_m);

            select nvl(pkg_inventario.fn_disponible(1, v_prod), 0) into v_q from dual;
            v_q := v_q;  -- saldo antes de anular
            pkg_facturacion.prc_anular_factura(v_f, null, 'admin');
            declare
                v_despues number;
            begin
                select nvl(pkg_inventario.fn_disponible(1, v_prod), 0) into v_despues from dual;
                espera_num('F4 anular con la NC pendiente no devuelve el stock', v_despues, v_q);
            end;
        end;
    exception
        when others then falla('F4 NC pendiente', sqlerrm);
    end;

    ------------------------------------------------------------------ resultado
    rollback to savepoint factura;

    if v_fallas > 0 then
        raise_application_error(-20101, 'RESULTADO: FALLAS=' || v_fallas || v_lista);
    end if;
    raise_application_error(-20100, 'RESULTADO: FALLAS=0');
end;
/
