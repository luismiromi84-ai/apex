-- =============================================================================
-- 20261124_inventario_reversa_verificacion.sql
--
-- Anular devuelve el inventario con movimientos de REVERSA (2026-11-24):
--
--   R1  anular una compra registrada deja el saldo como antes de la compra
--   R2  anular una factura sin NC revierte la salida, al costo con que salio
--   R3  anular una factura CON su nota de credito timbrada NO revierte otra vez
--   R4  reversar dos veces no duplica (idempotente)
--
-- Todo dentro de un savepoint: rollback al final.
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261124_inventario_reversa_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000) := '';
    v_prod   number;
    v_prod2  number;
    v_cli    number;
    v_prov   number;
    v_compra number;
    v_det    number;
    v_fac    number;
    v_nc     number;
    v_fac2   number;
    v_mov    number;
    v_n      number;
    v_cant   number;
    v_val    number;

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
                p_tipo || '-REV-' || to_char(systimestamp, 'HH24MISSFF3'),
                'VES', 1, trunc(sysdate), 'PENDIENTE', 0, p_origen)
        returning id_factura into p_id;
    end;

    procedure crea_linea(p_factura number, p_prod number, p_num number, p_cant number,
                         p_precio number, p_origen number, p_id out number) is
    begin
        insert into facturas_det (id_factura, num_linea, id_producto, descripcion, cantidad,
                                  precio_unitario, porcentaje_impuesto, monto_impuesto,
                                  subtotal_linea, monto_total_linea, tasa_cambio_aplicada,
                                  subtotal_bs, total_bs, id_detalle_origen)
        values (p_factura, p_num, p_prod, 'Linea', p_cant, p_precio, 0, 0,
                round(p_cant * p_precio, 2), round(p_cant * p_precio, 2), 1,
                round(p_cant * p_precio, 2), round(p_cant * p_precio, 2), p_origen)
        returning id_detalle into p_id;
    end;
begin
    savepoint rev;
    select min(id_cliente) into v_cli from clientes where id_empresa = 1 and nvl(estado, 'ACTIVO') = 'ACTIVO';
    select min(id_proveedor) into v_prov from proveedores where id_empresa = 1;
    if v_cli is null or v_prov is null then
        falla('R0 faltan cliente o proveedor de la empresa 1', 'no hay');
        raise_application_error(-20101, 'RESULTADO: FALLAS=' || v_fallas || v_lista);
    end if;

    insert into producto_servicio (id_empresa, nombre, tipo, precio_sugerido, impuesto_aplicable, estado)
    values (1, 'INV REV A ' || to_char(systimestamp, 'HH24MISSFF3'), 'PRODUCTO', 30, 0, 'ACTIVO')
    returning id_producto_servicio into v_prod;
    insert into producto_servicio (id_empresa, nombre, tipo, precio_sugerido, impuesto_aplicable, estado)
    values (1, 'INV REV B ' || to_char(systimestamp, 'HH24MISSFF3'), 'PRODUCTO', 30, 0, 'ACTIVO')
    returning id_producto_servicio into v_prod2;

    ---------------------------------------------------------------- R1 (compra)
    begin
        insert into compras (id_empresa, id_proveedor, tipo_documento, folio_factura,
                             fecha_emision, cod_moneda, tipo_cambio, estado, porcentaje_retencion)
        values (1, v_prov, 'FAC', 'REV-C-' || to_char(systimestamp, 'HH24MISSFF3'),
                trunc(sysdate), 'VES', 1, 'BORRADOR', 0)
        returning id_compra into v_compra;
        pkg_compra_detalle.guardar_detalle(v_det, v_compra, 1, v_prod, 'Linea',
                                           4, 25, 0, 0, null, 0, 'admin');
        pkg_compras.prc_registrar_compra(v_compra, 'admin');

        select nvl(pkg_inventario.fn_disponible(1, v_prod), 0) into v_cant from dual;
        espera_num('R1 la compra suma 4', v_cant, 4);

        pkg_compras.prc_anular_compra(v_compra, 'admin');

        select nvl(pkg_inventario.fn_disponible(1, v_prod), 0) into v_cant from dual;
        espera_num('R1 anular la compra deja el saldo en cero', v_cant, 0);

        select count(*) into v_n
          from kardex_mov
         where doc_tipo = 'COMPRA' and id_doc = v_compra and tipo_movimiento = 'REVERSA_ENTRADA';
        espera_num('R1 hay un movimiento de reversa de la entrada', v_n, 1);

        -- R4: anular otra vez no agrega nada
        pkg_compras.prc_anular_compra(v_compra, 'admin');
        select count(*) into v_n from kardex_mov where doc_tipo = 'COMPRA' and id_doc = v_compra;
        espera_num('R4 reversar dos veces no duplica', v_n, 2);
    exception
        when others then falla('R1 compra', sqlerrm);
    end;

    ---------------------------------------------------------------- R2 (factura sin NC)
    begin
        -- saldo de partida para v_prod2: 10 a 12
        pkg_inventario.prc_movimiento(
            p_id_empresa => 1, p_id_producto => v_prod2, p_fecha => trunc(sysdate),
            p_tipo => 'AJUSTE_ENTRADA', p_cantidad => 10, p_costo_unit_bs => 12,
            p_tasa => 1, p_moneda => 'VES', p_doc_tipo => 'AJUSTE', p_id_doc => null,
            p_id_detalle => null, p_motivo => 'partida', p_usuario => 'admin',
            p_id_movimiento => v_mov);

        crea_factura('FAC', null, v_fac);
        crea_linea(v_fac, v_prod2, 1, 3, 30, null, v_det);
        pkg_facturacion.prc_procesar_factura(v_fac, 'admin');

        select nvl(pkg_inventario.fn_disponible(1, v_prod2), 0) into v_cant from dual;
        espera_num('R2 la factura deja 7', v_cant, 7);

        pkg_facturacion.prc_anular_factura(v_fac, null, 'admin');

        select nvl(pkg_inventario.fn_disponible(1, v_prod2), 0) into v_cant from dual;
        espera_num('R2 anular la factura devuelve las 3', v_cant, 10);

        select count(*) into v_n
          from kardex_mov
         where doc_tipo = 'FACTURA' and id_doc = v_fac and tipo_movimiento = 'REVERSA_SALIDA';
        espera_num('R2 hay reversa de la salida', v_n, 1);
    exception
        when others then falla('R2 factura', sqlerrm);
    end;

    ---------------------------------------------------------------- R3 (factura con NC)
    begin
        -- otra vez saldo para v_prod2 = 10 (R2 ya lo dejo asi)
        crea_factura('FAC', null, v_fac2);
        crea_linea(v_fac2, v_prod2, 1, 2, 30, null, v_det);
        pkg_facturacion.prc_procesar_factura(v_fac2, 'admin');

        crea_factura('NC', v_fac2, v_nc);
        crea_linea(v_nc, v_prod2, 1, 2, 30, v_det, v_mov);
        pkg_facturacion.prc_procesar_factura(v_nc, 'admin');

        select nvl(pkg_inventario.fn_disponible(1, v_prod2), 0) into v_cant from dual;
        espera_num('R3 la NC devuelve las 2', v_cant, 10);

        pkg_facturacion.prc_anular_factura(v_fac2, null, 'admin');

        select nvl(pkg_inventario.fn_disponible(1, v_prod2), 0) into v_cant from dual;
        espera_num('R3 anular con NC no devuelve dos veces', v_cant, 10);

        select count(*) into v_n
          from kardex_mov
         where doc_tipo = 'FACTURA' and id_doc = v_fac2
           and tipo_movimiento in ('REVERSA_SALIDA', 'REVERSA_ENTRADA');
        espera_num('R3 no hay reversa de la salida de la factura', v_n, 0);
    exception
        when others then falla('R3 factura con NC', sqlerrm);
    end;


    ---------------------------------------------------------------- R5 (compra con nota)
    -- Anular una compra que ya tiene una nota registrada se rechaza con -20156:
    -- primero se anula la nota. Si no, el saldo quedaria corto (o -20150).
    begin
        declare
            v_c  number;
            v_p  number;
            v_d  number;
            v_nc number;
        begin
            insert into producto_servicio (id_empresa, nombre, tipo, precio_sugerido,
                                           impuesto_aplicable, estado)
            values (1, 'INV R5 ' || to_char(systimestamp, 'HH24MISSFF3'), 'PRODUCTO', 0, 0, 'ACTIVO')
            returning id_producto_servicio into v_p;

            insert into compras (id_empresa, id_proveedor, tipo_documento, folio_factura,
                                 fecha_emision, cod_moneda, tipo_cambio, estado, porcentaje_retencion)
            values (1, v_prov, 'FAC', 'R5-' || to_char(systimestamp, 'HH24MISSFF3'),
                    trunc(sysdate), 'VES', 1, 'BORRADOR', 0)
            returning id_compra into v_c;
            v_d := null;
            pkg_compra_detalle.guardar_detalle(v_d, v_c, 1, v_p, 'Linea', 5, 10, 0, 0, null, 0, 'admin');
            pkg_compras.prc_registrar_compra(v_c, 'admin');

            insert into compras (id_empresa, id_proveedor, tipo_documento, folio_factura,
                                 fecha_emision, cod_moneda, tipo_cambio, estado, porcentaje_retencion,
                                 id_compra_origen)
            values (1, v_prov, 'NC', 'R5NC-' || to_char(systimestamp, 'HH24MISSFF3'),
                    trunc(sysdate), 'VES', 1, 'BORRADOR', 0, v_c)
            returning id_compra into v_nc;
            v_d := null;
            pkg_compra_detalle.guardar_detalle(v_d, v_nc, 1, v_p, 'Linea', 2, 10, 0, 0, null, 0, 'admin');
            update compras_det set id_detalle_origen =
                   (select min(o.id_detalle) from compras_det o where o.id_compra = v_c)
             where id_compra = v_nc;
            pkg_compras.prc_registrar_compra(v_nc, 'admin');

            begin
                pkg_compras.prc_anular_compra(v_c, 'admin');
                falla('R5 anular compra con nota registrada', 'acepto la anulacion');
            exception
                when others then
                    if sqlcode <> -20156 then
                        falla('R5 anular compra con nota registrada',
                              'error ' || sqlcode || ': ' || sqlerrm);
                    end if;
            end;
        end;
    exception
        when others then falla('R5 compra con nota', sqlerrm);
    end;

    ------------------------------------------------------------------ resultado
    rollback to savepoint rev;

    if v_fallas > 0 then
        raise_application_error(-20101, 'RESULTADO: FALLAS=' || v_fallas || v_lista);
    end if;
    raise_application_error(-20100, 'RESULTADO: FALLAS=0');
end;
/
