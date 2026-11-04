-- Synpex - exportación de PACKAGE BODY desde la base
-- Ejecutar desde la raíz del repositorio, conectado como dueño del esquema:
--   sqlplus usuario/clave@servicio @deploy/export_bodies.sql
-- Genera un archivo por package en package_bodies/.

set define off
set pagesize 0
set linesize 32767
set long 20000000
set longchunksize 32767
set heading off
set feedback off
set echo off
set verify off
set trimspool on

begin
  dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'EMIT_SCHEMA', false);
  dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'PRETTY', true);
  dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'SQLTERMINATOR', true);
end;
/

spool package_bodies/pkg_usuario.sql
select dbms_metadata.get_ddl('PACKAGE_BODY', 'PKG_USUARIO') from dual;
prompt /
spool off

spool package_bodies/pkg_presupuestos.sql
select dbms_metadata.get_ddl('PACKAGE_BODY', 'PKG_PRESUPUESTOS') from dual;
prompt /
spool off

spool package_bodies/pkg_presupuesto_detalle.sql
select dbms_metadata.get_ddl('PACKAGE_BODY', 'PKG_PRESUPUESTO_DETALLE') from dual;
prompt /
spool off

spool package_bodies/pkg_facturacion.sql
select dbms_metadata.get_ddl('PACKAGE_BODY', 'PKG_FACTURACION') from dual;
prompt /
spool off

spool package_bodies/pkg_factura_detalle.sql
select dbms_metadata.get_ddl('PACKAGE_BODY', 'PKG_FACTURA_DETALLE') from dual;
prompt /
spool off

spool package_bodies/pkg_reportes_presupuesto.sql
select dbms_metadata.get_ddl('PACKAGE_BODY', 'PKG_REPORTES_PRESUPUESTO') from dual;
prompt /
spool off

spool package_bodies/pkg_reportes_factura.sql
select dbms_metadata.get_ddl('PACKAGE_BODY', 'PKG_REPORTES_FACTURA') from dual;
prompt /
spool off

prompt Exportación terminada. Revisar package_bodies/ y ejecutar @deploy/install_bodies.sql
