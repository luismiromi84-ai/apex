create or replace package body pkg_inventario as

    c_eps constant number := 0.00005;

    function fn_signo(p_tipo in varchar2) return number is
        v_tipo varchar2(20) := upper(trim(p_tipo));
    begin
        if v_tipo in ('ENTRADA_COMPRA', 'ENTRADA_NC_CLIENTE', 'ENTRADA_ND_PROVEEDOR',
                      'AJUSTE_ENTRADA', 'SALDO_INICIAL', 'REVERSA_SALIDA') then
            return 1;
        end if;
        if v_tipo in ('SALIDA_FACTURA', 'SALIDA_ND_CLIENTE', 'SALIDA_NC_PROVEEDOR',
                      'AJUSTE_SALIDA', 'REVERSA_ENTRADA') then
            return -1;
        end if;
        raise_application_error(-20023, 'Tipo de movimiento de inventario desconocido: ' || p_tipo);
    end fn_signo;

    function fn_disponible(p_id_empresa in number, p_id_producto in number) return number is
        v_n number;
    begin
        select cantidad into v_n
          from kardex_saldo
         where id_empresa = p_id_empresa and id_producto_servicio = p_id_producto;
        return v_n;
    exception
        when no_data_found then return 0;
    end fn_disponible;

    function fn_cpp_bs(p_id_empresa in number, p_id_producto in number) return number is
        v_n number;
    begin
        select costo_promedio_bs into v_n
          from kardex_saldo
         where id_empresa = p_id_empresa and id_producto_servicio = p_id_producto;
        return nvl(v_n, 0);
    exception
        when no_data_found then return 0;
    end fn_cpp_bs;

    function fn_tiene_movimiento(p_doc_tipo in varchar2, p_id_doc in number,
                                 p_id_detalle in number default null) return boolean is
        v_n number;
    begin
        if p_id_doc is null or upper(trim(nvl(p_doc_tipo, '#'))) in ('#', 'AJUSTE', 'SALDO_INICIAL') then
            return false;
        end if;
        select count(*) into v_n
          from kardex_mov
         where doc_tipo = upper(trim(p_doc_tipo))
           and id_doc = p_id_doc
           and (p_id_detalle is null or id_detalle_origen = p_id_detalle);
        return v_n > 0;
    end fn_tiene_movimiento;

    ----------------------------------------------------------------------------
    -- El movimiento
    ----------------------------------------------------------------------------
    procedure prc_movimiento(
        p_id_empresa    in number,
        p_id_producto   in number,
        p_fecha         in date,
        p_tipo          in varchar2,
        p_cantidad      in number,
        p_costo_unit_bs in number,
        p_tasa          in number,
        p_moneda        in varchar2,
        p_doc_tipo      in varchar2,
        p_id_doc        in number,
        p_id_detalle    in number,
        p_motivo        in varchar2,
        p_usuario       in varchar2,
        p_id_movimiento out number)
    is
        v_tipo     varchar2(20) := upper(trim(p_tipo));
        v_signo    number;
        v_emp_art  number;
        v_tipo_art varchar2(20);
        v_fecha    date := nvl(p_fecha, trunc(sysdate));
        v_tasa     number;
        v_moneda   varchar2(10);
        v_num      varchar2(20);

        v_cant     number;
        v_val      number;
        v_ref      number;
        v_cpp      number;
        v_cpp_ref  number;

        v_cant_n   number;
        v_val_n    number;
        v_ref_n    number;
        v_cpp_n    number;
        v_cpp_ref_n number;

        v_unit     number;
        v_total    number;
        v_total_ref number;
        v_permite  number;
    begin
        if p_id_empresa is null or p_id_empresa <= 0 then
            raise_application_error(-20023, 'El movimiento de inventario necesita empresa.');
        end if;
        if p_cantidad is null or p_cantidad <= 0 then
            raise_application_error(-20023, 'La cantidad del movimiento debe ser mayor que cero.');
        end if;

        if p_tasa is null or p_tasa <= 0 then
            raise_application_error(-20023,
                'El movimiento de inventario necesita una tasa mayor que cero.');
        end if;

        v_signo  := fn_signo(v_tipo);
        v_tasa   := p_tasa;
        v_moneda := upper(nvl(p_moneda, 'VES'));

        -- El articulo tiene que ser de la empresa del movimiento y no un servicio.
        begin
            select id_empresa, nvl(tipo, 'PRODUCTO')
              into v_emp_art, v_tipo_art
              from producto_servicio
             where id_producto_servicio = p_id_producto;
        exception
            when no_data_found then
                raise_application_error(-20151, 'El articulo ' || p_id_producto || ' no existe.');
        end;

        if v_emp_art <> p_id_empresa then
            raise_application_error(-20151, 'El articulo no es de la empresa del movimiento.');
        end if;
        if v_tipo_art = 'SERVICIO' then
            raise_application_error(-20155,
                'El articulo ' || p_id_producto || ' es un servicio: no lleva inventario.');
        end if;

        -- Un documento mueve inventario UNA vez (los ajustes no se controlan asi).
        -- Las reversas son la excepcion: su razon de ser es repetir la linea.
        if v_tipo not like 'REVERSA%' and fn_tiene_movimiento(p_doc_tipo, p_id_doc, p_id_detalle) then
            raise_application_error(-20152,
                'El documento ' || p_doc_tipo || ' ' || p_id_doc || ' ya movio inventario.');
        end if;

        -- Saldo con bloqueo de fila. Si no existe, se crea en cero.
        begin
            select cantidad, valor_bs, valor_ref, costo_promedio_bs, costo_promedio_ref
              into v_cant, v_val, v_ref, v_cpp, v_cpp_ref
              from kardex_saldo
             where id_empresa = p_id_empresa and id_producto_servicio = p_id_producto
               for update;
        exception
            when no_data_found then
                begin
                    insert into kardex_saldo (id_empresa, id_producto_servicio, cantidad,
                                              valor_bs, valor_ref, costo_promedio_bs,
                                              costo_promedio_ref)
                    values (p_id_empresa, p_id_producto, 0, 0, 0, 0, 0);
                exception
                    when dup_val_on_index then
                        select cantidad, valor_bs, valor_ref, costo_promedio_bs, costo_promedio_ref
                          into v_cant, v_val, v_ref, v_cpp, v_cpp_ref
                          from kardex_saldo
                         where id_empresa = p_id_empresa and id_producto_servicio = p_id_producto
                           for update;
                end;
                v_cant := nvl(v_cant, 0);
                v_val  := nvl(v_val, 0);
                v_ref  := nvl(v_ref, 0);
                v_cpp  := nvl(v_cpp, 0);
                v_cpp_ref := nvl(v_cpp_ref, 0);
        end;

        if v_signo > 0 then
            ------------------------------------------------------------ entrada
            v_unit      := nvl(p_costo_unit_bs, v_cpp);
            v_total     := round(p_cantidad * v_unit, 2);
            v_total_ref := round(v_total / v_tasa, 2);

            v_cant_n := v_cant + p_cantidad;
            v_val_n  := v_val + v_total;
            v_ref_n  := v_ref + v_total_ref;

            if abs(v_cant_n) > c_eps then
                v_cpp_n     := round(v_val_n / v_cant_n, 6);
                v_cpp_ref_n := round(v_ref_n / v_cant_n, 6);
            elsif abs(v_val_n) > 0.005 then
                -- Cruce desde existencia negativa: quedan 0 unidades pero hay valor
                -- (lo que costo reponer lo ya vendido). El CPP no puede irse a 0 o
                -- la siguiente venta saldria a costo cero para siempre.
                v_cpp_n     := v_unit;
                v_cpp_ref_n := round(v_unit / v_tasa, 6);
            else
                v_cpp_n     := 0;
                v_cpp_ref_n := 0;
            end if;
        else
            ------------------------------------------------------------- salida
            -- El costo es el CPP vigente, salvo que venga impuesto (reversas).
            v_unit := nvl(p_costo_unit_bs, v_cpp);

            if abs(v_cant - p_cantidad) <= c_eps then
                -- Agota el saldo: se lleva TODO el valor y el saldo queda en cero
                -- exacto (si se multiplicara, quedarian centimos colgando).
                v_total     := v_val;
                v_total_ref := round(v_val / v_tasa, 2);
                v_cant_n    := 0;
                v_val_n     := 0;
                v_ref_n     := 0;
                v_cpp_n     := 0;
                v_cpp_ref_n := 0;
            else
                v_total     := round(p_cantidad * v_unit, 2);
                v_total_ref := round(v_total / v_tasa, 2);
                v_cant_n    := v_cant - p_cantidad;
                v_val_n     := v_val - v_total;
                v_ref_n     := v_ref - v_total_ref;
                v_cpp_n     := v_cpp;          -- el CPP no cambia en una salida
                v_cpp_ref_n := v_cpp_ref;
            end if;

            -- El saldo negativo se permite o no segun el parametro.
            if v_cant_n < -c_eps then
                begin
                    select valor into v_permite
                      from syn_parametros where clave = 'INVENTARIO_PERMITE_NEGATIVO';
                exception
                    when no_data_found then v_permite := 1;
                end;
                if nvl(v_permite, 1) = 0 then
                    raise_application_error(-20150,
                        'No hay existencia suficiente del articulo ' || p_id_producto
                        || ': hay ' || to_char(v_cant) || ' y se piden ' || to_char(p_cantidad) || '.');
                end if;
            end if;
        end if;

        if abs(v_cant_n) <= c_eps then
            v_cant_n := 0;
        end if;

        v_num := fn_asignar_folio(p_id_empresa, 'KARDEX');

        insert into kardex_mov (
            id_empresa, num_movimiento, id_producto_servicio, fecha_movimiento,
            tipo_movimiento, cantidad, costo_unit_bs, costo_total_bs, tasa_cambio,
            moneda_documento, costo_unit_ref, costo_total_ref, doc_tipo, id_doc,
            id_detalle_origen, motivo, creado_por)
        values (
            p_id_empresa, v_num, p_id_producto, v_fecha,
            v_tipo, p_cantidad, v_unit, v_total, v_tasa,
            v_moneda, round(v_unit / v_tasa, 6), v_total_ref, upper(trim(p_doc_tipo)), p_id_doc,
            p_id_detalle, p_motivo, p_usuario)
        returning id_movimiento into p_id_movimiento;

        update kardex_saldo set cantidad          = v_cant_n,
               valor_bs          = v_val_n,
               valor_ref         = v_ref_n,
               costo_promedio_bs = v_cpp_n,
               costo_promedio_ref = v_cpp_ref_n,
               ultimo_movimiento = p_id_movimiento,
               actualizado_el    = systimestamp
         where id_empresa = p_id_empresa
           and id_producto_servicio = p_id_producto;
    end prc_movimiento;

    ----------------------------------------------------------------------------
    -- La compra (y sus notas)
    ----------------------------------------------------------------------------
    procedure prc_desde_compra(p_id_compra in number, p_usuario in varchar2) is
        v_tipo    varchar2(10);
        v_emp     number;
        v_moneda  varchar2(10);
        v_tasa    number;
        v_fecha   date;
        v_mov     number;
        v_costo   number;
        v_mov_tipo varchar2(20);
    begin
        select nvl(tipo_documento, 'FAC'), id_empresa, nvl(cod_moneda, 'VES'),
               nvl(nullif(tipo_cambio, 0), 1), nvl(fecha_emision, trunc(sysdate))
          into v_tipo, v_emp, v_moneda, v_tasa, v_fecha
          from compras
         where id_compra = p_id_compra;

        if fn_tiene_movimiento('COMPRA', p_id_compra) then
            return;
        end if;

        for r in (select d.id_detalle, d.id_producto_servicio, d.cantidad,
                         d.subtotal_linea, d.id_detalle_origen,
                         nvl(p.tipo, 'PRODUCTO') tipo_art
                    from compras_det d
                    left join producto_servicio p
                      on p.id_producto_servicio = d.id_producto_servicio
                   where d.id_compra = p_id_compra
                     and d.id_producto_servicio is not null
                     and nvl(d.cantidad, 0) > 0
                   order by d.id_producto_servicio, d.num_linea)
        loop
            if r.tipo_art <> 'SERVICIO' then
                -- Costo de la linea en BOLIVARES: SUBTOTAL_LINEA esta en la moneda del
                -- documento (una compra en USD hay que multiplicarla por la tasa).
                v_costo := case when nvl(r.cantidad, 0) <> 0
                                then (r.subtotal_linea * v_tasa) / r.cantidad else 0 end;

                -- Una nota se valora al costo de la linea de la compra original.
                if v_tipo in ('NC', 'ND') and r.id_detalle_origen is not null then
                    begin
                        select (o.subtotal_linea * v_tasa) / nullif(o.cantidad, 0)
                          into v_costo
                          from compras_det o
                         where o.id_detalle = r.id_detalle_origen;
                    exception
                        when no_data_found then null;
                    end;
                end if;

                v_mov_tipo := case v_tipo
                                when 'NC' then 'SALIDA_NC_PROVEEDOR'
                                when 'ND' then 'ENTRADA_ND_PROVEEDOR'
                                else 'ENTRADA_COMPRA'
                              end;

                prc_movimiento(
                    p_id_empresa    => v_emp,
                    p_id_producto   => r.id_producto_servicio,
                    p_fecha         => v_fecha,
                    p_tipo          => v_mov_tipo,
                    p_cantidad      => r.cantidad,
                    p_costo_unit_bs => v_costo,
                    p_tasa          => v_tasa,
                    p_moneda        => v_moneda,
                    p_doc_tipo      => 'COMPRA',
                    p_id_doc        => p_id_compra,
                    p_id_detalle    => r.id_detalle,
                    p_motivo        => 'Compra ' || p_id_compra,
                    p_usuario       => p_usuario,
                    p_id_movimiento => v_mov);
            end if;
        end loop;
    end prc_desde_compra;

    ----------------------------------------------------------------------------
    -- La factura (y sus notas de venta)
    ----------------------------------------------------------------------------
    procedure prc_desde_factura(p_id_factura in number, p_usuario in varchar2) is
        v_tipo    varchar2(10);
        v_emp     number;
        v_moneda  varchar2(10);
        v_tasa    number;
        v_fecha   date;
        v_mov     number;
        v_costo   number;
        v_mov_tipo varchar2(20);
    begin
        select nvl(tipo_documento, 'FAC'), id_empresa, nvl(cod_moneda, 'VES'),
               nvl(nullif(tipo_cambio, 0), 1), nvl(fecha_emision, trunc(sysdate))
          into v_tipo, v_emp, v_moneda, v_tasa, v_fecha
          from facturas
         where id_factura = p_id_factura;

        -- El documento mueve inventario una sola vez.
        if fn_tiene_movimiento('FACTURA', p_id_factura) then
            return;
        end if;

        for r in (select d.id_detalle, d.id_producto, d.cantidad, d.id_detalle_origen,
                         nvl(p.tipo, 'PRODUCTO') tipo_art
                    from facturas_det d
                    left join producto_servicio p
                      on p.id_producto_servicio = d.id_producto
                   where d.id_factura = p_id_factura
                     and d.id_producto is not null
                     and nvl(d.cantidad, 0) > 0
                   order by d.id_producto, d.num_linea)
        loop
            if r.tipo_art <> 'SERVICIO' then
                if v_tipo = 'NC' then
                    -- Devuelve lo que salio: el costo de la linea de la venta que acredita.
                    v_costo := null;
                    if r.id_detalle_origen is not null then
                        begin
                            select m.costo_unit_bs into v_costo
                              from kardex_mov m
                             where m.doc_tipo = 'FACTURA'
                               and m.tipo_movimiento = 'SALIDA_FACTURA'
                               and m.id_detalle_origen = r.id_detalle_origen
                               and rownum = 1;
                        exception
                            when no_data_found then v_costo := null;
                        end;
                    end if;
                    -- Si no encuentra la salida original, cae al CPP (nunca a 0).
                    if v_costo is null then
                        v_costo := fn_cpp_bs(v_emp, r.id_producto);
                    end if;
                    v_mov_tipo := 'ENTRADA_NC_CLIENTE';
                else
                    v_costo := null;   -- el CPP lo pone prc_movimiento
                    v_mov_tipo := case v_tipo when 'ND' then 'SALIDA_ND_CLIENTE'
                                               else 'SALIDA_FACTURA' end;
                end if;

                prc_movimiento(
                    p_id_empresa    => v_emp,
                    p_id_producto   => r.id_producto,
                    p_fecha         => v_fecha,
                    p_tipo          => v_mov_tipo,
                    p_cantidad      => r.cantidad,
                    p_costo_unit_bs => v_costo,
                    p_tasa          => v_tasa,
                    p_moneda        => v_moneda,
                    p_doc_tipo      => 'FACTURA',
                    p_id_doc        => p_id_factura,
                    p_id_detalle    => r.id_detalle,
                    p_motivo        => 'Factura ' || p_id_factura,
                    p_usuario       => p_usuario,
                    p_id_movimiento => v_mov);
            end if;
        end loop;
    end prc_desde_factura;

    ----------------------------------------------------------------------------
    -- La reversa (anulaciones)
    ----------------------------------------------------------------------------
    procedure prc_reversar(p_doc_tipo in varchar2, p_id_doc in number,
                           p_motivo in varchar2, p_usuario in varchar2) is
        v_tipo_rev  varchar2(20);
        v_nuevo     number;
        v_pendiente number;
        r_id        number;
        r_emp       number;
        r_prod      number;
        r_cant      number;
        r_costo     number;
        r_tasa      number;
        r_mon       varchar2(10);
        r_tipo      varchar2(20);
        r_fecha     date;
        r_det       number;
    begin
        if p_id_doc is null then
            return;
        end if;

        for c in (select id_movimiento
                    from kardex_mov
                   where doc_tipo = upper(trim(p_doc_tipo))
                     and id_doc = p_id_doc
                   order by id_movimiento)
        loop
            -- Se bloquea la fila y se vuelve a comprobar: dos anulaciones
            -- simultaneas no pueden crear dos reversas del mismo movimiento.
            -- (El bloqueo va en un SELECT simple: FOR UPDATE no admite count(*)).
            select count(*) into v_pendiente
              from kardex_mov m
             where m.id_movimiento = c.id_movimiento;
            select m.id_movimiento into v_pendiente
              from kardex_mov m
             where m.id_movimiento = c.id_movimiento
               for update;
            select count(*) into v_pendiente
              from kardex_mov m
             where m.id_movimiento = c.id_movimiento
               and m.tipo_movimiento not in ('REVERSA_ENTRADA', 'REVERSA_SALIDA')
               and m.id_movimiento_reversa is null
               and not exists (select 1 from kardex_mov x
                                where x.id_movimiento_reversa = m.id_movimiento);
            if v_pendiente = 0 then
                continue;
            end if;

            select m.id_movimiento, m.id_empresa, m.id_producto_servicio, m.cantidad,
                   m.costo_unit_bs, m.tasa_cambio, m.moneda_documento,
                   m.tipo_movimiento, m.fecha_movimiento, m.id_detalle_origen
              into r_id, r_emp, r_prod, r_cant, r_costo, r_tasa, r_mon, r_tipo, r_fecha, r_det
              from kardex_mov m
             where m.id_movimiento = c.id_movimiento;
            -- El reverso de una entrada es una salida y al reves, SIEMPRE al costo
            -- con que se movio: asi el saldo vuelve a como estaba.
            v_tipo_rev := case when fn_signo(r_tipo) > 0
                               then 'REVERSA_ENTRADA' else 'REVERSA_SALIDA' end;

            prc_movimiento(
                p_id_empresa    => r_emp,
                p_id_producto   => r_prod,
                p_fecha         => r_fecha,
                p_tipo          => v_tipo_rev,
                p_cantidad      => r_cant,
                p_costo_unit_bs => r_costo,
                p_tasa          => r_tasa,
                p_moneda        => r_mon,
                p_doc_tipo      => upper(trim(p_doc_tipo)),
                p_id_doc        => p_id_doc,
                p_id_detalle    => r_det,
                p_motivo        => p_motivo,
                p_usuario       => p_usuario,
                p_id_movimiento => v_nuevo);

            update kardex_mov set id_movimiento_reversa = v_nuevo
             where id_movimiento = r_id;
        end loop;
    end prc_reversar;

    ----------------------------------------------------------------------------
    -- Ajustes y carga inicial
    ----------------------------------------------------------------------------
    procedure prc_ajuste(p_id_empresa in number, p_id_producto in number, p_fecha in date,
                         p_tipo in varchar2, p_cantidad in number, p_costo_unit_bs in number,
                         p_moneda in varchar2, p_tasa in number, p_motivo in varchar2,
                         p_usuario in varchar2) is
        v_tipo varchar2(20) := upper(trim(p_tipo));
        v_mov  number;
        v_n    number;
    begin
        if p_motivo is null or trim(p_motivo) is null then
            raise_application_error(-20153,
                'El ajuste de inventario necesita un motivo.');
        end if;
        if v_tipo not in ('AJUSTE_ENTRADA', 'AJUSTE_SALIDA', 'SALDO_INICIAL') then
            raise_application_error(-20023,
                'Tipo de ajuste no valido: ' || p_tipo
                || '. Usa AJUSTE_ENTRADA, AJUSTE_SALIDA o SALDO_INICIAL.');
        end if;
        if not fn_usuario_empresa_valida(p_usuario, p_id_empresa) then
            raise_application_error(-20003, 'No tiene permisos sobre esta empresa.');
        end if;

        if v_tipo = 'SALDO_INICIAL' then
            select count(*) into v_n
              from kardex_mov
             where id_empresa = p_id_empresa
               and id_producto_servicio = p_id_producto;
            if v_n > 0 then
                raise_application_error(-20154,
                    'El articulo ' || p_id_producto
                    || ' ya tiene movimientos: la carga inicial solo se puede una vez.');
            end if;
        end if;

        prc_movimiento(
            p_id_empresa    => p_id_empresa,
            p_id_producto   => p_id_producto,
            p_fecha         => p_fecha,
            p_tipo          => v_tipo,
            p_cantidad      => p_cantidad,
            p_costo_unit_bs => p_costo_unit_bs,
            p_tasa          => p_tasa,
            p_moneda        => p_moneda,
            p_doc_tipo      => case when v_tipo = 'SALDO_INICIAL' then 'SALDO_INICIAL' else 'AJUSTE' end,
            p_id_doc        => null,
            p_id_detalle    => null,
            p_motivo        => p_motivo,
            p_usuario       => p_usuario,
            p_id_movimiento => v_mov);
    end prc_ajuste;

end pkg_inventario;
/
