-- =============================================================================
-- 20261105_gasto_real_verificacion.sql
--
-- Verificacion de PKG_GASTO_REAL y V_PRESUPUESTO_REAL. Todo va en una
-- transaccion con rollback: no deja gastos de prueba.
--
-- AMPLIADA EL 2026-11-06 con la conversion correcta a USD. La tasa se guarda,
-- como en todo el sistema (tipo_cambio, presupuestos.tipo_cambio,
-- facturas.tipo_cambio), en BOLIVARES POR UNIDAD de la moneda: no es un factor
-- a USD. El equivalente se calcula con:
--
--     factor_usd = tasa_moneda_a_ves / tasa_usd_a_ves
--     monto_base_usd = round(monto_origen * factor_usd, 2)
--
-- Antes el paquete hacia monto * tasa, asi que 100 Bs se guardaban como 100 USD
-- (1.000 veces su valor) y 100 MXN como 4.791,07 USD en vez de 5,35.
--
-- Casos:
--   G1  Alta en USD: factor 1 y monto_base_usd igual al monto; tasa = Bs/USD.
--   G2  Alta en MXN con tasa forzada: usa la forzada y convierte bien.
--   G3  Alta en bolivares sin tasa: 100 Bs NO son 100 USD.
--   G4  Alta en MXN sin tasa: toma la de TIPO_CAMBIO.
--   G5  Edicion del mismo gasto: no duplica y recalcula.
--   G6  fn_total_gasto_usd suma los cuatro gastos.
--   G7  La vista devuelve presupuestado, gastado y desviacion coherentes.
--   G8  Rechaza monto cero o negativo (-20041).
--   G9  Rechaza presupuesto inexistente (-20042).
--   G10 Rechaza presupuesto de otra empresa (-20003).
--   G11 Rechaza una moneda sin tasa (-20060) en vez de inventarse un 1.
--   G12 Baja del gasto: desaparece y el total baja.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;
/

declare
  v_fallas   number := 0;
  v_lista    varchar2(3000) := '';
  v_pre      number;                 -- presupuesto de la empresa 1 (el primero que haya)
  v_pre2     number;                -- uno de la empresa 2
  v_g1       number;
  v_g2       number;
  v_g3       number;
  v_g4       number;
  v_rusd     number := fn_tasa_ves(sysdate, 'USD');   -- bolivares por dolar
  v_rmxn     number := fn_tasa_ves(sysdate, 'MXN');
  v_total    number;
  v_pres     number;
  v_gasto    number;
  v_desv     number;
  v_usd      number;
  v_tasa     number;
  v_esperado number;

  procedure falla (p_caso in varchar2, p_detalle in varchar2) is
  begin
    v_fallas := v_fallas + 1;
    v_lista  := v_lista || ' | ' || p_caso || ': ' || p_detalle;
  end falla;

begin
  select min(id_presupuesto) into v_pre  from presupuestos
   where id_empresa = 1 and estado not in ('CANCELADO','FACTURADO');
  select min(id_presupuesto) into v_pre2 from presupuestos where id_empresa = 2;

  if v_pre is null then
    falla('G0', 'no hay presupuestos de la empresa 1: falta el fixture de prueba');
  end if;

  if v_rusd is null or v_rmxn is null then
    falla('G0', 'faltan tasas en tipo_cambio (USD=' || v_rusd || ', MXN=' || v_rmxn || ')');
  end if;

  -- G1: USD 100 -> 100 USD, y la tasa guardada es la del dolar en bolivares.
  -- Desde el 2026-11-18 la tasa es OBLIGATORIA cuando el gasto no esta en la moneda
  -- del presupuesto (aqui el presupuesto es en VES), asi que se pasa.
  pkg_gasto_real.prc_guardar_gasto(
      p_id_gasto => v_g1, p_id_presupuesto => v_pre,
      p_fecha_gasto => sysdate, p_monto_origen => 100,
      p_moneda_origen => 'USD', p_tasa_real => v_rusd);

  if v_g1 is null then
    falla('G1', 'no devolvio id_gasto');
  end if;

  select monto_base_usd, tasa_real into v_usd, v_tasa
    from gasto_real where id_gasto = v_g1;

  if v_usd <> 100 then
    falla('G1', 'USD 100 debe valer 100 USD y vale ' || v_usd);
  end if;
  if abs(v_tasa - v_rusd) > 0.000001 then
    falla('G1', 'la tasa debe ser Bs por dolar (' || v_rusd || ') y guardo ' || v_tasa);
  end if;

  -- G2: MXN 50 con tasa forzada (el doble de la del dia)
  pkg_gasto_real.prc_guardar_gasto(
      p_id_gasto => v_g2, p_id_presupuesto => v_pre,
      p_fecha_gasto => sysdate, p_monto_origen => 50,
      p_moneda_origen => 'MXN', p_tasa_real => v_rmxn * 2);

  v_esperado := round(50 * (v_rmxn * 2) / v_rusd, 2);

  select monto_base_usd, tasa_real into v_usd, v_tasa
    from gasto_real where id_gasto = v_g2;

  if abs(v_usd - v_esperado) > 0.01 then
    falla('G2', 'MXN 50 con tasa ' || v_rmxn * 2 || ' deben ser ' || v_esperado
                || ' USD y guardo ' || v_usd);
  end if;
  if abs(v_tasa - v_rmxn * 2) > 0.000001 then
    falla('G2', 'no guardo la tasa forzada: ' || v_tasa);
  end if;

  -- G3: bolivares sin tasa -> el equivalente es monto / tasa_usd, no el monto
  pkg_gasto_real.prc_guardar_gasto(
      p_id_gasto => v_g3, p_id_presupuesto => v_pre,
      p_fecha_gasto => sysdate, p_monto_origen => 100,
      p_moneda_origen => 'VES');

  v_esperado := round(100 / v_rusd, 2);

  select monto_base_usd into v_usd from gasto_real where id_gasto = v_g3;

  if abs(v_usd - v_esperado) > 0.01 then
    falla('G3', '100 Bs deben ser ' || v_esperado || ' USD y guardo ' || v_usd);
  end if;
  if v_usd >= 1 then
    falla('G3', 'los bolivares se siguen guardando como dolares: ' || v_usd);
  end if;

  -- G4 (2026-11-18): en OTRA moneda que la del presupuesto, sin tasa -> -20055.
  -- Antes se tomaba la de la tabla; ahora la tasa la teclea el usuario porque el
  -- equivalente en dolares tiene que cuadrar con lo que dice el comprobante.
  begin
    pkg_gasto_real.prc_guardar_gasto(
        p_id_gasto => v_g4, p_id_presupuesto => v_pre,
        p_fecha_gasto => sysdate, p_monto_origen => 100,
        p_moneda_origen => 'MXN');
    falla('G4', 'acepto un gasto en MXN sin tasa');
  exception
    when others then
      if sqlcode <> -20055 then falla('G4', 'fallo con ' || sqlcode || ' (se esperaba -20055)'); end if;
  end;

  -- G5: editar el primero a 250 USD: no duplica
  pkg_gasto_real.prc_guardar_gasto(
      p_id_gasto => v_g1, p_id_presupuesto => v_pre,
      p_fecha_gasto => sysdate, p_monto_origen => 250,
      p_moneda_origen => 'USD', p_tasa_real => v_rusd);

  declare
    v_n number;
  begin
    select count(*) into v_n from gasto_real where id_presupuesto = v_pre;
    if v_n <> 3 then
      falla('G5', 'esperaba 3 gastos y hay ' || v_n);
    end if;
  end;

  select monto_base_usd into v_usd from gasto_real where id_gasto = v_g1;
  if v_usd <> 250 then
    falla('G5', 'al editar a 250 USD guardo ' || v_usd);
  end if;

  -- G6: total
  v_total    := pkg_gasto_real.fn_total_gasto_usd(v_pre);
  v_esperado := 250
              + round(50 * (v_rmxn * 2) / v_rusd, 2)
              + round(100 / v_rusd, 2);

  if abs(v_total - v_esperado) > 0.02 then
    falla('G6', 'esperaba ' || v_esperado || ' y dio ' || v_total);
  end if;

  -- G7: la vista
  select presupuestado_usd, gasto_real_usd, desviacion_usd
    into v_pres, v_gasto, v_desv
    from v_presupuesto_real where id_presupuesto = v_pre;

  if abs(v_gasto - v_esperado) > 0.02 then
    falla('G7', 'la vista dice gastado ' || v_gasto);
  end if;
  if abs(v_desv - (v_pres - v_esperado)) > 0.02 then
    falla('G7', 'desviacion incoherente: ' || v_desv);
  end if;

  -- G8: monto invalido
  begin
    pkg_gasto_real.prc_guardar_gasto(
        p_id_gasto => v_g1, p_id_presupuesto => v_pre,
        p_fecha_gasto => sysdate, p_monto_origen => 0,
        p_moneda_origen => 'USD');
    falla('G8', 'acepto monto cero');
  exception
    when others then
      if sqlcode <> -20041 then falla('G8', 'fallo con ' || sqlcode); end if;
  end;

  -- G9: presupuesto inexistente
  begin
    pkg_gasto_real.prc_guardar_gasto(
        p_id_gasto => v_g1, p_id_presupuesto => 999999,
        p_fecha_gasto => sysdate, p_monto_origen => 10,
        p_moneda_origen => 'USD');
    falla('G9', 'acepto un presupuesto inexistente');
  exception
    when others then
      if sqlcode <> -20042 then falla('G9', 'fallo con ' || sqlcode); end if;
  end;

  -- G10: presupuesto de otra empresa (usuario de la empresa 1)
  begin
    pkg_gasto_real.prc_guardar_gasto(
        p_id_gasto => v_g1, p_id_presupuesto => v_pre2,
        p_fecha_gasto => sysdate, p_monto_origen => 10,
        p_moneda_origen => 'MXN', p_usuario => 'luis');
    falla('G10', 'acepto un presupuesto de otra empresa');
  exception
    when others then
      if sqlcode <> -20003 then falla('G10', 'fallo con ' || sqlcode); end if;
  end;

  -- G11: moneda sin tasa -> -20060, no un 1 silencioso
  begin
    pkg_gasto_real.prc_guardar_gasto(
        p_id_gasto => v_g1, p_id_presupuesto => v_pre,
        p_fecha_gasto => sysdate, p_monto_origen => 10,
        p_moneda_origen => 'GBP');
    falla('G11', 'acepto GBP sin tasa de cambio');
  exception
    when others then
      -- -20055: falta la tasa porque el gasto no esta en la moneda del presupuesto;
      -- -20060: hay tasa tecleada pero no la del dia para convertir a dolares.
      if sqlcode not in (-20055, -20060) then falla('G11', 'fallo con ' || sqlcode); end if;
  end;

  -- G12: baja
  pkg_gasto_real.prc_eliminar_gasto(v_g2);
  if abs(pkg_gasto_real.fn_total_gasto_usd(v_pre)
         - (v_esperado - round(50 * (v_rmxn * 2) / v_rusd, 2))) > 0.02 then
    falla('G12', 'el total no bajo al quitar el gasto en MXN');
  end if;

  rollback;

  raise_application_error(-20100, 'RESULTADO: FALLAS=' || v_fallas || v_lista);
end;
/
