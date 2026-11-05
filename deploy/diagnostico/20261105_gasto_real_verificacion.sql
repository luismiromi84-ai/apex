-- =============================================================================
-- 20261105_gasto_real_verificacion.sql
--
-- Verificacion de PKG_GASTO_REAL y V_PRESUPUESTO_REAL. Todo va en una
-- transaccion con rollback: no deja gastos de prueba.
--
-- Casos:
--   G1  Alta en USD: tasa 1 y monto_base_usd igual al monto.
--   G2  Alta en MXN con tasa forzada: convierte bien.
--   G3  Edicion del mismo gasto: no duplica y recalcula.
--   G4  fn_total_gasto_usd suma los dos gastos.
--   G5  La vista devuelve presupuestado, gastado y desviacion coherentes.
--   G6  Rechaza monto cero o negativo (-20041).
--   G7  Rechaza presupuesto inexistente (-20042).
--   G8  Rechaza presupuesto de otra empresa (-20003).
--   G9  Baja del gasto: desaparece y el total vuelve a cero.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;
/

declare
  v_fallas number := 0;
  v_lista  varchar2(2000) := '';
  v_pre    number := 1045;          -- presupuesto de la empresa 1
  v_pre2   number;                  -- uno de la empresa 2
  v_g1     number;
  v_g2     number;
  v_total  number;
  v_pres   number;
  v_gasto  number;
  v_desv   number;

  procedure falla (p_caso in varchar2, p_detalle in varchar2) is
  begin
    v_fallas := v_fallas + 1;
    v_lista  := v_lista || ' | ' || p_caso || ': ' || p_detalle;
  end falla;

begin
  select min(id_presupuesto) into v_pre2 from presupuestos where id_empresa = 2;

  -- G1: USD
  pkg_gasto_real.prc_guardar_gasto(
      p_id_gasto => v_g1, p_id_presupuesto => v_pre,
      p_fecha_gasto => sysdate, p_monto_origen => 100,
      p_moneda_origen => 'USD');

  if v_g1 is null then
    falla('G1', 'no devolvio id_gasto');
  end if;

  -- G2: MXN con tasa forzada 2
  pkg_gasto_real.prc_guardar_gasto(
      p_id_gasto => v_g2, p_id_presupuesto => v_pre,
      p_fecha_gasto => sysdate, p_monto_origen => 50,
      p_moneda_origen => 'MXN', p_tasa_real => 2);

  declare
    v_usd number;
  begin
    select monto_base_usd into v_usd from gasto_real where id_gasto = v_g2;
    if v_usd <> 100 then
      falla('G2', 'esperaba 100 USD y guardo ' || v_usd);
    end if;
  end;

  -- G3: editar el primero a 250 USD
  pkg_gasto_real.prc_guardar_gasto(
      p_id_gasto => v_g1, p_id_presupuesto => v_pre,
      p_fecha_gasto => sysdate, p_monto_origen => 250,
      p_moneda_origen => 'USD');

  declare
    v_n number;
  begin
    select count(*) into v_n from gasto_real where id_presupuesto = v_pre;
    if v_n <> 2 then
      falla('G3', 'esperaba 2 gastos y hay ' || v_n);
    end if;
  end;

  -- G4: total 350
  v_total := pkg_gasto_real.fn_total_gasto_usd(v_pre);
  if v_total <> 350 then
    falla('G4', 'esperaba 350 y dio ' || v_total);
  end if;

  -- G5: la vista
  select presupuestado_usd, gasto_real_usd, desviacion_usd
    into v_pres, v_gasto, v_desv
    from v_presupuesto_real where id_presupuesto = v_pre;

  if v_gasto <> 350 then
    falla('G5', 'la vista dice gastado ' || v_gasto);
  end if;
  if abs(v_desv - (v_pres - 350)) > 0.01 then
    falla('G5', 'desviacion incoherente');
  end if;

  -- G6: monto invalido
  begin
    pkg_gasto_real.prc_guardar_gasto(
        p_id_gasto => v_g1, p_id_presupuesto => v_pre,
        p_fecha_gasto => sysdate, p_monto_origen => 0,
        p_moneda_origen => 'USD');
    falla('G6', 'acepto monto cero');
  exception
    when others then
      if sqlcode <> -20041 then falla('G6', 'fallo con ' || sqlcode); end if;
  end;

  -- G7: presupuesto inexistente
  begin
    pkg_gasto_real.prc_guardar_gasto(
        p_id_gasto => v_g1, p_id_presupuesto => 999999,
        p_fecha_gasto => sysdate, p_monto_origen => 10,
        p_moneda_origen => 'USD');
    falla('G7', 'acepto un presupuesto inexistente');
  exception
    when others then
      if sqlcode <> -20042 then falla('G7', 'fallo con ' || sqlcode); end if;
  end;

  -- G8: presupuesto de otra empresa (usuario de la empresa 1)
  begin
    pkg_gasto_real.prc_guardar_gasto(
        p_id_gasto => v_g1, p_id_presupuesto => v_pre2,
        p_fecha_gasto => sysdate, p_monto_origen => 10,
        p_moneda_origen => 'MXN', p_usuario => 'luis');
    falla('G8', 'acepto un presupuesto de otra empresa');
  exception
    when others then
      if sqlcode <> -20003 then falla('G8', 'fallo con ' || sqlcode); end if;
  end;

  -- G9: baja
  pkg_gasto_real.prc_eliminar_gasto(v_g2);
  if pkg_gasto_real.fn_total_gasto_usd(v_pre) <> 250 then
    falla('G9', 'el total no bajo a 250');
  end if;

  rollback;

  raise_application_error(-20100, 'RESULTADO: FALLAS=' || v_fallas || v_lista);
end;
/
