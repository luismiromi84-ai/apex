-- =============================================================================
-- validar_demo.sql — verificación del dataset de ejemplo. SOLO LECTURA.
--
--   sql -name SYPEX_SQL_MCP @instalacion y migracion/validar_demo.sql
--
-- Esperado tras ejecutar datos_demo.sql:
--   roles 6, usuarios 8, clientes 12, productos 10, tipos de cambio 36,
--   dept 4, emp 14, presupuestos 45, facturas 40, hashes incorrectos 0.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;

-- 1) Conteos del dataset de ejemplo
select 'SYN_ROLES' as tabla, 6 as esperado, count(*) as filas from syn_roles where id_rol between 1000 and 1999
union all
select 'USUARIO', 8, count(*) from usuario where usuario_id between 1000 and 1999
union all
select 'CLIENTES', 12, count(*) from clientes where id_cliente between 1000 and 1999
union all
select 'PRODUCTO_SERVICIO', 10, count(*) from producto_servicio where id_producto_servicio between 1000 and 1999
union all
select 'TIPO_CAMBIO', 24, count(*) from tipo_cambio where id_tipo_cambio between 1000 and 1999
union all
select 'DEPT', 4, count(*) from dept where deptno in (10,20,30,40)
union all
select 'EMP', 14, count(*) from emp where empno between 7369 and 7934
union all
select 'PRESUPUESTOS', 45, count(*) from presupuestos where id_presupuesto between 1000 and 1999
union all
select 'PRESUPUESTOS_DET', 90, count(*) from presupuestos_det where id_detalle between 1000 and 1999
union all
select 'FACTURAS', 40, count(*) from facturas where id_factura between 1000 and 1999
union all
select 'FACTURAS_DET', 80, count(*) from facturas_det where id_detalle between 1000 and 1999
order by 1;

-- 2) Todos los usuarios del demo deben tener la clave Prueba#2026
select count(*) as usuarios_con_otro_hash
  from usuario
 where usuario_id between 1000 and 1999
   and password_hash <> sypex_hash_password('Prueba#2026');

-- 3) Tipos de cambio por par (esperado: 12 USD->VES y 12 MXN->VES)
select moneda_origen || '->' || moneda_destino as par, count(*) as filas
  from tipo_cambio
 where id_tipo_cambio between 1000 and 1999
 group by moneda_origen || '->' || moneda_destino
 order by 1;

-- 4) Coherencia: documentos sin cliente, detalles sin cabecera, totales descuadrados
select 'facturas sin cliente' as control, count(*) as casos
  from facturas f
 where f.id_factura between 1000 and 1999
   and not exists (select 1 from clientes c where c.id_cliente = f.id_cliente)
union all
select 'presupuestos sin cliente', count(*)
  from presupuestos p
 where p.id_presupuesto between 1000 and 1999
   and not exists (select 1 from clientes c where c.id_cliente = p.id_cliente)
union all
select 'detalle de factura sin cabecera', count(*)
  from facturas_det d
 where d.id_detalle between 1000 and 1999
   and not exists (select 1 from facturas f where f.id_factura = d.id_factura)
union all
select 'detalle de presupuesto sin cabecera', count(*)
  from presupuestos_det d
 where d.id_detalle between 1000 and 1999
   and not exists (select 1 from presupuestos p where p.id_presupuesto = d.id_presupuesto)
union all
select 'facturas descuadradas', count(*)
  from facturas f
 where f.id_factura between 1000 and 1999
   and abs(nvl(f.monto_total,0) - nvl((select sum(d.monto_total_linea) from facturas_det d
                                        where d.id_factura = f.id_factura),0)) > 0.01
union all
select 'presupuestos descuadrados', count(*)
  from presupuestos p
 where p.id_presupuesto between 1000 and 1999
   and abs(nvl(p.total,0) - nvl((select sum(d.monto_total_linea) from presupuestos_det d
                                  where d.id_presupuesto = p.id_presupuesto),0)) > 0.01;

-- 5) Distribución para el panel: por moneda y estado (facturas)
select cod_moneda, estado, count(*) as documentos, round(sum(monto_total),2) as monto
  from facturas
 where id_factura between 1000 and 1999
 group by cod_moneda, estado
 order by cod_moneda, estado;
