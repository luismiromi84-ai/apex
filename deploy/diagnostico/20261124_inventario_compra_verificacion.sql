-- =============================================================================
-- 20261124_inventario_compra_verificacion.sql
--
-- La compra registrada entra al kardex (2026-11-24):
--
--   C1  una compra con 2 lineas de producto deja 2 movimientos ENTRADA_COMPRA
--       y el saldo con las cantidades y el valor de las lineas (sin IVA)
--   C1b una linea de SERVICIO en la misma compra no genera movimiento ni saldo
--   C2  la doble valoracion del movimiento cuadra (ref = bs / tasa)
--   C3  registrar la compra dos veces no duplica (la segunda ni llega)
--
-- Todo dentro de un savepoint: rollback al final (no consume correlativos
-- fiscales ni deja datos).
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261124_inventario_compra_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000) := '';
    v_p1     number;
    v_p2     number;
    v_srv    number;
    v_prov   number;
    v_compra number;
    v_det    number;
    v_n      number;
    v_cant   number;
    v_val    number;
    v_bs     number;
    v_ref    number;
    v_tasa   number;

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

    procedure crea_articulo(p_tipo varchar2, p_nombre varchar2, p_id out number) is
    begin
        insert into producto_servicio (id_empresa, nombre, tipo, precio_sugerido,
                                       impuesto_aplicable, estado)
        values (1, p_nombre || ' ' || to_char(systimestamp, 'HH24MISSFF3'), p_tipo, 0, 0, 'ACTIVO')
        returning id_producto_servicio into p_id;
    end;
begin
    savepoint compra;
    crea_articulo('PRODUCTO', 'INV COMPRA A', v_p1);
    crea_articulo('PRODUCTO', 'INV COMPRA B', v_p2);
    crea_articulo('SERVICIO', 'INV COMPRA SERV', v_srv);

    select min(id_proveedor) into v_prov from proveedores where id_empresa = 1;
    if v_prov is null then
        falla('C0 hace falta un proveedor de la empresa 1', 'no hay');
        raise_application_error(-20101, 'RESULTADO: FALLAS=' || v_fallas || v_lista);
    end if;

    insert into compras (id_empresa, id_proveedor, tipo_documento, folio_factura,
                         fecha_emision, cod_moneda, tipo_cambio, estado, porcentaje_retencion)
    values (1, v_prov, 'FAC', 'INV-TEST-' || to_char(systimestamp, 'HH24MISSFF3'),
            trunc(sysdate), 'VES', 1, 'BORRADOR', 0)
    returning id_compra into v_compra;

    -- 5 x 10,00
    pkg_compra_detalle.guardar_detalle(v_det, v_compra, 1, v_p1, 'Linea A',
                                       5, 10, 0, 0, null, 0, 'admin');
    v_det := null;
    -- 2 x 7,50
    pkg_compra_detalle.guardar_detalle(v_det, v_compra, 2, v_p2, 'Linea B',
                                       2, 7.50, 0, 0, null, 0, 'admin');
    v_det := null;
    -- 1 x 100,00 de servicio
    pkg_compra_detalle.guardar_detalle(v_det, v_compra, 3, v_srv, 'Servicio',
                                       1, 100, 0, 0, null, 0, 'admin');

    ---------------------------------------------------------------- registrar
    begin
        pkg_compras.prc_registrar_compra(v_compra, 'admin');
    exception
        when others then
            falla('C1 registrar la compra', sqlerrm);
            raise_application_error(-20101, 'RESULTADO: FALLAS=' || v_fallas || v_lista);
    end;

    ---------------------------------------------------------------- C1
    select count(*) into v_n
      from kardex_mov
     where doc_tipo = 'COMPRA' and id_doc = v_compra and tipo_movimiento = 'ENTRADA_COMPRA';
    espera_num('C1 movimientos de la compra', v_n, 2);

    select cantidad, valor_bs into v_cant, v_val
      from kardex_saldo where id_empresa = 1 and id_producto_servicio = v_p1;
    espera_num('C1 cantidad del articulo A', v_cant, 5);
    espera_num('C1 valor del articulo A (sin IVA)', v_val, 50);

    select cantidad, valor_bs into v_cant, v_val
      from kardex_saldo where id_empresa = 1 and id_producto_servicio = v_p2;
    espera_num('C1 cantidad del articulo B', v_cant, 2);
    espera_num('C1 valor del articulo B', v_val, 15);

    ---------------------------------------------------------------- C1b
    select count(*) into v_n
      from kardex_saldo where id_empresa = 1 and id_producto_servicio = v_srv;
    espera_num('C1b el servicio no tiene saldo', v_n, 0);

    ---------------------------------------------------------------- C2
    for r in (select costo_total_bs, costo_total_ref, tasa_cambio
                from kardex_mov where doc_tipo = 'COMPRA' and id_doc = v_compra)
    loop
        if abs(r.costo_total_ref - round(r.costo_total_bs / r.tasa_cambio, 2)) > 0.01 then
            falla('C2 doble valoracion', r.costo_total_bs || ' Bs vs ' || r.costo_total_ref);
        end if;
    end loop;

    ---------------------------------------------------------------- C3
    begin
        pkg_compras.prc_registrar_compra(v_compra, 'admin');
        -- la compra ya no esta en BORRADOR: debe rechazar (-20083)
        falla('C3 registrar dos veces', 'acepto la segunda');
    exception
        when others then
            if sqlcode not in (-20083, -20152) then
                falla('C3 registrar dos veces', 'error ' || sqlcode || ': ' || sqlerrm);
            end if;
    end;

    select count(*) into v_n
      from kardex_mov where doc_tipo = 'COMPRA' and id_doc = v_compra;
    espera_num('C3 sigue habiendo 2 movimientos', v_n, 2);


    ---------------------------------------------------------------- C4 (divisa)
    -- Una compra en USD valorada en bolivares: 2 x 10 USD a 916,6477 => 18.332,95 Bs
    begin
        declare
            v_c2   number;
            v_p3   number;
            v_bs   number;
            v_ref  number;
            v_unit number;
        begin
            crea_articulo('PRODUCTO', 'INV COMPRA USD', v_p3);
            insert into compras (id_empresa, id_proveedor, tipo_documento, folio_factura,
                                 fecha_emision, cod_moneda, tipo_cambio, estado, porcentaje_retencion)
            values (1, v_prov, 'FAC', 'INV-USD-' || to_char(systimestamp, 'HH24MISSFF3'),
                    trunc(sysdate), 'USD', 916.6477, 'BORRADOR', 0)
            returning id_compra into v_c2;
            v_det := null;
            pkg_compra_detalle.guardar_detalle(v_det, v_c2, 1, v_p3, 'Linea USD',
                                               2, 10, 0, 0, null, 0, 'admin');
            pkg_compras.prc_registrar_compra(v_c2, 'admin');

            select costo_total_bs, costo_unit_ref into v_bs, v_unit
              from kardex_mov
             where doc_tipo = 'COMPRA' and id_doc = v_c2;
            espera_num('C4 la compra en divisa se valora en bolivares', v_bs, 18332.95, 0.05);
            espera_num('C4 el costo unitario en divisa es 10', v_unit, 10, 0.01);

            select nvl(pkg_inventario.fn_disponible(1, v_p3), 0) into v_ref from dual;
            espera_num('C4 cantidad del articulo en divisa', v_ref, 2);
        end;
    exception
        when others then falla('C4 compra en divisa', sqlerrm);
    end;

    ---------------------------------------------------------------- C5 (nota de compra)
    -- La NC de compra saca al costo de la linea original (en divisa, convertido).
    begin
        declare
            v_c3  number;
            v_p4  number;
            v_nc  number;
            v_d   number;
            v_bs  number;
        begin
            crea_articulo('PRODUCTO', 'INV COMPRA NOTA', v_p4);
            insert into compras (id_empresa, id_proveedor, tipo_documento, folio_factura,
                                 fecha_emision, cod_moneda, tipo_cambio, estado, porcentaje_retencion)
            values (1, v_prov, 'FAC', 'INV-NC-' || to_char(systimestamp, 'HH24MISSFF3'),
                    trunc(sysdate), 'USD', 916.6477, 'BORRADOR', 0)
            returning id_compra into v_c3;
            v_d := null;
            pkg_compra_detalle.guardar_detalle(v_d, v_c3, 1, v_p4, 'Linea',
                                               4, 10, 0, 0, null, 0, 'admin');
            pkg_compras.prc_registrar_compra(v_c3, 'admin');

            insert into compras (id_empresa, id_proveedor, tipo_documento, folio_factura,
                                 fecha_emision, cod_moneda, tipo_cambio, estado, porcentaje_retencion,
                                 id_compra_origen)
            values (1, v_prov, 'NC', 'INV-NCC-' || to_char(systimestamp, 'HH24MISSFF3'),
                    trunc(sysdate), 'USD', 916.6477, 'BORRADOR', 0, v_c3)
            returning id_compra into v_nc;
            v_d := null;
            pkg_compra_detalle.guardar_detalle(v_d, v_nc, 1, v_p4, 'Linea',
                                               2, 10, 0, 0, null, 0, 'admin');
            -- la nota copia el costo de la linea original
            update compras_det set id_detalle_origen =
                   (select min(o.id_detalle) from compras_det o where o.id_compra = v_c3)
             where id_compra = v_nc;
            pkg_compras.prc_registrar_compra(v_nc, 'admin');

            select nvl(pkg_inventario.fn_disponible(1, v_p4), 0) into v_bs from dual;
            espera_num('C5 la NC de compra devuelve 2 de 4', v_bs, 2);

            select m.costo_unit_bs into v_bs
              from kardex_mov m
             where m.doc_tipo = 'COMPRA' and m.id_doc = v_nc
               and m.tipo_movimiento = 'SALIDA_NC_PROVEEDOR';
            espera_num('C5 la NC saca al costo original en bolivares', v_bs, 9166.48, 0.05);
        end;
    exception
        when others then falla('C5 nota de compra', sqlerrm);
    end;

    ------------------------------------------------------------------ resultado
    rollback to savepoint compra;

    if v_fallas > 0 then
        raise_application_error(-20101, 'RESULTADO: FALLAS=' || v_fallas || v_lista);
    end if;
    raise_application_error(-20100, 'RESULTADO: FALLAS=0');
end;
/
