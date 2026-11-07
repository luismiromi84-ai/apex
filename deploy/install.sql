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
@@../tabla/syn_login_log.sql
@@../tabla/syn_error_log.sql
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
@@../tabla/empresa_fiscal.sql
@@../tabla/FACTURAS_DET.sql
@@../tabla/gasto_real.sql
@@../tabla/syn_reset_password_log.sql

prompt ============================================================
prompt 3/6 Funciones
prompt ============================================================
prompt    Requiere, como ADMIN, antes de este bloque:
prompt      grant execute on sys.dbms_crypto to <esquema>;
prompt    prc_auth_registrar va antes porque fn_autenticar_usuario lo llama.
@@../procedimientos/prc_auth_registrar.sql
@@../funciones/sypex_hash_password.sql
@@../funciones/fn_verificar_password.sql
@@../funciones/fn_password_es_legado.sql
@@../funciones/fn_autenticar_usuario.sql
@@../funciones/fn_clean_num.sql
@@../funciones/fn_tasa_ves.sql
@@../funciones/fn_validar_tasa_documento.sql
@@../funciones/fn_tasa_cambio.sql
@@../funciones/fn_tiene_rol.sql
@@../funciones/fn_usuario_empresa_valida.sql
@@../funciones/fn_presupuesto_propio.sql
@@../funciones/fn_factura_propio.sql
@@../funciones/fn_factura_editable.sql
@@../funciones/fn_presupuesto_editable.sql
@@../funciones/fn_transicion_estado_valida.sql
@@../funciones/fn_empresas_del_usuario.sql  

-- Monitoreo de errores: el procedimiento va antes porque fn_error_handler lo llama.
@@../procedimientos/prc_log_error.sql
@@../funciones/fn_error_handler.sql

prompt ============================================================
prompt 4/6 Especificaciones de packages
prompt ============================================================
@@../package/pkg_usuario.sql
@@../package/pkg_presupuestos.sql
@@../package/pkg_presupuesto_detalle.sql
@@../package/pkg_facturacion.sql
@@../package/pkg_factura_detalle.sql
@@../package/pkg_gasto_real.sql
@@../package/pkg_empresa_logo.sql
@@../package/pkg_reportes_presupuesto.sql
@@../package/pkg_reportes_factura.sql

prompt ============================================================
prompt 5/6 Procedimientos
prompt ============================================================
@@../procedimientos/prc_post_login.sql
@@../procedimientos/prc_actualizar_tasas_diarias.sql
@@../procedimientos/prc_log_reset_password.sql
@@../procedimientos/prc_purgar_logs.sql

prompt ============================================================
prompt 6/6 Verificación
prompt ============================================================
@@verify.sql

prompt ============================================================
prompt INSTALACIÓN BASE COMPLETA
prompt FALTA: ejecutar @@install_bodies.sql con los bodies exportados.
prompt FALTA: importar pagina_apex/f100.sql desde APEX.
prompt ============================================================
