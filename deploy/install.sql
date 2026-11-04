-- Synpex - instalación limpia del esquema
-- Ejecutar SIEMPRE desde la raíz del repositorio:
--   sqlplus usuario/clave@servicio @deploy/install.sql
-- Requiere un esquema VACÍO. No ejecutar sobre producción ni sobre una base con objetos existentes.

set define off
set verify off
set feedback on
set serveroutput on size unlimited
whenever sqlerror exit sql.sqlcode rollback

prompt ============================================================
prompt 1/6 Secuencias
prompt ============================================================
@@../sequencia/seq_producto_servicio.sql
@@../sequencia/seq_forma_pago.sql
@@../sequencia/seq_condicion_pago.sql

prompt ============================================================
prompt 2/6 Tablas, constraints, índices y triggers de totales
prompt ============================================================
@@../tabla/empresas.sql
@@../tabla/syn_roles.sql
@@../tabla/usuario.sql
@@../tabla/clientes.sql
@@../tabla/impuestos.sql
@@../tabla/tipo_cambio.sql
@@../tabla/tipo_documento.sql
@@../tabla/FORMA_PAGO.sql
@@../tabla/condicion_pago.sql
@@../tabla/producto_servicio.sql
@@../tabla/presupuestos.sql
@@../tabla/presupuestos_det.sql
@@../tabla/FACTURAS.sql
@@../tabla/FACTURAS_DET.sql
@@../tabla/gasto_real.sql

prompt ============================================================
prompt 3/6 Funciones
prompt ============================================================
@@../funciones/sypex_hash_password.sql
@@../funciones/fn_clean_num.sql
@@../funciones/fn_tasa_cambio.sql
@@../funciones/fn_autenticar_usuario.sql

prompt ============================================================
prompt 4/6 Especificaciones de packages
prompt ============================================================
@@../package/pkg_usuario.sql
@@../package/pkg_presupuestos.sql
@@../package/pkg_presupuesto_detalle.sql
@@../package/pkg_facturacion.sql
@@../package/pkg_factura_detalle.sql
@@../package/pkg_reportes_presupuesto.sql
@@../package/pkg_reportes_factura.sql

prompt ============================================================
prompt 5/6 Procedimientos
prompt ============================================================
@@../procedimientos/prc_post_login.sql
@@../procedimientos/prc_actualizar_tasas_diarias.sql

prompt ============================================================
prompt 6/6 Verificación
prompt ============================================================
@@verify.sql

prompt ============================================================
prompt INSTALACIÓN BASE COMPLETA
prompt FALTA: ejecutar @@install_bodies.sql con los bodies exportados.
prompt FALTA: importar pagina_apex/f100.sql desde APEX.
prompt ============================================================
