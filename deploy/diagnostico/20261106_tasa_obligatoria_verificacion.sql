-- =============================================================================
-- 20261106_tasa_obligatoria_verificacion.sql
--
-- Verifica que guardar un presupuesto o una factura exija un tipo de cambio
-- coherente. La tasa se guarda en BOLIVARES POR UNIDAD de la moneda del
-- documento (USD->VES 896,12 · MXN->VES 47,91 · VES = 1).
--
-- Antes del cambio:
--   * pkg_facturacion.prc_guardar_factura hacia `if v_tipo_cambio <= 0 then
--     v_tipo_cambio := 1`, o sea se inventaba la tasa.
--   * pkg_presupuestos.prc_guardar_presupuesto guardaba la tasa tal cual, sin
--     mirar si venia nula. De ahi los 29 presupuestos y 23 facturas en USD con
--     tipo_cambio = 1 que hubo que recalcular.
--
-- Todo va en una transaccion con rollback: no deja documentos de prueba.
--
-- Casos:
--   T1  Presupuesto MXN sin tasa                -> -20061
--   T2  Presupuesto MXN con tasa 0              -> -20061
--   T3  Presupuesto USD con tasa 1              -> -20061 (el bug historico)
--   T4  Presupuesto MXN con la tasa del dia     -> guarda
--   T5  Presupuesto MXN con la tasa x3          -> -20061 (fuera de rango)
--   T6  Presupuesto VES sin tasa                -> guarda con 1
--   T7  Factura MXN sin tasa                    -> -20061
--   T8  Factura USD con tasa 1                  -> -20061
--   T9  Factura MXN con la tasa del dia         -> guarda
--   T10 Factura VES sin tasa                    -> guarda con 1
--   T11 Presupuesto USD con la tasa del dia     -> guarda
--   T12 fn_clean_num conserva una tasa de 6 decimales (antes devolvia NULL
--       y la factura moria con ORA-01400 al insertar la tasa)
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;
/

declare
  v_fallas  number := 0;
  v_lista   varchar2(3000) := '';
  v_emp     number := 1;
  v_cli     number;
  v_id      number;
  v_tasa    number;
  v_mxn     number := fn_tasa_ves(sysdate, 'MXN');
  v_usd     number := fn_tasa_ves(sysdate, 'USD');

  procedure falla (p_caso in varchar2, p_detalle in varchar2) is
  begin
    v_fallas := v_fallas + 1;
    v_lista  := v_lista || ' | ' || p_caso || ': ' || p_detalle;
  end falla;

  -- Guarda un presupuesto y devuelve el id (o lanza).
  procedure presu (p_id out number, p_folio in varchar2, p_moneda in varchar2, p_tasa in number) is
  begin
    p_id := null;
    pkg_presupuestos.prc_guardar_presupuesto(
        p_id_presupuesto    => p_id,
        p_id_empresa        => v_emp,
        p_id_cliente        => v_cli,
        p_folio             => p_folio,
        p_cod_moneda        => p_moneda,
        p_fecha_vencimiento => sysdate + 30,
        p_fecha_emision     => sysdate,
        p_tipo_cambio       => p_tasa,
        p_estado            => 'PENDIENTE',
        p_observaciones     => 'prueba de tasa',
        p_usuario           => 'PRUEBA_TASA');
  end presu;

  procedure factu (p_id out number, p_folio in varchar2, p_moneda in varchar2, p_tasa in number) is
  begin
    p_id := null;
    pkg_facturacion.prc_guardar_factura(
        p_id_factura        => p_id,
        p_id_empresa        => v_emp,
        p_folio_factura     => p_folio,
        p_id_cliente        => v_cli,
        p_id_presupuesto    => null,
        p_rfc_emisor        => null,
        p_rfc_receptor      => null,
        p_uuid_fiscal       => null,
        p_uso_cfdi          => null,
        p_forma_pago        => null,
        p_metodo_pago       => null,
        p_condicion_pago    => null,
        p_fecha_emision     => to_char(sysdate, 'DD/MM/YYYY'),
        p_fecha_vencimiento => to_char(sysdate + 30, 'DD/MM/YYYY'),
        p_estado            => 'PENDIENTE',
        p_subtotal          => 0,
        p_monto_impuesto    => 0,
        p_monto_total       => 0,
        p_observaciones     => 'prueba de tasa',
        p_cod_moneda        => p_moneda,
        p_tipo_cambio       => p_tasa,
        p_usuario           => 'PRUEBA_TASA');
  end factu;

  -- Espera -20061; cualquier otro final es falla.
  procedure espera_error (p_caso in varchar2, p_que in varchar2) is
  begin
    falla(p_caso, 'acepto ' || p_que);
  exception
    when others then
      if sqlcode <> -20061 then
        falla(p_caso, 'fallo con ' || sqlcode || ' (' || sqlerrm || ')');
      end if;
  end espera_error;

begin
  select min(id_cliente) into v_cli from clientes where id_empresa = v_emp;

  if v_mxn is null or v_usd is null then
    falla('T0', 'faltan tasas en tipo_cambio (MXN=' || v_mxn || ', USD=' || v_usd || ')');
  end if;

  -- T1: MXN sin tasa
  begin
    presu(v_id, 990001, 'MXN', null);
    espera_error('T1', 'un presupuesto en MXN sin tipo de cambio');
  exception
    when others then
      if sqlcode <> -20061 then falla('T1', 'fallo con ' || sqlcode || ' (' || sqlerrm || ')'); end if;
  end;

  -- T2: MXN con tasa 0
  begin
    presu(v_id, 990002, 'MXN', 0);
    espera_error('T2', 'un presupuesto en MXN con tasa 0');
  exception
    when others then
      if sqlcode <> -20061 then falla('T2', 'fallo con ' || sqlcode || ' (' || sqlerrm || ')'); end if;
  end;

  -- T3: USD con tasa 1 (el bug historico)
  begin
    presu(v_id, 990003, 'USD', 1);
    espera_error('T3', 'un presupuesto en USD con tipo_cambio 1');
  exception
    when others then
      if sqlcode <> -20061 then falla('T3', 'fallo con ' || sqlcode || ' (' || sqlerrm || ')'); end if;
  end;

  -- T4: MXN con la tasa del dia
  begin
    presu(v_id, 990004, 'MXN', v_mxn);
    select tipo_cambio into v_tasa from presupuestos where id_presupuesto = v_id;
    if abs(v_tasa - v_mxn) > 0.000001 then
      falla('T4', 'guardo la tasa ' || v_tasa || ' en vez de ' || v_mxn);
    end if;
  exception
    when others then
      falla('T4', 'no dejo guardar con la tasa del dia: ' || sqlcode || ' ' || sqlerrm);
  end;

  -- T5: MXN con la tasa x3 (fuera de rango)
  begin
    presu(v_id, 990005, 'MXN', v_mxn * 3);
    espera_error('T5', 'un presupuesto en MXN con la tasa tres veces la del dia');
  exception
    when others then
      if sqlcode <> -20061 then falla('T5', 'fallo con ' || sqlcode || ' (' || sqlerrm || ')'); end if;
  end;

  -- T6: VES sin tasa -> 1
  begin
    presu(v_id, 990006, 'VES', null);
    select tipo_cambio into v_tasa from presupuestos where id_presupuesto = v_id;
    if v_tasa <> 1 then
      falla('T6', 'un presupuesto en bolivares debe quedar con tasa 1 y quedo ' || v_tasa);
    end if;
  exception
    when others then
      falla('T6', 'no dejo guardar en bolivares sin tasa: ' || sqlcode || ' ' || sqlerrm);
  end;

  -- T7: factura MXN sin tasa
  begin
    factu(v_id, 990007, 'MXN', null);
    espera_error('T7', 'una factura en MXN sin tipo de cambio');
  exception
    when others then
      if sqlcode <> -20061 then falla('T7', 'fallo con ' || sqlcode || ' (' || sqlerrm || ')'); end if;
  end;

  -- T8: factura USD con tasa 1
  begin
    factu(v_id, 990008, 'USD', 1);
    espera_error('T8', 'una factura en USD con tipo_cambio 1');
  exception
    when others then
      if sqlcode <> -20061 then falla('T8', 'fallo con ' || sqlcode || ' (' || sqlerrm || ')'); end if;
  end;

  -- T9: factura MXN con la tasa del dia
  begin
    factu(v_id, 990009, 'MXN', v_mxn);
    select tipo_cambio into v_tasa from facturas where id_factura = v_id;
    if abs(v_tasa - v_mxn) > 0.000001 then
      falla('T9', 'guardo la tasa ' || v_tasa || ' en vez de ' || v_mxn);
    end if;
  exception
    when others then
      falla('T9', 'no dejo guardar con la tasa del dia: ' || sqlcode || ' ' || sqlerrm);
  end;

  -- T10: factura VES sin tasa -> 1
  begin
    factu(v_id, 990010, 'VES', null);
    select tipo_cambio into v_tasa from facturas where id_factura = v_id;
    if v_tasa <> 1 then
      falla('T10', 'una factura en bolivares debe quedar con tasa 1 y quedo ' || v_tasa);
    end if;
  exception
    when others then
      falla('T10', 'no dejo guardar en bolivares sin tasa: ' || sqlcode || ' ' || sqlerrm);
  end;

  -- T11: USD con la tasa del dia
  begin
    presu(v_id, 990011, 'USD', v_usd);
    select tipo_cambio into v_tasa from presupuestos where id_presupuesto = v_id;
    if abs(v_tasa - v_usd) > 0.000001 then
      falla('T11', 'guardo la tasa ' || v_tasa || ' en vez de ' || v_usd);
    end if;
  exception
    when others then
      falla('T11', 'no dejo guardar un presupuesto en USD con la tasa del dia: '
                   || sqlcode || ' ' || sqlerrm);
  end;

  -- T12: una tasa con 6 decimales no puede perderse al pasar por fn_clean_num
  v_tasa := fn_clean_num(to_char(v_mxn));
  if v_tasa is null or abs(v_tasa - v_mxn) > 0.000001 then
    falla('T12', 'fn_clean_num(' || to_char(v_mxn) || ') devolvio ' || v_tasa);
  end if;

  rollback;

  raise_application_error(-20100, 'RESULTADO: FALLAS=' || v_fallas || v_lista);
end;
/
