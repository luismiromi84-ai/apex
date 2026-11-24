-- =============================================================================
-- 20261124_inventario_ajuste_verificacion.sql
--
-- Ajustes manuales y carga inicial (2026-11-24):
--
--   A1  ajuste de entrada de 5 a 8,00 deja saldo 5 y valor 40
--   A2  ajuste de salida sin costo sale al CPP (8): quedan 3 y 24
--   A3  un ajuste sin motivo se rechaza (-20153)
--   A4  el SALDO_INICIAL es una sola vez: la segunda da -20154
--   A5  un ajuste de un articulo de otra empresa se rechaza (-20003)
--
-- Todo dentro de un savepoint: rollback al final.
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261124_inventario_ajuste_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000) := '';
    v_prod   number;
    v_otro   number;
    v_cant   number;
    v_val    number;
    v_cpp    number;

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

    procedure crea_articulo(p_emp number, p_nombre varchar2, p_id out number) is
    begin
        insert into producto_servicio (id_empresa, nombre, tipo, precio_sugerido,
                                       impuesto_aplicable, estado)
        values (p_emp, p_nombre || ' ' || to_char(systimestamp, 'HH24MISSFF3'),
                'PRODUCTO', 0, 0, 'ACTIVO')
        returning id_producto_servicio into p_id;
    end;
begin
    savepoint ajuste;
    crea_articulo(1, 'INV AJUSTE', v_prod);

    ---------------------------------------------------------------- A1
    begin
        pkg_inventario.prc_ajuste(1, v_prod, trunc(sysdate), 'AJUSTE_ENTRADA',
                                  5, 8, 'VES', 1, 'conteo fisico', 'admin');
        select cantidad, valor_bs into v_cant, v_val
          from kardex_saldo where id_empresa = 1 and id_producto_servicio = v_prod;
        espera_num('A1 cantidad', v_cant, 5);
        espera_num('A1 valor', v_val, 40);
    exception
        when others then falla('A1 ajuste de entrada', sqlerrm);
    end;

    ---------------------------------------------------------------- A2
    begin
        pkg_inventario.prc_ajuste(1, v_prod, trunc(sysdate), 'AJUSTE_SALIDA',
                                  2, null, 'VES', 1, 'merma', 'admin');
        select cantidad, valor_bs, costo_promedio_bs into v_cant, v_val, v_cpp
          from kardex_saldo where id_empresa = 1 and id_producto_servicio = v_prod;
        espera_num('A2 cantidad', v_cant, 3);
        espera_num('A2 valor', v_val, 24);
        espera_num('A2 el CPP sigue en 8', v_cpp, 8, 0.000001);
    exception
        when others then falla('A2 ajuste de salida', sqlerrm);
    end;

    ---------------------------------------------------------------- A3
    begin
        pkg_inventario.prc_ajuste(1, v_prod, trunc(sysdate), 'AJUSTE_ENTRADA',
                                  1, 8, 'VES', 1, null, 'admin');
        falla('A3 el motivo es obligatorio', 'acepto un ajuste sin motivo');
    exception
        when others then
            if sqlcode <> -20153 then
                falla('A3 el motivo es obligatorio', 'error ' || sqlcode || ': ' || sqlerrm);
            end if;
    end;

    ---------------------------------------------------------------- A4
    begin
        crea_articulo(1, 'INV INICIAL', v_otro);
        pkg_inventario.prc_ajuste(1, v_otro, trunc(sysdate), 'SALDO_INICIAL',
                                  7, 5, 'VES', 1, 'carga inicial', 'admin');
        begin
            pkg_inventario.prc_ajuste(1, v_otro, trunc(sysdate), 'SALDO_INICIAL',
                                      2, 5, 'VES', 1, 'otra vez', 'admin');
            falla('A4 el saldo inicial es una sola vez', 'acepto la segunda');
        exception
            when others then
                if sqlcode <> -20154 then
                    falla('A4 el saldo inicial es una sola vez', 'error ' || sqlcode || ': ' || sqlerrm);
                end if;
        end;
    exception
        when others then falla('A4 saldo inicial', sqlerrm);
    end;

    ---------------------------------------------------------------- A5
    begin
        pkg_inventario.prc_ajuste(2, v_prod, trunc(sysdate), 'AJUSTE_ENTRADA',
                                  1, 8, 'VES', 1, 'empresa ajena', 'admin');
        falla('A5 empresa ajena', 'acepto el ajuste en otra empresa');
    exception
        when others then
            if sqlcode <> -20003 then
                falla('A5 empresa ajena', 'error ' || sqlcode || ': ' || sqlerrm);
            end if;
    end;

    ------------------------------------------------------------------ resultado
    rollback to savepoint ajuste;

    if v_fallas > 0 then
        raise_application_error(-20101, 'RESULTADO: FALLAS=' || v_fallas || v_lista);
    end if;
    raise_application_error(-20100, 'RESULTADO: FALLAS=0');
end;
/
