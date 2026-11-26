-- =============================================================================
-- 20261108_fixture_prueba.sql
--
-- Datos MINIMOS para que las verificaciones de deploy/diagnostico puedan correr
-- despues de la purga del demo (2026-11-08). Antes dependian del dataset de
-- ejemplo (documentos 1000-1999 y usuarios admin.demo / luis / mx.demo), que ya
-- no existe.
--
-- QUE CREA (todo en el rango reservado 900000-900999, facil de borrar):
--   * usuarios  prueba1 (empresa 1, ADMIN) y prueba2 (empresa 2, ADMIN)
--               clave Prueba#2026, ACTIVO, sin cambio obligatorio
--   * producto  900001
--   * presupuestos 900001 PENDIENTE, 900002 CANCELADO, 900003 FACTURADO
--                 900021 PENDIENTE de la empresa 2
--   * facturas     900011 PENDIENTE, 900012 PAGADA, 900013 ANULADA
--                 900031 PENDIENTE de la empresa 2
--   * una linea por documento (los triggers de totales recalculan la cabecera)
--
-- QUE NO TOCA: empresas 1/2, clientes 1-3 y 201-203, roles, tasas del dia.
--
-- Es idempotente: primero borra el rango y luego lo vuelve a crear.
--
-- Uso:
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261108_fixture_prueba.sql
--   ... ejecutar las verificaciones ...
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261108_limpiar_fixture.sql
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;
/

-- -----------------------------------------------------------------------------
-- 1. Limpieza previa del rango (orden inverso a las FK). Cada borrado con su
--    COMMIT: varias DML sobre tablas con identity en la misma transaccion dan
--    ORA-12839/ORA-12860 en esta base (medido el 2026-11-08).
-- -----------------------------------------------------------------------------
delete from gasto_real where id_gasto between 900000 and 900999;
/
commit;
/

delete from facturas_det where id_detalle between 900000 and 900999;
/
commit;
/

delete from facturas where id_factura between 900000 and 900999;
/
commit;
/

delete from presupuestos_det where id_detalle between 900000 and 900999;
/
commit;
/

delete from presupuestos where id_presupuesto between 900000 and 900999;
/
commit;
/

delete from producto_servicio where id_producto_servicio between 900000 and 900999;
/
commit;
/

delete from usuario_empresa where usuario_id between 900000 and 900999;
/
commit;
/

delete from usuario where usuario_id between 900000 and 900999;
/
commit;
/

-- -----------------------------------------------------------------------------
-- 2. Usuarios de prueba (uno por empresa, para las pruebas de propiedad)
-- -----------------------------------------------------------------------------
insert into usuario (usuario_id, username, email, password_hash, estado, id_empresa, rol_id, debe_cambiar_clave)
values (900001, 'prueba1', 'prueba1@synpex.local', sypex_hash_password('Prueba#2026'), 'ACTIVO', 1,
        (select id_rol from syn_roles where codigo_rol = 'ADMIN'), 'N');
/
insert into usuario (usuario_id, username, email, password_hash, estado, id_empresa, rol_id, debe_cambiar_clave)
values (900002, 'prueba2', 'prueba2@synpex.local', sypex_hash_password('Prueba#2026'), 'ACTIVO', 2,
        (select id_rol from syn_roles where codigo_rol = 'ADMIN'), 'N');
/
insert into usuario (usuario_id, username, email, password_hash, estado, id_empresa, rol_id, debe_cambiar_clave)
values (900003, 'prueba3', 'prueba3@synpex.local', sypex_hash_password('Prueba#2026'), 'ACTIVO', 1,
        (select id_rol from syn_roles where codigo_rol = 'CONSULTA'), 'N');
/

--
-- Los pares en USUARIO_EMPRESA (tarea 4 del plan de multiempresa, 2026-11-10).
-- El fixture es anterior al modelo multiempresa (2026-11-08) y creaba los
-- usuarios solo con la columna unica USUARIO.ID_EMPRESA. Con el modelo
-- nuevo, un usuario SIN par no tiene ninguna empresa: la vista
-- V_EMPRESAS_USUARIO no le devuelve nada y el filtro de la pagina 3 (F5) lo
-- trata como 'pendiente sin empresa'. Se siembran los pares que
-- corresponden a la empresa principal de cada usuario de prueba.
insert into usuario_empresa (usuario_id, id_empresa)
select u, e from (
    select 900001 u, 1 e from dual
    union all select 900002, 2 from dual
    union all select 900003, 1 from dual) p
 where not exists (select 1 from usuario_empresa x
                    where x.usuario_id = p.u and x.id_empresa = p.e);
/

-- -----------------------------------------------------------------------------
commit;
/

-- 3. Producto
-- -----------------------------------------------------------------------------
-- El catalogo es por empresa desde el 2026-11-23: el articulo de prueba es de la empresa 1.
insert into producto_servicio (id_producto_servicio, id_empresa, codigo, nombre, descripcion, tipo, precio_sugerido, estado)
values (900001, 1, 'PRUEBA-001', 'Producto de prueba', 'Producto de prueba', 'SERVICIO', 100, 'ACTIVO');
/

-- -----------------------------------------------------------------------------
commit;
/

-- 4. Presupuestos (uno por estado) con su linea
-- -----------------------------------------------------------------------------
insert into presupuestos (id_presupuesto, id_empresa, folio, id_cliente, fecha_emision, cod_moneda, tipo_cambio, estado)
values (900001, 1, 900001, 1, trunc(sysdate), 'USD', 894.8876, 'PENDIENTE');
/
insert into presupuestos (id_presupuesto, id_empresa, folio, id_cliente, fecha_emision, cod_moneda, tipo_cambio, estado)
values (900002, 1, 900002, 1, trunc(sysdate), 'USD', 894.8876, 'CANCELADO');
/
insert into presupuestos (id_presupuesto, id_empresa, folio, id_cliente, fecha_emision, cod_moneda, tipo_cambio, estado)
values (900003, 1, 900003, 1, trunc(sysdate), 'USD', 894.8876, 'FACTURADO');
/
insert into presupuestos (id_presupuesto, id_empresa, folio, id_cliente, fecha_emision, cod_moneda, tipo_cambio, estado)
values (900021, 2, 900021, 201, trunc(sysdate), 'MXN', 48.136823, 'PENDIENTE');
/

insert into presupuestos_det (id_detalle, id_presupuesto, descripcion, cantidad, precio_unitario,
                              porcentaje_impuesto, monto_impuesto, subtotal_linea, monto_total_linea)
values (900001, 900001, 'Linea de prueba', 2, 100, 16, 32, 200, 232);
/
insert into presupuestos_det (id_detalle, id_presupuesto, descripcion, cantidad, precio_unitario,
                              porcentaje_impuesto, monto_impuesto, subtotal_linea, monto_total_linea)
values (900002, 900002, 'Linea de prueba', 2, 100, 16, 32, 200, 232);
/
insert into presupuestos_det (id_detalle, id_presupuesto, descripcion, cantidad, precio_unitario,
                              porcentaje_impuesto, monto_impuesto, subtotal_linea, monto_total_linea)
values (900003, 900003, 'Linea de prueba', 2, 100, 16, 32, 200, 232);
/
insert into presupuestos_det (id_detalle, id_presupuesto, descripcion, cantidad, precio_unitario,
                              porcentaje_impuesto, monto_impuesto, subtotal_linea, monto_total_linea)
values (900021, 900021, 'Linea de prueba', 2, 100, 16, 32, 200, 232);
/

-- -----------------------------------------------------------------------------
commit;
/

-- 5. Facturas (una por estado) con su linea
-- -----------------------------------------------------------------------------
insert into facturas (id_factura, id_empresa, id_cliente, tipo_documento, folio_factura, nro_control, cod_moneda, tipo_cambio,
                      fecha_emision, subtotal, monto_impuesto, monto_total, estado, fecha_creacion)
values (900011, 1, 1, 'FAC', 'T-900011', '00-900011', 'USD', 894.8876, trunc(sysdate), 200, 32, 232, 'PENDIENTE', systimestamp);
/
insert into facturas (id_factura, id_empresa, id_cliente, tipo_documento, folio_factura, nro_control, cod_moneda, tipo_cambio,
                      fecha_emision, subtotal, monto_impuesto, monto_total, estado, fecha_creacion)
values (900012, 1, 1, 'FAC', 'T-900012', '00-900012', 'USD', 894.8876, trunc(sysdate), 200, 32, 232, 'PAGADA', systimestamp);
/
insert into facturas (id_factura, id_empresa, id_cliente, tipo_documento, folio_factura, nro_control, cod_moneda, tipo_cambio,
                      fecha_emision, subtotal, monto_impuesto, monto_total, estado, fecha_creacion)
values (900013, 1, 1, 'FAC', 'T-900013', '00-900013', 'USD', 894.8876, trunc(sysdate), 200, 32, 232, 'ANULADA', systimestamp);
/
insert into facturas (id_factura, id_empresa, id_cliente, tipo_documento, folio_factura, nro_control, cod_moneda, tipo_cambio,
                      fecha_emision, subtotal, monto_impuesto, monto_total, estado, fecha_creacion)
values (900031, 2, 201, 'FAC', 'T-900031', '00-900031', 'MXN', 48.136823, trunc(sysdate), 200, 32, 232, 'PENDIENTE', systimestamp);
/

insert into facturas_det (id_detalle, id_factura, num_linea, descripcion, cantidad, precio_unitario,
                          porcentaje_impuesto, monto_impuesto, subtotal_linea, monto_total_linea,
                          tasa_cambio_aplicada, subtotal_bs, total_bs)
values (900011, 900011, 1, 'Linea de prueba', 2, 100, 16, 32, 200, 232, 894.8876, 178977.52, 207613.92);
/
insert into facturas_det (id_detalle, id_factura, num_linea, descripcion, cantidad, precio_unitario,
                          porcentaje_impuesto, monto_impuesto, subtotal_linea, monto_total_linea,
                          tasa_cambio_aplicada, subtotal_bs, total_bs)
values (900012, 900012, 1, 'Linea de prueba', 2, 100, 16, 32, 200, 232, 894.8876, 178977.52, 207613.92);
/
insert into facturas_det (id_detalle, id_factura, num_linea, descripcion, cantidad, precio_unitario,
                          porcentaje_impuesto, monto_impuesto, subtotal_linea, monto_total_linea,
                          tasa_cambio_aplicada, subtotal_bs, total_bs)
values (900013, 900013, 1, 'Linea de prueba', 2, 100, 16, 32, 200, 232, 894.8876, 178977.52, 207613.92);
/
insert into facturas_det (id_detalle, id_factura, num_linea, descripcion, cantidad, precio_unitario,
                          porcentaje_impuesto, monto_impuesto, subtotal_linea, monto_total_linea,
                          tasa_cambio_aplicada, subtotal_bs, total_bs)
values (900031, 900031, 1, 'Linea de prueba', 2, 100, 16, 32, 200, 232, 48.136823, 9627.36, 11167.74);
/

commit;
/

-- -----------------------------------------------------------------------------
commit;
/

-- 6. Constancia
-- -----------------------------------------------------------------------------
select 'presupuestos fixture' as control, count(*) as filas from presupuestos where id_presupuesto between 900000 and 900999
union all
select 'facturas fixture', count(*) from facturas where id_factura between 900000 and 900999
union all
select 'usuarios fixture', count(*) from usuario where usuario_id between 900000 and 900999
union all
select 'estados factura', count(distinct estado) from facturas where id_factura between 900000 and 900999
union all
select 'estados presupuesto', count(distinct estado) from presupuestos where id_presupuesto between 900000 and 900999
/
