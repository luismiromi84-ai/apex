-- =============================================================================
-- pkg_conciliacion (body) - conciliacion bancaria (2026-11-25)
-- =============================================================================

create or replace package body pkg_conciliacion as

    function fn_importe(p_monto in number, p_moneda in varchar2, p_tc in number,
                        p_fecha in date, p_moneda_cuenta in varchar2) return number is
        v_t number;
    begin
        if upper(nvl(p_moneda, '#')) = upper(nvl(p_moneda_cuenta, '#')) then
            return nvl(p_monto, 0);
        end if;
        -- otra moneda: a bolivares con la tasa del movimiento y de ahi a la de la cuenta
        v_t := nvl(fn_tasa_ves(trunc(p_fecha), upper(p_moneda_cuenta)), 0);
        if upper(p_moneda_cuenta) in ('VES', 'BS') then
            v_t := 1;
        end if;
        if v_t = 0 then
            return 0;
        end if;
        return round(nvl(p_monto, 0) * nvl(p_tc, 1) / v_t, 2);
    end fn_importe;

    -- La conciliacion, validada contra la empresa del usuario. Bloquea la fila.
    function lee(p_id in number, p_usuario in varchar2) return conciliaciones%rowtype is
        r conciliaciones%rowtype;
    begin
        begin
            select * into r from conciliaciones where id_conciliacion = p_id for update;
        exception
            when no_data_found then
                raise_application_error(-20173, 'La conciliacion no existe.');
        end;
        if not fn_usuario_empresa_valida(p_usuario, r.id_empresa) then
            raise_application_error(-20173, 'La conciliacion es de otra empresa.');
        end if;
        return r;
    end lee;

    function fn_abrir(p_id_cuenta in number, p_desde in date, p_hasta in date,
                      p_usuario in varchar2) return number is
        v_emp   number;
        v_n     number;
        v_ult   date;
        v_saldo number;
        v_id    number;
    begin
        begin
            select id_empresa into v_emp from cuentas_fondos where id_cuenta = p_id_cuenta;
        exception
            when no_data_found then
                raise_application_error(-20173, 'La caja o cuenta no existe.');
        end;
        if not fn_usuario_empresa_valida(p_usuario, v_emp) then
            raise_application_error(-20173, 'La caja o cuenta es de otra empresa.');
        end if;
        if p_desde is null or p_hasta is null or p_desde > p_hasta then
            raise_application_error(-20171, 'Indica un periodo valido: desde no puede ser mayor que hasta.');
        end if;
        select count(*) into v_n from conciliaciones
         where id_cuenta = p_id_cuenta and estado = 'ABIERTA';
        if v_n > 0 then
            raise_application_error(-20170,
                'Ya hay una conciliacion abierta para esta cuenta: cierrala o anulala antes.');
        end if;
        select max(hasta) into v_ult from conciliaciones
         where id_cuenta = p_id_cuenta and estado = 'CERRADA';
        if v_ult is not null and trunc(p_desde) <= v_ult then
            raise_application_error(-20171,
                'El periodo pisa el ultimo cierre (hasta el ' || to_char(v_ult, 'DD/MM/YYYY')
                || '): empieza despues de esa fecha.');
        end if;
        select max(saldo_banco) keep (dense_rank last order by hasta, id_conciliacion)
          into v_saldo
          from conciliaciones
         where id_cuenta = p_id_cuenta and estado = 'CERRADA';
        -- 2026-11-26: la primera conciliacion arranca con el saldo inicial de la cuenta
        -- (el que tenia antes de usar Synpex), no en cero.
        if v_saldo is null then
            select nvl(saldo_inicial, 0) into v_saldo from cuentas_fondos where id_cuenta = p_id_cuenta;
        end if;

        insert into conciliaciones (id_empresa, id_cuenta, desde, hasta, saldo_inicial, estado, creado_por)
        values (v_emp, p_id_cuenta, trunc(p_desde), trunc(p_hasta), nvl(v_saldo, 0), 'ABIERTA', p_usuario)
        returning id_conciliacion into v_id;
        return v_id;
    end fn_abrir;

    procedure prc_marcar(p_id_conciliacion in number, p_json in clob, p_usuario in varchar2) is
        r conciliaciones%rowtype;
    begin
        r := lee(p_id_conciliacion, p_usuario);
        if r.estado <> 'ABIERTA' then
            raise_application_error(-20174, 'La conciliacion esta ' || r.estado || ': no se puede cambiar.');
        end if;
        for m in (select jt.t, jt.id, jt.ok
                    from json_table(nvl(p_json, '[]'), '$[*]'
                         columns (t varchar2(1) path '$.t', id number path '$.id', ok number path '$.ok')) jt) loop
            if m.t = 'R' then
                update recibos x set x.conciliado = case when m.ok = 1 then 'S' else 'N' end,
                       x.fecha_conciliacion = case when m.ok = 1 then nvl(x.fecha_conciliacion, sysdate) end,
                       x.id_conciliacion = case when m.ok = 1 then p_id_conciliacion end
                 where x.id_recibo = m.id
                   and x.id_cuenta = r.id_cuenta
                   and x.estado = 'ACTIVO'
                   and (x.id_conciliacion is null or x.id_conciliacion = p_id_conciliacion);
            elsif m.t = 'P' then
                update pagos y set y.conciliado = case when m.ok = 1 then 'S' else 'N' end,
                       y.fecha_conciliacion = case when m.ok = 1 then nvl(y.fecha_conciliacion, sysdate) end,
                       y.id_conciliacion = case when m.ok = 1 then p_id_conciliacion end
                 where y.id_pago = m.id
                   and y.id_cuenta = r.id_cuenta
                   and y.estado = 'ACTIVO'
                   and (y.id_conciliacion is null or y.id_conciliacion = p_id_conciliacion);
            end if;
        end loop;
    end prc_marcar;

    function fn_saldo_sistema(p_id_conciliacion in number) return number is
        v_ini number;
        v_mon varchar2(3);
        v_ent number;
        v_sal number;
    begin
        select c.saldo_inicial, f.cod_moneda into v_ini, v_mon
          from conciliaciones c join cuentas_fondos f on f.id_cuenta = c.id_cuenta
         where c.id_conciliacion = p_id_conciliacion;
        select nvl(sum(fn_importe(x.monto_neto, x.cod_moneda, x.tipo_cambio, x.fecha_cobro, v_mon)), 0)
          into v_ent from recibos x
         where x.id_conciliacion = p_id_conciliacion and x.estado = 'ACTIVO';
        select nvl(sum(fn_importe(y.monto + nvl(y.igtf_monto, 0), y.cod_moneda, y.tipo_cambio, y.fecha_pago, v_mon)), 0)
          into v_sal from pagos y
         where y.id_conciliacion = p_id_conciliacion and y.estado = 'ACTIVO';
        return round(nvl(v_ini, 0) + v_ent - v_sal, 2);
    end fn_saldo_sistema;

    procedure prc_cerrar(p_id_conciliacion in number, p_saldo_banco in number, p_usuario in varchar2) is
        r     conciliaciones%rowtype;
        v_sis number;
        v_dif number;
    begin
        r := lee(p_id_conciliacion, p_usuario);
        if r.estado <> 'ABIERTA' then
            raise_application_error(-20174, 'La conciliacion ya esta ' || r.estado || '.');
        end if;
        if p_saldo_banco is null then
            raise_application_error(-20172, 'Escribe el saldo segun el banco (el del extracto al cierre del periodo).');
        end if;
        v_sis := fn_saldo_sistema(p_id_conciliacion);
        v_dif := round(p_saldo_banco - v_sis, 2);
        if abs(v_dif) > 0.01 then
            raise_application_error(-20172,
                'No cuadra: el banco dice ' || to_char(p_saldo_banco, 'FM999G999G999G990D00')
                || ' y el sistema ' || to_char(v_sis, 'FM999G999G999G990D00')
                || ' (diferencia ' || to_char(v_dif, 'FM999G999G999G990D00')
                || '). Revisa los movimientos marcados.');
        end if;
        update conciliaciones c set c.estado = 'CERRADA', c.saldo_banco = p_saldo_banco, c.saldo_sistema = v_sis,
               c.diferencia = v_dif, c.cerrado_por = p_usuario, c.fecha_cierre = sysdate
         where c.id_conciliacion = p_id_conciliacion;
    end prc_cerrar;

    procedure prc_anular(p_id_conciliacion in number, p_usuario in varchar2) is
        r conciliaciones%rowtype;
    begin
        r := lee(p_id_conciliacion, p_usuario);
        if r.estado <> 'ABIERTA' then
            raise_application_error(-20174, 'Solo se anula una conciliacion abierta (esta ' || r.estado || ').');
        end if;
        update recibos x set x.conciliado = 'N', x.fecha_conciliacion = null, x.id_conciliacion = null
         where x.id_conciliacion = p_id_conciliacion;
        update pagos y set y.conciliado = 'N', y.fecha_conciliacion = null, y.id_conciliacion = null
         where y.id_conciliacion = p_id_conciliacion;
        update conciliaciones c set c.estado = 'ANULADA' where c.id_conciliacion = p_id_conciliacion;
    end prc_anular;

end pkg_conciliacion;
/
