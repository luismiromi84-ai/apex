-- Synpex - instalación de PACKAGE BODY
-- Los bodies NO están versionados todavía. Primero ejecutar deploy/export_bodies.sql
-- y confirmar que package_bodies/ contiene los 7 archivos.
-- Ejecutar desde la raíz del repositorio:
--   sqlplus usuario/clave@servicio @deploy/install_bodies.sql

set define off
set verify off
set feedback on
whenever sqlerror exit sql.sqlcode rollback

@@../package_bodies/pkg_usuario.sql
@@../package_bodies/pkg_presupuestos.sql
@@../package_bodies/pkg_presupuesto_detalle.sql
@@../package_bodies/pkg_facturacion.sql
@@../package_bodies/pkg_factura_detalle.sql
@@../package_bodies/pkg_reportes_presupuesto.sql
@@../package_bodies/pkg_reportes_factura.sql

prompt Bodies compilados. Ejecutar @deploy/verify.sql
