-- =============================================================================
-- 20261117_pkg_cobros.sql
--
-- Paquete de cobros (2026-11-17). Idempotente (create or replace).
--
-- Registra un cobro sobre una factura: calcula el equivalente en la moneda de la
-- factura con la tasa del dia del cobro, el IGTF (solo si la empresa es SPE y el
-- cobro es en divisas, con la alicuota de IMPUESTOS) y el neto
-- (monto - retencion + IGTF), inserta el recibo y deja la factura en PARCIAL o
-- PAGADA con el resumen de la retencion real en la cabecera.
--
-- Reversa: drop package pkg_cobros. Los recibos ya guardados no se tocan.
--
-- Verificacion: deploy/diagnostico/20261117_cobros_registrar_verificacion.sql
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

-- =============================================================================
-- pkg_cobros.sql (especificacion)
--
-- Cobros de las facturas (2026-11-17). Un recibo es un cobro: puede ser el total
-- o un abono. El saldo lo lleva fn_saldo_factura, no se guarda.
--
-- El IGTF se calcula aqui, no en la factura: solo si la empresa es SPE y el cobro
-- es en moneda extranjera, sobre la parte cobrada (nunca sobre el total de la
-- factura) y con la alicuota configurada en IMPUESTOS.
--
-- El IGTF no es ingreso: MONTO_NETO es el dinero que entra al banco y el IGTF se
-- guarda aparte (impuesto por enterar).
-- =============================================================================

create or replace package pkg_cobros as

    -- Lo que la pantalla propone antes de guardar: el 3 % (o lo que diga la
    -- configuracion) del monto si el cobro es en divisas y la empresa es SPE.
    function fn_igtf_sugerido (
        p_id_factura in number,
        p_cod_moneda in varchar2,
        p_monto      in number
    ) return number;

    -- Lo que la pantalla propone como retencion de IVA: el porcentaje de la
    -- factura prorrateado a la parte que se esta cobrando. p_cod_moneda es la
    -- moneda del cobro: el monto se lleva antes a la moneda de la factura.
    function fn_retencion_sugerida (
        p_id_factura in number,
        p_monto      in number,
        p_cod_moneda in varchar2 default null
    ) return number;

    -- Registra un cobro. p_tasa es bolivares por unidad de la moneda del cobro;
    -- si no llega se toma la del dia. p_aplica_igtf permite forzar S/N (para los
    -- pagos en divisas que la ley exceptua); si llega nulo se decide solo.
    procedure prc_registrar_cobro (
        p_id_factura     in  number,
        p_fecha          in  date,
        p_id_forma_pago  in  number,
        p_cod_moneda     in  varchar2,
        p_monto          in  number,
        p_tasa           in  number   default null,
        p_retencion_iva_bs in number default 0,
        p_nro_comprobante  in varchar2 default null,
        p_referencia     in  varchar2 default null,
        p_aplica_igtf    in  varchar2 default null,
        p_usuario        in  varchar2,
        p_id_recibo      out number
    );

    -- Anula un cobro (no se borra: queda el rastro) y devuelve la factura a
    -- TIMBRADA o PARCIAL segun lo que quede cobrado.
    procedure prc_anular_cobro (
        p_id_recibo in number,
        p_usuario   in varchar2
    );

    -- Marca el cobro como conciliado con el ingreso bancario.
    procedure prc_conciliar (
        p_id_recibo   in number,
        p_referencia  in varchar2,
        p_usuario     in varchar2 default null
    );

end pkg_cobros;
/

-- =============================================================================
-- pkg_cobros.sql (body)
--
-- Reglas del cobro (2026-11-17):
--   * Solo se cobran facturas TIMBRADA o PARCIAL, de las empresas del usuario.
--   * El monto no puede pasar del saldo (sobrepago -> -20094).
--   * El equivalente en la moneda de la factura usa la tasa del dia del cobro.
--   * IGTF: moneda extranjera + empresa SPE + alicuota de IMPUESTOS. Se puede
--     exceptuar con p_aplica_igtf = 'N' (pagos en divisas del sistema financiero
--     nacional). Nunca se cobra IGTF en bolivares.
--   * neto = monto - retencion + igtf  (el IGTF entra al banco: no es ingreso,
--     es un impuesto por enterar, y por eso se guarda aparte).
--   * La cabecera queda con el resumen de la retencion real (suma de los recibos)
--     y el primer comprobante no nulo, que es lo que leen el libro y el impreso.
-- =============================================================================

create or replace package body pkg_cobros as

    ---------------------------------------------------------------------------
    -- Utilidades privadas
    ---------------------------------------------------------------------------

    -- Tasa de una moneda contra el bolivar a una fecha (1 si es VES/BS).
    function tasa_a_bs (p_moneda in varchar2, p_fecha in date) return number is
        v_tasa number;
    begin
        if upper(trim(p_moneda)) in ('VES', 'BS') then
            return 1;
        end if;

        select max(tasa_cambio) keep (dense_rank last order by fecha_vigencia)
          into v_tasa
          from tipo_cambio
         where moneda_origen = upper(trim(p_moneda))
           and moneda_destino = 'VES'
           and tipo_tasa = 'REAL'
           and fecha_vigencia < trunc(nvl(p_fecha, sysdate)) + 1;

        return v_tasa;
    end tasa_a_bs;

    -- Deja la factura en PARCIAL/PAGADA segun el saldo y refresca el resumen de
    -- la retencion que se declara (real, de los recibos activos). Si ya no queda
    -- ningun cobro vivo (se anularon todos), la factura vuelve a TIMBRADA.
    procedure actualiza_factura (p_id_factura in number) is
        v_saldo number;
        v_ret   number;
        v_comp  varchar2(20);
        v_cobros number;
    begin
        v_saldo := fn_saldo_factura(p_id_factura);

        select count(*),
               nvl(sum(retencion_iva_bs), 0),
               max(nro_comprobante_retencion) keep (
                   dense_rank first
                   order by case when nro_comprobante_retencion is not null then 0 else 1 end,
                            fecha_cobro, id_recibo)
          into v_cobros, v_ret, v_comp
          from recibos
         where id_factura = p_id_factura
           and estado = 'ACTIVO';

        update facturas set
               estado = case
                          when v_cobros = 0 then 'TIMBRADA'
                          when v_saldo <= 0.01 then 'PAGADA'
                          else 'PARCIAL'
                        end,
               retencion_iva_bs = v_ret,
               nro_comprobante_retencion = v_comp,
               fecha_modificacion = systimestamp,
               modificado_por = nvl(modificado_por, creado_por)
         where id_factura = p_id_factura;
    end actualiza_factura;

    ---------------------------------------------------------------------------
    -- Lo que la pantalla propone
    ---------------------------------------------------------------------------

    function fn_igtf_sugerido (
        p_id_factura in number,
        p_cod_moneda in varchar2,
        p_monto      in number
    ) return number is
        v_emp    number;
        v_spe    char(1);
        v_alic   number;
    begin
        if upper(trim(p_cod_moneda)) in ('VES', 'BS') then
            return 0;
        end if;

        select f.id_empresa, nvl(e.es_spe, 'N')
          into v_emp, v_spe
          from facturas f
          join empresas e on e.id_empresa = f.id_empresa
         where f.id_factura = p_id_factura;

        if v_spe <> 'S' then
            return 0;
        end if;

        v_alic := fn_alicuota_igtf(v_emp);
        return round(nvl(p_monto, 0) * v_alic / 100, 2);
    exception
        when no_data_found then
            return 0;
    end fn_igtf_sugerido;

    function fn_retencion_sugerida (
        p_id_factura in number,
        p_monto      in number,
        p_cod_moneda in varchar2 default null
    ) return number is
        v_pct       number;
        v_total     number;
        v_tasa_doc  number;
        v_mon       varchar2(3);   -- moneda de la factura
        v_cobro     varchar2(3);   -- moneda del cobro
        v_tasa      number;
        v_monto_fac number;
        v_iva_bs    number;
    begin
        select nvl(porcentaje_retencion, 0), nvl(monto_total, 0), nvl(tipo_cambio, 1),
               upper(cod_moneda)
          into v_pct, v_total, v_tasa_doc, v_mon
          from facturas
         where id_factura = p_id_factura;

        if v_pct <= 0 or v_total <= 0 then
            return 0;
        end if;

        -- El monto del cobro se lleva a la moneda de la factura antes de prorratear:
        -- si no, pagar en bolivares una factura en dolares proponia una retencion
        -- cientos de veces mayor.
        v_cobro := upper(trim(nvl(p_cod_moneda, v_mon)));
        if v_cobro = v_mon then
            v_monto_fac := nvl(p_monto, 0);
        elsif v_cobro in ('VES', 'BS') then
            v_monto_fac := round(nvl(p_monto, 0) / nvl(v_tasa_doc, 1), 2);
        else
            v_tasa := nvl(tasa_a_bs(v_cobro, sysdate), 1);
            v_monto_fac := round(nvl(p_monto, 0) * v_tasa / nvl(v_tasa_doc, 1), 2);
        end if;

        -- El IVA de la factura en bolivares (fn_iva_retenido_bs con 100 %).
        v_iva_bs := fn_iva_retenido_bs(p_id_factura, 100, v_tasa_doc);

        -- Se prorratea a la parte de la factura que se esta cobrando.
        return round(v_iva_bs * least(v_monto_fac / v_total, 1) * v_pct / 100, 2);
    exception
        when no_data_found then
            return 0;
    end fn_retencion_sugerida;

    ---------------------------------------------------------------------------
    -- Registrar el cobro
    ---------------------------------------------------------------------------

    procedure prc_registrar_cobro (
        p_id_factura     in  number,
        p_fecha          in  date,
        p_id_forma_pago  in  number,
        p_cod_moneda     in  varchar2,
        p_monto          in  number,
        p_tasa           in  number   default null,
        p_retencion_iva_bs in number default 0,
        p_nro_comprobante  in varchar2 default null,
        p_referencia     in  varchar2 default null,
        p_aplica_igtf    in  varchar2 default null,
        p_usuario        in  varchar2,
        p_id_recibo      out number
    ) is
        v_emp      number;
        v_estado   varchar2(20);
        v_mon_doc  varchar2(3);
        v_tasa_doc number;
        v_saldo    number;
        v_moneda   varchar2(3);
        v_tasa     number;
        v_monto    number;
        v_mon_bs   number;
        v_mon_fac  number;
        v_tasa_fac number;
        v_spe      char(1);
        v_alic     number;
        v_aplica   char(1);
        v_igtf     number;
        v_igtf_bs  number;
        v_retencion number;
        v_comprobante varchar2(20);
        v_neto     number;
        v_fecha    date;
        v_fecha_emision date;
        v_iva_bs   number;
    begin
        if p_id_factura is null then
            raise_application_error(-20090, 'No se indico la factura que se esta cobrando.');
        end if;

        -- FOR UPDATE: dos cobros simultaneos sobre la misma factura tienen que
        -- hacer cola; si no, los dos leen el mismo saldo y la dejan en negativo.
        select f.id_empresa, f.estado, f.cod_moneda, nvl(f.tipo_cambio, 1), nvl(e.es_spe, 'N'),
               f.fecha_emision
          into v_emp, v_estado, v_mon_doc, v_tasa_doc, v_spe, v_fecha_emision
          from facturas f
          join empresas e on e.id_empresa = f.id_empresa
         where f.id_factura = p_id_factura
           for update of f.id_factura;

        if not fn_usuario_empresa_valida(p_usuario, v_emp) then
            raise_application_error(-20003, 'Esa factura no es de una empresa suya.');
        end if;

        if v_estado not in ('TIMBRADA', 'PARCIAL') then
            raise_application_error(-20090,
                'La factura no se puede cobrar en estado ' || v_estado
                || case v_estado
                     when 'ANULADA' then ': esta anulada.'
                     when 'PAGADA' then ': ya esta pagada.'
                     else ': procesala antes de cobrarla.'
                   end);
        end if;

        v_fecha := trunc(nvl(p_fecha, sysdate));

        if v_fecha < trunc(nvl(v_fecha_emision, v_fecha)) then
            raise_application_error(-20092,
                'El cobro no puede ser anterior a la factura ('
                || to_char(v_fecha_emision, 'DD/MM/YYYY') || ').');
        end if;

        v_monto := round(nvl(p_monto, 0), 2);
        if v_monto <= 0 then
            raise_application_error(-20092, 'El monto del cobro debe ser mayor que cero.');
        end if;

        v_moneda := upper(trim(nvl(p_cod_moneda, v_mon_doc)));
        v_tasa := case
                    when v_moneda in ('VES', 'BS') then 1
                    else nvl(p_tasa, tasa_a_bs(v_moneda, v_fecha))
                  end;

        if v_tasa is null or v_tasa <= 0
           or (v_moneda not in ('VES', 'BS') and v_tasa = 1) then
            raise_application_error(-20093,
                'No hay una tasa de cambio valida para ' || v_moneda
                || ' al ' || to_char(v_fecha, 'DD/MM/YYYY') || '.');
        end if;

        v_mon_bs := round(v_monto * v_tasa, 2);

        -- Equivalente en la moneda de la factura: si es la misma moneda, el monto;
        -- si la factura es en bolivares, los bolivares; si no, con la tasa de la
        -- moneda de la factura el dia del cobro.
        if v_moneda = upper(v_mon_doc) then
            v_mon_fac := v_monto;
        elsif upper(v_mon_doc) in ('VES', 'BS') then
            v_mon_fac := v_mon_bs;
        else
            v_tasa_fac := tasa_a_bs(v_mon_doc, v_fecha);
            if v_tasa_fac is null or v_tasa_fac <= 0 then
                raise_application_error(-20093,
                    'No hay tasa para la moneda de la factura (' || v_mon_doc || ') al '
                    || to_char(v_fecha, 'DD/MM/YYYY') || '.');
            end if;
            v_mon_fac := round(v_mon_bs / v_tasa_fac, 2);
        end if;

        v_saldo := fn_saldo_factura(p_id_factura);
        if v_mon_fac > v_saldo + 0.01 then
            raise_application_error(-20094,
                'El cobro (' || to_char(v_mon_fac, 'FM999G999G990D00') || ' ' || v_mon_doc
                || ') supera el saldo de la factura ('
                || to_char(v_saldo, 'FM999G999G990D00') || ' ' || v_mon_doc || ').');
        end if;

        -- IGTF
        if p_aplica_igtf is null then
            v_aplica := case when v_moneda not in ('VES', 'BS') and v_spe = 'S' then 'S' else 'N' end;
        else
            v_aplica := case when upper(trim(p_aplica_igtf)) = 'S' then 'S' else 'N' end;
            if v_aplica = 'S' and (v_moneda in ('VES', 'BS') or v_spe <> 'S') then
                raise_application_error(-20093,
                    'El IGTF solo aplica a cobros en moneda extranjera de una empresa SPE.');
            end if;
        end if;

        if v_aplica = 'S' then
            v_alic := fn_alicuota_igtf(v_emp);
            if v_alic <= 0 then
                raise_application_error(-20093,
                    'La empresa no tiene alicuota de IGTF configurada para su pais.');
            end if;
            v_igtf := round(v_monto * v_alic / 100, 2);
            v_igtf_bs := round(v_igtf * v_tasa, 2);
        else
            v_igtf := 0;
            v_igtf_bs := 0;
        end if;

        -- Retencion de IVA: se teclea la del comprobante; si es mayor que cero el
        -- comprobante es obligatorio y de 14 digitos.
        v_retencion := round(nvl(p_retencion_iva_bs, 0), 2);
        if v_retencion < 0 then
            raise_application_error(-20092, 'La retencion no puede ser negativa.');
        end if;
        if v_retencion > 0 then
            if p_nro_comprobante is null then
                raise_application_error(-20081,
                    'Falta el numero del comprobante de retencion del cliente (14 digitos).');
            end if;
            if not regexp_like(trim(p_nro_comprobante), '^[0-9]{14}$') then
                raise_application_error(-20081,
                    'El comprobante de retencion del cliente debe tener 14 digitos (AAAAMM + 8).');
            end if;
            v_comprobante := trim(p_nro_comprobante);
        end if;

        -- La retencion se declara en bolivares; el neto va en la moneda del cobro.
        if v_retencion > 0 then
            v_iva_bs := fn_iva_retenido_bs(p_id_factura, 100, v_tasa_doc);
            if v_retencion > v_iva_bs * 1.01 then
                raise_application_error(-20092,
                    'La retencion (' || to_char(v_retencion, 'FM999G999G990D00')
                    || ' Bs) no puede pasar del IVA de la factura ('
                    || to_char(v_iva_bs, 'FM999G999G990D00') || ' Bs).');
            end if;
        end if;

        v_neto := round(v_monto - round(v_retencion / v_tasa, 2) + v_igtf, 2);

        insert into recibos (id_empresa, id_factura, fecha_cobro, id_forma_pago, cod_moneda,
                             tipo_cambio, monto_cobrado, monto_bs, monto_factura, aplica_igtf,
                             igtf_monto, igtf_bs, retencion_iva_bs, nro_comprobante_retencion,
                             monto_neto, referencia, conciliado, estado, creado_por)
        values (v_emp, p_id_factura, v_fecha, p_id_forma_pago, v_moneda,
                v_tasa, v_monto, v_mon_bs, v_mon_fac, v_aplica,
                v_igtf, v_igtf_bs, v_retencion, v_comprobante,
                v_neto, p_referencia, 'N', 'ACTIVO', p_usuario)
        returning id_recibo into p_id_recibo;

        actualiza_factura(p_id_factura);
    end prc_registrar_cobro;

    ---------------------------------------------------------------------------
    -- Anular y conciliar
    ---------------------------------------------------------------------------

    procedure prc_anular_cobro (
        p_id_recibo in number,
        p_usuario   in varchar2
    ) is
        v_id_factura number;
        v_empresa    number;
        v_estado     varchar2(10);
    begin
        select id_factura, id_empresa, estado
          into v_id_factura, v_empresa, v_estado
          from recibos
         where id_recibo = p_id_recibo;

        if not fn_usuario_empresa_valida(p_usuario, v_empresa) then
            raise_application_error(-20003, 'Ese cobro no es de una empresa suya.');
        end if;

        if v_estado = 'ANULADO' then
            raise_application_error(-20095, 'Ese cobro ya esta anulado.');
        end if;

        update recibos set
               estado = 'ANULADO',
               modificado_por = p_usuario,
               fecha_modificacion = systimestamp
         where id_recibo = p_id_recibo;

        actualiza_factura(v_id_factura);
    exception
        when no_data_found then
            raise_application_error(-20095, 'Ese cobro no existe.');
    end prc_anular_cobro;

    procedure prc_conciliar (
        p_id_recibo   in number,
        p_referencia  in varchar2,
        p_usuario     in varchar2 default null
    ) is
        v_empresa number;
        v_estado  varchar2(10);
    begin
        select id_empresa, estado into v_empresa, v_estado
          from recibos where id_recibo = p_id_recibo;

        if not fn_usuario_empresa_valida(nvl(p_usuario, v('APP_USER')), v_empresa) then
            raise_application_error(-20003, 'Ese cobro no es de una empresa suya.');
        end if;

        if v_estado = 'ANULADO' then
            raise_application_error(-20095, 'Ese cobro esta anulado: no se concilia.');
        end if;

        update recibos set
               conciliado = 'S',
               referencia = nvl(p_referencia, referencia),
               fecha_conciliacion = sysdate,
               fecha_modificacion = systimestamp
         where id_recibo = p_id_recibo;
    exception
        when no_data_found then
            raise_application_error(-20095, 'Ese cobro no existe.');
    end prc_conciliar;

end pkg_cobros;
/

begin
    dbms_utility.compile_schema('WKSP_SYPEXWS', false);
end;
/
