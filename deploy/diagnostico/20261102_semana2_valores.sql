-- Synpex - Semana 2 - Valores para evidencia
--
-- UNA SOLA CONSULTA. Devuelve ~60 filas de 3 columnas, facil de descargar.
--
-- EJECUTAR EN: APEX SQL Workshop > SQL COMMANDS  (NO en SQL Scripts)
--   1. Copiar TODO este archivo y pegarlo en el editor.
--   2. Ejecutar.
--   3. En la grilla de resultados, pulsar "Download".
--   4. Guardar como deploy/resultados/20261102_semana2_valores.csv
--
-- SI YA LO CORRISTE EN SQL SCRIPTS:
--   En la pagina de Results, cambiar el selector "View: Summary" a "View: Detail".
--   Summary solo muestra el conteo de filas; Detail muestra los valores.

-- OJO: DATA_DEFAULT es de tipo LONG en esta instancia (Oracle 26ai), tambien en
-- ALL_TAB_COLUMNS: concatenarlo da ORA-00932. Por eso esta consulta NO lee el
-- default. Los DEFAULT de las columnas PORCENTAJE* estan en tabla/*.sql, que es
-- la fuente canonica. Si hace falta el default aqui, consultarlo solo (sin
-- concatenar) en una consulta aparte.
select 'A-PORCENTAJE' as seccion,
       t.table_name || '.' || t.column_name as concepto,
       t.data_type
       || ' prec=' || nvl(to_char(t.data_precision), to_char(t.data_length))
       || ' esc='   || nvl(to_char(t.data_scale), '-')
       || ' nullable=' || t.nullable as valor
  from all_tab_columns t
 where t.owner = sys_context('USERENV', 'CURRENT_SCHEMA')
   and t.column_name like '%PORCENTA%'

union all
select 'B-METRICA', 'FACTURAS_DET lineas',            to_char(count(*))                   from facturas_det
union all
select 'B-METRICA', 'FACTURAS_DET con PORCENTAGE_IMPUESTO',  to_char(count(porcentage_impuesto))  from facturas_det
union all
select 'B-METRICA', 'FACTURAS_DET con PORCENTAJE_IMPUESTO',  to_char(count(porcentaje_impuesto))  from facturas_det
union all
select 'B-METRICA', 'FACTURAS_DET solo legacy imp',
       to_char(sum(case when porcentage_impuesto is not null and porcentaje_impuesto is null then 1 else 0 end)) from facturas_det
union all
select 'B-METRICA', 'FACTURAS_DET solo correcta imp',
       to_char(sum(case when porcentage_impuesto is null and porcentaje_impuesto is not null then 1 else 0 end)) from facturas_det
union all
select 'B-METRICA', 'FACTURAS_DET difieren imp',
       to_char(sum(case when porcentage_impuesto is not null and porcentaje_impuesto is not null
                         and porcentage_impuesto <> porcentaje_impuesto then 1 else 0 end)) from facturas_det
union all
select 'B-METRICA', 'FACTURAS_DET con PORCENTAGE_DESCUENTO', to_char(count(porcentage_descuento)) from facturas_det
union all
select 'B-METRICA', 'FACTURAS_DET con PORCENTAJE_DESCUENTO', to_char(count(porcentaje_descuento)) from facturas_det
union all
select 'B-METRICA', 'FACTURAS_DET solo legacy desc',
       to_char(sum(case when porcentage_descuento is not null and porcentaje_descuento is null then 1 else 0 end)) from facturas_det
union all
select 'B-METRICA', 'FACTURAS_DET solo correcta desc',
       to_char(sum(case when porcentage_descuento is null and porcentaje_descuento is not null then 1 else 0 end)) from facturas_det
union all
select 'B-METRICA', 'FACTURAS_DET difieren desc',
       to_char(sum(case when porcentage_descuento is not null and porcentaje_descuento is not null
                         and porcentage_descuento <> porcentaje_descuento then 1 else 0 end)) from facturas_det
union all
select 'B-METRICA', 'PRESUPUESTOS_DET lineas',        to_char(count(*))                   from presupuestos_det
union all
select 'B-METRICA', 'PRESUPUESTOS_DET imp nulo',
       to_char(sum(case when porcentage_impuesto  is null then 1 else 0 end))  from presupuestos_det
union all
select 'B-METRICA', 'PRESUPUESTOS_DET desc nulo',
       to_char(sum(case when porcentage_descuento is null then 1 else 0 end))  from presupuestos_det
union all
select 'B-METRICA', 'PRESUPUESTOS lineas',            to_char(count(*))                   from presupuestos
union all
select 'B-METRICA', 'FACTURAS lineas',                to_char(count(*))                   from facturas
union all
select 'B-METRICA', 'CLIENTES lineas',                to_char(count(*))                   from clientes
union all
select 'B-METRICA', 'PRODUCTO_SERVICIO lineas',       to_char(count(*))                   from producto_servicio
union all
select 'B-METRICA', 'USUARIO lineas',                 to_char(count(*))                   from usuario
union all
select 'B-METRICA', 'EMPRESAS lineas',                to_char(count(*))                   from empresas

union all
-- FKs que SI existen
select 'C-FK',
       c.table_name || '.' || cc.column_name,
       'EXISTE -> ' || rc.table_name || '.' || rcc.column_name
       || ' [' || c.status || '/' || c.validated || ']'
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
-- Columnas ID_* que no son PK ni FK  -> candidatas reales
select 'C-FK',
       c.table_name || '.' || c.column_name,
       'FALTA FK (' || case c.nullable when 'Y' then 'NULL' else 'NOT NULL' end || ')'
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
                    where k.constraint_type in ('R', 'P')
                      and k.table_name = c.table_name
                      and kc.column_name = c.column_name)

union all
select 'D-CONTROL', 'PRESUPUESTOS sin cliente',  to_char(count(*))
  from presupuestos p
 where p.id_cliente is not null
   and not exists (select 1 from clientes c where c.id_cliente = p.id_cliente)
union all
select 'D-CONTROL', 'FACTURAS sin cliente',      to_char(count(*))
  from facturas f
 where f.id_cliente is not null
   and not exists (select 1 from clientes c where c.id_cliente = f.id_cliente)
union all
select 'D-CONTROL', 'PRESUPUESTOS_DET sin producto', to_char(count(*))
  from presupuestos_det d
 where d.id_producto_servicio is not null
   and not exists (select 1 from producto_servicio p where p.id_producto_servicio = d.id_producto_servicio)
union all
select 'D-CONTROL', 'PRESUPUESTOS_DET sin impuesto', to_char(count(*))
  from presupuestos_det d
 where d.id_impuesto is not null
   and not exists (select 1 from impuestos i where i.id_impuesto = d.id_impuesto)
union all
select 'D-CONTROL', 'FACTURAS_DET sin producto', to_char(count(*))
  from facturas_det d
 where d.id_producto is not null
   and not exists (select 1 from producto_servicio p where p.id_producto_servicio = d.id_producto)
union all
select 'D-CONTROL', 'FACTURAS_DET sin impuesto', to_char(count(*))
  from facturas_det d
 where d.id_impuesto is not null
   and not exists (select 1 from impuestos i where i.id_impuesto = d.id_impuesto)
union all
select 'D-CONTROL', 'FACTURAS sin presupuesto',  to_char(count(*))
  from facturas f
 where f.id_presupuesto is not null
   and not exists (select 1 from presupuestos p where p.id_presupuesto = f.id_presupuesto)
union all
select 'D-CONTROL', 'PRESUPUESTOS estado ' || estado, to_char(count(*)) from presupuestos group by estado
union all
select 'D-CONTROL', 'FACTURAS estado ' || estado,      to_char(count(*)) from facturas      group by estado
union all
select 'D-CONTROL', 'USUARIO estado ' || estado,       to_char(count(*)) from usuario       group by estado

union all
-- Confirmar en que esquema viven realmente los objetos.
-- SQL Scripts reporta Parsing Schema = WKSP_SYPEXWS, pero el pie de la
-- consola muestra ADMIN_SYPEX. Esta seccion resuelve la duda.
select 'E-ESQUEMA', 'current_schema',            sys_context('USERENV', 'CURRENT_SCHEMA') from dual
union all
select 'E-ESQUEMA', 'usuario de sesion',         user from dual
union all
select 'E-ESQUEMA', 'tablas en user_tables',     to_char(count(*)) from user_tables
union all
select 'E-ESQUEMA', 'tablas en current_schema',  to_char(count(*))
  from all_tables where owner = sys_context('USERENV', 'CURRENT_SCHEMA')
union all
select 'E-ESQUEMA', 'bodies en user_objects',    to_char(count(*))
  from user_objects where object_type = 'PACKAGE BODY'

 order by 1, 2;
