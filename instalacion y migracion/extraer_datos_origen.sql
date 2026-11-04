-- =============================================================================
-- extraer_datos_origen.sql
-- Extracción de DATOS de la base ORIGINAL (SypexSystem) hacia un archivo de
-- INSERT statements. SOLO LECTURA: no crea, altera ni borra nada.
--
-- Requiere SQLcl (usa `set sqlformat insert`, que no existe en APEX SQL
-- Workshop). Ejecutar conectado a la base ORIGINAL, nunca a Sypex_SQL:
--
--   sql /nolog
--   conn -name <alias_de_la_base_original>
--   @extraer_datos_origen.sql
--
-- Si el alias `sypexsystem` sigue roto (ORA-12261), recrearlo antes:
--   conn -save sypexsystem -savepwd ADMIN@<connect_string>
--
-- Salida: datos_origen.sql, en el orden que respeta las claves foráneas.
-- Ese archivo contiene datos reales (incluidos hashes de contraseña):
-- NO versionarlo ni compartirlo.
-- =============================================================================

set define off
set feedback off
set verify off
set pagesize 0
set linesize 32767
set trimspool on
set long 1000000
set sqlformat insert

spool datos_origen.sql

prompt -- 1/10 DEPT
select * from dept;

prompt -- 2/10 EMP
select * from emp;

prompt -- 3/10 SYN_ROLES
select * from syn_roles;

prompt -- 4/10 USUARIO
select * from usuario;

prompt -- 5/10 TIPO_CAMBIO
select * from tipo_cambio;

prompt -- 6/10 PRODUCTO_SERVICIO
select * from producto_servicio;

prompt -- 7/10 PRESUPUESTOS
select * from presupuestos;

prompt -- 8/10 PRESUPUESTOS_DET
select * from presupuestos_det;

prompt -- 9/10 FACTURAS
select * from facturas;

prompt -- 10/10 FACTURAS_DET
select * from facturas_det;

spool off

prompt
prompt Listo: datos_origen.sql generado en el directorio actual.
prompt Revisar que termine con las 10 tablas y luego cargarlo con cargar_datos_destino.sql
