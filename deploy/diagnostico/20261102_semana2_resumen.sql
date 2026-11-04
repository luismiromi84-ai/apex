-- Synpex - Semana 2 - Resumen compacto para evidencia
--
-- SOLO CONSULTAS. Version reducida de 20261102_semana2_inventario.sql.
-- Devuelve pocas filas y columnas angostas, para poder copiar la salida facil.
--
-- Ejecutar en APEX SQL Workshop > SQL Commands, UNA consulta a la vez.
-- No pegar resultados dentro de este archivo.


-- ============================================================
-- A. Columnas de porcentaje que existen realmente  (7 filas esperadas)
-- ============================================================
select table_name as tabla,
       column_name as columna,
       data_type as tipo,
       nvl(to_char(data_precision), to_char(data_length)) as precision_,
       nvl(to_char(data_scale), '-') as escala,
       nullable as nulo_permitido,
       data_default as valor_por_defecto
  from user_tab_columns
 where column_name like '%PORCENTA%'
 order by table_name, column_name;


-- ============================================================
-- B. Metricas de la migracion, una por fila
--    (evita la fila ancha de la seccion 4 del inventario)
-- ============================================================
select 'FACTURAS_DET lineas' as metrica,
       to_char(count(*)) as valor
  from facturas_det
union all
select 'FACTURAS_DET con PORCENTAGE_IMPUESTO',   to_char(count(porcentage_impuesto))  from facturas_det
union all
select 'FACTURAS_DET con PORCENTAJE_IMPUESTO',   to_char(count(porcentaje_impuesto))  from facturas_det
union all
select 'FACTURAS_DET solo legacy imp',           to_char(sum(case when porcentage_impuesto  is not null and porcentaje_impuesto  is null then 1 else 0 end)) from facturas_det
union all
select 'FACTURAS_DET solo correcta imp',         to_char(sum(case when porcentage_impuesto  is null and porcentaje_impuesto  is not null then 1 else 0 end)) from facturas_det
union all
select 'FACTURAS_DET difieren imp',              to_char(sum(case when porcentage_impuesto  is not null and porcentaje_impuesto  is not null and porcentage_impuesto  <> porcentaje_impuesto  then 1 else 0 end)) from facturas_det
union all
select 'FACTURAS_DET con PORCENTAGE_DESCUENTO',  to_char(count(porcentage_descuento)) from facturas_det
union all
select 'FACTURAS_DET con PORCENTAJE_DESCUENTO',  to_char(count(porcentaje_descuento)) from facturas_det
union all
select 'FACTURAS_DET solo legacy desc',          to_char(sum(case when porcentage_descuento is not null and porcentaje_descuento is null then 1 else 0 end)) from facturas_det
union all
select 'FACTURAS_DET solo correcta desc',        to_char(sum(case when porcentage_descuento is null and porcentaje_descuento is not null then 1 else 0 end)) from facturas_det
union all
select 'FACTURAS_DET difieren desc',             to_char(sum(case when porcentage_descuento is not null and porcentaje_descuento is not null and porcentage_descuento <> porcentaje_descuento then 1 else 0 end)) from facturas_det
union all
select 'PRESUPUESTOS_DET lineas',                to_char(count(*)) from presupuestos_det
union all
select 'PRESUPUESTOS_DET imp nulo',              to_char(sum(case when porcentage_impuesto  is null then 1 else 0 end)) from presupuestos_det
union all
select 'PRESUPUESTOS_DET desc nulo',             to_char(sum(case when porcentage_descuento is null then 1 else 0 end)) from presupuestos_det
union all
select 'PRESUPUESTOS lineas',                    to_char(count(*)) from presupuestos
union all
select 'FACTURAS lineas',                        to_char(count(*)) from facturas
union all
select 'CLIENTES lineas',                        to_char(count(*)) from clientes
union all
select 'PRODUCTO_SERVICIO lineas',               to_char(count(*)) from producto_servicio
union all
select 'USUARIO lineas',                         to_char(count(*)) from usuario
union all
select 'EMPRESAS lineas',                        to_char(count(*)) from empresas;


-- ============================================================
-- C. FKs: lo que existe y lo que falta  (28 filas esperadas)
--    tipo = 'EXISTE' -> FK declarada
--    tipo = 'FALTA'  -> columna ID_* sin FK
-- ============================================================
select 'EXISTE' as tipo,
       c.table_name || '.' || cc.column_name as columna,
       rc.table_name || '.' || rcc.column_name as referencia,
       c.status as estado,
       c.validated as validada
  from user_constraints c
  join user_cons_columns cc
    on cc.constraint_name = c.constraint_name
  left join user_constraints rc
    on rc.constraint_name = c.r_constraint_name
  left join user_cons_columns rcc
    on rcc.constraint_name = c.r_constraint_name
   and rcc.position = cc.position
 where c.constraint_type = 'R'
union all
select 'FALTA',
       c.table_name || '.' || c.column_name,
       '(sin FK)',
       case c.nullable when 'Y' then 'NULL' else 'NOT NULL' end,
       '-'
  from user_tab_columns c
 where substr(c.column_name, 1, 3) = 'ID_'
   and c.table_name in ('EMPRESAS', 'SYN_ROLES', 'USUARIO', 'CLIENTES', 'IMPUESTOS',
                        'TIPO_CAMBIO', 'TIPO_DOCUMENTO', 'FORMA_PAGO', 'CONDICION_PAGO',
                        'PRODUCTO_SERVICIO', 'PRESUPUESTOS', 'PRESUPUESTOS_DET',
                        'FACTURAS', 'FACTURAS_DET', 'GASTO_REAL')
   and not exists (select 1
                     from user_constraints k
                     join user_cons_columns kc
                       on kc.constraint_name = k.constraint_name
                    where k.constraint_type = 'R'
                      and k.table_name = c.table_name
                      and kc.column_name = c.column_name)
 order by 1 desc, 2;


-- ============================================================
-- D. Huerfanos y estados  (7 + 3 filas esperadas)
--    Todo huerfano debe ser 0 antes de crear FKs.
-- ============================================================
select 'PRESUPUESTOS sin cliente' as control, count(*) as filas
  from presupuestos p
 where p.id_cliente is not null
   and not exists (select 1 from clientes c where c.id_cliente = p.id_cliente)
union all
select 'FACTURAS sin cliente', count(*)
  from facturas f
 where f.id_cliente is not null
   and not exists (select 1 from clientes c where c.id_cliente = f.id_cliente)
union all
select 'PRESUPUESTOS_DET sin producto', count(*)
  from presupuestos_det d
 where d.id_producto_servicio is not null
   and not exists (select 1 from producto_servicio p where p.id_producto_servicio = d.id_producto_servicio)
union all
select 'PRESUPUESTOS_DET sin impuesto', count(*)
  from presupuestos_det d
 where d.id_impuesto is not null
   and not exists (select 1 from impuestos i where i.id_impuesto = d.id_impuesto)
union all
select 'FACTURAS_DET sin producto', count(*)
  from facturas_det d
 where d.id_producto is not null
   and not exists (select 1 from producto_servicio p where p.id_producto_servicio = d.id_producto)
union all
select 'FACTURAS_DET sin impuesto', count(*)
  from facturas_det d
 where d.id_impuesto is not null
   and not exists (select 1 from impuestos i where i.id_impuesto = d.id_impuesto)
union all
select 'FACTURAS sin presupuesto', count(*)
  from facturas f
 where f.id_presupuesto is not null
   and not exists (select 1 from presupuestos p where p.id_presupuesto = f.id_presupuesto);


select 'PRESUPUESTOS' as tabla, estado, count(*) as filas
  from presupuestos
 group by estado
union all
select 'FACTURAS', estado, count(*)
  from facturas
 group by estado
 order by 1, 2;
