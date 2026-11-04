-- Synpex - verificación posterior al despliegue
-- Ejecutar desde la raíz del repositorio:
--   sqlplus usuario/clave@servicio @deploy/verify.sql

set pagesize 300
set linesize 200
set feedback off
set trimspool on

column object_name format a40
column object_type format a20
column status format a10

prompt ============================================================
prompt Usuario conectado
prompt ============================================================
show user

prompt ============================================================
prompt Objetos por tipo
prompt ============================================================
select object_type, count(*) as cantidad
  from user_objects
 where object_type in ('TABLE', 'SEQUENCE', 'INDEX', 'TRIGGER', 'FUNCTION', 'PROCEDURE', 'PACKAGE', 'PACKAGE BODY')
 group by object_type
 order by object_type;

prompt ============================================================
prompt Packages sin body (deben ser 0)
prompt ============================================================
select p.object_name
  from user_objects p
 where p.object_type = 'PACKAGE'
   and not exists (
       select 1
         from user_objects b
        where b.object_type = 'PACKAGE BODY'
          and b.object_name = p.object_name
   )
 order by p.object_name;

prompt ============================================================
prompt Objetos inválidos (deben ser 0)
prompt ============================================================
select object_type, object_name, status
  from user_objects
 where status <> 'VALID'
   and object_type in ('PACKAGE', 'PACKAGE BODY', 'PROCEDURE', 'FUNCTION', 'TRIGGER', 'VIEW')
 order by object_type, object_name;

prompt ============================================================
prompt Triggers
prompt ============================================================
select trigger_name, status
  from user_triggers
 order by trigger_name;

prompt ============================================================
prompt Tablas esperadas
prompt ============================================================
select table_name
  from user_tables
 where table_name in (
       'EMPRESAS', 'SYN_ROLES', 'USUARIO', 'CLIENTES', 'IMPUESTOS',
       'TIPO_CAMBIO', 'TIPO_DOCUMENTO', 'FORMA_PAGO', 'CONDICION_PAGO',
       'PRODUCTO_SERVICIO', 'PRESUPUESTOS', 'PRESUPUESTOS_DET',
       'FACTURAS', 'FACTURAS_DET', 'GASTO_REAL'
 )
 order by table_name;
