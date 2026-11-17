-- =============================================================================
-- 20261117_cobros_registrar_verificacion.sql
--
-- Registrar un cobro (2026-11-17). Paquete PKG_COBROS.
--
--   R1  cobro completo en Bs de una factura en Bs: IGTF 0, neto = monto, factura PAGADA
--   R2  abono parcial: factura PARCIAL y saldo correcto
--   R3  cobro en divisas de empresa SPE: IGTF = alicuota x monto, y su equivalente en Bs
--   R4  empresa no SPE: IGTF 0 aunque la moneda sea extranjera
--   R5  sobrepago -> -20094
--   R6  monto 0 o negativo -> -20092
--   R7  moneda extranjera con tasa 1 -> -20093
--   R8  factura PAGADA -> -20090
--   R9  factura ANULADA -> -20090
--   R10 factura de otra empresa -> -20003
--   R11 retencion sin comprobante -> -20081
--   R12 la retencion tecleada manda (no se recalcula al 75 %)
--   R13 factura en USD cobrada en Bs: el equivalente usa la tasa del cobro
--   R14 el resumen de retencion y comprobante queda en la cabecera
--
-- Todo el DML va dentro de un SAVEPOINT y se revierte.
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261117_cobros_registrar_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

begin
    begin execute immediate 'drop table tmp_cobreg_fallas purge'; exception when others then null; end;
end;
/

create table tmp_cobreg_fallas (caso varchar2(300))
/

declare
    type t_lista is table of varchar2(300);
    v_fallas t_lista := t_lista();
    v_msg    varchar2(300);
    v_cli    number;
    v_fac    number;
    v_rec    number;
    v_n      number;
    v_estado varchar2(20);
    v_usr    varchar2(100);
    v_igtf_bs number;
    v_bs      number;
    v_neto    number;
    v_tasa_hoy number;
    v_paso   varchar2(20) := 'inicio';

    procedure falla(p_texto varchar2) is
    begin
        v_fallas.extend;
        v_fallas(v_fallas.last) := substrb(p_texto, 1, 300);
    end;

    function nueva_factura(p_total number, p_moneda varchar2, p_tasa number,
                           p_estado varchar2 default 'TIMBRADA') return number is
        v_id number;
    begin
        insert into facturas (id_empresa, id_cliente, tipo_documento, folio_factura,
                              cod_moneda, tipo_cambio, fecha_emision, subtotal,
                              monto_impuesto, monto_total, estado, creado_por)
        values (1, v_cli, 'FAC',
                'REG-ZZ-' || to_char(sysdate, 'HH24MISS') || '-' || lpad(round(dbms_random.value(1, 99999)), 5, '0'),
                p_moneda, p_tasa, sysdate - 1, p_total, 0, p_total, p_estado, 'test')
        returning id_factura into v_id;
        return v_id;
    end;

    procedure exige_error(p_codigo number, p_que varchar2, p_bloque varchar2) is
    begin
        begin
            execute immediate p_bloque;
            falla(p_que || ': no dio error');
        exception
            when others then
                if sqlcode <> p_codigo then
                    falla(p_que || ': codigo ' || sqlcode || ' en vez de ' || p_codigo
                          || ' (' || substrb(sqlerrm, 1, 90) || ')');
                end if;
        end;
    end;
begin
    savepoint sp_cobreg;

    -- Empresa 1 es SPE y su cliente es el primero de la empresa; el usuario de
    -- prueba tiene que existir y estar ACTIVO para la guarda de empresa.
    select min(id_cliente) into v_cli from clientes where id_empresa = 1;
    v_usr := 'ADMIN';
    update empresas set es_spe = 'S' where id_empresa = 1;

    v_paso := 'R1';
    -- R1: cobro completo en Bs, factura en Bs
    v_fac := nueva_factura(116, 'VES', 1);
    pkg_cobros.prc_registrar_cobro(
        p_id_factura => v_fac,
        p_fecha      => sysdate,
        p_id_forma_pago => null,
        p_cod_moneda => 'VES',
        p_monto      => 116,
        p_usuario    => v_usr,
        p_id_recibo  => v_rec);
    select estado into v_estado from facturas where id_factura = v_fac;
    select igtf_monto, monto_neto into v_n, v_msg from recibos where id_recibo = v_rec;
    if v_estado <> 'PAGADA' then falla('R1: la factura quedo ' || v_estado); end if;
    if v_n <> 0 then falla('R1: IGTF ' || v_n || ' en un cobro en bolivares'); end if;

    v_paso := 'R2';
    -- R2: abono parcial
    v_fac := nueva_factura(100, 'VES', 1);
    pkg_cobros.prc_registrar_cobro(
        p_id_factura => v_fac, p_fecha => sysdate, p_id_forma_pago => null,
        p_cod_moneda => 'VES', p_monto => 40, p_usuario => v_usr, p_id_recibo => v_rec);
    select estado into v_estado from facturas where id_factura = v_fac;
    if v_estado <> 'PARCIAL' then falla('R2: la factura quedo ' || v_estado || ' en vez de PARCIAL'); end if;
    if fn_saldo_factura(v_fac) <> 60 then
        falla('R2: saldo ' || fn_saldo_factura(v_fac) || ' en vez de 60');
    end if;

    v_paso := 'R3';
    -- R3: cobro en divisas, empresa SPE
    v_fac := nueva_factura(200000, 'VES', 1);
    pkg_cobros.prc_registrar_cobro(
        p_id_factura => v_fac, p_fecha => sysdate, p_id_forma_pago => null,
        p_cod_moneda => 'USD', p_monto => 100, p_usuario => v_usr, p_id_recibo => v_rec);
    select igtf_monto, igtf_bs, monto_bs, monto_neto, aplica_igtf
      into v_n, v_igtf_bs, v_bs, v_neto, v_estado
      from recibos where id_recibo = v_rec;
    if v_n <> 3 then falla('R3: IGTF en divisa ' || v_n || ' en vez de 3'); end if;
    if v_igtf_bs <= 0 then falla('R3: el IGTF en bolivares quedo ' || v_igtf_bs); end if;
    if v_estado <> 'S' then falla('R3: el recibo no quedo marcado con IGTF (' || v_estado || ')'); end if;
    if abs(v_neto - (100 - 0 + 3)) > 0.01 then
        falla('R3: el neto es ' || v_neto || ' y debia ser 103 (monto + IGTF)');
    end if;

    v_paso := 'R4';
    -- R4: empresa no SPE
    update empresas set es_spe = 'N' where id_empresa = 1;
    v_fac := nueva_factura(200000, 'VES', 1);
    pkg_cobros.prc_registrar_cobro(
        p_id_factura => v_fac, p_fecha => sysdate, p_id_forma_pago => null,
        p_cod_moneda => 'USD', p_monto => 100, p_usuario => v_usr, p_id_recibo => v_rec);
    select igtf_monto into v_n from recibos where id_recibo = v_rec;
    if v_n <> 0 then falla('R4: empresa no SPE cobro IGTF ' || v_n); end if;
    update empresas set es_spe = 'S' where id_empresa = 1;

    v_paso := 'R5';
    -- R5: sobrepago
    v_fac := nueva_factura(100, 'VES', 1);
    exige_error(-20094, 'R5',
        'declare v_r number; begin pkg_cobros.prc_registrar_cobro(p_id_factura => ' || v_fac
        || ', p_fecha => sysdate, p_id_forma_pago => null, p_cod_moneda => ''VES'', p_monto => 150,'
        || ' p_usuario => ''ADMIN'', p_id_recibo => v_r); end;');

    v_paso := 'R6';
    -- R6: monto invalido
    exige_error(-20092, 'R6',
        'declare v_r number; begin pkg_cobros.prc_registrar_cobro(p_id_factura => ' || v_fac
        || ', p_fecha => sysdate, p_id_forma_pago => null, p_cod_moneda => ''VES'', p_monto => 0,'
        || ' p_usuario => ''ADMIN'', p_id_recibo => v_r); end;');

    v_paso := 'R7';
    -- R7: moneda extranjera con tasa 1
    exige_error(-20093, 'R7',
        'declare v_r number; begin pkg_cobros.prc_registrar_cobro(p_id_factura => ' || v_fac
        || ', p_fecha => sysdate, p_id_forma_pago => null, p_cod_moneda => ''USD'', p_monto => 10,'
        || ' p_tasa => 1, p_usuario => ''ADMIN'', p_id_recibo => v_r); end;');

    v_paso := 'R8';
    -- R8 / R9: factura ya pagada o anulada
    v_fac := nueva_factura(100, 'VES', 1, 'PAGADA');
    exige_error(-20090, 'R8',
        'declare v_r number; begin pkg_cobros.prc_registrar_cobro(p_id_factura => ' || v_fac
        || ', p_fecha => sysdate, p_id_forma_pago => null, p_cod_moneda => ''VES'', p_monto => 10,'
        || ' p_usuario => ''ADMIN'', p_id_recibo => v_r); end;');
    v_fac := nueva_factura(100, 'VES', 1, 'ANULADA');
    exige_error(-20090, 'R9',
        'declare v_r number; begin pkg_cobros.prc_registrar_cobro(p_id_factura => ' || v_fac
        || ', p_fecha => sysdate, p_id_forma_pago => null, p_cod_moneda => ''VES'', p_monto => 10,'
        || ' p_usuario => ''ADMIN'', p_id_recibo => v_r); end;');

    v_paso := 'R10';
    -- R10: factura de otra empresa (empresa 2, usuario de la 1)
    v_fac := nueva_factura(100, 'VES', 1);
    update facturas set id_empresa = 2 where id_factura = v_fac;
    exige_error(-20003, 'R10',
        'declare v_r number; begin pkg_cobros.prc_registrar_cobro(p_id_factura => ' || v_fac
        || ', p_fecha => sysdate, p_id_forma_pago => null, p_cod_moneda => ''VES'', p_monto => 10,'
        || ' p_usuario => ''ADMIN'', p_id_recibo => v_r); end;');
    update facturas set id_empresa = 1 where id_factura = v_fac;

    v_paso := 'R11';
    -- R11: retencion sin comprobante. La factura necesita su IVA en el detalle:
    -- la retencion no puede pasar del IVA de la factura (R17).
    v_fac := nueva_factura(116, 'VES', 1);
    insert into facturas_det (id_factura, num_linea, descripcion, cantidad, precio_unitario,
                              id_impuesto, porcentaje_impuesto, monto_impuesto,
                              subtotal_linea, monto_total_linea, tasa_cambio_aplicada,
                              subtotal_bs, total_bs)
    values (v_fac, 1, 'Servicio', 1, 100,
            (select id_impuesto from impuestos
              where cod_pais = 'VE' and cod_impuesto = 'IVA_GEN' and rownum = 1),
            16, 16, 100, 116, 1, 100, 116);
    exige_error(-20081, 'R11',
        'declare v_r number; begin pkg_cobros.prc_registrar_cobro(p_id_factura => ' || v_fac
        || ', p_fecha => sysdate, p_id_forma_pago => null, p_cod_moneda => ''VES'', p_monto => 116,'
        || ' p_retencion_iva_bs => 12, p_usuario => ''ADMIN'', p_id_recibo => v_r); end;');

    v_paso := 'R12';
    -- R12/R14: la retencion tecleada manda y queda el resumen en la cabecera
    pkg_cobros.prc_registrar_cobro(
        p_id_factura => v_fac, p_fecha => sysdate, p_id_forma_pago => null,
        p_cod_moneda => 'VES', p_monto => 116, p_retencion_iva_bs => 12,
        p_nro_comprobante => '20261100000077', p_usuario => v_usr, p_id_recibo => v_rec);
    select retencion_iva_bs, nro_comprobante_retencion into v_n, v_estado
      from facturas where id_factura = v_fac;
    if v_n <> 12 then falla('R12: la cabecera tiene retencion ' || v_n || ' en vez de 12'); end if;
    if v_estado <> '20261100000077' then
        falla('R14: el comprobante en la cabecera quedo ' || v_estado);
    end if;
    select retencion_iva_bs into v_n from recibos where id_recibo = v_rec;
    if v_n <> 12 then falla('R12: el recibo guardo retencion ' || v_n || ' en vez de 12'); end if;

    v_paso := 'R13';
    -- R13: factura en USD cobrada en Bs: el equivalente usa la tasa del dia del
    -- cobro (no la de emision), asi que se paga lo que valen hoy los 100 USD.
    v_fac := nueva_factura(100, 'USD', 500);
    select max(tasa_cambio) keep (dense_rank last order by fecha_vigencia)
      into v_tasa_hoy
      from tipo_cambio
     where moneda_origen = 'USD' and moneda_destino = 'VES' and tipo_tasa = 'REAL'
       and fecha_vigencia < trunc(sysdate) + 1;
    pkg_cobros.prc_registrar_cobro(
        p_id_factura => v_fac, p_fecha => sysdate, p_id_forma_pago => null,
        p_cod_moneda => 'VES', p_monto => round(100 * v_tasa_hoy, 2),
        p_usuario => v_usr, p_id_recibo => v_rec);
    select monto_factura into v_n from recibos where id_recibo = v_rec;
    if abs(v_n - 100) > 1 then
        falla('R13: el equivalente en la moneda de la factura es ' || v_n || ' y se esperaba ~100');
    end if;
    select estado into v_estado from facturas where id_factura = v_fac;
    if v_estado <> 'PAGADA' then falla('R13: la factura quedo ' || v_estado); end if;

    v_paso := 'R15';
    -- R15: un cobro anterior a la factura se rechaza (la factura es de ayer).
    v_fac := nueva_factura(100, 'VES', 1);
    exige_error(-20092, 'R15',
        'declare v_r number; begin pkg_cobros.prc_registrar_cobro(p_id_factura => ' || v_fac
        || ', p_fecha => sysdate - 10, p_id_forma_pago => null, p_cod_moneda => ''VES'', p_monto => 10,'
        || ' p_usuario => ''ADMIN'', p_id_recibo => v_r); end;');

    v_paso := 'R16';
    -- R16: cobro en USD con retencion en bolivares: el neto pasa la retencion a la
    -- moneda del cobro (antes restaba bolivares de dolares).
    v_fac := nueva_factura(200000, 'VES', 1);
    declare
        v_fac_usd number;
        v_tasa    number;
    begin
        select max(tasa_cambio) keep (dense_rank last order by fecha_vigencia) into v_tasa
          from tipo_cambio
         where moneda_origen = 'USD' and moneda_destino = 'VES' and tipo_tasa = 'REAL'
           and fecha_vigencia < trunc(sysdate) + 1;
        insert into facturas (id_empresa, id_cliente, tipo_documento, folio_factura,
                              cod_moneda, tipo_cambio, fecha_emision, subtotal,
                              monto_impuesto, monto_total, estado, creado_por)
        values (1, v_cli, 'FAC', 'REG-USD-' || to_char(sysdate, 'HH24MISS'),
                'USD', v_tasa, sysdate - 1, 100, 16, 116, 'TIMBRADA', 'test')
        returning id_factura into v_fac_usd;
        insert into facturas_det (id_factura, num_linea, descripcion, cantidad, precio_unitario,
                                  id_impuesto, porcentaje_impuesto, monto_impuesto,
                                  subtotal_linea, monto_total_linea, tasa_cambio_aplicada,
                                  subtotal_bs, total_bs)
        values (v_fac_usd, 1, 'Servicio', 1, 100,
                (select id_impuesto from impuestos
                  where cod_pais = 'VE' and cod_impuesto = 'IVA_GEN' and rownum = 1),
                16, 16, 100, 116, v_tasa, round(100 * v_tasa, 2), round(116 * v_tasa, 2));
        -- IVA de 16 USD = 16 x tasa bolivares; se retiene 10 Bs
        pkg_cobros.prc_registrar_cobro(
            p_id_factura => v_fac_usd, p_fecha => sysdate, p_id_forma_pago => null,
            p_cod_moneda => 'USD', p_monto => 116, p_retencion_iva_bs => 10,
            p_nro_comprobante => '20261100000099', p_usuario => v_usr, p_id_recibo => v_rec);
        select monto_neto into v_n from recibos where id_recibo = v_rec;
        -- 116 - 10 Bs pasados a USD + el 3 % de IGTF (empresa SPE y cobro en divisas)
        if abs(v_n - (116 - round(10 / v_tasa, 2) + round(116 * 3 / 100, 2))) > 0.02 then
            falla('R16: el neto es ' || v_n || ' y debia ser 116 - 10 Bs pasados a USD + IGTF');
        end if;
    end;

    v_paso := 'R17';
    -- R17: una retencion mayor que el IVA de la factura se rechaza.
    v_fac := nueva_factura(116, 'VES', 1);
    exige_error(-20092, 'R17',
        'declare v_r number; begin pkg_cobros.prc_registrar_cobro(p_id_factura => ' || v_fac
        || ', p_fecha => sysdate, p_id_forma_pago => null, p_cod_moneda => ''VES'', p_monto => 116,'
        || ' p_retencion_iva_bs => 999, p_nro_comprobante => ''20261100000011'','
        || ' p_usuario => ''ADMIN'', p_id_recibo => v_r); end;');

    v_paso := 'R18';
    -- R18: la retencion sugerida no depende de la moneda del cobro: prorratea en
    -- la moneda de la factura.
    declare
        v_fac_usd number;
        v_tasa    number;
        v_usd     number;
        v_bs      number;
    begin
        select max(tasa_cambio) keep (dense_rank last order by fecha_vigencia) into v_tasa
          from tipo_cambio
         where moneda_origen = 'USD' and moneda_destino = 'VES' and tipo_tasa = 'REAL'
           and fecha_vigencia < trunc(sysdate) + 1;
        insert into facturas (id_empresa, id_cliente, tipo_documento, folio_factura,
                              cod_moneda, tipo_cambio, fecha_emision, subtotal,
                              monto_impuesto, monto_total, estado, creado_por,
                              porcentaje_retencion, retencion_iva_bs)
        values (1, v_cli, 'FAC', 'REG-SUG-' || to_char(sysdate, 'HH24MISS'),
                'USD', v_tasa, sysdate - 1, 100, 16, 116, 'TIMBRADA', 'test', 75, 0)
        returning id_factura into v_fac_usd;
        insert into facturas_det (id_factura, num_linea, descripcion, cantidad, precio_unitario,
                                  id_impuesto, porcentaje_impuesto, monto_impuesto,
                                  subtotal_linea, monto_total_linea, tasa_cambio_aplicada,
                                  subtotal_bs, total_bs)
        values (v_fac_usd, 1, 'Servicio', 1, 100,
                (select id_impuesto from impuestos
                  where cod_pais = 'VE' and cod_impuesto = 'IVA_GEN' and rownum = 1),
                16, 16, 100, 116, v_tasa, round(100 * v_tasa, 2), round(116 * v_tasa, 2));
        v_usd := pkg_cobros.fn_retencion_sugerida(v_fac_usd, 100, 'USD');
        v_bs  := pkg_cobros.fn_retencion_sugerida(v_fac_usd, round(100 * v_tasa, 2), 'VES');
        if v_usd <= 0 then falla('R18: la sugerencia en USD salio ' || v_usd); end if;
        if abs(v_usd - v_bs) > 1 then
            falla('R18: la sugerencia cambia con la moneda (USD ' || v_usd || ' vs Bs ' || v_bs || ')');
        end if;
    end;

    v_paso := 'R19';
    -- R19: la cabecera se queda con el comprobante del cobro que si lo tiene.
    v_fac := nueva_factura(200, 'VES', 1);
    insert into facturas_det (id_factura, num_linea, descripcion, cantidad, precio_unitario,
                              id_impuesto, porcentaje_impuesto, monto_impuesto,
                              subtotal_linea, monto_total_linea, tasa_cambio_aplicada,
                              subtotal_bs, total_bs)
    values (v_fac, 1, 'Servicio', 1, 200,
            (select id_impuesto from impuestos
              where cod_pais = 'VE' and cod_impuesto = 'IVA_GEN' and rownum = 1),
            16, 30, 200, 230, 1, 200, 230);
    pkg_cobros.prc_registrar_cobro(
        p_id_factura => v_fac, p_fecha => sysdate, p_id_forma_pago => null,
        p_cod_moneda => 'VES', p_monto => 100, p_usuario => v_usr, p_id_recibo => v_rec);
    pkg_cobros.prc_registrar_cobro(
        p_id_factura => v_fac, p_fecha => sysdate, p_id_forma_pago => null,
        p_cod_moneda => 'VES', p_monto => 100, p_retencion_iva_bs => 5,
        p_nro_comprobante => '20261100000055', p_usuario => v_usr, p_id_recibo => v_rec);
    select nvl(nro_comprobante_retencion, '#') into v_msg from facturas where id_factura = v_fac;
    if v_msg <> '20261100000055' then
        falla('R19: la cabecera se quedo con el comprobante ' || v_msg
              || ' (el segundo cobro es el que lo tiene)');
    end if;

    rollback to sp_cobreg;

    for i in 1 .. v_fallas.count loop
        insert into tmp_cobreg_fallas values (v_fallas(i));
    end loop;
exception
    when others then
        rollback to sp_cobreg;
        v_msg := substrb('R?: el caso revento en ' || v_paso || ': ' || sqlerrm, 1, 300);
        insert into tmp_cobreg_fallas values (v_msg);
end;
/

declare
    v_fallas number;
    v_lista  varchar2(3000);
begin
    select count(*) into v_fallas from tmp_cobreg_fallas;
    select substrb(listagg(caso, ' | ' on overflow truncate) within group (order by caso), 1, 3000)
      into v_lista from tmp_cobreg_fallas;
    execute immediate 'drop table tmp_cobreg_fallas purge';
    raise_application_error(-20100, substrb('RESULTADO: FALLAS=' || v_fallas || ' | ' || v_lista, 1, 3000));
end;
/
