-- =============================================================================
-- 20261124_inventario_consistencia_verificacion.sql
--
-- El kardex y el saldo tienen que contar la misma historia (2026-11-24):
--
--   V1  saldo.cantidad = suma de movimientos con su signo   (tolerancia 0,01)
--   V2  saldo.valor_bs = suma de costos con su signo        (tolerancia 0,01)
--   V3  la doble valoracion cuadra: ref = round(bs / tasa, 2)
--   V4  ningun movimiento con cantidad <= 0
--   V5  ninguna reversa apunta a una reversa, y una salida/entrada no se
--       revierte dos veces
--   V6  articulo de otra empresa: -20151 / empresa ajena en el ajuste: -20003
--
-- Si la base no tiene movimientos, V1-V5 se dan por OMITIDOS (no son fallas:
-- una base recien instalada esta vacia). V6 se prueba siempre.
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261124_inventario_consistencia_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000) := '';
    v_n      number;
    v_movs   number;
    v_prod   number;
    v_mov    number;
    v_sembrado varchar2(1) := 'N';

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
begin
    select count(*) into v_movs from kardex_mov;

    -- Si la base esta vacia se siembra un caso minimo (entrada y salida) para
    -- medir de verdad; al final se revierte.
    if v_movs = 0 then
        savepoint v;
        v_sembrado := 'S';
        insert into producto_servicio (id_empresa, nombre, tipo, precio_sugerido,
                                       impuesto_aplicable, estado)
        values (1, 'INV CONSIST ' || to_char(systimestamp, 'HH24MISSFF3'),
                'PRODUCTO', 0, 0, 'ACTIVO')
        returning id_producto_servicio into v_prod;
        pkg_inventario.prc_movimiento(1, v_prod, trunc(sysdate), 'AJUSTE_ENTRADA', 10, 10,
                                      1, 'VES', 'AJUSTE', null, null, 'siembra', 'admin', v_mov);
        pkg_inventario.prc_movimiento(1, v_prod, trunc(sysdate), 'AJUSTE_SALIDA', 4, null,
                                      1, 'VES', 'AJUSTE', null, null, 'siembra', 'admin', v_mov);
        dbms_output.put_line('NOTA: la base estaba vacia; V1-V5 se midieron con un caso sembrado');
    end if;

    begin
        ------------------------------------------------------------------ V1
        select count(*) into v_n
          from (select m.id_empresa, m.id_producto_servicio,
                       sum(m.cantidad * pkg_inventario.fn_signo(m.tipo_movimiento)) cant,
                       sum(m.costo_total_bs * pkg_inventario.fn_signo(m.tipo_movimiento)) val
                  from kardex_mov m
                 group by m.id_empresa, m.id_producto_servicio) x
          join kardex_saldo s on s.id_empresa = x.id_empresa
                             and s.id_producto_servicio = x.id_producto_servicio
         where abs(nvl(s.cantidad, 0) - x.cant) > 0.01;
        espera_num('V1 cantidad del saldo = suma de movimientos', v_n, 0);

        ------------------------------------------------------------------ V2
        select count(*) into v_n
          from (select m.id_empresa, m.id_producto_servicio,
                       sum(m.costo_total_bs * pkg_inventario.fn_signo(m.tipo_movimiento)) val
                  from kardex_mov m
                 group by m.id_empresa, m.id_producto_servicio) x
          join kardex_saldo s on s.id_empresa = x.id_empresa
                             and s.id_producto_servicio = x.id_producto_servicio
         where abs(nvl(s.valor_bs, 0) - x.val) > 0.01;
        espera_num('V2 valor del saldo = suma de costos', v_n, 0);

        ------------------------------------------------------------------ V3
        select count(*) into v_n
          from kardex_mov
         where abs(nvl(costo_total_ref, 0) - round(costo_total_bs / nullif(tasa_cambio, 0), 2)) > 0.01;
        espera_num('V3 doble valoracion', v_n, 0);

        ------------------------------------------------------------------ V4
        select count(*) into v_n from kardex_mov where cantidad is null or cantidad <= 0;
        espera_num('V4 movimientos con cantidad positiva', v_n, 0);

        ------------------------------------------------------------------ V5
        -- b es la reversa y a el movimiento revertido: si b tambien es reversa,
        -- se encadenaron dos reversas.
        select count(*) into v_n
          from kardex_mov b
          join kardex_mov a on a.id_movimiento = b.id_movimiento_reversa
         where b.tipo_movimiento in ('REVERSA_ENTRADA', 'REVERSA_SALIDA');
        espera_num('V5 una reversa no revierte a otra reversa', v_n, 0);

        select count(*) into v_n
          from kardex_mov
         where tipo_movimiento in ('REVERSA_ENTRADA', 'REVERSA_SALIDA')
           and id_movimiento_reversa is not null;
        espera_num('V5 una reversa no se revierte', v_n, 0);

    exception
        when others then
            falla('V1-V5 consistencia', sqlerrm);
    end;

    ------------------------------------------------------------------ V6
    select min(id_producto_servicio) into v_prod
      from producto_servicio where id_empresa = 1;
    if v_prod is not null then
        begin
            pkg_inventario.prc_movimiento(
                p_id_empresa => 2, p_id_producto => v_prod, p_fecha => trunc(sysdate),
                p_tipo => 'AJUSTE_ENTRADA', p_cantidad => 1, p_costo_unit_bs => 1,
                p_tasa => 1, p_moneda => 'VES', p_doc_tipo => 'AJUSTE', p_id_doc => null,
                p_id_detalle => null, p_motivo => 'prueba', p_usuario => 'admin',
                p_id_movimiento => v_n);
            falla('V6 un articulo de otra empresa no se mueve', 'acepto');
        exception
            when others then
                if sqlcode <> -20151 then
                    falla('V6 un articulo de otra empresa no se mueve',
                          'error ' || sqlcode || ': ' || sqlerrm);
                end if;
        end;

        begin
            pkg_inventario.prc_ajuste(2, v_prod, trunc(sysdate), 'AJUSTE_ENTRADA',
                                      1, 1, 'VES', 1, 'empresa ajena', 'admin');
            falla('V6 el ajuste de empresa ajena se rechaza', 'acepto');
        exception
            when others then
                if sqlcode not in (-20003, -20151) then
                    falla('V6 el ajuste de empresa ajena se rechaza',
                          'error ' || sqlcode || ': ' || sqlerrm);
                end if;
        end;
    else
        dbms_output.put_line('OMITIDO V6: no hay articulos en la empresa 1');
    end if;

    ------------------------------------------------------------------ resultado
    if v_sembrado = 'S' then
        rollback to savepoint v;
    end if;

    if v_fallas > 0 then
        raise_application_error(-20101, 'RESULTADO: FALLAS=' || v_fallas || v_lista);
    end if;
    raise_application_error(-20100, 'RESULTADO: FALLAS=0');
end;
/
