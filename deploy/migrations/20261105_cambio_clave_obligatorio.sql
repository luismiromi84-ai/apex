-- =============================================================================
-- 20261105_cambio_clave_obligatorio.sql
--
-- Objetivo: marcar en USUARIO las cuentas cuya clave la eligio un administrador
--           (alta desde la pagina 2, alta/reseteo desde la pagina 4), para
--           obligar a cambiarla en el primer login.
--
-- Responsable: dueno del esquema (WKSP_SYPEXWS) o ADMIN con ALTER ANY TABLE.
-- Base: Sypex_SQL (GFD7E2575D251AE_SYPEXSQL).
--
-- Afecta a: USUARIO (solo metadatos: una columna con DEFAULT 'N' NOT NULL y su
--           CHECK). No toca datos: las 14 filas existentes quedan en 'N' por el
--           DEFAULT (medido el 2026-11-05 antes y despues).
--
-- Ejecutar:
--   python deploy/conexion/importar_export.py deploy/migrations/20261105_cambio_clave_obligatorio.sql
--
-- REVERSA:
--   alter table usuario drop column debe_cambiar_clave;
--   (el DROP COLUMN se lleva por delante el CHECK ck_usuario_debe_cambiar;
--    no hay otra tabla ni indice que dependa de la columna)
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;
/

-- -----------------------------------------------------------------------------
-- Validacion ANTES: si la columna no existe, devuelve la fila que lo dice.
-- Antes de aplicar esta migracion debe devolver 1 fila (RED).
-- -----------------------------------------------------------------------------
select 'FALLA: falta DEBE_CAMBIAR_CLAVE' as caso from dual
 where not exists (select 1 from all_tab_columns
                    where owner='WKSP_SYPEXWS' and table_name='USUARIO'
                      and column_name='DEBE_CAMBIAR_CLAVE');
/

-- -----------------------------------------------------------------------------
-- Avance
-- -----------------------------------------------------------------------------
alter table usuario add (debe_cambiar_clave char(1) default 'N' not null enable);
/

alter table usuario add constraint ck_usuario_debe_cambiar
  check (debe_cambiar_clave in ('S','N')) enable;
/

-- -----------------------------------------------------------------------------
-- Validacion DESPUES: los tres select deben devolver CERO filas (GREEN).
-- -----------------------------------------------------------------------------
select 'FALLA: columna ausente' as caso from dual
 where not exists (select 1 from all_tab_columns
                    where owner='WKSP_SYPEXWS' and table_name='USUARIO'
                      and column_name='DEBE_CAMBIAR_CLAVE');
/

select 'FALLA: quedan nulos' as caso from dual
 where exists (select 1 from usuario where debe_cambiar_clave is null);
/

select 'FALLA: valores raros' as caso from dual
 where exists (select 1 from usuario where debe_cambiar_clave not in ('S','N'));
/

-- Constancia de como quedo la columna y el CHECK (no es una validacion).
select column_name, data_type, data_length, nullable, data_default
  from all_tab_columns
 where owner = 'WKSP_SYPEXWS' and table_name = 'USUARIO'
   and column_name = 'DEBE_CAMBIAR_CLAVE';
/

select constraint_name, constraint_type, status, validated, search_condition
  from all_constraints
 where owner = 'WKSP_SYPEXWS' and table_name = 'USUARIO'
   and constraint_name = 'CK_USUARIO_DEBE_CAMBIAR';
/

commit;
/
