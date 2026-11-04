-- =============================================================================
-- 20261104_folio_unico.sql
--
-- Objetivo: impedir folios repetidos por empresa. Hoy la numeración la decide
--           solo la página (7 para presupuestos, 9 para facturas): dos altas
--           simultáneas pueden calcular el mismo número y la base lo acepta.
--
-- Responsable: dueño del esquema (WKSP_SYPEXWS) o ADMIN con ALTER ANY TABLE.
-- Base: Sypex_SQL (GFD7E2575D251AE_SYPEXSQL).
--
-- Precondiciones:
--   - Sin duplicados ni nulos en las combinaciones que se van a indexar
--     (la validación de abajo debe devolver 0).
--   - Los folios de factura son correlativos por empresa SIN importar el tipo
--     de documento (medido: FAC F-1001..F-1032, NC F-1033..F-1037,
--     ND F-1038..F-1040), por eso el índice es (ID_EMPRESA, FOLIO_FACTURA) y
--     no incluye TIPO_DOCUMENTO.
--
-- Afecta a: PRESUPUESTOS y FACTURAS (solo metadatos: dos índices únicos).
--           No toca datos.
--
-- OJO: a partir de aquí un folio repetido falla con
--      ORA-00001: unique constraint (WKSP_SYPEXWS.UQ_..._FOLIO) violated
--      y la página lo muestra envuelto en su mensaje de error.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;

-- -----------------------------------------------------------------------------
-- Validación ANTES: debe devolver 0 en ambas filas
-- -----------------------------------------------------------------------------
select 'antes: duplicados presupuestos' as control, count(*) as filas
  from (select id_empresa, folio
          from presupuestos
         group by id_empresa, folio
        having count(*) > 1);

select 'antes: duplicados facturas' as control, count(*) as filas
  from (select id_empresa, folio_factura
          from facturas
         group by id_empresa, folio_factura
        having count(*) > 1);

select 'antes: nulos' as control,
       (select count(*) from presupuestos where folio is null) as folio_pres_nulo,
       (select count(*) from facturas where folio_factura is null) as folio_fact_null
  from dual;

-- -----------------------------------------------------------------------------
-- Avance
-- -----------------------------------------------------------------------------
alter table presupuestos add constraint uq_presupuestos_folio unique (id_empresa, folio) enable;

alter table facturas add constraint uq_facturas_folio unique (id_empresa, folio_factura) enable;

-- -----------------------------------------------------------------------------
-- Validación DESPUÉS: las dos restricciones UNIQUE habilitadas y sus índices
-- -----------------------------------------------------------------------------
select 'despues: restricciones' as control, constraint_name, status, validated
  from all_constraints
 where owner = 'WKSP_SYPEXWS'
   and constraint_name in ('UQ_PRESUPUESTOS_FOLIO', 'UQ_FACTURAS_FOLIO')
 order by constraint_name;

select 'despues: indices' as control, index_name, uniqueness, status
  from all_indexes
 where owner = 'WKSP_SYPEXWS'
   and index_name in ('UQ_PRESUPUESTOS_FOLIO', 'UQ_FACTURAS_FOLIO')
 order by index_name;

-- Prueba del caso que ahora falla (deja el dato y lo revierte):
--   insert into presupuestos (id_empresa, folio, id_cliente)
--   select id_empresa, folio, id_cliente from presupuestos where id_presupuesto = (select min(id_presupuesto) from presupuestos);
--   -> ORA-00001: unique constraint (WKSP_SYPEXWS.UQ_PRESUPUESTOS_FOLIO) violated
--   rollback;

-- -----------------------------------------------------------------------------
-- Reversa
-- -----------------------------------------------------------------------------
-- alter table presupuestos drop constraint uq_presupuestos_folio;
-- alter table facturas drop constraint uq_facturas_folio;

commit;
