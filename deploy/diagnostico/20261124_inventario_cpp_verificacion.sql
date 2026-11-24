-- =============================================================================
-- 20261124_inventario_cpp_verificacion.sql
--
-- El costo promedio ponderado de PKG_INVENTARIO (2026-11-24), sin documentos:
--
--   K1  entrada 10 a 10,00 Bs        -> cantidad 10, valor 100,00, CPP 10
--   K2  salida de 6                  -> valor 40,00 y CPP sigue en 10
--   K3  segunda entrada 10 a 20,00   -> CPP 15,000000 (ponderado)
--   K4  salida que AGOTA el saldo    -> cantidad 0 y valor 0,00 exactos
--   K5  la doble valoracion cuadra   -> costo_total_ref = round(bs/tasa,2)
--   K8  un SERVICIO no tiene kardex  -> -20155
--   K11 el mismo documento dos veces -> -20152
--
-- Todo dentro de un savepoint con su propio articulo: al final rollback y la
-- base queda igual. (Las identidades y los folios consumidos no vuelven, es
-- lo esperado.)
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261124_inventario_cpp_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000) := '';
    v_prod   number;
    v_prod2  number;
    v_mov    number;
    v_n      number;
    v_num    number;
    v_cant   number;
    v_val    number;
    v_cpp    number;
    v_ref    number;
    v_bs     number;
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

    procedure crea_articulo(p_tipo varchar2, p_id out number) is
    begin
        insert into producto_servicio (id_empresa, nombre, tipo, precio_sugerido,
                                       impuesto_aplicable, estado)
        values (1, 'INV PRUEBA ' || p_tipo || ' ' || to_char(systimestamp, 'HH24MISSFF3'),
                p_tipo, 0, 16, 'ACTIVO')
        returning id_producto_servicio into p_id;
    end;
begin
    savepoint cpp;
    crea_articulo('PRODUCTO', v_prod);
    crea_articulo('SERVICIO', v_prod2);

    ---------------------------------------------------------------- K1
    begin
        pkg_inventario.prc_movimiento(
            p_id_empresa => 1, p_id_producto => v_prod, p_fecha => trunc(sysdate),
            p_tipo => 'AJUSTE_ENTRADA', p_cantidad => 10, p_costo_unit_bs => 10,
            p_tasa => 1, p_moneda => 'VES', p_doc_tipo => 'AJUSTE', p_id_doc => null,
            p_id_detalle => null, p_motivo => 'prueba K1', p_usuario => 'VERIF',
            p_id_movimiento => v_mov);
        select cantidad, valor_bs, costo_promedio_bs into v_cant, v_val, v_cpp
          from kardex_saldo where id_empresa = 1 and id_producto_servicio = v_prod;
        espera_num('K1 cantidad', v_cant, 10);
        espera_num('K1 valor', v_val, 100);
        espera_num('K1 CPP', v_cpp, 10, 0.000001);
    exception
        when others then falla('K1 entrada simple', sqlerrm);
    end;

    ---------------------------------------------------------------- K2
    begin
        pkg_inventario.prc_movimiento(
            p_id_empresa => 1, p_id_producto => v_prod, p_fecha => trunc(sysdate),
            p_tipo => 'AJUSTE_SALIDA', p_cantidad => 6, p_costo_unit_bs => null,
            p_tasa => 1, p_moneda => 'VES', p_doc_tipo => 'AJUSTE', p_id_doc => null,
            p_id_detalle => null, p_motivo => 'prueba K2', p_usuario => 'VERIF',
            p_id_movimiento => v_mov);
        select cantidad, valor_bs, costo_promedio_bs into v_cant, v_val, v_cpp
          from kardex_saldo where id_empresa = 1 and id_producto_servicio = v_prod;
        espera_num('K2 cantidad', v_cant, 4);
        espera_num('K2 valor', v_val, 40);
        espera_num('K2 el CPP no cambia', v_cpp, 10, 0.000001);
    exception
        when others then falla('K2 salida al CPP', sqlerrm);
    end;

    ---------------------------------------------------------------- K3
    begin
        pkg_inventario.prc_movimiento(
            p_id_empresa => 1, p_id_producto => v_prod, p_fecha => trunc(sysdate),
            p_tipo => 'AJUSTE_ENTRADA', p_cantidad => 10, p_costo_unit_bs => 20,
            p_tasa => 1, p_moneda => 'VES', p_doc_tipo => 'AJUSTE', p_id_doc => null,
            p_id_detalle => null, p_motivo => 'prueba K3', p_usuario => 'VERIF',
            p_id_movimiento => v_mov);
        select cantidad, valor_bs, costo_promedio_bs into v_cant, v_val, v_cpp
          from kardex_saldo where id_empresa = 1 and id_producto_servicio = v_prod;
        espera_num('K3 cantidad', v_cant, 14);
        espera_num('K3 valor', v_val, 240);
        espera_num('K3 CPP ponderado', v_cpp, 17.142857, 0.000001);
    exception
        when others then falla('K3 CPP ponderado', sqlerrm);
    end;

    ---------------------------------------------------------------- K4 (agota)
    begin
        pkg_inventario.prc_movimiento(
            p_id_empresa => 1, p_id_producto => v_prod, p_fecha => trunc(sysdate),
            p_tipo => 'AJUSTE_SALIDA', p_cantidad => 14, p_costo_unit_bs => null,
            p_tasa => 1, p_moneda => 'VES', p_doc_tipo => 'AJUSTE', p_id_doc => null,
            p_id_detalle => null, p_motivo => 'prueba K4', p_usuario => 'VERIF',
            p_id_movimiento => v_mov);
        select cantidad, valor_bs, costo_promedio_bs, valor_ref into v_cant, v_val, v_cpp, v_ref
          from kardex_saldo where id_empresa = 1 and id_producto_servicio = v_prod;
        espera_num('K4 cantidad en cero', v_cant, 0);
        espera_num('K4 valor exacto en cero', v_val, 0, 0);
        espera_num('K4 CPP en cero', v_cpp, 0, 0.000001);
        espera_num('K4 valor de referencia en cero', v_ref, 0, 0);
    exception
        when others then falla('K4 salida que agota', sqlerrm);
    end;

    ---------------------------------------------------------------- K5 (doble valoracion)
    begin
        pkg_inventario.prc_movimiento(
            p_id_empresa => 1, p_id_producto => v_prod, p_fecha => trunc(sysdate),
            p_tipo => 'AJUSTE_ENTRADA', p_cantidad => 1, p_costo_unit_bs => 916.6477,
            p_tasa => 916.6477, p_moneda => 'USD', p_doc_tipo => 'AJUSTE', p_id_doc => null,
            p_id_detalle => null, p_motivo => 'prueba K5', p_usuario => 'VERIF',
            p_id_movimiento => v_mov);

        select costo_total_bs, costo_total_ref, tasa_cambio
          into v_bs, v_ref, v_tasa
          from kardex_mov where id_movimiento = v_mov;
        espera_num('K5 bs del movimiento', v_bs, 916.65, 0.01);
        espera_num('K5 referencia = bs/tasa', v_ref, round(v_bs / v_tasa, 2), 0.01);
        if v_tasa <> 916.6477 then
            falla('K5 la tasa se congela', to_char(v_tasa));
        end if;
    exception
        when others then falla('K5 doble valoracion', sqlerrm);
    end;

    ---------------------------------------------------------------- K8 (servicio)
    begin
        pkg_inventario.prc_movimiento(
            p_id_empresa => 1, p_id_producto => v_prod2, p_fecha => trunc(sysdate),
            p_tipo => 'AJUSTE_ENTRADA', p_cantidad => 1, p_costo_unit_bs => 10,
            p_tasa => 1, p_moneda => 'VES', p_doc_tipo => 'AJUSTE', p_id_doc => null,
            p_id_detalle => null, p_motivo => 'prueba K8', p_usuario => 'VERIF',
            p_id_movimiento => v_mov);
        falla('K8 un servicio no lleva kardex', 'acepto el movimiento');
    exception
        when others then
            if sqlcode <> -20155 then
                falla('K8 un servicio no lleva kardex', 'error ' || sqlcode || ': ' || sqlerrm);
            end if;
    end;

    ---------------------------------------------------------------- K11 (duplicado)
    begin
        pkg_inventario.prc_movimiento(
            p_id_empresa => 1, p_id_producto => v_prod, p_fecha => trunc(sysdate),
            p_tipo => 'ENTRADA_COMPRA', p_cantidad => 1, p_costo_unit_bs => 10,
            p_tasa => 1, p_moneda => 'VES', p_doc_tipo => 'COMPRA', p_id_doc => 999999,
            p_id_detalle => 1, p_motivo => 'prueba K11', p_usuario => 'VERIF',
            p_id_movimiento => v_mov);

        begin
            pkg_inventario.prc_movimiento(
                p_id_empresa => 1, p_id_producto => v_prod, p_fecha => trunc(sysdate),
                p_tipo => 'ENTRADA_COMPRA', p_cantidad => 1, p_costo_unit_bs => 10,
                p_tasa => 1, p_moneda => 'VES', p_doc_tipo => 'COMPRA', p_id_doc => 999999,
                p_id_detalle => 1, p_motivo => 'prueba K11 bis', p_usuario => 'VERIF',
                p_id_movimiento => v_mov);
            falla('K11 el mismo documento no se mueve dos veces', 'acepto el duplicado');
        exception
            when others then
                if sqlcode <> -20152 then
                    falla('K11 el mismo documento no se mueve dos veces',
                          'error ' || sqlcode || ': ' || sqlerrm);
                end if;
        end;
    exception
        when others then falla('K11 duplicado', sqlerrm);
    end;


    ---------------------------------------------------------------- K12 (cruce por cero)
    -- Vender sin stock y luego comprar: al volver a cero el CPP NO puede quedar en 0.
    begin
        declare
            v_p3 number;
            v_m  number;
        begin
            crea_articulo('PRODUCTO', v_p3);
            -- salida de 5 sin existencia (saldo -5, CPP 0)
            pkg_inventario.prc_movimiento(1, v_p3, trunc(sysdate), 'AJUSTE_SALIDA', 5, null,
                                          1, 'VES', 'AJUSTE', null, null, 'venta sin stock', 'VERIF', v_m);
            -- compra de 5 a 10: cruza a cero
            pkg_inventario.prc_movimiento(1, v_p3, trunc(sysdate), 'AJUSTE_ENTRADA', 5, 10,
                                          1, 'VES', 'AJUSTE', null, null, 'reposicion', 'VERIF', v_m);
            select costo_promedio_bs into v_cpp
              from kardex_saldo where id_empresa = 1 and id_producto_servicio = v_p3;
            espera_num('K12 al cruzar a cero el CPP es el costo de la compra', v_cpp, 10, 0.000001);

            -- la siguiente salida ya no puede costar 0
            pkg_inventario.prc_movimiento(1, v_p3, trunc(sysdate), 'AJUSTE_SALIDA', 5, null,
                                          1, 'VES', 'AJUSTE', null, null, 'venta', 'VERIF', v_m);
            select costo_total_bs into v_bs
              from kardex_mov where id_movimiento = v_m;
            espera_num('K12 la salida posterior cuesta 50, no 0', v_bs, 50, 0.01);
        end;
    exception
        when others then falla('K12 cruce por cero', sqlerrm);
    end;

    ---------------------------------------------------------------- K13 (entrada sin costo)
    -- Un ajuste de entrada sin costo usa el CPP vigente, no 0.
    begin
        declare
            v_p4 number;
            v_m  number;
        begin
            crea_articulo('PRODUCTO', v_p4);
            pkg_inventario.prc_movimiento(1, v_p4, trunc(sysdate), 'AJUSTE_ENTRADA', 2, 7,
                                          1, 'VES', 'AJUSTE', null, null, 'base', 'VERIF', v_m);
            pkg_inventario.prc_movimiento(1, v_p4, trunc(sysdate), 'AJUSTE_ENTRADA', 2, null,
                                          1, 'VES', 'AJUSTE', null, null, 'sin costo', 'VERIF', v_m);
            select costo_promedio_bs into v_cpp
              from kardex_saldo where id_empresa = 1 and id_producto_servicio = v_p4;
            espera_num('K13 la entrada sin costo usa el CPP', v_cpp, 7, 0.000001);
        end;
    exception
        when others then falla('K13 entrada sin costo', sqlerrm);
    end;

    ------------------------------------------------------------------ resultado
    rollback to savepoint cpp;

    if v_fallas > 0 then
        raise_application_error(-20101, 'RESULTADO: FALLAS=' || v_fallas || v_lista);
    end if;
    raise_application_error(-20100, 'RESULTADO: FALLAS=0');
end;
/
