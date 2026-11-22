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
prompt 1/8 Secuencias
prompt ============================================================
@@../sequencia/seq_producto_servicio.sql
@@../sequencia/seq_forma_pago.sql
@@../sequencia/seq_condicion_pago.sql

prompt ============================================================
prompt 2/8 Tablas, constraints, índices y triggers de totales
prompt ============================================================
@@../tabla/paises.sql
@@../tabla/empresas.sql
@@../tabla/syn_roles.sql
@@../tabla/usuario.sql
@@../tabla/usuario_empresa.sql
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
@@../tabla/empresa_logo.sql
@@../tabla/FACTURAS_DET.sql
-- Compras (libro de compras y ventas, 2026-11-16): proveedores antes que compras
-- por la FK, y las notas de compra despues de la cabecera.
-- El catalogo de conceptos de ISLR va antes de proveedores y compras por la FK.
@@../tabla/islr_conceptos.sql
@@../tabla/proveedores.sql
@@../tabla/compras.sql
@@../tabla/compras_det.sql
-- Retenciones de IVA e ISLR (2026-11-19): cabecera y lineas, despues de compras
-- por las FK. RETENCIONES_IVA queda como historico.
@@../tabla/retenciones.sql
@@../tabla/retenciones_det.sql
@@../tabla/retenciones_iva.sql
@@../tabla/retencion_contador.sql
-- Cobros (2026-11-17): recibos por factura; despues de FACTURAS y FORMA_PAGO por las FK.
@@../tabla/recibos.sql
@@../tabla/gasto_real.sql
@@../tabla/folio_contador.sql
@@../tabla/syn_parametros.sql
@@../tabla/log_tasas_bcv.sql
@@../tabla/syn_reset_password_log.sql

prompt ============================================================
prompt 3/8 Funciones y vistas
prompt ============================================================
prompt    Requiere, como ADMIN, antes de este bloque:
prompt      grant execute on sys.dbms_crypto to <esquema>;
prompt    prc_auth_registrar va antes porque fn_autenticar_usuario lo llama.
@@../procedimientos/prc_auth_registrar.sql
@@../funciones/sypex_hash_password.sql
@@../funciones/fn_verificar_password.sql
@@../funciones/fn_password_es_legado.sql
@@../funciones/fn_autenticar_usuario.sql
@@../funciones/fn_login_aviso.sql
@@../funciones/fn_formato_rif.sql
@@../funciones/fn_clean_num.sql
@@../funciones/fn_tasa_ves.sql
@@../funciones/fn_validar_tasa_documento.sql
@@../funciones/fn_tasa_cambio.sql
@@../funciones/fn_tiene_rol.sql
@@../funciones/fn_usuario_empresa_valida.sql
@@../funciones/fn_usuario_administrable.sql
@@../funciones/fn_presupuesto_propio.sql
@@../funciones/fn_factura_propio.sql
@@../funciones/fn_factura_editable.sql
@@../funciones/fn_factura_cobrable.sql
@@../funciones/fn_estado_factura.sql
@@../funciones/fn_estado_compra.sql
@@../funciones/fn_compra_tiene_islr.sql
@@../funciones/fn_compra_tiene_iva.sql
@@../funciones/fn_imprimir_retencion.sql
@@../funciones/fn_forma_pago_pide_ref.sql
@@../funciones/fn_presupuesto_editable.sql
@@../funciones/fn_nota_traible.sql
@@../funciones/fn_nota_con_lineas.sql
@@../funciones/fn_rif_cliente_valido.sql
@@../funciones/fn_rif_empresa_valido.sql
@@../funciones/fn_empresa_activa.sql
@@../funciones/fn_iva_retenido_bs.sql
-- Cobros e IGTF (2026-11-17): saldo de la factura y alicuota configurada.
@@../funciones/fn_saldo_factura.sql
@@../funciones/fn_alicuota_igtf.sql
@@../funciones/fn_transicion_estado_valida.sql
-- Folio atomico por empresa (lo llaman pkg_presupuestos y pkg_facturacion).
@@../funciones/fn_asignar_folio.sql  
@@../funciones/fn_siguiente_folio.sql
@@../funciones/fn_control_en_rango.sql
@@../funciones/fn_asignar_control.sql
-- Excel fiscal del libro de compras y ventas (lo usa el proceso de la pagina 26).
@@../funciones/fn_periodo_desde.sql
@@../funciones/fn_periodo_hasta.sql
@@../funciones/fn_libro_excel.sql  
-- Recibo de cobro en papel (lo usa la region de la pagina 35).
@@../funciones/fn_imprimir_recibo.sql

-- Monitoreo de errores: el procedimiento va antes porque fn_error_handler lo llama.
@@../procedimientos/prc_log_error.sql
@@../funciones/fn_error_handler.sql

-- Vistas (dependen de tablas y del paquete de gasto real, pero no del body).
@@../vistas/v_presupuesto_real.sql
@@../vistas/v_empresas_usuario.sql

prompt ============================================================
prompt 4/8 Especificaciones de packages
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
@@../package/pkg_retenciones.sql
@@../package/pkg_compras.sql
@@../package/pkg_compra_detalle.sql
-- Cobros (2026-11-17)
@@../package/pkg_cobros.sql

prompt ============================================================
prompt 5/8 Triggers de estado
prompt ============================================================
prompt    Van despues de fn_transicion_estado_valida (bloque 3).
@@../trigger/trg_valida_estado_presupuesto.sql
@@../trigger/trg_valida_estado_factura.sql
-- Compras: los totales de la cabecera salen del detalle.
@@../trigger/trg_actualiza_totales_compra.sql
-- Multiempresa: la empresa "principal" del usuario queda siempre asociada.
@@../trigger/trg_usuario_empresa_principal.sql

prompt ============================================================
prompt 6/8 Procedimientos
prompt ============================================================
@@../procedimientos/prc_post_login.sql
@@../procedimientos/prc_empresas_usuario.sql
@@../procedimientos/prc_actualizar_tasas_diarias.sql
@@../procedimientos/prc_job_tasas_bcv.sql
@@../procedimientos/prc_log_reset_password.sql
@@../procedimientos/prc_purgar_logs.sql
@@../procedimientos/prc_anular_factura_nc.sql

prompt ============================================================
prompt 7/8 Jobs y datos mínimos
prompt ============================================================
@@install_jobs.sql
@@install_datos.sql

prompt ============================================================
prompt 8/8 Verificación
prompt ============================================================
@@verify.sql

prompt ============================================================
prompt INSTALACIÓN BASE COMPLETA
prompt FALTA: ejecutar @@install_bodies.sql con los bodies exportados.
prompt FALTA: importar pagina_apex/f100.sql desde APEX.
prompt ============================================================
