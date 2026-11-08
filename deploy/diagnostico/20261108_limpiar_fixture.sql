-- =============================================================================
-- 20261108_limpiar_fixture.sql
--
-- Borra el fixture de pruebas creado por 20261108_fixture_prueba.sql (rango
-- reservado 900000-900999). No toca nada mas.
--
-- OJO: cada borrado lleva su COMMIT. Varias DML sobre tablas con identity en la
-- misma transaccion dan ORA-12839 en esta base (medido el 2026-11-08).
--
-- Uso:
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261108_limpiar_fixture.sql
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;
/

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

delete from usuario where usuario_id between 900000 and 900999;
/
commit;
/

-- Constancia: los cinco conteos deben dar 0.
select 'presupuestos' as tabla, count(*) as quedan from presupuestos where id_presupuesto between 900000 and 900999
union all
select 'facturas', count(*) from facturas where id_factura between 900000 and 900999
union all
select 'productos', count(*) from producto_servicio where id_producto_servicio between 900000 and 900999
union all
select 'usuarios', count(*) from usuario where usuario_id between 900000 and 900999
union all
select 'gastos', count(*) from gasto_real where id_gasto between 900000 and 900999
/
