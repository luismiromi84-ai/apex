-- =============================================================================
-- Verificacion de la columna FACTURAS_DET.ID_DETALLE_ORIGEN (2026-11-09)
--
-- Es la trazabilidad linea a linea de la nota de credito: cada linea de la nota
-- apunta a la linea exacta de la factura que acredita. Sin ella el tope solo se
-- podria controlar por producto, y un producto puede repetirse en dos lineas.
--
-- Casos:
--   C1  la columna existe, es NUMBER y admite nulos
--   C2  existe la FK FK_FACT_DET_ORIGEN hacia FACTURAS_DET
--   C3  existe el indice IX_FACT_DET_ORIGEN
--   C4  ninguna fila existente la tiene informada (las viejas quedan en nulo)
--   C5  0 objetos invalidos en el esquema
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;
/

declare
  v_fallas number := 0;
  v_lista  varchar2(3000) := '';
  v_n      number;
  v_tipo   varchar2(30);
  v_null   varchar2(1);

  procedure falla (p_caso in varchar2, p_detalle in varchar2) is
  begin
    v_fallas := v_fallas + 1;
    v_lista  := v_lista || ' | ' || p_caso || ': ' || p_detalle;
  end falla;
begin
  -- C1: la columna existe con el tipo esperado y admite nulos
  begin
    select data_type, nullable into v_tipo, v_null
      from all_tab_columns
     where owner = 'WKSP_SYPEXWS'
       and table_name = 'FACTURAS_DET'
       and column_name = 'ID_DETALLE_ORIGEN';
    if v_tipo <> 'NUMBER' then
      falla('C1', 'tipo ' || v_tipo || ' en vez de NUMBER');
    end if;
    if v_null <> 'Y' then
      falla('C1', 'la columna no admite nulos');
    end if;
  exception
    when no_data_found then
      falla('C1', 'no existe la columna ID_DETALLE_ORIGEN');
  end;

  -- C2: la FK hacia la propia FACTURAS_DET
  select count(*) into v_n
    from all_constraints fk
    join all_constraints pk
      on pk.owner = fk.r_owner
     and pk.constraint_name = fk.r_constraint_name
   where fk.owner = 'WKSP_SYPEXWS'
     and fk.table_name = 'FACTURAS_DET'
     and fk.constraint_name = 'FK_FACT_DET_ORIGEN'
     and fk.constraint_type = 'R'
     and pk.table_name = 'FACTURAS_DET';
  if v_n = 0 then
    falla('C2', 'no existe la FK FK_FACT_DET_ORIGEN hacia FACTURAS_DET');
  end if;

  -- C3: el indice
  select count(*) into v_n
    from all_indexes
   where owner = 'WKSP_SYPEXWS'
     and table_name = 'FACTURAS_DET'
     and index_name = 'IX_FACT_DET_ORIGEN';
  if v_n = 0 then
    falla('C3', 'no existe el indice IX_FACT_DET_ORIGEN');
  end if;

  -- C4: las lineas con origen tienen que apuntar a una linea que existe.
  -- Originalmente la columna nacia vacia y el caso exigia cero filas informadas;
  -- desde que hay notas de credito reales (2026-11-16) eso ya no es cierto: lo
  -- que hay que vigilar es que no queden origenes huerfanos.
  begin
    select count(*) into v_n
      from facturas_det d
     where d.id_detalle_origen is not null
       and not exists (select 1 from facturas_det o
                        where o.id_detalle = d.id_detalle_origen);
    if v_n > 0 then
      falla('C4', v_n || ' linea(s) con id_detalle_origen huerfano');
    end if;
  exception
    when others then
      falla('C4', 'no se pudo consultar la columna: ' || sqlerrm);
  end;

  -- C5: nada invalido en el esquema
  select count(*) into v_n
    from all_objects
   where owner = 'WKSP_SYPEXWS' and status <> 'VALID';
  if v_n > 0 then
    falla('C5', v_n || ' objeto(s) invalido(s)');
  end if;

  raise_application_error(-20100, 'RESULTADO: FALLAS=' || v_fallas || v_lista);
end;
/
