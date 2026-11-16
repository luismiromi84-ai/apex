-- =============================================================================
-- 20261109_nota_detalle_origen.sql
--
-- Agrega FACTURAS_DET.ID_DETALLE_ORIGEN: la trazabilidad linea a linea de la nota
-- de credito. Cada linea de la nota apunta a la linea exacta de la factura que
-- acredita, y el tope ("no acreditar mas de lo facturado") se controla contra esa
-- linea, no por producto: un mismo producto puede repetirse en dos lineas de la
-- misma factura y el tope por producto no distinguiria cual se acredito.
--
-- Idempotente: si la columna, la FK o el indice ya existen, no hace nada.
-- Al final recompila el esquema: un `alter table` sobre FACTURAS_DET deja
-- TRG_ACTUALIZA_TOTALES_FACTURA y los packages del detalle en INVALID.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
  v_n number;
begin
  select count(*) into v_n
    from all_tab_columns
   where owner = 'WKSP_SYPEXWS'
     and table_name = 'FACTURAS_DET'
     and column_name = 'ID_DETALLE_ORIGEN';
  if v_n = 0 then
    execute immediate 'alter table facturas_det add (id_detalle_origen number)';
  end if;
end;
/

declare
  v_n number;
begin
  select count(*) into v_n
    from all_constraints
   where owner = 'WKSP_SYPEXWS'
     and table_name = 'FACTURAS_DET'
     and constraint_name = 'FK_FACT_DET_ORIGEN';
  if v_n = 0 then
    execute immediate 'alter table facturas_det add constraint fk_fact_det_origen '
                   || 'foreign key (id_detalle_origen) references facturas_det (id_detalle) enable';
  end if;
end;
/

declare
  v_n number;
begin
  select count(*) into v_n
    from all_indexes
   where owner = 'WKSP_SYPEXWS'
     and table_name = 'FACTURAS_DET'
     and index_name = 'IX_FACT_DET_ORIGEN';
  if v_n = 0 then
    execute immediate 'create index ix_fact_det_origen on facturas_det (id_detalle_origen)';
  end if;
end;
/

begin
  dbms_utility.compile_schema('WKSP_SYPEXWS', false);
end;
/

-- Constancia: la columna, la FK, el indice y 0 invalidos.
select count(*) as columna
  from all_tab_columns
 where owner = 'WKSP_SYPEXWS' and table_name = 'FACTURAS_DET'
   and column_name = 'ID_DETALLE_ORIGEN'
/

select count(*) as fk
  from all_constraints
 where owner = 'WKSP_SYPEXWS' and table_name = 'FACTURAS_DET'
   and constraint_name = 'FK_FACT_DET_ORIGEN'
/

select count(*) as indice
  from all_indexes
 where owner = 'WKSP_SYPEXWS' and table_name = 'FACTURAS_DET'
   and index_name = 'IX_FACT_DET_ORIGEN'
/

select count(*) as invalidos
  from all_objects
 where owner = 'WKSP_SYPEXWS' and status <> 'VALID'
/
