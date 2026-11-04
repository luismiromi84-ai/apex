-- =============================================================================
-- 20261103_tipo_tasa_12.sql
--
-- Objetivo: corregir TIPO_CAMBIO.TIPO_TASA, que es VARCHAR2(10) mientras su
--           CHECK admite 'PRESUPUESTO' (11 caracteres). Hoy el CHECK es
--           insatisfacible para esa rama y cualquier INSERT con ese valor
--           falla con ORA-12899.
--
-- Responsable: dueño del esquema (WKSP_SYPEXWS) o ADMIN con ALTER ANY TABLE.
-- Base: Sypex_SQL (GFD7E2575D251AE_SYPEXSQL).
--
-- Precondiciones:
--   - No es necesario ventana de mantenimiento: es un ALTER de metadatos sobre
--     36 filas (o 24 en el dataset de ejemplo).
--   - Backup del esquema antes de ejecutar, como en cualquier migración.
--
-- Afecta a: TIPO_CAMBIO (una columna). No toca datos existentes.
-- =============================================================================

-- Ejecutable como WKSP_SYPEXWS o como ADMIN con ALTER ANY TABLE.
alter session set current_schema = WKSP_SYPEXWS;

-- -----------------------------------------------------------------------------
-- Validación ANTES: la columna debe medir 10 y no debe haber valores > 10
-- -----------------------------------------------------------------------------
select 'antes: longitud' as control, data_length
  from all_tab_columns
 where owner = 'WKSP_SYPEXWS' and table_name = 'TIPO_CAMBIO' and column_name = 'TIPO_TASA';

select 'antes: valores fuera de rango' as control, count(*) as filas
  from tipo_cambio
 where length(tipo_tasa) > 12;

-- -----------------------------------------------------------------------------
-- Avance
-- -----------------------------------------------------------------------------
alter table tipo_cambio modify (tipo_tasa varchar2(12));

-- -----------------------------------------------------------------------------
-- Validación DESPUÉS: longitud 12 y el CHECK sigue activo
-- -----------------------------------------------------------------------------
select 'despues: longitud' as control, data_length
  from all_tab_columns
 where owner = 'WKSP_SYPEXWS' and table_name = 'TIPO_CAMBIO' and column_name = 'TIPO_TASA';

select 'despues: check' as control, constraint_name, status
  from all_constraints
 where owner = 'WKSP_SYPEXWS' and table_name = 'TIPO_CAMBIO' and constraint_type = 'C';

-- Prueba del caso que fallaba (deja el dato y lo revierte):
-- insert into tipo_cambio (moneda_origen, moneda_destino, tipo_tasa, tasa_cambio, fecha_vigencia)
-- values ('USD','VES','PRESUPUESTO', 56.10, trunc(sysdate));
-- rollback;

-- -----------------------------------------------------------------------------
-- Reversa
--   Ojo: solo es válida si no existen filas con tipo_tasa de 11 caracteres.
--   Comprobarlo antes:
--     select count(*) from tipo_cambio where length(tipo_tasa) > 10;
--   Debe dar 0.
-- -----------------------------------------------------------------------------
-- alter table tipo_cambio modify (tipo_tasa varchar2(10));

commit;
