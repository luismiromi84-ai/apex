-- =============================================================================
-- 20261122_favor_disponible.sql
--
-- pkg_pagos.fn_favor_disponible: el credito del proveedor que se puede aplicar
-- YA (pagos ACTIVOS y NO conciliados), que es el mismo conjunto que consume
-- prc_usar_favor. La pantalla 37 lo ofrece en la tabla de facturas abiertas.
--
-- Se anade a fn_saldo_favor_proveedor, que cuenta tambien los pagos conciliados
-- y por eso no sirve para decidir si el boton "Usar credito" tiene sentido.
--
-- Incluye spec y body completos (concatenados de package/ y package_bodies/)
-- y valida al final. Idempotente.
--
-- Uso:
--   python deploy/conexion/importar_export.py deploy/migrations/20261122_favor_disponible.sql
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

-- =============================================================================
-- pkg_pagos.sql
--
-- Pagos a proveedores (2026-11-21). Espejo de pkg_cobros del lado del dinero que
-- sale: cabecera (PAGOS) + reparto a facturas de compra (PAGOS_DETALLE).
--
-- Reglas que viven aqui (no en la pantalla):
--   - Un pago se aplica a varias compras y una compra se cancela con varios pagos.
--   - Un pago SIN aplicaciones es un anticipo: su monto queda como saldo a favor.
--   - Lo aplicado nunca supera el saldo de la compra ni el monto del pago.
--   - Nada se borra: se anula, y al anularse las compras vuelven a estar pendientes.
--   - Un pago conciliado no se anula ni recibe aplicaciones sin desmarcarlo.
--
-- El saldo de la compra sale de fn_saldo_compra (formula unica del sistema).
-- =============================================================================

create or replace package pkg_pagos as

    -- Registra un pago con su reparto, en una sola transaccion.
    -- p_aplicaciones es JSON: [{"id_compra":123,"monto":895.00}, ...] y puede
    -- llegar nulo (anticipo). El monto de cada aplicacion va en la MONEDA DE LA
    -- COMPRA. La forma que devuelve fn_reparto_sugerido, asi que la pantalla lo
    -- reenvia tal cual.
    procedure prc_registrar_pago (
        p_id_proveedor   in  number,
        p_fecha          in  date,
        p_moneda         in  varchar2,
        p_tasa           in  number,
        p_monto          in  number,
        p_id_forma_pago  in  number   default null,
        p_referencia     in  varchar2 default null,
        p_observaciones  in  varchar2 default null,
        p_aplicaciones   in  varchar2 default null,
        p_usuario        in  varchar2,
        p_id_pago        out number
    );

    -- Anula el pago (no lo borra) y devuelve sus compras a pendientes.
    procedure prc_anular_pago (
        p_id_pago in number,
        p_usuario in varchar2
    );

    -- Marca o desmarca la conciliacion bancaria.
    procedure prc_conciliar (
        p_id_pago    in number,
        p_conciliado in char,
        p_usuario    in varchar2
    );

    -- Aplica el saldo a favor de un pago ya guardado a una compra nueva.
    procedure prc_aplicar_saldo (
        p_id_pago   in number,
        p_id_compra in number,
        p_monto     in number,
        p_usuario   in varchar2
    );

    -- Aplica el saldo a favor del proveedor a una compra, consumiendo primero los
    -- pagos mas antiguos (2026-11-22). Devuelve cuanto se aplico, en la moneda de
    -- la compra. Si no hay saldo a favor lanza -20121.
    procedure prc_usar_favor (
        p_id_proveedor in number,
        p_id_compra    in number,
        p_usuario      in varchar2,
        p_aplicado     out number
    );

    -- Recalcula el estado de una compra segun su saldo (lo llama pkg_compras al
    -- registrar o anular una nota de credito o debito).
    procedure prc_recalcular_compra (
        p_id_compra in number
    );

    -- Propuesta de reparto (no escribe nada): FIFO por fecha de emision, sin
    -- pasarse de cada saldo. Devuelve el mismo JSON que come prc_registrar_pago.
    function fn_reparto_sugerido (
        p_id_proveedor in number,
        p_moneda       in varchar2,
        p_tasa         in number,
        p_monto        in number
    ) return varchar2;

    -- Deuda viva del proveedor (suma de saldos pendientes), en la moneda pedida.
    function fn_saldo_proveedor (
        p_id_proveedor in number,
        p_moneda       in varchar2
    ) return number;

    -- Saldo a favor disponible (pagos activos menos lo aplicado), en la moneda pedida.
    function fn_saldo_favor_proveedor (
        p_id_proveedor in number,
        p_moneda       in varchar2
    ) return number;

    -- Credito que se puede aplicar YA: pagos ACTIVOS y NO conciliados, que es
    -- exactamente el conjunto que consume prc_usar_favor (2026-11-22). La pantalla
    -- ofrece este numero; fn_saldo_favor_proveedor cuenta tambien los conciliados.
    function fn_favor_disponible (
        p_id_proveedor in number,
        p_moneda       in varchar2
    ) return number;

end pkg_pagos;
/

-- =============================================================================
-- pkg_pagos.sql (body)
--
-- Pagos a proveedores (2026-11-21). Toda la logica de dinero del lado de las
-- compras vive aqui; la pantalla solo arma el JSON del reparto.
--
-- Convenciones del repo que se respetan en este body:
--   - Los mensajes van en ASCII (la base no es AL32UTF8).
--   - Los errores de negocio (-20999..-20000) se relanzan tal cual; lo
--     inesperado deja el detalle en SYN_ERROR_LOG con prc_log_error.
--   - No se borra nada: se anula.
-- =============================================================================

create or replace package body pkg_pagos as

    -- -------------------------------------------------------------------------
    -- privadas
    -- -------------------------------------------------------------------------

    -- Saldo a favor libre de un pago, en la MONEDA DEL PAGO.
    function fn_favor_pago (p_id_pago in number) return number is
        v_monto    number;
        v_aplicado number;
    begin
        select nvl(p.monto, 0)
          into v_monto
          from pagos p
         where p.id_pago = p_id_pago;

        select nvl(sum(case
                          when upper(nvl(c.cod_moneda, 'VES')) = upper(nvl(p.cod_moneda, 'VES'))
                          then d.monto_aplicado
                          else d.monto_aplicado * nvl(nullif(c.tipo_cambio, 0), 1)
                               / nvl(nullif(p.tipo_cambio, 0), 1)
                        end), 0)
          into v_aplicado
          from pagos_detalle d
          join pagos p on p.id_pago = d.id_pago
          join compras c on c.id_compra = d.id_compra
         where d.id_pago = p_id_pago;

        return round(v_monto - v_aplicado, 2);
    exception
        when no_data_found then
            return 0;
    end fn_favor_pago;

    -- Tasa en bolivares por unidad de una moneda (1 para VES/BS).
    function fn_tasa_moneda (p_moneda in varchar2) return number is
    begin
        if nvl(upper(p_moneda), 'VES') in ('VES', 'BS') then
            return 1;
        end if;
        return nvl(nullif(fn_tasa_ves(trunc(sysdate), upper(p_moneda)), 0), 1);
    end fn_tasa_moneda;

    -- Recalcula el estado de una compra segun su saldo. BORRADOR y ANULADA no se
    -- tocan: el primero no esta cerrado y la segunda no cuenta.
    procedure recalcula_estado (p_id_compra in number) is
        v_estado  varchar2(20);
        v_importe number;
        v_saldo   number;
    begin
        select c.estado into v_estado
          from compras c
         where c.id_compra = p_id_compra;

        if v_estado in ('BORRADOR', 'ANULADA') then
            return;
        end if;

        v_importe := fn_importe_compra(p_id_compra);
        v_saldo   := fn_saldo_compra(p_id_compra);

        if v_saldo <= 0.01 then
            update compras set estado = 'PAGADA' where id_compra = p_id_compra;
        elsif v_saldo < v_importe - 0.01 then
            update compras set estado = 'PARCIAL' where id_compra = p_id_compra;
        else
            update compras set estado = 'REGISTRADA' where id_compra = p_id_compra;
        end if;
    end recalcula_estado;

    -- Valida una aplicacion contra su compra y devuelve el importe ya expresado
    -- en la moneda del pago (para poder compararlo con el monto).
    function valida_aplicacion (p_id_compra in number,
                                p_id_pago_prov in number,
                                p_monto in number,
                                p_tasa_pago in number,
                                p_id_empresa in number,
                                p_moneda_pago in varchar2) return number is
        v_prov   number;
        v_emp    number;
        v_tc     number;
        v_mon    varchar2(3);
        v_saldo  number;
    begin
        if p_monto is null or p_monto <= 0 then
            raise_application_error(-20110, 'Cada aplicacion debe tener un monto mayor que cero.');
        end if;

        begin
            select c.id_proveedor, c.id_empresa, nvl(nullif(c.tipo_cambio, 0), 1),
                   nvl(c.cod_moneda, 'VES')
              into v_prov, v_emp, v_tc, v_mon
              from compras c
             where c.id_compra = p_id_compra;
        exception
            when no_data_found then
                raise_application_error(-20112,
                    'La compra ' || p_id_compra || ' no existe o no es de esta empresa.');
        end;

        if v_prov <> p_id_pago_prov or v_emp <> p_id_empresa then
            raise_application_error(-20112,
                'La compra ' || p_id_compra || ' no es de este proveedor o de esta empresa.');
        end if;

        if fn_compra_pagable(p_id_compra) <> 'S' then
            raise_application_error(-20115,
                'La compra ' || p_id_compra || ' no se puede pagar: solo las registradas o abonadas con saldo.');
        end if;

        v_saldo := fn_saldo_compra(p_id_compra);
        if p_monto > v_saldo + 0.01 then
            raise_application_error(-20111,
                'Lo aplicado a la compra ' || p_id_compra || ' supera su saldo de '
                || to_char(v_saldo, 'FM999G999G999G990D00') || '.');
        end if;

        -- Misma moneda = mismas unidades (2026-11-22). Sin esto, un pago de 500 USD
        -- aplicado a una factura en USD con otra tasa descontaba 501,16: el usuario
        -- teclea 500 y ve otra cifra.
        if upper(nvl(v_mon, 'VES')) = upper(nvl(p_moneda_pago, 'VES')) then
            return round(p_monto, 2);
        end if;

        return round(p_monto * v_tc / nvl(nullif(p_tasa_pago, 0), 1), 2);
    end valida_aplicacion;

    -- -------------------------------------------------------------------------
    -- publicas
    -- -------------------------------------------------------------------------

    procedure prc_registrar_pago (
        p_id_proveedor   in  number,
        p_fecha          in  date,
        p_moneda         in  varchar2,
        p_tasa           in  number,
        p_monto          in  number,
        p_id_forma_pago  in  number   default null,
        p_referencia     in  varchar2 default null,
        p_observaciones  in  varchar2 default null,
        p_aplicaciones   in  varchar2 default null,
        p_usuario        in  varchar2,
        p_id_pago        out number
    ) is
        v_emp        number;
        v_pide_ref   varchar2(1);
        v_genera     varchar2(1);
        v_es_spe     varchar2(1);
        v_tasa       number;
        v_total      number := 0;
        v_en_pago    number;
        v_aplica_ig  char(1) := 'N';
        v_igtf       number := 0;
        v_json       varchar2(32767);
        v_vistos     varchar2(32767) := ',';
    begin
        -- cabecera ------------------------------------------------------------
        if p_monto is null or p_monto <= 0 then
            raise_application_error(-20110, 'El pago debe tener un monto mayor que cero.');
        end if;

        if p_id_proveedor is null then
            raise_application_error(-20112, 'El pago necesita un proveedor.');
        end if;

        select p.id_empresa into v_emp
          from proveedores p
         where p.id_proveedor = p_id_proveedor;

        if not fn_usuario_empresa_valida(p_usuario, v_emp) then
            raise_application_error(-20003, 'No tiene permisos sobre esta empresa.');
        end if;

        v_tasa := nvl(nullif(p_tasa, 0), 1);

        -- Una tasa 1 en una moneda extranjera es el error historico del sistema
        -- (2026-11-22): un pago en divisas quedaria valiendo lo mismo en bolivares.
        if v_tasa <= 1 and nvl(upper(p_moneda), 'VES') not in ('VES', 'BS') then
            raise_application_error(-20119,
                'Un pago en ' || upper(p_moneda) || ' necesita su tasa en bolivares por unidad.');
        end if;

        if p_id_forma_pago is not null then
            select nvl(fp.requiere_ref, 'N'), nvl(fp.genera_igtf, 'N')
              into v_pide_ref, v_genera
              from forma_pago fp
             where fp.id_forma_pago = p_id_forma_pago;

            if v_pide_ref = 'Y' and trim(nvl(p_referencia, ' ')) is null then
                raise_application_error(-20114,
                    'Esa forma de pago necesita la referencia bancaria.');
            end if;
        end if;

        select nvl(e.es_spe, 'N') into v_es_spe
          from empresas e
         where e.id_empresa = v_emp;

        -- el IGTF del pago es informativo: la compra ya lo lleva congelado
        if v_es_spe = 'S' and v_genera = 'S'
           and nvl(upper(p_moneda), 'VES') not in ('VES', 'BS') then
            v_aplica_ig := 'S';
            v_igtf      := round(p_monto * nvl(fn_alicuota_igtf(v_emp), 0) / 100, 2);
        end if;

        -- validacion del reparto: primero se comprueba todo, despues se escribe -
        v_json := nvl(p_aplicaciones, '[]');

        for r in (select jt.id_compra, jt.monto
                    from json_table(v_json, '$[*]'
                         columns (id_compra number path '$.id_compra',
                                  monto     number path '$.monto')) jt) loop

            if instr(v_vistos, ',' || r.id_compra || ',') > 0 then
                raise_application_error(-20111,
                    'La compra ' || r.id_compra || ' viene dos veces en el reparto.');
            end if;
            v_vistos := v_vistos || r.id_compra || ',';

            v_en_pago := valida_aplicacion(r.id_compra, p_id_proveedor, r.monto,
                                           v_tasa, v_emp, p_moneda);
            v_total   := v_total + v_en_pago;
        end loop;

        if v_total > p_monto + 0.01 then
            raise_application_error(-20117,
                'Lo aplicado (' || to_char(v_total, 'FM999G999G999G990D00')
                || ') supera el monto del pago ('
                || to_char(p_monto, 'FM999G999G999G990D00') || ').');
        end if;

        -- escritura ----------------------------------------------------------
        insert into pagos (id_empresa, id_proveedor, fecha_pago, cod_moneda, tipo_cambio,
                           monto, monto_bs, id_forma_pago, referencia, aplica_igtf,
                           igtf_monto, igtf_bs, estado, observaciones, creado_por)
        values (v_emp, p_id_proveedor, nvl(p_fecha, trunc(sysdate)), upper(p_moneda), v_tasa,
                p_monto, round(p_monto * v_tasa, 2), p_id_forma_pago, p_referencia, v_aplica_ig,
                v_igtf, round(v_igtf * v_tasa, 2), 'ACTIVO', p_observaciones, p_usuario)
        returning id_pago into p_id_pago;

        for r in (select jt.id_compra, jt.monto
                    from json_table(v_json, '$[*]'
                         columns (id_compra number path '$.id_compra',
                                  monto     number path '$.monto')) jt) loop
            insert into pagos_detalle (id_pago, id_compra, monto_aplicado)
            values (p_id_pago, r.id_compra, r.monto);
        end loop;

        for r in (select jt.id_compra
                    from json_table(v_json, '$[*]'
                         columns (id_compra number path '$.id_compra')) jt) loop
            recalcula_estado(r.id_compra);
        end loop;
    exception
        when others then
            if sqlcode between -20999 and -20000 then
                raise;
            end if;
            prc_log_error('PKG_PAGOS', 'prc_registrar_pago', sqlerrm, dbms_utility.format_error_backtrace);
            raise_application_error(-20120, 'No se pudo registrar el pago. Avisa al administrador.');
    end prc_registrar_pago;

    procedure prc_anular_pago (
        p_id_pago in number,
        p_usuario in varchar2
    ) is
        v_estado     varchar2(10);
        v_conciliado char(1);
        v_emp        number;
    begin
        begin
            select p.estado, nvl(p.conciliado, 'N'), p.id_empresa
              into v_estado, v_conciliado, v_emp
              from pagos p
             where p.id_pago = p_id_pago;
        exception
            when no_data_found then
                raise_application_error(-20113, 'El pago ' || p_id_pago || ' no existe.');
        end;

        if not fn_usuario_empresa_valida(p_usuario, v_emp) then
            raise_application_error(-20003, 'No tiene permisos sobre esta empresa.');
        end if;

        if v_estado = 'ANULADO' then
            raise_application_error(-20113, 'El pago ya esta anulado.');
        end if;

        if v_conciliado = 'S' then
            raise_application_error(-20116,
                'El pago esta conciliado: desmarca la conciliacion antes de anularlo.');
        end if;

        update pagos set estado = 'ANULADO', modificado_por = p_usuario,
               fecha_modificacion = systimestamp
         where id_pago = p_id_pago;

        for r in (select d.id_compra
                    from pagos_detalle d
                   where d.id_pago = p_id_pago) loop
            recalcula_estado(r.id_compra);
        end loop;
    exception
        when others then
            if sqlcode between -20999 and -20000 then
                raise;
            end if;
            prc_log_error('PKG_PAGOS', 'prc_anular_pago', sqlerrm, dbms_utility.format_error_backtrace);
            raise_application_error(-20120, 'No se pudo anular el pago. Avisa al administrador.');
    end prc_anular_pago;

    procedure prc_conciliar (
        p_id_pago    in number,
        p_conciliado in char,
        p_usuario    in varchar2
    ) is
        v_estado varchar2(10);
        v_emp    number;
    begin
        select p.estado, p.id_empresa into v_estado, v_emp
          from pagos p
         where p.id_pago = p_id_pago;

        if not fn_usuario_empresa_valida(p_usuario, v_emp) then
            raise_application_error(-20003, 'No tiene permisos sobre esta empresa.');
        end if;

        if v_estado = 'ANULADO' then
            raise_application_error(-20113, 'El pago esta anulado: no se concilia.');
        end if;

        update pagos set conciliado = case when upper(nvl(p_conciliado, 'N')) = 'S' then 'S' else 'N' end,
               fecha_conciliacion = case when upper(nvl(p_conciliado, 'N')) = 'S'
                                         then trunc(sysdate) end,
               modificado_por = p_usuario,
               fecha_modificacion = systimestamp
         where id_pago = p_id_pago;
    exception
        when no_data_found then
            raise_application_error(-20113, 'El pago ' || p_id_pago || ' no existe.');
    end prc_conciliar;

    procedure prc_aplicar_saldo (
        p_id_pago   in number,
        p_id_compra in number,
        p_monto     in number,
        p_usuario   in varchar2
    ) is
        v_estado     varchar2(10);
        v_conciliado char(1);
        v_emp        number;
        v_prov       number;
        v_favor      number;
        v_en_pago    number;
        v_tasa       number;
        v_mon        varchar2(3);
    begin
        begin
            select p.estado, nvl(p.conciliado, 'N'), p.id_empresa, p.id_proveedor,
                   nvl(nullif(p.tipo_cambio, 0), 1), nvl(p.cod_moneda, 'VES')
              into v_estado, v_conciliado, v_emp, v_prov, v_tasa, v_mon
              from pagos p
             where p.id_pago = p_id_pago;
        exception
            when no_data_found then
                raise_application_error(-20113, 'El pago ' || p_id_pago || ' no existe.');
        end;

        if not fn_usuario_empresa_valida(p_usuario, v_emp) then
            raise_application_error(-20003, 'No tiene permisos sobre esta empresa.');
        end if;

        if v_estado = 'ANULADO' then
            raise_application_error(-20113, 'El pago esta anulado: no se le aplica saldo.');
        end if;

        if v_conciliado = 'S' then
            raise_application_error(-20116,
                'El pago esta conciliado: desmarca la conciliacion antes de aplicarle saldo.');
        end if;

        v_en_pago := valida_aplicacion(p_id_compra, v_prov, p_monto, v_tasa, v_emp, v_mon);

        v_favor := fn_favor_pago(p_id_pago);
        if v_en_pago > v_favor + 0.01 then
            raise_application_error(-20117,
                'El pago solo tiene ' || to_char(v_favor, 'FM999G999G999G990D00')
                || ' de saldo a favor.');
        end if;

        insert into pagos_detalle (id_pago, id_compra, monto_aplicado)
        values (p_id_pago, p_id_compra, p_monto);

        recalcula_estado(p_id_compra);
    exception
        when dup_val_on_index then
            raise_application_error(-20111,
                'Ese pago ya tiene una aplicacion a la compra ' || p_id_compra || '.');
        when others then
            if sqlcode between -20999 and -20000 then
                raise;
            end if;
            prc_log_error('PKG_PAGOS', 'prc_aplicar_saldo', sqlerrm, dbms_utility.format_error_backtrace);
            raise_application_error(-20120, 'No se pudo aplicar el saldo. Avisa al administrador.');
    end prc_aplicar_saldo;

    -- Recalcula el estado de una compra por su saldo. Se expone porque lo llama
    -- pkg_compras al registrar o anular una nota (2026-11-22): una nota cambia la
    -- deuda de la factura que acredita y su estado tiene que seguirlo.
    procedure prc_usar_favor (
        p_id_proveedor in number,
        p_id_compra    in number,
        p_usuario      in varchar2,
        p_aplicado     out number
    ) is
        v_saldo  number;
        v_tc     number;
        v_mon    varchar2(3);
        v_libre  number;
        v_en_com number;
        v_apl    number;
    begin
        p_aplicado := 0;

        select nvl(nullif(c.tipo_cambio, 0), 1), nvl(c.cod_moneda, 'VES')
          into v_tc, v_mon
          from compras c
         where c.id_compra = p_id_compra;

        v_saldo := fn_saldo_compra(p_id_compra);
        if v_saldo <= 0.01 then
            raise_application_error(-20121, 'La compra no tiene saldo que aplicar.');
        end if;

        for r in (select p.id_pago,
                         nvl(nullif(p.tipo_cambio, 0), 1) as tc,
                         nvl(p.cod_moneda, 'VES') as mon
                    from pagos p
                   where p.id_proveedor = p_id_proveedor
                     and p.estado = 'ACTIVO'
                     and nvl(p.conciliado, 'N') = 'N'
                   order by p.fecha_pago, p.id_pago) loop
            exit when v_saldo <= 0.01;

            v_libre := fn_favor_pago(r.id_pago);
            if v_libre > 0.01 then
                -- el saldo a favor vive en la moneda del pago; se lleva a la de la compra
                if upper(r.mon) = upper(v_mon) then
                    v_en_com := v_libre;
                else
                    v_en_com := round(v_libre * r.tc / v_tc, 2);
                end if;

                v_apl := least(v_en_com, v_saldo);
                if v_apl > 0.01 then
                    prc_aplicar_saldo(r.id_pago, p_id_compra, v_apl, p_usuario);
                    p_aplicado := p_aplicado + v_apl;
                    v_saldo    := v_saldo - v_apl;
                end if;
            end if;
        end loop;

        if p_aplicado <= 0.01 then
            raise_application_error(-20121,
                'El proveedor no tiene saldo a favor disponible en este momento.');
        end if;
    end prc_usar_favor;

    procedure prc_recalcular_compra (
        p_id_compra in number
    ) is
    begin
        if p_id_compra is not null then
            recalcula_estado(p_id_compra);
        end if;
    end prc_recalcular_compra;

    function fn_reparto_sugerido (
        p_id_proveedor in number,
        p_moneda       in varchar2,
        p_tasa         in number,
        p_monto        in number
    ) return varchar2 is
        v_tasa    number := nvl(nullif(p_tasa, 0), 1);
        v_resta   number := nvl(p_monto, 0);
        v_json    varchar2(32767) := '';
        v_aplica  number;
        v_tc      number;
    begin
        for r in (select c.id_compra, c.tipo_cambio
                    from compras c
                   where c.id_proveedor = p_id_proveedor
                     and c.estado in ('REGISTRADA', 'PARCIAL')
                     and nvl(c.tipo_documento, 'FAC') = 'FAC'
                   order by c.fecha_emision, c.id_compra) loop

            exit when v_resta <= 0.01;

            v_tc     := nvl(nullif(r.tipo_cambio, 0), 1);
            v_aplica := least(fn_saldo_compra(r.id_compra), round(v_resta * v_tasa / v_tc, 2));

            if v_aplica > 0.01 then
                if v_json is not null then
                    v_json := v_json || ',';
                end if;
                v_json  := v_json || '{"id_compra":' || r.id_compra
                        || ',"monto":' || to_char(v_aplica, 'FM9999999990D00', 'NLS_NUMERIC_CHARACTERS=''.,''') || '}';
                v_resta := v_resta - round(v_aplica * v_tc / v_tasa, 2);
            end if;
        end loop;

        return '[' || nvl(v_json, '') || ']';
    end fn_reparto_sugerido;

    function fn_saldo_proveedor (
        p_id_proveedor in number,
        p_moneda       in varchar2
    ) return number is
        v_tasa  number := fn_tasa_moneda(p_moneda);
        v_total number := 0;
        v_saldo number;
    begin
        for r in (select c.id_compra, nvl(nullif(c.tipo_cambio, 0), 1) tc
                    from compras c
                   where c.id_proveedor = p_id_proveedor
                     and c.estado in ('REGISTRADA', 'PARCIAL')
                     and nvl(c.tipo_documento, 'FAC') = 'FAC') loop
            v_saldo := fn_saldo_compra(r.id_compra);
            if v_saldo > 0 then
                v_total := v_total + round(v_saldo * r.tc / v_tasa, 2);
            end if;
        end loop;

        return round(v_total, 2);
    end fn_saldo_proveedor;

    function fn_saldo_favor_proveedor (
        p_id_proveedor in number,
        p_moneda       in varchar2
    ) return number is
        v_tasa  number := fn_tasa_moneda(p_moneda);
        v_total number := 0;
        v_favor number;
    begin
        for r in (select p.id_pago, nvl(nullif(p.tipo_cambio, 0), 1) tc
                    from pagos p
                   where p.id_proveedor = p_id_proveedor
                     and p.estado = 'ACTIVO') loop
            v_favor := fn_favor_pago(r.id_pago);
            if v_favor > 0.01 then
                v_total := v_total + round(v_favor * r.tc / v_tasa, 2);
            end if;
        end loop;

        return round(v_total, 2);
    end fn_saldo_favor_proveedor;

    function fn_favor_disponible (
        p_id_proveedor in number,
        p_moneda       in varchar2
    ) return number is
        v_tasa  number := fn_tasa_moneda(p_moneda);
        v_total number := 0;
        v_favor number;
    begin
        for r in (select p.id_pago, nvl(nullif(p.tipo_cambio, 0), 1) tc
                    from pagos p
                   where p.id_proveedor = p_id_proveedor
                     and p.estado = 'ACTIVO'
                     and nvl(p.conciliado, 'N') = 'N') loop
            v_favor := fn_favor_pago(r.id_pago);
            if v_favor > 0.01 then
                v_total := v_total + round(v_favor * r.tc / v_tasa, 2);
            end if;
        end loop;

        return round(v_total, 2);
    end fn_favor_disponible;

end pkg_pagos;
/


declare
    v_n     number;
    v_lista varchar2(500) := '';
    v_val   number;
begin
    select count(*) into v_n
      from all_objects
     where owner = 'WKSP_SYPEXWS' and object_name = 'PKG_PAGOS'
       and object_type in ('PACKAGE', 'PACKAGE BODY') and status = 'VALID';
    if v_n <> 2 then
        v_lista := v_lista || ' | PACKAGE o BODY invalido';
    end if;

    select count(*) into v_n
      from all_procedures
     where owner = 'WKSP_SYPEXWS' and object_name = 'PKG_PAGOS'
       and procedure_name = 'FN_FAVOR_DISPONIBLE';
    if v_n <> 1 then
        v_lista := v_lista || ' | falta fn_favor_disponible en la spec';
    end if;

    -- Sin pagos, el credito es 0 y no lanza.
    begin
        v_val := pkg_pagos.fn_favor_disponible(-987654, 'VES');
        if nvl(v_val, -1) <> 0 then
            v_lista := v_lista || ' | un proveedor sin pagos devuelve ' || v_val;
        end if;
    exception
        when others then
            v_lista := v_lista || ' | ' || sqlerrm;
    end;

    if v_lista is null then
        raise_application_error(-20100, 'RESULTADO: FALLAS=0');
    else
        raise_application_error(-20100, substrb('RESULTADO: FALLAS=1' || v_lista, 1, 500));
    end if;
end;
/
