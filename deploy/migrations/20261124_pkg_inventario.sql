-- =============================================================================
-- 20261124_pkg_inventario.sql
--
-- PKG_INVENTARIO y los paquetes que lo llaman (2026-11-24). Spec y bodies se
-- pegan aqui desde los canonicos para que una base existente quede igual que una
-- instalacion limpia: `install.sql` + `install_bodies.sql` no se ejecutan sobre
-- una base con datos.
--
-- Requiere el modelo de 20261124_inventario_modelo.sql (tablas + serie KARDEX).
--
-- Idempotente: todo es create or replace.
--
-- REVERSA: drop package body pkg_inventario; drop package pkg_inventario; y
--          volver a compilar el body de pkg_compras sin la llamada al kardex
--          (git checkout del canonico anterior). Los movimientos quedan.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;
/

-- Parametro del saldo negativo (decision del dueno, 2026-11-23: en Venezuela se
-- despacha antes de que llegue la compra). VALOR es NUMBER: 1 permite, 0 prohibe.
insert into syn_parametros (clave, valor, descripcion)
select 'INVENTARIO_PERMITE_NEGATIVO', 1,
       'Inventario: 1 permite dejar existencias en negativo, 0 lo prohibe' from dual
 where not exists (select 1 from syn_parametros where clave = 'INVENTARIO_PERMITE_NEGATIVO');
/

-- =============================================================================
-- PKG_INVENTARIO — spec (canonico package/)
-- =============================================================================

-- =============================================================================
-- PKG_INVENTARIO — el unico escritor del kardex (2026-11-24)
--
-- Reglas que manda el diseno (documentacion/docs/superpowers/specs/
-- 2026-11-23-inventario-kardex-design.md):
--   * El movimiento es inmutable; se revierte con otro movimiento.
--   * El costo promedio ponderado (CPP) se aplica en la SALIDA y se congela.
--   * Doble valoracion: bolivares a la tasa del documento y la divisa a esa
--     misma tasa.
--   * No hace COMMIT: manda el documento que llama.
-- =============================================================================

create or replace package pkg_inventario as

    -- +1 si el tipo suma cantidad, -1 si la resta.
    function fn_signo(p_tipo in varchar2) return number;

    -- Cuanto hay y a que costo. 0 si el articulo no tiene saldo.
    function fn_disponible(p_id_empresa in number, p_id_producto in number) return number;
    function fn_cpp_bs(p_id_empresa in number, p_id_producto in number) return number;

    -- Si el documento (o una de sus lineas) ya movio inventario: el documento se
    -- mueve una vez y cada linea genera su propio movimiento.
    function fn_tiene_movimiento(p_doc_tipo in varchar2, p_id_doc in number,
                                 p_id_detalle in number default null) return boolean;

    -- Cuelga del documento: la compra registrada (o su nota) y la factura emitida
    -- (o su nota). Lo llaman pkg_compras y pkg_facturacion.
    procedure prc_desde_compra(p_id_compra in number, p_usuario in varchar2);
    procedure prc_desde_factura(p_id_factura in number, p_usuario in varchar2);

    -- Devuelve el documento a como estaba antes de mover inventario, con
    -- movimientos de reversa numerados (nunca borra). Idempotente.
    procedure prc_reversar(p_doc_tipo in varchar2, p_id_doc in number,
                           p_motivo in varchar2, p_usuario in varchar2);

    -- Ajuste manual y carga inicial del stock. El motivo es obligatorio y el
    -- SALDO_INICIAL solo se admite una vez por articulo (mientras no tenga
    -- movimientos).
    procedure prc_ajuste(p_id_empresa in number, p_id_producto in number, p_fecha in date,
                         p_tipo in varchar2, p_cantidad in number, p_costo_unit_bs in number,
                         p_moneda in varchar2, p_tasa in number, p_motivo in varchar2,
                         p_usuario in varchar2);

    -- El unico insert del kardex. p_costo_unit_bs nulo en una salida = CPP.
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
        p_id_movimiento out number);

end pkg_inventario;
/


-- =============================================================================
-- PKG_INVENTARIO — body (canonico package_bodies/)
-- =============================================================================

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


-- =============================================================================
-- PKG_COMPRAS — body con el gancho de la compra
-- =============================================================================

-- =============================================================================
-- package_bodies/pkg_compras.sql
--
-- OJO con el runner: descarta las lineas que empiezan por "set ", asi que los
-- UPDATE llevan el SET en la misma linea.
-- =============================================================================

create or replace package body pkg_compras as

    procedure prc_guardar_compra(
        p_id_compra            in out number,
        p_id_empresa           in number,
        p_id_proveedor         in number,
        p_tipo_documento       in varchar2 default 'FAC',
        p_folio_factura        in varchar2,
        p_nro_control          in varchar2 default null,
        p_fecha_emision        in date,
        p_cod_moneda           in varchar2 default 'VES',
        p_tipo_cambio          in number default 1,
        p_porcentaje_retencion in number default null,
        p_id_compra_origen     in number default null,
        p_observaciones        in varchar2 default null,
        p_id_forma_pago        in number default null,
        p_id_concepto_islr     in number default -1,
        p_usuario              in varchar2) is
        v_estado    varchar2(20);
        v_prov_emp  number;
        v_prov_con  number;
        v_con       number;
        v_tasa      number;
        v_tasa_ant  number;
        v_pct       number;
        v_fecha     date;
        v_folio     varchar2(50);
        v_control   varchar2(50);
    begin
        if p_id_proveedor is null then
            raise_application_error(-20087, 'La compra necesita un proveedor.');
        end if;

        if not fn_usuario_empresa_valida(p_usuario, p_id_empresa) then
            raise_application_error(-20003, 'No tiene permisos sobre esta empresa.');
        end if;

        begin
            select id_empresa, id_concepto_islr into v_prov_emp, v_prov_con
              from proveedores where id_proveedor = p_id_proveedor;
        exception
            when no_data_found then
                raise_application_error(-20084, 'El proveedor no existe.');
        end;
        if v_prov_emp <> p_id_empresa then
            raise_application_error(-20084, 'El proveedor no es de la empresa del documento.');
        end if;

        if p_porcentaje_retencion is not null
           and (p_porcentaje_retencion < 0 or p_porcentaje_retencion > 100) then
            raise_application_error(-20082, 'El porcentaje de retencion debe estar entre 0 y 100.');
        end if;

        v_fecha := nvl(p_fecha_emision, sysdate);

        if upper(nvl(p_cod_moneda, 'VES')) in ('VES', 'BS') then
            v_tasa := 1;
        else
            v_tasa := fn_validar_tasa_documento(p_cod_moneda, v_fecha, p_tipo_cambio);
        end if;

        if p_porcentaje_retencion is null then
            v_pct := pkg_retenciones.fn_porcentaje(p_id_proveedor);
        else
            v_pct := p_porcentaje_retencion;
        end if;

        -- Una nota (NC/ND) tiene que decir que factura de compra afecta: es lo que
        -- pide la providencia del SENIAT y lo que cruza el libro de compras.
        --
        -- CORRELACION DE LA TASA (2026-11-20): la nota lleva la TASA de la factura
        -- que acredita, no la del dia en que se emite, igual que las notas de venta
        -- desde el 2026-11-09. Sin esto la cabecera quedaba a la tasa del dia y las
        -- lineas copiadas con la de la factura: el libro suma las filas por el
        -- detalle y los totales del mes por la cabecera, y los dos numeros no
        -- cuadraban (nota de compra 1462: 1.294,71 Bs de diferencia).
        -- Si la factura que acredita esta ANULADA se mantiene la tasa recibida (de
        -- un documento anulado no se hereda nada). Y si la nota esta en otra moneda
        -- que la factura, la tasa de la factura no significa nada en esa moneda:
        -- se respeta la que llega (la pantalla copia la moneda del origen).
        if upper(nvl(p_tipo_documento, 'FAC')) in ('NC', 'ND') then
            if p_id_compra_origen is null then
                raise_application_error(-20097,
                    'Una nota de credito o debito necesita la factura de compra que afecta.');
            end if;
            declare
                v_tipo_origen varchar2(10);
                v_emp_origen  number;
                v_est_origen  varchar2(20);
                v_tasa_origen number;
                v_mon_origen  varchar2(5);
            begin
                select tipo_documento, id_empresa, estado, tipo_cambio, cod_moneda
                  into v_tipo_origen, v_emp_origen, v_est_origen, v_tasa_origen, v_mon_origen
                  from compras where id_compra = p_id_compra_origen;
                if v_tipo_origen <> 'FAC' or v_emp_origen <> p_id_empresa then
                    raise_application_error(-20097,
                        'La factura afectada tiene que ser una factura de compra de esta empresa.');
                end if;
                if v_est_origen <> 'ANULADA'
                   and v_tasa_origen is not null
                   and upper(nvl(v_mon_origen, 'VES')) = upper(nvl(p_cod_moneda, 'VES')) then
                    v_tasa := v_tasa_origen;
                end if;
            exception
                when no_data_found then
                    raise_application_error(-20097, 'La factura afectada no existe.');
            end;
        end if;

        -- Numeracion del PROVEEDOR (2026-11-18): la serie vive en FOLIO_CONTADOR
        -- (FAC_PROV y CONTROL_PROV) para que la pantalla la proponga sola. Al dar de
        -- alta se CONSUME solo si se dejo la propuesta (o vacio); si el usuario
        -- escribio otro numero, se respeta el suyo y la serie no se mueve.
        v_folio := trim(p_folio_factura);
        v_control := trim(p_nro_control);

        if p_id_compra is null then
            if v_folio is null
               or upper(v_folio) = upper(fn_siguiente_folio(p_id_empresa, 'FAC_PROV')) then
                v_folio := fn_asignar_folio(p_id_empresa, 'FAC_PROV');
            end if;
            if v_control is null
               or upper(v_control) = upper(fn_siguiente_folio(p_id_empresa, 'CONTROL_PROV')) then
                v_control := fn_asignar_folio(p_id_empresa, 'CONTROL_PROV');
            end if;
        end if;

        if v_folio is null then
            raise_application_error(-20087,
                'El numero de factura del proveedor es obligatorio.');
        end if;
        if v_control is not null and length(v_control) < 3 then
            raise_application_error(-20089,
                'El numero de control del proveedor no puede ser un numero suelto de 1 o 2 digitos. '
                || 'Escribelo como aparece en la factura (por ejemplo 00-000045).');
        end if;

        if p_id_compra is null then
            -- Concepto de ISLR con CENTINELA (ver la spec): -1 o nulo = no se envio y
            -- se HEREDA del proveedor; 0 = sin concepto; otro = ese concepto. Un nulo
            -- no puede significar a la vez "borralo" y "no lo mande": el llamador que
            -- no pasa el parametro borraba el concepto heredado en cada guardado y el
            -- comprobante de ISLR dejaba de emitirse en silencio.
            v_con := p_id_concepto_islr;
            if v_con is null or v_con = -1 then
                v_con := v_prov_con;
            elsif v_con = 0 then
                v_con := null;
            end if;

            begin
                insert into compras (id_empresa, id_proveedor, tipo_documento, folio_factura,
                                     nro_control, fecha_emision, cod_moneda, tipo_cambio,
                                     porcentaje_retencion, estado, observaciones,
                                     id_compra_origen, id_forma_pago, id_concepto_islr,
                                     creado_por)
                values (p_id_empresa, p_id_proveedor, nvl(p_tipo_documento, 'FAC'),
                        v_folio, v_control, v_fecha, nvl(p_cod_moneda, 'VES'),
                        v_tasa, v_pct, 'BORRADOR', p_observaciones,
                        p_id_compra_origen, p_id_forma_pago, v_con, p_usuario)
                returning id_compra into p_id_compra;
            exception
                when dup_val_on_index then
                    raise_application_error(-20080,
                        'Ya existe la factura ' || v_folio || ' de este proveedor.');
            end;
        else
            begin
                select estado, tipo_cambio into v_estado, v_tasa_ant
                  from compras where id_compra = p_id_compra;
            exception
                when no_data_found then
                    raise_application_error(-20085, 'La compra ' || p_id_compra || ' no existe.');
            end;
            if v_estado <> 'BORRADOR' then
                raise_application_error(-20083,
                    'La compra esta ' || v_estado || ': no se puede modificar.');
            end if;
            begin
                update compras set id_proveedor = p_id_proveedor,
                       tipo_documento = nvl(p_tipo_documento, 'FAC'),
                       folio_factura = v_folio, nro_control = v_control,
                       fecha_emision = v_fecha, cod_moneda = nvl(p_cod_moneda, 'VES'),
                       tipo_cambio = v_tasa, porcentaje_retencion = v_pct,
                       observaciones = p_observaciones, id_compra_origen = p_id_compra_origen,
                       id_forma_pago = p_id_forma_pago,
                       -- Centinela: -1 (el defecto) deja el concepto que ya tenia la
                       -- compra; 0 o nulo lo borran (sin concepto); otro pone ese
                       -- concepto. Es lo que cierra la fuga de guardar un borrador y
                       -- perder el ISLR.
                       id_concepto_islr = case when p_id_concepto_islr = -1
                                             then id_concepto_islr
                                             else nullif(p_id_concepto_islr, 0) end,
                       modificado_por = p_usuario, fecha_modificacion = systimestamp
                 where id_compra = p_id_compra
                   -- Defensa en profundidad: el documento tiene que ser de la empresa
                   -- que se esta guardando. El id llega del navegador y no esta
                   -- protegido; sin este predicado un POST con el id de una compra ajena
                   -- la reescribia y le cambiaba la empresa.
                   and id_empresa = p_id_empresa;
                if sql%rowcount = 0 then
                    raise_application_error(-20003,
                        'No tiene permisos sobre esta compra.');
                end if;
            exception
                when dup_val_on_index then
                    raise_application_error(-20080,
                        'Ya existe la factura ' || v_folio || ' de este proveedor.');
            end;

            -- Si la TASA de la cabecera cambio en un borrador, el detalle se queda con
            -- la vieja y los dos comprobantes salen en monedas distintas: el de IVA usa
            -- la tasa de la LINEA (compras_det.tasa_cambio_aplicada) y el de ISLR la de
            -- la CABECERA. Se reprecian las lineas del borrador en el mismo guardado;
            -- un documento que ya no es BORRADOR no llega aqui (arriba se corta).
            if nvl(v_tasa_ant, 1) <> nvl(v_tasa, 1) then
                update compras_det set tasa_cambio_aplicada = v_tasa,
                       subtotal_bs = round(nvl(subtotal_linea, 0) * v_tasa, 2),
                       total_bs = round(nvl(total_linea, 0) * v_tasa, 2)
                 where id_compra = p_id_compra;
            end if;
        end if;
    end prc_guardar_compra;

    procedure prc_registrar_compra(p_id_compra in number, p_usuario in varchar2) is
        v_estado  varchar2(20);
        v_tipo    varchar2(10);
        v_empresa number;
        v_lineas  number;
        v_idret   number;
        v_es_spe  varchar2(1);
        v_genera  varchar2(1);
        v_moneda  varchar2(3);
        v_tc      number;
        v_total   number;
        v_dias    number;
        v_igtf    number;
    begin
        select estado, nvl(tipo_documento, 'FAC'), id_empresa
          into v_estado, v_tipo, v_empresa
          from compras where id_compra = p_id_compra for update;

        -- La compra es de OTRA empresa si el usuario no la administra. Se valida en el
        -- package y ANTES de tocar nada: registrar quema la numeracion de ESA empresa
        -- (los comprobantes de IVA e ISLR consumen RETENCION_CONTADOR) y el id llega
        -- del navegador sin proteger. Los procesos de la pagina solo miran el rol.
        if not fn_usuario_empresa_valida(p_usuario, v_empresa) then
            raise_application_error(-20003, 'No tiene permisos sobre esta compra.');
        end if;

        if v_estado <> 'BORRADOR' then
            raise_application_error(-20083,
                'La compra esta ' || v_estado || ': no se puede registrar.');
        end if;

        select count(*) into v_lineas from compras_det where id_compra = p_id_compra;
        if v_lineas = 0 then
            raise_application_error(-20085,
                'La compra no tiene lineas: agrega al menos una antes de registrarla.');
        end if;

        -- Fotos historicas (2026-11-21): el IGTF del documento y el vencimiento se
        -- congelan AHORA. Cambiar despues la marca SPE, la forma de pago o la tasa
        -- del dia no puede mover la deuda de un documento ya cerrado.
        select nvl(e.es_spe, 'N'), nvl(c.cod_moneda, 'VES'),
               nvl(nullif(c.tipo_cambio, 0), 1), nvl(c.monto_total, 0),
               nvl(fp.genera_igtf, 'N'), nvl(p.dias_credito, 0)
          into v_es_spe, v_moneda, v_tc, v_total, v_genera, v_dias
          from compras c
          join empresas e on e.id_empresa = c.id_empresa
          left join forma_pago fp on fp.id_forma_pago = c.id_forma_pago
          left join proveedores p on p.id_proveedor = c.id_proveedor
         where c.id_compra = p_id_compra;

        v_igtf := 0;
        if v_es_spe = 'S' and v_genera = 'S'
           and upper(v_moneda) not in ('VES', 'BS') then
            v_igtf := round(round(v_total * nvl(fn_alicuota_igtf(v_empresa), 0) / 100, 2) * v_tc, 2);
        end if;

        update compras set estado = 'REGISTRADA', igtf_bs = v_igtf, fecha_vencimiento = nvl(fecha_vencimiento, nvl(fecha_emision, trunc(sysdate)) + v_dias), modificado_por = p_usuario, fecha_modificacion = systimestamp where id_compra = p_id_compra;

        -- El inventario se mueve con la compra REGISTRADA (2026-11-24), nunca en
        -- borrador. Va antes de los comprobantes y en la misma transaccion: si el
        -- kardex falla, la compra no queda registrada sin existencias.
        pkg_inventario.prc_desde_compra(p_id_compra, p_usuario);

        -- SOLO LAS FACTURAS EMITEN COMPROBANTE (decision del dueno, 2026-11-19): una
        -- nota de credito o de debito no emite, no consume numeracion y no toca el
        -- comprobante de la factura original. Antes la nota emitia un comprobante de
        -- IVA por el importe de la nota y en positivo, lo que sobre-retiene.
        if v_tipo = 'FAC' then
            pkg_retenciones.prc_emitir(p_id_compra, v_idret, p_usuario);
            pkg_retenciones.prc_emitir_islr(p_id_compra, v_idret, p_usuario);
        else
            -- Una nota cambia la deuda de la factura que acredita (2026-11-22):
            -- su estado se recalcula aqui o quedaria PAGADA con saldo pendiente.
            declare
                v_origen number;
            begin
                select c.id_compra_origen into v_origen
                  from compras c where c.id_compra = p_id_compra;
                pkg_pagos.prc_recalcular_compra(v_origen);
            exception
                when no_data_found then
                    null;
            end;
        end if;
    exception
        when no_data_found then
            raise_application_error(-20085, 'La compra ' || p_id_compra || ' no existe.');
    end prc_registrar_compra;

    procedure prc_anular_compra(p_id_compra in number, p_usuario in varchar2) is
        v_estado  varchar2(20);
        v_empresa number;
        v_pagos   number;
        v_notas   number;
    begin
        select estado, id_empresa into v_estado, v_empresa
          from compras where id_compra = p_id_compra for update;

        -- Anular es escritura: sin esta guarda un POST con el id de una compra ajena
        -- la anulaba (y de paso los comprobantes de retencion de esa empresa).
        if not fn_usuario_empresa_valida(p_usuario, v_empresa) then
            raise_application_error(-20003, 'No tiene permisos sobre esta compra.');
        end if;

        if v_estado = 'ANULADA' then
            return;
        end if;

        -- Con dinero de por medio no se anula a ciegas (2026-11-21): si hay pagos
        -- vivos, primero se anulan ellos (que liberan las compras).
        select count(*) into v_pagos
          from pagos_detalle d
          join pagos pg on pg.id_pago = d.id_pago
         where d.id_compra = p_id_compra
           and pg.estado = 'ACTIVO';

        if v_pagos > 0 then
            raise_application_error(-20118,
                'La compra ' || p_id_compra || ' tiene ' || v_pagos
                || ' pagos activos. Anulalos primero para poder anular la compra.');
        end if;

        -- Una nota registrada ya movio inventario (devolvio o sumo mercancia):
        -- anular la compra primero dejaria el saldo corto.
        select count(*) into v_notas
          from compras
         where id_compra_origen = p_id_compra
           and estado = 'REGISTRADA'
           and tipo_documento in ('NC', 'ND');
        if v_notas > 0 then
            raise_application_error(-20156,
                'La compra ' || p_id_compra || ' tiene ' || v_notas
                || ' nota(s) registrada(s): anulalas primero.');
        end if;

        -- El inventario se devuelve al anular (2026-11-24). Antes del cambio de
        -- estado: si el kardex falla, la compra no queda anulada a medias.
        begin
            pkg_inventario.prc_reversar('COMPRA', p_id_compra,
                'Anulacion de la compra ' || p_id_compra, p_usuario);
        exception
            when others then
                if sqlcode between -20999 and -20000 then
                    raise;
                end if;
                prc_log_error(
                    p_usuario   => nvl(p_usuario, v('APP_USER')),
                    p_codigo    => 'ORA-' || lpad(to_char(abs(sqlcode)), 5, '0'),
                    p_mensaje   => 'No se pudo reversar el inventario de la compra',
                    p_detalle   => sqlerrm,
                    p_sentencia => dbms_utility.format_error_backtrace);
                raise_application_error(-20001,
                    'No se pudo anular la compra. Avisa al administrador.');
        end;

        update compras set estado = 'ANULADA', modificado_por = p_usuario,
               fecha_modificacion = systimestamp
         where id_compra = p_id_compra;

        pkg_retenciones.prc_anular(p_id_compra, p_usuario);

        -- si era una nota, la factura que acreditaba vuelve a estar pendiente
        declare
            v_origen number;
        begin
            select c.id_compra_origen into v_origen
              from compras c where c.id_compra = p_id_compra;
            pkg_pagos.prc_recalcular_compra(v_origen);
        exception
            when no_data_found then
                null;
        end;
    exception
        when no_data_found then
            raise_application_error(-20085, 'La compra ' || p_id_compra || ' no existe.');
    end prc_anular_compra;

end pkg_compras;
/


-- =============================================================================
-- PKG_FACTURACION — body con el gancho de la factura
-- =============================================================================

create or replace PACKAGE BODY pkg_facturacion AS

    ---------------------------------------------------------------------------
    -- El saldo de la factura cambia cuando se procesa o se anula una NOTA sobre
    -- ella; su estado tiene que decirlo: PAGADA si no queda saldo, TIMBRADA si no
    -- hay cobros y vuelve a haber saldo, PARCIAL si hay cobros parciales. Es un
    -- recalculo del SISTEMA, no del usuario, asi que al revertir un PAGADA usa la
    -- escotilla del trigger de transiciones (SYPEX_FORZAR_ESTADO).
    ---------------------------------------------------------------------------
    PROCEDURE actualiza_estado_origen (p_id_factura IN NUMBER, p_usuario IN VARCHAR2) IS
        v_estado facturas.estado%TYPE;
        v_saldo  NUMBER;
        v_cobros NUMBER;
        v_nuevo  facturas.estado%TYPE;
    BEGIN
        IF p_id_factura IS NULL THEN RETURN; END IF;

        BEGIN
            SELECT UPPER(estado) INTO v_estado FROM facturas WHERE id_factura = p_id_factura;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN RETURN;
        END;
        IF v_estado = 'ANULADA' THEN RETURN; END IF;

        v_saldo := NVL(fn_saldo_factura(p_id_factura), 0);
        SELECT COUNT(*) INTO v_cobros
          FROM recibos
         WHERE id_factura = p_id_factura AND estado = 'ACTIVO';

        v_nuevo := CASE WHEN v_saldo <= 0.01 THEN 'PAGADA'
                        WHEN v_cobros = 0      THEN 'TIMBRADA'
                        ELSE 'PARCIAL' END;
        IF v_nuevo = v_estado THEN RETURN; END IF;

        dbms_application_info.set_client_info('SYPEX_FORZAR_ESTADO');
        UPDATE facturas SET
               estado             = v_nuevo,
               fecha_modificacion = SYSDATE,
               modificado_por     = NVL(p_usuario, v('APP_USER'))
         WHERE id_factura = p_id_factura;
        dbms_application_info.set_client_info(NULL);
    END actualiza_estado_origen;

    -- Si el documento es una nota con factura de origen, recalcula el estado de esa
    -- factura. Nunca tumba la operacion: es un remate, no el objetivo del proceso.
    PROCEDURE remata_origen (p_id_factura IN NUMBER, p_usuario IN VARCHAR2) IS
        v_origen NUMBER;
    BEGIN
        BEGIN
            SELECT id_factura_origen INTO v_origen
              FROM facturas WHERE id_factura = p_id_factura;
        EXCEPTION
            WHEN OTHERS THEN RETURN;
        END;
        IF v_origen IS NOT NULL THEN
            actualiza_estado_origen(v_origen, p_usuario);
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            NULL;
    END remata_origen;

--------------------------------------------------------------------------------
-- 1. IMPLEMENTACIÓN DE INSERCIÓN
--------------------------------------------------------------------------------
    PROCEDURE prc_insertar (
        p_id_factura        IN OUT NUMBER,
        p_id_empresa        IN NUMBER,
        p_folio_factura     IN VARCHAR2,
        p_id_cliente        IN NUMBER,
        p_id_presupuesto    IN NUMBER,
        p_rfc_emisor        IN VARCHAR2,
        p_rfc_receptor      IN VARCHAR2,
        p_uuid_fiscal       IN VARCHAR2,
        p_uso_cfdi          IN VARCHAR2,
        p_forma_pago        IN VARCHAR2,
        p_metodo_pago       IN VARCHAR2,
        p_condicion_pago    IN VARCHAR2,
        p_fecha_emision     IN VARCHAR2,
        p_fecha_vencimiento IN VARCHAR2,
        p_estado            IN VARCHAR2,
        p_subtotal          IN NUMBER,
        p_monto_impuesto    IN NUMBER,
        p_monto_total       IN NUMBER,
        p_observaciones     IN VARCHAR2,
        p_cod_moneda        IN VARCHAR2,
        p_tipo_cambio       IN NUMBER,
        p_usuario           IN VARCHAR2,
        p_tipo_documento    IN VARCHAR2 DEFAULT 'FAC',
        p_nro_control       IN VARCHAR2 DEFAULT NULL,
        p_id_factura_origen IN NUMBER DEFAULT NULL
    ) IS
    BEGIN
        -- El cliente tiene que ser de la MISMA empresa que la factura.
        if p_id_cliente is not null then
            declare
                v_hay number;
            begin
                select count(*) into v_hay
                  from clientes c
                 where c.id_cliente = p_id_cliente
                   and c.id_empresa = p_id_empresa;
                if v_hay = 0 then
                    raise_application_error(-20029,
                        'El cliente no es de la empresa de la factura.');
                end if;
            end;
        end if;

        INSERT INTO facturas (
            id_empresa, folio_factura, id_cliente, id_presupuesto, rfc_emisor, 
            rfc_receptor, uuid_fiscal, uso_cfdi, forma_pago, metodo_pago, 
            condicion_pago, creado_por,
            fecha_emision, fecha_vencimiento, estado, subtotal, monto_impuesto, 
            monto_total, observaciones, cod_moneda, tipo_cambio, tipo_documento,
            nro_control, id_factura_origen
        ) VALUES (
            p_id_empresa, p_folio_factura, p_id_cliente, p_id_presupuesto, p_rfc_emisor,
            p_rfc_receptor, p_uuid_fiscal, p_uso_cfdi, p_forma_pago, p_metodo_pago,
            p_condicion_pago, p_usuario,
            CASE WHEN p_fecha_emision IS NOT NULL THEN TO_DATE(p_fecha_emision, 'DD/MM/YYYY') ELSE SYSDATE END,
            CASE WHEN p_fecha_vencimiento IS NOT NULL THEN TO_DATE(p_fecha_vencimiento, 'DD/MM/YYYY') ELSE NULL END,
            NVL(p_estado, 'PENDIENTE'), p_subtotal, p_monto_impuesto,
            p_monto_total, p_observaciones, NVL(p_cod_moneda, 'USD'), p_tipo_cambio,
            NVL(UPPER(TRIM(p_tipo_documento)), 'FAC'),
            p_nro_control, p_id_factura_origen
        ) RETURN id_factura INTO p_id_factura;
    END prc_insertar;

--------------------------------------------------------------------------------
-- 2. IMPLEMENTACIÓN DE ACTUALIZACIÓN
--------------------------------------------------------------------------------
    PROCEDURE prc_actualizar (
        p_id_factura        IN NUMBER,
        p_id_empresa        IN NUMBER,
        p_folio_factura     IN VARCHAR2,
        p_id_cliente        IN NUMBER,
        p_id_presupuesto    IN NUMBER,
        p_rfc_emisor        IN VARCHAR2,
        p_rfc_receptor      IN VARCHAR2,
        p_uuid_fiscal       IN VARCHAR2,
        p_uso_cfdi          IN VARCHAR2,
        p_forma_pago        IN VARCHAR2,
        p_metodo_pago       IN VARCHAR2,
        p_condicion_pago    IN VARCHAR2,
        p_fecha_emision     IN VARCHAR2,
        p_fecha_vencimiento IN VARCHAR2,
        p_estado            IN VARCHAR2,
        p_subtotal          IN NUMBER,
        p_monto_impuesto    IN NUMBER,
        p_monto_total       IN NUMBER,
        p_observaciones     IN VARCHAR2,
        p_cod_moneda        IN VARCHAR2,
        p_tipo_cambio       IN NUMBER,
        p_tipo_documento    IN VARCHAR2 DEFAULT 'FAC',
        p_nro_control       IN VARCHAR2 DEFAULT NULL,
        p_id_factura_origen IN NUMBER DEFAULT NULL
    ) IS
        v_folio  facturas.folio_factura%type;
        v_estado facturas.estado%type;
    BEGIN
        -- Seguridad: la factura existente tiene que ser de una empresa del usuario. Sin esto
        -- un POST con un id ajeno la reescribiria y le cambiaria la empresa.
        if apex_application.g_user is not null
           and not fn_factura_propio(p_id_factura, apex_application.g_user) then
            raise_application_error(-20003,
                'Esa factura no es de una empresa suya: no se puede modificar.');
        end if;

        -- El cliente tiene que ser de la MISMA empresa que la factura.
        if p_id_cliente is not null then
            declare
                v_hay number;
            begin
                select count(*) into v_hay
                  from clientes c
                 where c.id_cliente = p_id_cliente
                   and c.id_empresa = p_id_empresa;
                if v_hay = 0 then
                    raise_application_error(-20029,
                        'El cliente no es de la empresa de la factura.');
                end if;
            end;
        end if;

        -- Un documento cerrado no se edita: PAGADA y ANULADA son estados finales.
        -- Para corregirlo hay que anular la factura y emitir otra.
        IF NOT fn_factura_editable(p_id_factura) THEN
            SELECT folio_factura, UPPER(estado)
              INTO v_folio, v_estado
              FROM facturas
             WHERE id_factura = p_id_factura;

            raise_application_error(-20024,
                'La factura ' || v_folio || ' está ' || v_estado
                || ': no se puede modificar un documento cerrado. '
                || 'Anúlala y emite otra.');
        END IF;

        UPDATE facturas SET
            id_empresa         = p_id_empresa,
            folio_factura      = p_folio_factura,
            tipo_documento     = NVL(UPPER(TRIM(p_tipo_documento)), 'FAC'),
            nro_control        = p_nro_control,
            id_factura_origen  = p_id_factura_origen,
            id_cliente         = p_id_cliente,
            id_presupuesto     = p_id_presupuesto,
            rfc_emisor         = p_rfc_emisor,
            rfc_receptor       = p_rfc_receptor,
            uuid_fiscal        = p_uuid_fiscal,
            uso_cfdi           = p_uso_cfdi,
            forma_pago         = p_forma_pago,
            metodo_pago        = p_metodo_pago,
            condicion_pago     = p_condicion_pago,
            fecha_emision      = CASE WHEN p_fecha_emision IS NOT NULL THEN TO_DATE(p_fecha_emision, 'DD/MM/YYYY') ELSE SYSDATE END,
            fecha_vencimiento  = CASE WHEN p_fecha_vencimiento IS NOT NULL THEN TO_DATE(p_fecha_vencimiento, 'DD/MM/YYYY') ELSE NULL END,
            estado             = NVL(p_estado, 'PENDIENTE'),
            subtotal           = p_subtotal,
            monto_impuesto     = p_monto_impuesto,
            monto_total        = p_monto_total,
            observaciones      = p_observaciones,
            cod_moneda         = NVL(p_cod_moneda, 'USD'),
            tipo_cambio        = p_tipo_cambio
        WHERE id_factura = p_id_factura;
    END prc_actualizar;

--------------------------------------------------------------------------------
-- 3. PROCESAR PRESUPUESTO (CON RECÁLCULO POR TASA DEL DÍA)
--------------------------------------------------------------------------------
  PROCEDURE prc_procesar_presupuesto_factura (
        p_id_presupuesto_str IN VARCHAR2,
        p_fecha_emision_str  IN VARCHAR2,
        p_id_factura         IN NUMBER,
        p_es_vencido         OUT VARCHAR2,
        p_id_empresa         OUT VARCHAR2,
        p_id_cliente         OUT VARCHAR2,
        p_subtotal           OUT VARCHAR2,
        p_monto_impuesto     OUT VARCHAR2,
        p_monto_total        OUT VARCHAR2,
        p_cod_moneda         OUT VARCHAR2,
        p_tipo_cambio        OUT VARCHAR2,
        p_observaciones      OUT VARCHAR2
    ) AS
        v_id_presupuesto     NUMBER;
        v_fecha_emision      DATE;
        v_vencimiento        DATE;
        v_tasa               NUMBER(14,6) := 1;
        v_tasa_presupuesto   NUMBER(14,6) := 1;
        v_factor             NUMBER(14,6) := 1;
    BEGIN
        p_es_vencido := 'N';
        v_id_presupuesto := TO_NUMBER(REGEXP_SUBSTR(p_id_presupuesto_str, '^[0-9]+') DEFAULT NULL ON CONVERSION ERROR);

        IF v_id_presupuesto IS NOT NULL THEN
            IF p_fecha_emision_str IS NULL THEN
                v_fecha_emision := TRUNC(SYSDATE);
            ELSE
                v_fecha_emision := TO_DATE(SUBSTR(p_fecha_emision_str, 1, 10) DEFAULT NULL ON CONVERSION ERROR, 'DD/MM/YYYY');
                IF v_fecha_emision IS NULL THEN
                    v_fecha_emision := TRUNC(SYSDATE);
                END IF;
            END IF;

            -- 1. Validar fecha de vencimiento del presupuesto
            SELECT fecha_vencimiento
              INTO v_vencimiento
              FROM presupuestos
             WHERE id_presupuesto = v_id_presupuesto;

            IF TRUNC(v_vencimiento) < TRUNC(v_fecha_emision) THEN
                p_es_vencido := 'Y';
                p_id_empresa := NULL;
                p_id_cliente := NULL;
                p_subtotal := NULL;
                p_monto_impuesto := NULL;
                p_monto_total := NULL;
                p_cod_moneda := NULL;
                p_tipo_cambio := NULL;
                p_observaciones := NULL;
            ELSE
                -- 2. Obtener moneda y tasa original del presupuesto para calcular la diferencia
                SELECT p.cod_moneda, NVL(p.tipo_cambio, 1)
                  INTO p_cod_moneda, v_tasa_presupuesto
                  FROM presupuestos p
                 WHERE p.id_presupuesto = v_id_presupuesto;

                IF v_tasa_presupuesto <= 0 THEN v_tasa_presupuesto := 1; END IF;

                IF p_cod_moneda IN ('VES', 'BS') THEN
                    v_tasa := 1;
                ELSE
                    BEGIN
                        -- Buscar la tasa vigente exacta para la fecha de emisión[cite: 4]
                        SELECT tasa_cambio  
                          INTO v_tasa  
                          FROM tipo_cambio  
                         WHERE moneda_origen = p_cod_moneda  
                           AND moneda_destino = 'VES'
                           AND tipo_tasa = 'REAL'
                           AND fecha_vigencia = v_fecha_emision;
                    EXCEPTION
                        WHEN NO_DATA_FOUND THEN
                            BEGIN
                                -- Si no existe exacta, buscar la más reciente anterior o igual[cite: 4]
                                SELECT tasa_cambio  
                                  INTO v_tasa  
                                  FROM (SELECT tasa_cambio  
                                          FROM tipo_cambio  
                                         WHERE moneda_origen = p_cod_moneda  
                                           AND moneda_destino = 'VES'
                                           AND tipo_tasa = 'REAL'
                                           AND fecha_vigencia <= v_fecha_emision  
                                         ORDER BY fecha_vigencia DESC)
                                 WHERE ROWNUM = 1;
                            EXCEPTION
                                WHEN OTHERS THEN v_tasa := v_tasa_presupuesto; 
                            END;
                        WHEN OTHERS THEN 
                            v_tasa := v_tasa_presupuesto;
                    END;
                END IF;

                -- Calcular el factor de proporción entre la tasa nueva y la vieja
                v_factor := v_tasa / v_tasa_presupuesto;

                -- 3. Cargar datos principales aplicando el factor de conversión
                SELECT TO_CHAR(p.id_empresa),
                       TO_CHAR(p.id_cliente),
                       TO_CHAR(p.subtotal * v_factor, 'FM9999999990.00'),
                       TO_CHAR(p.impuesto_iva * v_factor, 'FM9999999990.00'),
                       TO_CHAR(p.total * v_factor, 'FM9999999990.00'),
                       p.cod_moneda,
                       TO_CHAR(v_tasa, 'FM9999999990.0000'),
                       p.observaciones
                  INTO p_id_empresa,
                       p_id_cliente,
                       p_subtotal,
                       p_monto_impuesto,
                       p_monto_total,
                       p_cod_moneda,
                       p_tipo_cambio,
                       p_observaciones
                  FROM presupuestos p
                 WHERE p.id_presupuesto = v_id_presupuesto;

                -- 4. Reconstruir el detalle de la factura aplicando también el factor a las líneas.
                --    El INSERT vive en PKG_FACTURA_DETALLE: un solo package escribe en FACTURAS_DET.
                IF p_id_factura IS NOT NULL THEN
                    pkg_factura_detalle.reemplazar_desde_presupuesto(
                        p_id_factura     => p_id_factura,
                        p_id_presupuesto => v_id_presupuesto,
                        p_factor         => v_factor,
                        p_tasa_cambio    => v_tasa,
                        p_usuario        => v('APP_USER'));
                END IF;
            END IF;
        ELSE
            p_id_empresa := NULL;
            p_id_cliente := NULL;
            p_subtotal := NULL;
            p_monto_impuesto := NULL;
            p_monto_total := NULL;
            p_cod_moneda := NULL;
            p_tipo_cambio := NULL;
            p_observaciones := NULL;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            p_es_vencido := 'N';
    END prc_procesar_presupuesto_factura;

--------------------------------------------------------------------------------
-- 4. ORQUESTADOR DE GUARDADO
--------------------------------------------------------------------------------
    PROCEDURE prc_guardar_factura (
        p_id_factura         IN OUT NUMBER,
        p_id_empresa         IN NUMBER,
        p_folio_factura      IN VARCHAR2,
        p_id_cliente         IN NUMBER,
        p_id_presupuesto     IN NUMBER,
        p_rfc_emisor         IN VARCHAR2,
        p_rfc_receptor       IN VARCHAR2,
        p_uuid_fiscal        IN VARCHAR2,
        p_uso_cfdi           IN VARCHAR2,
        p_forma_pago         IN VARCHAR2,
        p_metodo_pago        IN VARCHAR2,
        p_condicion_pago     IN VARCHAR2,
        p_fecha_emision      IN VARCHAR2,
        p_fecha_vencimiento  IN VARCHAR2,
        p_estado             IN VARCHAR2,
        p_subtotal           IN NUMBER,       
        p_monto_impuesto     IN NUMBER,       
        p_monto_total        IN NUMBER,       
        p_observaciones      IN VARCHAR2,
        p_cod_moneda         IN VARCHAR2,
        p_tipo_cambio        IN NUMBER,       
        p_usuario            IN VARCHAR2,
        p_tipo_documento     IN VARCHAR2 DEFAULT 'FAC',
        p_nro_control        IN VARCHAR2 DEFAULT NULL,
        p_id_factura_origen  IN NUMBER DEFAULT NULL,
        p_fecha_referencia   IN DATE DEFAULT NULL,
        p_porcentaje_retencion       IN NUMBER DEFAULT NULL,
        p_nro_comprobante_retencion  IN VARCHAR2 DEFAULT NULL
    ) AS
        v_tipo_cambio    NUMBER;
        v_tipo_doc       VARCHAR2(10) := NVL(UPPER(TRIM(p_tipo_documento)), 'FAC');
        v_folio          VARCHAR2(50);
        v_subtotal       NUMBER;
        v_monto_impuesto NUMBER;
        v_monto_total    NUMBER;
        v_id_empresa     NUMBER := NVL(p_id_empresa, 1);
        v_existe         NUMBER := 0;
        v_fecha          DATE;
        v_nro_control    VARCHAR2(60);
        v_pct_retencion  NUMBER;
        v_ret_bs         NUMBER;
    BEGIN
    -- Seguridad: la empresa debe pertenecer al usuario de la sesion APEX
    if apex_application.g_user is not null
       and not fn_usuario_empresa_valida(apex_application.g_user, p_id_empresa) then
        raise_application_error(-20003, 'No tiene acceso a la empresa indicada.');
    end if;

        -- La tasa llega ya como numero: no se pasa por fn_clean_num (TO_CHAR + el
        -- validador de texto anulaba las tasas de 6 decimales, como 47,910741, y
        -- el INSERT moria con ORA-01400 en TIPO_CAMBIO).
        v_tipo_cambio    := p_tipo_cambio;
        v_subtotal       := fn_clean_num(TO_CHAR(p_subtotal));
        v_monto_impuesto := fn_clean_num(TO_CHAR(p_monto_impuesto));
        v_monto_total    := fn_clean_num(TO_CHAR(p_monto_total));

        -- Editar sin tocar la tasa conserva la que ya tenia el documento; una
        -- tasa nueva (o una alta) se valida en fn_validar_tasa_documento.
        IF (v_tipo_cambio IS NULL OR v_tipo_cambio <= 0)
           AND p_id_factura IS NOT NULL AND p_id_factura > 0 THEN
            SELECT MAX(tipo_cambio)
              INTO v_tipo_cambio
              FROM facturas 
             WHERE id_factura = p_id_factura;
        END IF;

        BEGIN
            v_fecha := TO_DATE(p_fecha_emision, 'DD/MM/YYYY');
        EXCEPTION
            WHEN OTHERS THEN
                v_fecha := SYSDATE;
        END;

        IF v_fecha IS NULL THEN
            v_fecha := SYSDATE;
        END IF;

        v_tipo_cambio := fn_validar_tasa_documento(p_cod_moneda, v_fecha, v_tipo_cambio,
                                                   p_fecha_referencia);

        -- Tope de la nota de credito: la suma de las notas de credito no anuladas
        -- de esa factura (sin contar esta) mas el total de esta no puede pasar el
        -- total de la factura que acredita.
        IF v_tipo_doc = 'NC' AND p_id_factura_origen IS NOT NULL THEN
            DECLARE
                v_origen_total NUMBER;
                v_ya_credito   NUMBER;
            BEGIN
                SELECT monto_total INTO v_origen_total
                  FROM facturas WHERE id_factura = p_id_factura_origen;

                SELECT NVL(SUM(f.monto_total), 0) INTO v_ya_credito
                  FROM facturas f
                 WHERE f.tipo_documento = 'NC'
                   AND f.estado <> 'ANULADA'
                   AND f.id_factura_origen = p_id_factura_origen
                   AND f.id_factura <> NVL(p_id_factura, 0);

                IF v_ya_credito + v_monto_total > v_origen_total + 0.01 THEN
                    raise_application_error(-20049,
                        'La nota deja el total acreditado en '
                        || TO_CHAR(v_ya_credito + v_monto_total, 'FM999G999G990D00')
                        || ' y la factura que acredita vale '
                        || TO_CHAR(v_origen_total, 'FM999G999G990D00')
                        || '. No se puede acreditar mas de lo facturado.');
                END IF;
            END;
        END IF;

        IF v_id_empresa <= 0 THEN
            v_id_empresa := 1;
        END IF;

        IF p_id_factura IS NOT NULL AND p_id_factura > 0 THEN
            SELECT COUNT(1) 
              INTO v_existe 
              FROM facturas 
             WHERE id_factura = p_id_factura;
        END IF;  

        -- Numero de control: en las facturas sale del rango de la providencia
        -- (EMPRESA_FISCAL). Si se teclea, se valida contra el rango; si no, se
        -- asigna el siguiente y se consume el contador atomico. Las notas llevan
        -- el que se teclee (cada serie de notas se controla aparte).
        IF v_tipo_doc = 'FAC' THEN
            IF p_nro_control IS NOT NULL THEN
                v_nro_control := fn_control_en_rango(v_id_empresa, p_nro_control);
            ELSIF v_existe > 0 THEN
                SELECT nro_control INTO v_nro_control
                  FROM facturas WHERE id_factura = p_id_factura;
            ELSE
                v_nro_control := fn_asignar_control(v_id_empresa);
            END IF;
        ELSE
            v_nro_control := p_nro_control;
        END IF;


        IF v_existe > 0 THEN
            prc_actualizar(
                p_id_factura        => p_id_factura,
                p_id_empresa        => v_id_empresa,
                p_folio_factura     => p_folio_factura,
                p_id_cliente        => p_id_cliente,
                p_id_presupuesto    => p_id_presupuesto,
                p_rfc_emisor        => p_rfc_emisor,
                p_rfc_receptor      => p_rfc_receptor,
                p_uuid_fiscal       => p_uuid_fiscal,
                p_uso_cfdi          => p_uso_cfdi,
                p_forma_pago        => p_forma_pago,
                p_metodo_pago       => p_metodo_pago,
                p_condicion_pago    => p_condicion_pago,
                p_fecha_emision     => p_fecha_emision,
                p_fecha_vencimiento => p_fecha_vencimiento,
                p_estado            => p_estado,
                p_subtotal          => v_subtotal,
                p_monto_impuesto    => v_monto_impuesto,
                p_monto_total       => v_monto_total,
                p_observaciones     => p_observaciones,
                p_cod_moneda        => p_cod_moneda,
                p_tipo_cambio       => v_tipo_cambio,
                p_tipo_documento    => v_tipo_doc,
                p_nro_control       => v_nro_control,
                p_id_factura_origen => p_id_factura_origen
            );
        ELSE
            p_id_factura := NULL;
            -- El folio lo asigna el contador de la empresa por tipo de documento
            -- (FAC / NC / ND): el que trae la pagina es solo vista previa.
            v_folio := fn_asignar_folio(v_id_empresa, v_tipo_doc);
            prc_insertar(
                p_id_factura        => p_id_factura,
                p_id_empresa        => v_id_empresa,
                p_folio_factura     => v_folio,
                p_id_cliente        => p_id_cliente,
                p_id_presupuesto    => p_id_presupuesto,
                p_rfc_emisor        => p_rfc_emisor,
                p_rfc_receptor      => p_rfc_receptor,
                p_uuid_fiscal       => p_uuid_fiscal,
                p_uso_cfdi          => p_uso_cfdi,
                p_forma_pago        => p_forma_pago,
                p_metodo_pago       => p_metodo_pago,
                p_condicion_pago    => p_condicion_pago,
                p_fecha_emision     => p_fecha_emision,
                p_fecha_vencimiento => p_fecha_vencimiento,
                p_estado            => p_estado,
                p_subtotal          => v_subtotal,
                p_monto_impuesto    => v_monto_impuesto,
                p_monto_total       => v_monto_total,
                p_observaciones     => p_observaciones,
                p_cod_moneda        => p_cod_moneda,
                p_tipo_cambio       => v_tipo_cambio,
                p_usuario           => p_usuario,
                p_tipo_documento    => v_tipo_doc,
                p_nro_control       => v_nro_control,
                p_id_factura_origen => p_id_factura_origen
            );
        END IF;

        -- Retencion de IVA del cliente (2026-11-16). El porcentaje sale del
        -- cliente si la pagina no manda uno; el monto se guarda en bolivares
        -- porque es lo que se declara y lo que dice el comprobante del cliente.
        BEGIN
            IF p_porcentaje_retencion IS NULL THEN
                SELECT CASE WHEN NVL(es_agente_retencion, 'N') = 'S'
                            THEN NVL(porcentaje_retencion, 75) ELSE 0 END
                  INTO v_pct_retencion
                  FROM clientes WHERE id_cliente = p_id_cliente;
            ELSE
                v_pct_retencion := p_porcentaje_retencion;
            END IF;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_pct_retencion := 0;
        END;

        IF v_pct_retencion IS NULL OR v_pct_retencion < 0 OR v_pct_retencion > 100 THEN
            raise_application_error(-20082,
                'El porcentaje de retencion debe estar entre 0 y 100.');
        END IF;

        IF p_nro_comprobante_retencion IS NOT NULL
           AND NOT REGEXP_LIKE(TRIM(p_nro_comprobante_retencion), '^[0-9]{14}$') THEN
            raise_application_error(-20081,
                'El comprobante de retencion del cliente debe tener 14 digitos (AAAAMM + 8).');
        END IF;

        -- El comprobante de retencion NO es obligatorio al emitir: en Venezuela lo
        -- emite el cliente DESPUES de recibir la factura, asi que en el momento de
        -- guardar todavia no existe. Se valida el formato si viene (-20081) y se
        -- guarda cuando llegue; el NVL del UPDATE conserva el que ya tuviera.
        -- El monto se calcula sobre el IVA (sin IGTF) y del detalle real, no del
        -- monto_impuesto que manda la pantalla: en un alta la cabecera llega en 0
        -- porque los totales los pone el detalle (pagina 10).
        v_ret_bs := fn_iva_retenido_bs(p_id_factura, v_pct_retencion, v_tipo_cambio);

        UPDATE facturas SET porcentaje_retencion = v_pct_retencion,
               retencion_iva_bs = v_ret_bs,
               nro_comprobante_retencion = NVL(p_nro_comprobante_retencion, nro_comprobante_retencion)
         WHERE id_factura = p_id_factura;

    EXCEPTION
        WHEN DUP_VAL_ON_INDEX THEN
            RAISE_APPLICATION_ERROR(-20022,
                'El folio ' || nvl(v_folio, p_folio_factura) || ' ya existe para esta empresa. Elige otro numero.');
    END prc_guardar_factura;

--------------------------------------------------------------------------------
-- 5. IMPLEMENTACIÓN DE ANULACIÓN DE FACTURA
--------------------------------------------------------------------------------
    PROCEDURE prc_anular_factura (
        p_id_factura     IN NUMBER,
        p_id_presupuesto IN NUMBER,
        p_usuario        IN VARCHAR2
    ) IS
        v_id_factura     NUMBER := fn_clean_num(TO_CHAR(p_id_factura));
        v_id_presupuesto NUMBER := fn_clean_num(TO_CHAR(p_id_presupuesto));
        v_folio          VARCHAR2(30);
        v_cobros         NUMBER;
        v_estado         VARCHAR2(20);
    BEGIN
        -- Se bloquea la cabecera: dos anulaciones simultaneas no pueden reversar
        -- el inventario dos veces.
        SELECT estado INTO v_estado
          FROM facturas
         WHERE id_factura = v_id_factura
           FOR UPDATE;
        IF v_estado = 'ANULADA' THEN
            RETURN;
        END IF;

        -- Con dinero cobrado no se anula el documento: el cobro queda colgando de
        -- una factura muerta y el arqueo no cuadra. Primero se anulan los cobros
        -- (misma regla que «anula la factura antes de cancelar el presupuesto»).
        SELECT folio_factura,
               (SELECT COUNT(*) FROM recibos r
                 WHERE r.id_factura = v_id_factura AND r.estado = 'ACTIVO')
          INTO v_folio, v_cobros
          FROM facturas
         WHERE id_factura = v_id_factura;

        IF v_cobros > 0 THEN
            RAISE_APPLICATION_ERROR(-20091,
                'La factura ' || v_folio || ' tiene ' || v_cobros
                || CASE WHEN v_cobros = 1 THEN ' cobro registrado' ELSE ' cobros registrados' END
                || ': anula primero los cobros y despues la factura.');
        END IF;

        -- Inventario (2026-11-24): si la factura ya tiene su nota de credito
        -- timbrada, la devolucion del stock la hizo la NC; revertir aqui la salida
        -- la devolveria dos veces. Sin NC, se revierte la salida.
        DECLARE
            v_nc NUMBER;
        BEGIN
            -- Cualquier nota viva (aunque este pendiente) va a devolver el stock:
            -- si se revierte aqui tambien, el articulo entra dos veces.
            SELECT COUNT(*) INTO v_nc
              FROM facturas
             WHERE NVL(id_factura_origen, 0) = v_id_factura
               AND tipo_documento = 'NC'
               AND estado <> 'ANULADA';
            IF v_nc = 0 THEN
                pkg_inventario.prc_reversar('FACTURA', v_id_factura,
                    'Anulacion de la factura ' || v_folio, p_usuario);
            END IF;
        END;

        UPDATE facturas SET
               estado             = 'ANULADA',
               observaciones      = observaciones || ' [ANULADA EL ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI') || ']',
               MODIFICADO_POR     = NVL(p_usuario, v('APP_USER')),
               fecha_modificacion = SYSDATE
         WHERE id_factura         = v_id_factura;

        IF v_id_presupuesto IS NOT NULL AND v_id_presupuesto > 0 THEN
            UPDATE presupuestos SET
                   estado             = 'APROBADO',
                   fecha_modificacion = SYSDATE,
                   MODIFICADO_POR     = NVL(p_usuario, v('APP_USER'))
             WHERE id_presupuesto     = v_id_presupuesto;
        END IF;

        -- Al anular una nota, la factura que acreditaba recupera su saldo.
        remata_origen(v_id_factura, p_usuario);
    EXCEPTION
        WHEN OTHERS THEN
            -- Los errores de negocio (-20xxx) se propagan tal cual: envolverlos
            -- le enseña jerga al usuario y le oculta el motivo (el trigger de
            -- transiciones lanza -20070, por ejemplo).
            IF SQLCODE BETWEEN -20999 AND -20000 THEN
                RAISE;
            END IF;
            -- Sin ROLLBACK: el error se propaga y la transaccion la decide quien
            -- llama (APEX revierte su proceso). El detalle tecnico va al log.
            prc_log_error(
                p_usuario   => nvl(v('APP_USER'), 'SISTEMA'),
                p_codigo    => 'ORA-' || lpad(to_char(abs(SQLCODE)), 5, '0'),
                p_mensaje   => 'No se pudo anular la factura',
                p_detalle   => SQLERRM,
                p_sentencia => dbms_utility.format_error_backtrace);
            raise_application_error(-20001,
                'No se pudo anular la factura. Avisa al administrador.');
    END prc_anular_factura;

--------------------------------------------------------------------------------
-- 6. IMPLEMENTACIÓN DE PROCESAR / TIMBRAR FACTURA
--------------------------------------------------------------------------------
   --------------------------------------------------------------------------------
-- 6. IMPLEMENTACIÓN DE PROCESAR / TIMBRAR FACTURA
--------------------------------------------------------------------------------
    PROCEDURE prc_procesar_factura (
        p_id_factura IN NUMBER,
        p_usuario    IN VARCHAR2
    ) IS
        v_id_factura     NUMBER := fn_clean_num(TO_CHAR(p_id_factura));
        v_id_presupuesto NUMBER;
    BEGIN
        IF v_id_factura IS NULL OR v_id_factura <= 0 THEN
            raise_application_error(-20002, 'Error: El ID de la factura es nulo o inválido.');
        END IF;

        UPDATE facturas SET
               estado             = 'TIMBRADA',
               fecha_modificacion = SYSDATE,
               MODIFICADO_POR     = NVL(p_usuario, v('APP_USER'))
         WHERE id_factura         = v_id_factura;

        IF SQL%ROWCOUNT = 0 THEN
            raise_application_error(-20003, 'No se encontró la factura con ID: ' || v_id_factura);
        END IF;

        -- El inventario se mueve con la factura EMITIDA (2026-11-24) y entra con la
        -- nota de credito. Antes de remata_origen y en la misma transaccion.
        pkg_inventario.prc_desde_factura(v_id_factura, p_usuario);

        BEGIN
            SELECT id_presupuesto
              INTO v_id_presupuesto
              FROM facturas
             WHERE id_factura = v_id_factura;
        EXCEPTION
            WHEN OTHERS THEN
                v_id_presupuesto := NULL;
        END; -- <--- CORREGIDO: Era END IF;, debe ser END;

        IF v_id_presupuesto IS NOT NULL AND v_id_presupuesto > 0 THEN
            UPDATE presupuestos SET
                   estado             = 'FACTURADO',
                   fecha_modificacion = SYSDATE,
                   MODIFICADO_POR     = NVL(p_usuario, v('APP_USER'))
             WHERE id_presupuesto     = v_id_presupuesto;
        END IF;

        -- Si lo procesado es una nota, la factura que acredita cambia de saldo.
        remata_origen(v_id_factura, p_usuario);
    EXCEPTION
        WHEN OTHERS THEN
            -- Sin ROLLBACK, igual que en prc_anular_factura, y con los errores
            -- de negocio propagados tal cual.
            IF SQLCODE BETWEEN -20999 AND -20000 THEN
                RAISE;
            END IF;
            prc_log_error(
                p_usuario   => nvl(v('APP_USER'), 'SISTEMA'),
                p_codigo    => 'ORA-' || lpad(to_char(abs(SQLCODE)), 5, '0'),
                p_mensaje   => 'No se pudo procesar la factura',
                p_detalle   => SQLERRM,
                p_sentencia => dbms_utility.format_error_backtrace);
            raise_application_error(-20003,
                'No se pudo procesar la factura. Avisa al administrador.');
    END prc_procesar_factura;

--------------------------------------------------------------------------------
-- 7. COMPROBANTE DE RETENCION DEL CLIENTE (DOCUMENTO YA EMITIDO)
--------------------------------------------------------------------------------
    -- El comprobante llega dias despues de emitir la factura, cuando ya esta
    -- TIMBRADA/PARCIAL/PAGADA y fn_factura_editable la cierra. Esto NO es una
    -- edicion del documento: solo se anota el numero en su columna. No se toca
    -- el estado, los importes ni RETENCION_IVA_BS (que ya se calculo al emitir).
    PROCEDURE prc_registrar_comprobante_retencion (
        p_id_factura IN NUMBER,
        p_nro        IN VARCHAR2,
        p_usuario    IN VARCHAR2
    ) IS
        v_id_factura NUMBER := fn_clean_num(TO_CHAR(p_id_factura));
        v_empresa    NUMBER;
        v_folio      VARCHAR2(30);
        v_estado     VARCHAR2(20);
    BEGIN
        BEGIN
            SELECT id_empresa, folio_factura, UPPER(estado)
              INTO v_empresa, v_folio, v_estado
              FROM facturas
             WHERE id_factura = v_id_factura;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                raise_application_error(-20085,
                    'La factura ' || p_id_factura || ' no existe.');
        END;

        -- Seguridad primero: sin esto un POST con un id ajeno escribiria el
        -- comprobante en la factura de otra empresa.
        IF NOT fn_usuario_empresa_valida(p_usuario, v_empresa) THEN
            raise_application_error(-20003,
                'No tiene acceso a la empresa indicada.');
        END IF;

        -- Una factura anulada no admite papeles: su comprobante ya no respalda nada.
        IF v_estado = 'ANULADA' THEN
            raise_application_error(-20024,
                'La factura ' || v_folio || ' esta ANULADA: '
                || 'no se puede registrar un comprobante de retencion.');
        END IF;

        IF TRIM(p_nro) IS NULL
           OR NOT REGEXP_LIKE(TRIM(p_nro), '^[0-9]{14}$') THEN
            raise_application_error(-20081,
                'El comprobante de retencion del cliente debe tener 14 digitos (AAAAMM + 8).');
        END IF;

        UPDATE facturas set nro_comprobante_retencion = TRIM(p_nro),
               modificado_por            = p_usuario,
               fecha_modificacion        = SYSTIMESTAMP
         WHERE id_factura = v_id_factura;
    END prc_registrar_comprobante_retencion;

END pkg_facturacion;
/

-- El create or replace del body deja dependientes en INVALID a veces: se recompila.
begin
    dbms_utility.compile_schema('WKSP_SYPEXWS', false);
end;
/

select 'FALLA: ' || object_name || ' (' || object_type || ') quedo invalido' as caso
  from all_objects
 where owner = 'WKSP_SYPEXWS' and status <> 'VALID'
   and object_type in ('FUNCTION','PROCEDURE','PACKAGE','PACKAGE BODY','TRIGGER','VIEW');
/

commit;
/
