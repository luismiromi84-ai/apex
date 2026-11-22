-- =============================================================================
-- 20261121_pagos_saldo_verificacion.sql
--
-- La formula unica del saldo de una compra (2026-11-21):
--
--   importe = total + IGTF_BS/tc - RETENCION_IVA_BS/tc - RETENCION_ISLR_BS/tc
--             + notas de debito - notas de credito
--   saldo   = importe - pagos aplicados (solo pagos ACTIVO)
--
--   P1   compra en bolivares con las dos retenciones: 1000 - 75 - 30 = 895
--   P2   compra en divisa: las cantidades en bolivares se dividen por la tasa de
--        la compra (100 - 10 - 4 = 86 con tc 900), no por la del dia
--   P2b  una NC registrada baja el saldo, una ND lo sube y una NC ANULADA no cuenta
--   P2c  el saldo NO cambia al mover la configuracion despues (ES_SPE): el IGTF
--        esta congelado en la compra
--   P18  fn_compra_pagable en los cinco estados y saldo 0 en una anulada
--
-- Las funciones se llaman con SQL dinamico a proposito: una referencia estatica a
-- una funcion que aun no existe rompe la compilacion del bloque y el verificador
-- no llega a imprimir su resultado (medido en el RED de la tarea 1).
--
-- Los ayudantes comparan VALOR contra ESPERADO y no booleanos: con `if not p_ok`
-- un NULL de PL/SQL no entra y el caso pasaria sin medir nada (paso en la primera
-- version de este archivo, y se vio porque el RED salio FALLAS=0).
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261121_pagos_saldo_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000) := '';
    v_emp    number;
    v_prov   number;
    v_fac    number;
    v_usd    number;
    v_nc     number;
    v_nd     number;
    v_nc_anu number;
    v_num    number;
    v_txt    varchar2(20);

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

    -- llamada a una funcion numerica por nombre: null si no existe
    function fnum(p_fn varchar2, p_id number) return number is
        v number;
    begin
        execute immediate 'select ' || p_fn || '(:1) from dual' into v using p_id;
        return v;
    exception
        when others then
            return null;
    end;

    function ftxt(p_fn varchar2, p_id number) return varchar2 is
        v varchar2(20);
    begin
        execute immediate 'select ' || p_fn || '(:1) from dual' into v using p_id;
        return v;
    exception
        when others then
            return null;
    end;

begin
    select min(id_empresa) into v_emp from empresas where cod_pais = 'VE';
    select min(id_proveedor) into v_prov from proveedores where id_empresa = v_emp;

    if v_prov is null then
        select min(id_proveedor) into v_prov from proveedores;
    end if;

    if v_emp is null or v_prov is null then
        raise_application_error(-20100, 'RESULTADO: FALLAS=0 OMITIDO sin empresa o proveedor');
    end if;

    savepoint sp_saldo;

    -- P1: compra en bolivares -------------------------------------------------
    insert into compras (id_empresa, id_proveedor, tipo_documento, folio_factura, fecha_emision,
                         cod_moneda, tipo_cambio, subtotal, monto_impuesto, monto_total,
                         estado, retencion_iva_bs, retencion_islr_bs, igtf_bs)
    values (v_emp, v_prov, 'FAC', 'VERIF-P1', date '2026-11-21',
            'VES', 1, 1000, 0, 1000, 'REGISTRADA', 75, 30, 0)
    returning id_compra into v_fac;

    espera_num('P1', fnum('fn_importe_compra', v_fac), 895, 'importe');
    espera_num('P1', fnum('fn_saldo_compra', v_fac), 895, 'saldo');

    -- P2: compra en divisa, las cantidades en bolivares se dividen por la tasa --
    insert into compras (id_empresa, id_proveedor, tipo_documento, folio_factura, fecha_emision,
                         cod_moneda, tipo_cambio, subtotal, monto_impuesto, monto_total,
                         estado, retencion_iva_bs, retencion_islr_bs, igtf_bs)
    values (v_emp, v_prov, 'FAC', 'VERIF-P2', date '2026-11-21',
            'USD', 900, 86.21, 13.79, 100, 'REGISTRADA', 9000, 3600, 0)
    returning id_compra into v_usd;

    espera_num('P2', fnum('fn_importe_compra', v_usd), 86, 'importe (100 - 10 - 4)');

    -- P2c: congelado. Se le pone IGTF 30 a la compra en bolivares y se apaga SPE.
    update compras set igtf_bs = 30 where id_compra = v_fac;
    espera_num('P2c', fnum('fn_importe_compra', v_fac), 925, 'importe con IGTF de 30');

    update empresas set es_spe = 'N' where id_empresa = v_emp;
    espera_num('P2c', fnum('fn_importe_compra', v_fac), 925, 'importe con ES_SPE apagado');
    update empresas set es_spe = 'S' where id_empresa = v_emp;

    -- P2b: notas ---------------------------------------------------------------
    insert into compras (id_empresa, id_proveedor, tipo_documento, folio_factura, fecha_emision,
                         cod_moneda, tipo_cambio, subtotal, monto_impuesto, monto_total,
                         estado, id_compra_origen)
    values (v_emp, v_prov, 'NC', 'VERIF-NC', date '2026-11-21', 'VES', 1, 100, 0, 100,
            'REGISTRADA', v_fac)
    returning id_compra into v_nc;

    espera_num('P2b', fnum('fn_importe_compra', v_fac), 825, 'importe con NC de 100');

    insert into compras (id_empresa, id_proveedor, tipo_documento, folio_factura, fecha_emision,
                         cod_moneda, tipo_cambio, subtotal, monto_impuesto, monto_total,
                         estado, id_compra_origen)
    values (v_emp, v_prov, 'ND', 'VERIF-ND', date '2026-11-21', 'VES', 1, 50, 0, 50,
            'REGISTRADA', v_fac)
    returning id_compra into v_nd;

    espera_num('P2b', fnum('fn_importe_compra', v_fac), 875, 'importe con ND de 50');

    insert into compras (id_empresa, id_proveedor, tipo_documento, folio_factura, fecha_emision,
                         cod_moneda, tipo_cambio, subtotal, monto_impuesto, monto_total,
                         estado, id_compra_origen)
    values (v_emp, v_prov, 'NC', 'VERIF-NC-ANU', date '2026-11-21', 'VES', 1, 999, 0, 999,
            'ANULADA', v_fac)
    returning id_compra into v_nc_anu;

    espera_num('P2b', fnum('fn_importe_compra', v_fac), 875, 'importe con una NC ANULADA de 999');

    -- P18: pagable en los cinco estados ---------------------------------------
    espera_txt('P18', ftxt('fn_compra_pagable', v_fac), 'S', 'pagable en REGISTRADA');

    update compras set estado = 'PARCIAL' where id_compra = v_fac;
    espera_txt('P18', ftxt('fn_compra_pagable', v_fac), 'S', 'pagable en PARCIAL');

    update compras set estado = 'PAGADA' where id_compra = v_fac;
    espera_txt('P18', ftxt('fn_compra_pagable', v_fac), 'N', 'pagable en PAGADA');

    update compras set estado = 'BORRADOR' where id_compra = v_fac;
    espera_txt('P18', ftxt('fn_compra_pagable', v_fac), 'N', 'pagable en BORRADOR');

    update compras set estado = 'ANULADA' where id_compra = v_fac;
    espera_txt('P18', ftxt('fn_compra_pagable', v_fac), 'N', 'pagable en ANULADA');
    espera_num('P18', fnum('fn_saldo_compra', v_fac), 0, 'saldo de una compra ANULADA');

    rollback to sp_saldo;

    raise_application_error(-20100,
        substrb('RESULTADO: FALLAS=' || v_fallas || v_lista, 1, 3000));
end;
/
