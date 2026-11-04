-- =============================================================================
-- validar_carga.sql
-- Validación de la carga de datos en DESTINO. SOLO LECTURA: no modifica nada.
-- Se puede ejecutar en cualquier momento, incluso a media carga, y desde
-- APEX SQL Workshop (es SQL puro; no usa comandos de SQLcl).
--
--   sql -name SYPEX_SQL_MCP @validar_carga.sql
--
-- Esperado final: 216 filas en 17 tablas, 0 huérfanos y 0 diferencias.
--
-- Las filas de prueba (ids >= 9000, ver usuario_prueba.sql) se excluyen de los
-- conteos de USUARIO y SYN_ROLES para que el 216 siga siendo la referencia.
-- =============================================================================

-- 1) Filas por tabla contra los conteos de la base original
select e.tabla,
       e.esperado,
       x.c as filas,
       case when x.c = e.esperado then 'OK' else 'DIFERENCIA' end as estado
  from (select 'CLIENTES' as tabla, 3 as esperado, '1=1' as filtro from dual union all
        select 'CONDICION_PAGO', 7, '1=1' from dual union all
        select 'DEPT', 4, '1=1' from dual union all
        select 'EMP', 14, '1=1' from dual union all
        select 'EMPRESAS', 1, '1=1' from dual union all
        select 'FACTURAS', 22, '1=1' from dual union all
        select 'FACTURAS_DET', 40, '1=1' from dual union all
        select 'FORMA_PAGO', 6, '1=1' from dual union all
        select 'GASTO_REAL', 0, '1=1' from dual union all
        select 'IMPUESTOS', 5, '1=1' from dual union all
        select 'PRESUPUESTOS', 40, '1=1' from dual union all
        select 'PRESUPUESTOS_DET', 18, '1=1' from dual union all
        select 'PRODUCTO_SERVICIO', 4, '1=1' from dual union all
        select 'SYN_ROLES', 4, '"ID_ROL" < 9000' from dual union all
        select 'TIPO_CAMBIO', 36, '1=1' from dual union all
        select 'TIPO_DOCUMENTO', 4, '1=1' from dual union all
        select 'USUARIO', 8, '"USUARIO_ID" < 9000' from dual) e,
       xmltable('/ROWSET/ROW'
                passing xmltype(dbms_xmlgen.getxml(
                    'select count(*) c from "WKSP_SYPEXWS"."' || e.tabla || '" where ' || e.filtro))
                columns c number path 'C') x
 order by e.tabla;

-- 2) Huérfanos: filas que apuntan a un padre inexistente (rompen las FK al cargar)
select 'DEPT -> EMP' as relacion, count(*) as huerfanos
  from "WKSP_SYPEXWS"."EMP" c
 where c.deptno is not null
   and not exists (select 1 from "WKSP_SYPEXWS"."DEPT" p where p.deptno = c.deptno)
union all
select 'SYN_ROLES -> USUARIO', count(*)
  from "WKSP_SYPEXWS"."USUARIO" c
 where c.rol_id is not null
   and not exists (select 1 from "WKSP_SYPEXWS"."SYN_ROLES" p where p.id_rol = c.rol_id)
union all
select 'EMPRESAS -> USUARIO', count(*)
  from "WKSP_SYPEXWS"."USUARIO" c
 where c.id_empresa is not null
   and not exists (select 1 from "WKSP_SYPEXWS"."EMPRESAS" p where p.id_empresa = c.id_empresa)
union all
select 'EMPRESAS -> PRESUPUESTOS', count(*)
  from "WKSP_SYPEXWS"."PRESUPUESTOS" c
 where not exists (select 1 from "WKSP_SYPEXWS"."EMPRESAS" p where p.id_empresa = c.id_empresa)
union all
select 'CLIENTES -> PRESUPUESTOS', count(*)
  from "WKSP_SYPEXWS"."PRESUPUESTOS" c
 where not exists (select 1 from "WKSP_SYPEXWS"."CLIENTES" p where p.id_cliente = c.id_cliente)
union all
select 'PRESUPUESTOS -> PRESUPUESTOS_DET', count(*)
  from "WKSP_SYPEXWS"."PRESUPUESTOS_DET" c
 where not exists (select 1 from "WKSP_SYPEXWS"."PRESUPUESTOS" p where p.id_presupuesto = c.id_presupuesto)
union all
select 'PRODUCTO_SERVICIO -> PRESUPUESTOS_DET', count(*)
  from "WKSP_SYPEXWS"."PRESUPUESTOS_DET" c
 where c.id_producto_servicio is not null
   and not exists (select 1 from "WKSP_SYPEXWS"."PRODUCTO_SERVICIO" p where p.id_producto_servicio = c.id_producto_servicio)
union all
select 'EMPRESAS -> FACTURAS', count(*)
  from "WKSP_SYPEXWS"."FACTURAS" c
 where not exists (select 1 from "WKSP_SYPEXWS"."EMPRESAS" p where p.id_empresa = c.id_empresa)
union all
select 'CLIENTES -> FACTURAS', count(*)
  from "WKSP_SYPEXWS"."FACTURAS" c
 where not exists (select 1 from "WKSP_SYPEXWS"."CLIENTES" p where p.id_cliente = c.id_cliente)
union all
select 'PRESUPUESTOS -> FACTURAS', count(*)
  from "WKSP_SYPEXWS"."FACTURAS" c
 where c.id_presupuesto is not null
   and not exists (select 1 from "WKSP_SYPEXWS"."PRESUPUESTOS" p where p.id_presupuesto = c.id_presupuesto)
union all
select 'FACTURAS -> FACTURAS_DET', count(*)
  from "WKSP_SYPEXWS"."FACTURAS_DET" c
 where not exists (select 1 from "WKSP_SYPEXWS"."FACTURAS" p where p.id_factura = c.id_factura)
union all
select 'IMPUESTOS -> FACTURAS_DET', count(*)
  from "WKSP_SYPEXWS"."FACTURAS_DET" c
 where c.id_impuesto is not null
   and not exists (select 1 from "WKSP_SYPEXWS"."IMPUESTOS" p where p.id_impuesto = c.id_impuesto);

-- 3) Folios duplicados por empresa (deben ser únicos)
select 'PRESUPUESTOS folio repetido' as control, count(*) as casos
  from (select id_empresa, folio
          from "WKSP_SYPEXWS"."PRESUPUESTOS"
         group by id_empresa, folio
        having count(*) > 1)
union all
select 'FACTURAS folio repetido', count(*)
  from (select id_empresa, folio_factura, tipo_documento
          from "WKSP_SYPEXWS"."FACTURAS"
         group by id_empresa, folio_factura, tipo_documento
        having count(*) > 1);

-- 4) Coherencia de totales: cabecera contra la suma del detalle
--    (los triggers compound recalculan la cabecera; esto detecta desajustes)
select 'PRESUPUESTOS subtotal' as metrica, count(*) as filas_descuadradas
  from "WKSP_SYPEXWS"."PRESUPUESTOS" p
 where abs(nvl(p.subtotal,0) - nvl((select sum(d.subtotal_linea) from "WKSP_SYPEXWS"."PRESUPUESTOS_DET" d
                                     where d.id_presupuesto = p.id_presupuesto),0)) > 0.01
union all
select 'PRESUPUESTOS impuesto_iva', count(*)
  from "WKSP_SYPEXWS"."PRESUPUESTOS" p
 where abs(nvl(p.impuesto_iva,0) - nvl((select sum(d.monto_impuesto) from "WKSP_SYPEXWS"."PRESUPUESTOS_DET" d
                                         where d.id_presupuesto = p.id_presupuesto),0)) > 0.01
union all
select 'PRESUPUESTOS total', count(*)
  from "WKSP_SYPEXWS"."PRESUPUESTOS" p
 where abs(nvl(p.total,0) - nvl((select sum(d.monto_total_linea) from "WKSP_SYPEXWS"."PRESUPUESTOS_DET" d
                                  where d.id_presupuesto = p.id_presupuesto),0)) > 0.01
union all
select 'FACTURAS subtotal', count(*)
  from "WKSP_SYPEXWS"."FACTURAS" f
 where abs(nvl(f.subtotal,0) - nvl((select sum(d.subtotal_linea) from "WKSP_SYPEXWS"."FACTURAS_DET" d
                                     where d.id_factura = f.id_factura),0)) > 0.01
union all
select 'FACTURAS monto_impuesto', count(*)
  from "WKSP_SYPEXWS"."FACTURAS" f
 where abs(nvl(f.monto_impuesto,0) - nvl((select sum(d.monto_impuesto) from "WKSP_SYPEXWS"."FACTURAS_DET" d
                                           where d.id_factura = f.id_factura),0)) > 0.01
union all
select 'FACTURAS monto_total', count(*)
  from "WKSP_SYPEXWS"."FACTURAS" f
 where abs(nvl(f.monto_total,0) - nvl((select sum(d.monto_total_linea) from "WKSP_SYPEXWS"."FACTURAS_DET" d
                                        where d.id_factura = f.id_factura),0)) > 0.01;

-- 5) Resumen final
select case when s.filas = 216 then '216/216 - carga completa' else 'carga incompleta' end as resultado,
       s.filas as filas_totales
  from (select sum(x.c) as filas
          from (select 'CLIENTES' as tabla, 3 as esperado, '1=1' as filtro from dual union all
                select 'CONDICION_PAGO', 7, '1=1' from dual union all
                select 'DEPT', 4, '1=1' from dual union all
                select 'EMP', 14, '1=1' from dual union all
                select 'EMPRESAS', 1, '1=1' from dual union all
                select 'FACTURAS', 22, '1=1' from dual union all
                select 'FACTURAS_DET', 40, '1=1' from dual union all
                select 'FORMA_PAGO', 6, '1=1' from dual union all
                select 'GASTO_REAL', 0, '1=1' from dual union all
                select 'IMPUESTOS', 5, '1=1' from dual union all
                select 'PRESUPUESTOS', 40, '1=1' from dual union all
                select 'PRESUPUESTOS_DET', 18, '1=1' from dual union all
                select 'PRODUCTO_SERVICIO', 4, '1=1' from dual union all
                select 'SYN_ROLES', 4, '"ID_ROL" < 9000' from dual union all
                select 'TIPO_CAMBIO', 36, '1=1' from dual union all
                select 'TIPO_DOCUMENTO', 4, '1=1' from dual union all
                select 'USUARIO', 8, '"USUARIO_ID" < 9000' from dual) e,
               xmltable('/ROWSET/ROW'
                        passing xmltype(dbms_xmlgen.getxml(
                            'select count(*) c from "WKSP_SYPEXWS"."' || e.tabla || '" where ' || e.filtro))
                        columns c number path 'C') x) s;
