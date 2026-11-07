-- =============================================================================
-- Verificacion del folio atomico por empresa (2026-11-07)
--
-- Comprueba FOLIO_CONTADOR, fn_asignar_folio y fn_siguiente_folio, y que los
-- packages ya no usen el folio que manda la pagina al insertar.
--
-- Todo va en una transaccion con ROLLBACK: no deja documentos de prueba.
--
-- Casos:
--   F1  fn_siguiente_folio devuelve ultimo+1 y NO mueve el contador
--   F2  fn_asignar_folio incrementa de uno en uno
--   F3  formato por tipo: FAC -> F-n, NC -> NC-n, ND -> ND-n
--   F3d NC y ND llevan series independientes
--   F4  el presupuesto guardado ignora el folio de la pagina y usa el contador
--   F5  dos notas de credito seguidas llevan correlativo propio (NC-1, NC-2...)
--   F6  el UNIQUE por empresa sigue rechazando un folio repetido a mano
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;
/

declare
  v_fallas  number := 0;
  v_lista   varchar2(3000) := '';
  v_caso    varchar2(20);
  v_ultimo  number;
  v_txt     varchar2(50);
  v_id      number;
  v_folio   number;
  v_folio_f varchar2(50);
  v_tipo    varchar2(20);
  v_cli     number;
  v_emp     number := 1;

  procedure falla (p_caso in varchar2, p_detalle in varchar2) is
  begin
    v_fallas := v_fallas + 1;
    v_lista  := v_lista || ' | ' || p_caso || ': ' || p_detalle;
  end falla;

  function num (p_txt in varchar2) return number is
  begin
    return to_number(regexp_substr(p_txt, '[0-9]+$'));
  end num;
begin
  select min(id_cliente) into v_cli from clientes where id_empresa = v_emp;

  -- F1: la vista previa no mueve el contador
  select nvl(max(ultimo), 0) into v_ultimo from folio_contador
   where id_empresa = v_emp and tipo = 'PRESUPUESTO';
  v_txt := fn_siguiente_folio(v_emp, 'PRESUPUESTO');
  if to_number(v_txt) <> v_ultimo + 1 then
    falla('F1', 'fn_siguiente_folio devolvio ' || v_txt || ' con ultimo=' || v_ultimo);
  end if;
  select nvl(max(ultimo), 0) into v_id from folio_contador
   where id_empresa = v_emp and tipo = 'PRESUPUESTO';
  if v_id <> v_ultimo then
    falla('F1', 'la vista previa movio el contador de ' || v_ultimo || ' a ' || v_id);
  end if;

  -- F2: asignar incrementa de uno en uno
  v_txt := fn_asignar_folio(v_emp, 'PRESUPUESTO');
  if to_number(v_txt) <> v_ultimo + 1 then
    falla('F2', 'primer folio asignado ' || v_txt || ', esperaba ' || (v_ultimo + 1));
  end if;
  if to_number(fn_asignar_folio(v_emp, 'PRESUPUESTO')) <> v_ultimo + 2 then
    falla('F2', 'el segundo folio no fue consecutivo');
  end if;

  -- F3: formato por tipo
  v_txt := fn_asignar_folio(v_emp, 'FAC');
  if not regexp_like(v_txt, '^F-[0-9]+$') then
    falla('F3', 'FAC devolvio ' || v_txt);
  end if;
  v_txt := fn_asignar_folio(v_emp, 'NC');
  if not regexp_like(v_txt, '^NC-[0-9]+$') then
    falla('F3', 'NC devolvio ' || v_txt);
  end if;
  v_txt := fn_asignar_folio(v_emp, 'ND');
  if not regexp_like(v_txt, '^ND-[0-9]+$') then
    falla('F3', 'ND devolvio ' || v_txt);
  end if;

  -- F3d: series independientes
  if num(fn_siguiente_folio(v_emp, 'NC')) <> num(fn_siguiente_folio(v_emp, 'ND')) then
    falla('F3d', 'NC y ND comparten contador (' || fn_siguiente_folio(v_emp, 'NC')
                 || ' / ' || fn_siguiente_folio(v_emp, 'ND') || ')');
  end if;

  -- F4: el package ignora el folio de la pagina
  v_id := null;
  pkg_presupuestos.prc_guardar_presupuesto(
      p_id_presupuesto    => v_id,
      p_id_empresa        => v_emp,
      p_id_cliente        => v_cli,
      p_folio             => '9999',
      p_cod_moneda        => 'VES',
      p_fecha_vencimiento => sysdate + 30,
      p_fecha_emision     => sysdate,
      p_tipo_cambio       => 1,
      p_estado            => 'PENDIENTE',
      p_observaciones     => 'verificacion folio',
      p_usuario           => 'VERIFICACION');
  select folio into v_folio from presupuestos where id_presupuesto = v_id;
  if v_folio = 9999 or v_folio <> v_ultimo + 3 then
    falla('F4', 'guardo el folio ' || v_folio || ' (esperaba ' || (v_ultimo + 3) || ')');
  end if;

  -- F5: dos notas de credito seguidas
  for i in 1 .. 2 loop
    v_id := null;
    pkg_facturacion.prc_guardar_factura(
        p_id_factura        => v_id,
        p_id_empresa        => v_emp,
        p_folio_factura     => 'F-1',
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
        p_fecha_vencimiento => null,
        p_estado            => 'PENDIENTE',
        p_subtotal          => 0,
        p_monto_impuesto    => 0,
        p_monto_total       => 0,
        p_observaciones     => 'verificacion folio NC',
        p_cod_moneda        => 'VES',
        p_tipo_cambio       => 1,
        p_usuario           => 'VERIFICACION',
        p_tipo_documento    => 'NC');
    select folio_factura, tipo_documento into v_folio_f, v_tipo
      from facturas where id_factura = v_id;
    if not regexp_like(v_folio_f, '^NC-[0-9]+$') or v_tipo <> 'NC' then
      falla('F5', 'nota de credito ' || i || ' quedo como ' || v_folio_f || ' / ' || v_tipo);
    end if;
    if i = 1 and v_id is null then
      falla('F5', 'no devolvio el id de la nota de credito');
    end if;
  end loop;

  -- F6: el UNIQUE por empresa sigue protegiendo
  begin
    insert into facturas (id_empresa, folio_factura, id_cliente, fecha_emision,
                          estado, cod_moneda, tipo_cambio, creado_por)
    values (v_emp, v_folio_f, v_cli, sysdate, 'PENDIENTE', 'USD', 1, 'VERIFICACION');
    falla('F6', 'acepto un folio repetido (' || v_folio_f || ')');
  exception
    when dup_val_on_index then
      null;
  end;

  rollback;

  raise_application_error(-20100, 'RESULTADO: FALLAS=' || v_fallas || v_lista);
end;
/
