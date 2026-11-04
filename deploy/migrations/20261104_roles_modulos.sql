-- =============================================================================
-- 20261104_roles_modulos.sql
-- Garantiza los codigos_rol que usan los esquemas de autorizacion por modulo.
-- Idempotente: MERGE por codigo_rol; si el rol ya existe no lo modifica.
-- La identidad de SYN_ROLES asigna id_rol (no fijar ids: 1000-1999 es el rango
-- del dataset de ejemplo y se purga con datos_demo.sql).
--
-- Medido el 2026-11-04 antes de ejecutar: ya existen ADMIN(1001), GERENCIA(1002),
-- VENTAS(1003), CONTABILIDAD(1004), ALMACEN(1005), CONSULTA(1006) y PRUEBA(9001).
-- Solo falta FACTURACION; los otros seis son no-op.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;

merge into syn_roles t
using (
    select 'FACTURACION'  codigo_rol, 'Facturación' nombre_rol, 'Emite y gestiona facturas' descripcion from dual union all
    select 'CONSULTA',                 'Consulta',                 'Solo lectura'                          from dual union all
    select 'CONTABILIDAD',             'Contabilidad',             'Modulo contable (sin paginas aun)'     from dual union all
    select 'ALMACEN',                  'Almacén',                  'Productos y servicios (sin paginas aun)' from dual
) s
on (upper(trim(t.codigo_rol)) = s.codigo_rol)
when not matched then
    insert (codigo_rol, nombre_rol, descripcion)
    values (s.codigo_rol, s.nombre_rol, s.descripcion);

commit;

select id_rol, codigo_rol, nombre_rol
  from syn_roles
 where codigo_rol in ('FACTURACION','CONSULTA','CONTABILIDAD','ALMACEN')
 order by codigo_rol;

-- Reversa (solo si ningun usuario los usa):
--   delete from syn_roles where codigo_rol in ('FACTURACION','CONSULTA','CONTABILIDAD','ALMACEN');
