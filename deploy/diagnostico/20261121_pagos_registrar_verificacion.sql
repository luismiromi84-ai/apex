-- =============================================================================
-- 20261121_pagos_registrar_verificacion.sql
--
-- PKG_PAGOS (2026-11-21): registrar, repartir, anular, conciliar y aplicar saldos
-- a favor. Cada caso arma sus compras y su pago dentro de un savepoint y se
-- revierte: no toca datos del cliente.
--
--   P3   pago por el saldo exacto -> PAGADA y saldo 0
--   P4   pago parcial -> PARCIAL y saldo = importe - pagado
--   P5   un pago aplica a tres compras -> las tres PAGADA
--   P6   pago mayor que la deuda -> no lanza; el sobrante es saldo a favor
--   P7   anticipo (sin aplicaciones) -> todo el monto a favor
--   P8   ese anticipo se aplica despues a una compra nueva -> PAGADA
--   P9   anular el pago devuelve las compras a pendiente y no borra filas
--   P10  aplicar mas que el saldo -> -20111
--   P11  compra de otro proveedor -> -20112
--   P12  pagar un BORRADOR o una ANULADA -> -20115
--   P13  lo aplicado supera el monto del pago -> -20117
--   P14  forma de pago que exige referencia y no llega -> -20114
--   P15  anular un pago conciliado -> -20116; desmarcar y anular -> funciona
--   P24  aplicar saldo a un pago conciliado -> -20116
--   P25  pago en divisa aplicado a una compra en bolivares: usa la tasa del pago
--   P26  una NC posterior al pago deja saldo negativo, estado PAGADA y no admite
--        mas aplicaciones
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261121_pagos_registrar_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000) := '';
    v_emp    number;
    v_prov   number;
    v_prov2  number;
    v_user   varchar2(100);
    v_forma  number;
    v_forma_ref number;
    v_folio  number := 0;
    v_id     number;
    v_num    number;
    v_txt    varchar2(20);
    v_favor0 number;

    procedure falla(p_caso varchar2, p_detalle varchar2) is
    begin
        v_fallas := v_fallas + 1;
        v_lista  := v_lista || ' | ' || p_caso || ': ' || p_detalle;
    end;

    procedure espera_num(p_caso varchar2, p_valor number, p_esperado number, p_que varchar2) is
    begin
        if p_valor is null or p_valor <> p_esperado then
            falla(p_caso, p_que || ' = ' || nvl(to_char(p_valor), 'NULL')
                        || ' (esperado ' || to_char(p_esperado) || ')');
        end if;
    end;

    procedure espera_txt(p_caso varchar2, p_valor varchar2, p_esperado varchar2, p_que varchar2) is
    begin
        if p_valor is null or p_valor <> p_esperado then
            falla(p_caso, p_que || ' = ' || nvl(p_valor, 'NULL')
                        || ' (esperado ' || p_esperado || ')');
        end if;
    end;

    -- crea una compra de prueba y devuelve su id
    procedure nueva_compra(p_total number, p_estado varchar2, p_moneda varchar2, p_tasa number,
                           p_riva number, p_rislr number, p_tipo varchar2, p_origen number,
                           p_id out number) is
    begin
        v_folio := v_folio + 1;
        insert into compras (id_empresa, id_proveedor, tipo_documento, folio_factura, fecha_emision,
                             cod_moneda, tipo_cambio, subtotal, monto_impuesto, monto_total,
                             estado, retencion_iva_bs, retencion_islr_bs, id_compra_origen)
        values (v_emp, v_prov, p_tipo, 'VERIF-PG-' || v_folio, date '2026-11-21', p_moneda,
                p_tasa, p_total, 0, p_total, p_estado, p_riva, p_rislr, p_origen)
        returning id_compra into p_id;
    end;

    procedure espera_estado(p_caso varchar2, p_id number, p_esperado varchar2) is
        v varchar2(20);
    begin
        select estado into v from compras where id_compra = p_id;
        espera_txt(p_caso, v, p_esperado, 'estado de la compra ' || p_id);
    end;

begin
    select min(id_empresa) into v_emp from empresas where cod_pais = 'VE';

    select min(u.username) into v_user
      from usuario u
      join usuario_empresa ue on ue.usuario_id = u.usuario_id
     where ue.id_empresa = v_emp;

    select min(p.id_proveedor) into v_prov from proveedores p where p.id_empresa = v_emp;
    select max(p.id_proveedor) into v_prov2 from proveedores p where p.id_empresa = v_emp;

    select min(id_forma_pago) into v_forma
      from forma_pago where nvl(requiere_ref, 'N') = 'N';
    select min(id_forma_pago) into v_forma_ref
      from forma_pago where nvl(requiere_ref, 'N') = 'Y';

    if v_emp is null or v_prov is null or v_user is null then
        raise_application_error(-20100, 'RESULTADO: FALLAS=0 OMITIDO sin empresa, proveedor o usuario');
    end if;

    -- El saldo a favor se mide por DIFERENCIA: si el cliente tiene pagos vivos con
    -- saldo a favor, el absoluto no es 0 y el caso fallaria sin que la app falle.
    v_favor0 := pkg_pagos.fn_saldo_favor_proveedor(v_prov, 'VES');

    savepoint sp_pagos;

    -- P3: pago por el saldo exacto -------------------------------------------
    nueva_compra(1000, 'REGISTRADA', 'VES', 1, 75, 30, 'FAC', null, v_id);
    pkg_pagos.prc_registrar_pago(
        p_id_proveedor => v_prov, p_fecha => date '2026-11-21', p_moneda => 'VES', p_tasa => 1,
        p_monto => 895, p_id_forma_pago => v_forma, p_referencia => null, p_observaciones => null,
        p_aplicaciones => '[{"id_compra":' || v_id || ',"monto":895}]',
        p_usuario => v_user, p_id_pago => v_num);
    espera_num('P3', fn_saldo_compra(v_id), 0, 'saldo');
    espera_estado('P3', v_id, 'PAGADA');

    -- P4: pago parcial ---------------------------------------------------------
    nueva_compra(500, 'REGISTRADA', 'VES', 1, 0, 0, 'FAC', null, v_id);
    pkg_pagos.prc_registrar_pago(
        p_id_proveedor => v_prov, p_fecha => date '2026-11-21', p_moneda => 'VES', p_tasa => 1,
        p_monto => 200, p_id_forma_pago => v_forma, p_aplicaciones => '[{"id_compra":' || v_id || ',"monto":200}]',
        p_usuario => v_user, p_id_pago => v_num);
    espera_num('P4', fn_saldo_compra(v_id), 300, 'saldo');
    espera_estado('P4', v_id, 'PARCIAL');

    -- P5: un pago a tres compras ----------------------------------------------
    declare
        v_a number; v_b number; v_c number;
    begin
        nueva_compra(100, 'REGISTRADA', 'VES', 1, 0, 0, 'FAC', null, v_a);
        nueva_compra(100, 'REGISTRADA', 'VES', 1, 0, 0, 'FAC', null, v_b);
        nueva_compra(100, 'REGISTRADA', 'VES', 1, 0, 0, 'FAC', null, v_c);
        pkg_pagos.prc_registrar_pago(
            p_id_proveedor => v_prov, p_fecha => date '2026-11-21', p_moneda => 'VES', p_tasa => 1,
            p_monto => 300, p_id_forma_pago => v_forma,
            p_aplicaciones => '[{"id_compra":' || v_a || ',"monto":100},'
                           || '{"id_compra":' || v_b || ',"monto":100},'
                           || '{"id_compra":' || v_c || ',"monto":100}]',
            p_usuario => v_user, p_id_pago => v_num);
        espera_estado('P5', v_a, 'PAGADA');
        espera_estado('P5', v_b, 'PAGADA');
        espera_estado('P5', v_c, 'PAGADA');
    end;

    -- P6: pago mayor que la deuda: el sobrante queda a favor -------------------
    nueva_compra(100, 'REGISTRADA', 'VES', 1, 0, 0, 'FAC', null, v_id);
    pkg_pagos.prc_registrar_pago(
        p_id_proveedor => v_prov, p_fecha => date '2026-11-21', p_moneda => 'VES', p_tasa => 1,
        p_monto => 150, p_id_forma_pago => v_forma, p_aplicaciones => '[{"id_compra":' || v_id || ',"monto":100}]',
        p_usuario => v_user, p_id_pago => v_num);
    espera_num('P6', fn_saldo_compra(v_id), 0, 'saldo');
    espera_estado('P6', v_id, 'PAGADA');
    espera_num('P6', pkg_pagos.fn_saldo_favor_proveedor(v_prov, 'VES') - v_favor0, 50, 'saldo a favor');

    -- P7 y P8: anticipo y su aplicacion despues -------------------------------
    declare
        v_ant number;
        v_nueva number;
    begin
        pkg_pagos.prc_registrar_pago(
            p_id_proveedor => v_prov, p_fecha => date '2026-11-21', p_moneda => 'VES', p_tasa => 1,
            p_monto => 200, p_id_forma_pago => v_forma, p_aplicaciones => null,
            p_usuario => v_user, p_id_pago => v_ant);
        espera_num('P7', pkg_pagos.fn_saldo_favor_proveedor(v_prov, 'VES') - v_favor0, 250, 'saldo a favor con el anticipo');

        nueva_compra(200, 'REGISTRADA', 'VES', 1, 0, 0, 'FAC', null, v_nueva);
        pkg_pagos.prc_aplicar_saldo(v_ant, v_nueva, 200, v_user);
        espera_estado('P8', v_nueva, 'PAGADA');
        espera_num('P8', pkg_pagos.fn_saldo_favor_proveedor(v_prov, 'VES') - v_favor0, 50, 'saldo a favor tras aplicar');
    end;

    -- P9: anular el pago -------------------------------------------------------
    nueva_compra(1000, 'REGISTRADA', 'VES', 1, 0, 0, 'FAC', null, v_id);
    pkg_pagos.prc_registrar_pago(
        p_id_proveedor => v_prov, p_fecha => date '2026-11-21', p_moneda => 'VES', p_tasa => 1,
        p_monto => 1000, p_id_forma_pago => v_forma, p_aplicaciones => '[{"id_compra":' || v_id || ',"monto":1000}]',
        p_usuario => v_user, p_id_pago => v_num);
    espera_estado('P9', v_id, 'PAGADA');
    pkg_pagos.prc_anular_pago(v_num, v_user);
    espera_estado('P9', v_id, 'REGISTRADA');
    espera_num('P9', fn_saldo_compra(v_id), 1000, 'saldo tras anular');
    declare
        v_est varchar2(20);
        v_cnt number;
    begin
        select estado into v_est from pagos where id_pago = v_num;
        espera_txt('P9', v_est, 'ANULADO', 'estado del pago');
        select count(*) into v_cnt from pagos_detalle where id_pago = v_num;
        espera_num('P9', v_cnt, 1, 'filas del detalle que se conservan');
    end;

    -- P10: aplicar mas que el saldo --------------------------------------------
    nueva_compra(100, 'REGISTRADA', 'VES', 1, 0, 0, 'FAC', null, v_id);
    begin
        pkg_pagos.prc_registrar_pago(
            p_id_proveedor => v_prov, p_fecha => date '2026-11-21', p_moneda => 'VES', p_tasa => 1,
            p_monto => 999, p_id_forma_pago => v_forma,
            p_aplicaciones => '[{"id_compra":' || v_id || ',"monto":999}]',
            p_usuario => v_user, p_id_pago => v_num);
        falla('P10', 'no lanzo error al aplicar 999 sobre un saldo de 100');
    exception
        when others then
            if sqlcode <> -20111 then
                falla('P10', 'codigo ' || sqlcode || ' en vez de -20111: ' || substr(sqlerrm, 1, 70));
            end if;
    end;

    -- P11: compra de otro proveedor -------------------------------------------
    if v_prov2 is not null and v_prov2 <> v_prov then
        declare
            v_otra number;
        begin
            v_folio := v_folio + 1;
            insert into compras (id_empresa, id_proveedor, tipo_documento, folio_factura,
                                 fecha_emision, cod_moneda, tipo_cambio, subtotal, monto_impuesto,
                                 monto_total, estado)
            values (v_emp, v_prov2, 'FAC', 'VERIF-PG-OTRO-' || v_folio, date '2026-11-21', 'VES', 1,
                    100, 0, 100, 'REGISTRADA')
            returning id_compra into v_otra;

            begin
                pkg_pagos.prc_registrar_pago(
                    p_id_proveedor => v_prov, p_fecha => date '2026-11-21', p_moneda => 'VES',
                    p_tasa => 1, p_monto => 100, p_id_forma_pago => v_forma,
                    p_aplicaciones => '[{"id_compra":' || v_otra || ',"monto":100}]',
                    p_usuario => v_user, p_id_pago => v_num);
                falla('P11', 'acepto una compra de otro proveedor');
            exception
                when others then
                    if sqlcode <> -20112 then
                        falla('P11', 'codigo ' || sqlcode || ' en vez de -20112');
                    end if;
            end;
        end;
    end if;

    -- P12: pagar un BORRADOR y una ANULADA -------------------------------------
    nueva_compra(100, 'BORRADOR', 'VES', 1, 0, 0, 'FAC', null, v_id);
    begin
        pkg_pagos.prc_registrar_pago(
            p_id_proveedor => v_prov, p_fecha => date '2026-11-21', p_moneda => 'VES', p_tasa => 1,
            p_monto => 100, p_id_forma_pago => v_forma,
            p_aplicaciones => '[{"id_compra":' || v_id || ',"monto":100}]',
            p_usuario => v_user, p_id_pago => v_num);
        falla('P12', 'acepto pagar un BORRADOR');
    exception
        when others then
            if sqlcode <> -20115 then
                falla('P12', 'codigo ' || sqlcode || ' en vez de -20115 (BORRADOR)');
            end if;
    end;

    nueva_compra(100, 'ANULADA', 'VES', 1, 0, 0, 'FAC', null, v_id);
    begin
        pkg_pagos.prc_registrar_pago(
            p_id_proveedor => v_prov, p_fecha => date '2026-11-21', p_moneda => 'VES', p_tasa => 1,
            p_monto => 100, p_id_forma_pago => v_forma,
            p_aplicaciones => '[{"id_compra":' || v_id || ',"monto":100}]',
            p_usuario => v_user, p_id_pago => v_num);
        falla('P12', 'acepto pagar una compra ANULADA');
    exception
        when others then
            if sqlcode <> -20115 then
                falla('P12', 'codigo ' || sqlcode || ' en vez de -20115 (ANULADA)');
            end if;
    end;

    -- P13: lo aplicado supera el monto del pago --------------------------------
    declare
        v_a number; v_b number;
    begin
        nueva_compra(100, 'REGISTRADA', 'VES', 1, 0, 0, 'FAC', null, v_a);
        nueva_compra(100, 'REGISTRADA', 'VES', 1, 0, 0, 'FAC', null, v_b);
        begin
            pkg_pagos.prc_registrar_pago(
                p_id_proveedor => v_prov, p_fecha => date '2026-11-21', p_moneda => 'VES', p_tasa => 1,
                p_monto => 100, p_id_forma_pago => v_forma,
                p_aplicaciones => '[{"id_compra":' || v_a || ',"monto":100},'
                               || '{"id_compra":' || v_b || ',"monto":100}]',
                p_usuario => v_user, p_id_pago => v_num);
            falla('P13', 'acepto aplicar 200 con un pago de 100');
        exception
            when others then
                if sqlcode <> -20117 then
                    falla('P13', 'codigo ' || sqlcode || ' en vez de -20117');
                end if;
        end;
    end;

    -- P14: falta la referencia bancaria ----------------------------------------
    if v_forma_ref is not null then
        nueva_compra(100, 'REGISTRADA', 'VES', 1, 0, 0, 'FAC', null, v_id);
        begin
            pkg_pagos.prc_registrar_pago(
                p_id_proveedor => v_prov, p_fecha => date '2026-11-21', p_moneda => 'VES', p_tasa => 1,
                p_monto => 100, p_id_forma_pago => v_forma_ref, p_referencia => null,
                p_aplicaciones => null, p_usuario => v_user, p_id_pago => v_num);
            falla('P14', 'acepto un pago sin la referencia que exige la forma de pago');
        exception
            when others then
                if sqlcode <> -20114 then
                    falla('P14', 'codigo ' || sqlcode || ' en vez de -20114');
                end if;
        end;
    end if;

    -- P15 y P24: conciliado -----------------------------------------------------
    nueva_compra(100, 'REGISTRADA', 'VES', 1, 0, 0, 'FAC', null, v_id);
    pkg_pagos.prc_registrar_pago(
        p_id_proveedor => v_prov, p_fecha => date '2026-11-21', p_moneda => 'VES', p_tasa => 1,
        p_monto => 50, p_id_forma_pago => v_forma, p_aplicaciones => null,
        p_usuario => v_user, p_id_pago => v_num);
    pkg_pagos.prc_conciliar(v_num, 'S', v_user);

    begin
        pkg_pagos.prc_anular_pago(v_num, v_user);
        falla('P15', 'anulo un pago conciliado');
    exception
        when others then
            if sqlcode <> -20116 then
                falla('P15', 'codigo ' || sqlcode || ' en vez de -20116');
            end if;
    end;

    begin
        pkg_pagos.prc_aplicar_saldo(v_num, v_id, 10, v_user);
        falla('P24', 'aplico saldo de un pago conciliado');
    exception
        when others then
            if sqlcode <> -20116 then
                falla('P24', 'codigo ' || sqlcode || ' en vez de -20116');
            end if;
    end;

    pkg_pagos.prc_conciliar(v_num, 'N', v_user);
    pkg_pagos.prc_anular_pago(v_num, v_user);
    declare
        v_est varchar2(20);
    begin
        select estado into v_est from pagos where id_pago = v_num;
        espera_txt('P15', v_est, 'ANULADO', 'estado tras desmarcar y anular');
    end;

    -- P25: pago en divisa contra una compra en bolivares -----------------------
    nueva_compra(100000, 'REGISTRADA', 'VES', 1, 0, 0, 'FAC', null, v_id);
    pkg_pagos.prc_registrar_pago(
        p_id_proveedor => v_prov, p_fecha => date '2026-11-21', p_moneda => 'USD', p_tasa => 900,
        p_monto => 100, p_id_forma_pago => v_forma,
        p_aplicaciones => '[{"id_compra":' || v_id || ',"monto":90000}]',
        p_usuario => v_user, p_id_pago => v_num);
    espera_num('P25', fn_saldo_compra(v_id), 10000, 'saldo con 100 USD a tasa 900');
    declare
        v_bs number;
    begin
        select monto_bs into v_bs from pagos where id_pago = v_num;
        espera_num('P25', v_bs, 90000, 'monto en bolivares del pago');
    end;

    -- P26: la NC que llega despues de pagar ------------------------------------
    nueva_compra(100, 'REGISTRADA', 'VES', 1, 0, 0, 'FAC', null, v_id);
    pkg_pagos.prc_registrar_pago(
        p_id_proveedor => v_prov, p_fecha => date '2026-11-21', p_moneda => 'VES', p_tasa => 1,
        p_monto => 100, p_id_forma_pago => v_forma, p_aplicaciones => '[{"id_compra":' || v_id || ',"monto":100}]',
        p_usuario => v_user, p_id_pago => v_num);
    declare
        v_nc number;
    begin
        nueva_compra(30, 'REGISTRADA', 'VES', 1, 0, 0, 'NC', v_id, v_nc);
        espera_num('P26', fn_saldo_compra(v_id), -30, 'saldo con NC posterior al pago');
        espera_estado('P26', v_id, 'PAGADA');
        begin
            pkg_pagos.prc_registrar_pago(
                p_id_proveedor => v_prov, p_fecha => date '2026-11-21', p_moneda => 'VES',
                p_tasa => 1, p_monto => 10, p_id_forma_pago => v_forma,
                p_aplicaciones => '[{"id_compra":' || v_id || ',"monto":10}]',
                p_usuario => v_user, p_id_pago => v_num);
            falla('P26', 'acepto aplicar a una compra con saldo negativo');
        exception
            when others then
                if sqlcode <> -20115 then
                    falla('P26', 'codigo ' || sqlcode || ' en vez de -20115: ' || substr(sqlerrm, 1, 60));
                end if;
        end;
    end;

    -- P27: MISMA MONEDA, UNO A UNO. Un pago de 500 USD aplicado a una factura en USD
    -- con otra tasa descontaba 501,16 (el usuario teclea 500 y ve otra cifra).
    declare
        v_usd number;
        v_pg  number;
    begin
        nueva_compra(100, 'REGISTRADA', 'USD', 900, 0, 0, 'FAC', null, v_usd);
        pkg_pagos.prc_registrar_pago(
            p_id_proveedor => v_prov, p_fecha => date '2026-11-21', p_moneda => 'USD',
            p_tasa => 950, p_monto => 100, p_id_forma_pago => null,
            p_aplicaciones => '[{"id_compra":' || v_usd || ',"monto":100}]',
            p_usuario => v_user, p_id_pago => v_pg);
        espera_num('P27', fn_saldo_compra(v_usd), 0, 'saldo con la misma moneda');
        declare
            v_apl number;
        begin
            select d.monto_aplicado into v_apl
              from pagos_detalle d where d.id_pago = v_pg;
            espera_num('P27', v_apl, 100, 'lo aplicado es lo tecleado, no la conversion');
        end;
    end;

    -- P28: usar el saldo a favor desde la pantalla. Un anticipo cubre una compra nueva
    -- sin que salga dinero otra vez; sin esto el saldo a favor queda muerto.
    declare
        v_ant  number;
        v_comp number;
        v_apl  number;
    begin
        pkg_pagos.prc_registrar_pago(
            p_id_proveedor => v_prov, p_fecha => date '2026-11-21', p_moneda => 'VES',
            p_tasa => 1, p_monto => 400, p_id_forma_pago => null,
            p_aplicaciones => null, p_usuario => v_user, p_id_pago => v_ant);

        nueva_compra(400, 'REGISTRADA', 'VES', 1, 0, 0, 'FAC', null, v_comp);

        pkg_pagos.prc_usar_favor(v_prov, v_comp, v_user, v_apl);
        espera_num('P28', v_apl, 400, 'aplicado con saldo a favor');
        espera_num('P28', fn_saldo_compra(v_comp), 0, 'saldo de la compra cubierta');
        espera_estado('P28', v_comp, 'PAGADA');

    end;

    rollback to sp_pagos;

    raise_application_error(-20100,
        substrb('RESULTADO: FALLAS=' || v_fallas || v_lista, 1, 3000));
end;
/
