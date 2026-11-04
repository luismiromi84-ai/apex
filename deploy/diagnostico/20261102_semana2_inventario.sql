-- Synpex - Semana 2 - Inventario previo a la migracion
--
-- SOLO CONSULTAS. No crea, altera ni borra nada.
-- Ejecutar en: APEX SQL Workshop > SQL Commands (una consulta a la vez).
--
-- Objetivo:
--   1. Saber que columnas de porcentaje existen REALMENTE en la base.
--   2. Medir cuantos datos habria que migrar.
--   3. Inventariar FKs y unicidad antes de tocarlas.
--
-- IMPORTANTE:
--   - No pegar resultados dentro de este archivo.
--   - Guardar la evidencia en deploy/resultados/AAAAAMMDD_semana2.txt
--   - Las secciones marcadas [CONDICIONAL] solo se ejecutan si la seccion 1
--     o la 2 confirma que la columna existe. Si no existe, la consulta falla
--     con ORA-00904 y no pasa nada; simplemente se omite.
--
-- El DDL del repositorio es la referencia, no la verdad. La verdad es la base.


-- ============================================================
-- 1. Columnas reales de las dos tablas de detalle
-- ============================================================
select table_name,
       column_id,
       column_name,
       data_type,
       data_length,
       data_precision,
       data_scale,
       nullable,
       data_default
  from user_tab_columns
 where table_name in ('FACTURAS_DET', 'PRESUPUESTOS_DET')
 order by table_name, column_id;


-- ============================================================
-- 2. Todas las columnas con "PORCENTA" en el esquema
--    Esta es la consulta que define el alcance real del problema.
-- ============================================================
select table_name,
       column_name,
       data_type,
       data_precision,
       data_scale,
       nullable,
       data_default
  from user_tab_columns
 where column_name like '%PORCENTA%'
 order by table_name, column_name;


-- ============================================================
-- 3. Volumen de datos por tabla
-- ============================================================
select 'PRESUPUESTOS'      as tabla, count(*) as filas from presupuestos
union all
select 'PRESUPUESTOS_DET',          count(*) from presupuestos_det
union all
select 'FACTURAS',                  count(*) from facturas
union all
select 'FACTURAS_DET',              count(*) from facturas_det
union all
select 'CLIENTES',                  count(*) from clientes
union all
select 'PRODUCTO_SERVICIO',         count(*) from producto_servicio
union all
select 'IMPUESTOS',                 count(*) from impuestos
union all
select 'USUARIO',                   count(*) from usuario
union all
select 'EMPRESAS',                  count(*) from empresas
union all
select 'TIPO_CAMBIO',               count(*) from tipo_cambio
order by tabla;


-- ============================================================
-- 4. [CONDICIONAL] FACTURAS_DET: las dos parejas de columnas
--    Ejecutar solo si la seccion 2 muestra PORCENTAGE_IMPUESTO
--    y PORCENTAJE_IMPUESTO (o PORCENTAGE_DESCUENTO y PORCENTAJE_DESCUENTO).
--
--    Interpretacion:
--      difieren_*  > 0  -> hay datos inconsistentes entre legacy y correcta
--      solo_legacy > 0  -> la pagina 6 (que usa legacy) si escribio datos
--      solo_correcta> 0 -> la pagina 10 (que usa correcta) si escribio datos
-- ============================================================
select count(*) as total_lineas,
       count(porcentage_impuesto)  as con_valor_legacy_imp,
       count(porcentaje_impuesto)  as con_valor_correcta_imp,
       sum(case when porcentage_impuesto is not null
                 and porcentaje_impuesto is null then 1 else 0 end) as solo_legacy_imp,
       sum(case when porcentage_impuesto is null
                 and porcentaje_impuesto is not null then 1 else 0 end) as solo_correcta_imp,
       sum(case when porcentage_impuesto is not null
                 and porcentaje_impuesto is not null
                 and porcentage_impuesto <> porcentaje_impuesto then 1 else 0 end) as difieren_imp,
       count(porcentage_descuento) as con_valor_legacy_desc,
       count(porcentaje_descuento) as con_valor_correcta_desc,
       sum(case when porcentage_descuento is not null
                 and porcentaje_descuento is null then 1 else 0 end) as solo_legacy_desc,
       sum(case when porcentage_descuento is null
                 and porcentaje_descuento is not null then 1 else 0 end) as solo_correcta_desc,
       sum(case when porcentage_descuento is not null
                 and porcentaje_descuento is not null
                 and porcentage_descuento <> porcentaje_descuento then 1 else 0 end) as difieren_desc
  from facturas_det;


-- ============================================================
-- 5. [CONDICIONAL] PRESUPUESTOS_DET: columnas legacy
--    Ejecutar solo si la seccion 2 muestra PORCENTAGE_IMPUESTO
--    / PORCENTAGE_DESCUENTO en PRESUPUESTOS_DET.
-- ============================================================
select count(*) as total_lineas,
       count(porcentage_impuesto)  as con_valor_imp,
       count(porcentage_descuento) as con_valor_desc,
       sum(case when porcentage_impuesto  is null then 1 else 0 end) as imp_nulo,
       sum(case when porcentage_descuento is null then 1 else 0 end) as desc_nulo
  from presupuestos_det;


-- ============================================================
-- 6. Inventario de constraints por tabla y tipo
--    P=PK  U=UNIQUE  R=FK  C=CHECK
-- ============================================================
select table_name,
       constraint_type,
       count(*) as cantidad,
       listagg(constraint_name, ', ') within group (order by constraint_name) as nombres
  from user_constraints
 where constraint_type in ('P', 'U', 'R', 'C')
 group by table_name, constraint_type
 order by table_name, constraint_type;


-- ============================================================
-- 7. FKs existentes, en detalle
-- ============================================================
select c.table_name          as tabla_origen,
       cc.column_name        as columna_origen,
       rc.table_name         as tabla_destino,
       rcc.column_name       as columna_destino,
       c.constraint_name,
       c.status,
       c.validated,
       c.delete_rule
  from user_constraints c
  join user_cons_columns cc
    on cc.constraint_name = c.constraint_name
  left join user_constraints rc
    on rc.constraint_name = c.r_constraint_name
  left join user_cons_columns rcc
    on rcc.constraint_name = c.r_constraint_name
   and rcc.position = cc.position
 where c.constraint_type = 'R'
 order by c.table_name, cc.column_name;


-- ============================================================
-- 8. Columnas ID_* que NO tienen FK declarada
--    Estas son las candidatas a la migracion de la Semana 2.
-- ============================================================
select c.table_name, c.column_name, c.nullable
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
 order by c.table_name, c.column_name;


-- ============================================================
-- 9. Filas huerfanas: detalle que apunta a un padre inexistente
--    Cada consulta debe devolver 0.
-- ============================================================
select 'PRESUPUESTOS sin cliente' as control, count(*) as huerfanas
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
   and not exists (select 1 from producto_servicio p
                    where p.id_producto_servicio = d.id_producto_servicio)
union all
select 'PRESUPUESTOS_DET sin impuesto', count(*)
  from presupuestos_det d
 where d.id_impuesto is not null
   and not exists (select 1 from impuestos i where i.id_impuesto = d.id_impuesto)
union all
select 'FACTURAS_DET sin producto', count(*)
  from facturas_det d
 where d.id_producto is not null
   and not exists (select 1 from producto_servicio p
                    where p.id_producto_servicio = d.id_producto)
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


-- ============================================================
-- 10. Unicidad de folio por empresa
--     Cada consulta debe devolver 0 filas.
--     Presupuestos usa la columna FOLIO; facturas usa FOLIO_FACTURA.
-- ============================================================
select id_empresa, folio, count(*) as repeticiones
  from presupuestos
 group by id_empresa, folio
having count(*) > 1
 order by repeticiones desc;


select id_empresa, folio_factura, tipo_documento, count(*) as repeticiones
  from facturas
 group by id_empresa, folio_factura, tipo_documento
having count(*) > 1
 order by repeticiones desc;


-- ============================================================
-- 11. Usuarios: case-insensitive y estados
-- ============================================================
select upper(username) as username_normalizado, count(*) as repeticiones
  from usuario
 group by upper(username)
having count(*) > 1
 order by repeticiones desc;


select upper(email) as email_normalizado, count(*) as repeticiones
  from usuario
 where email is not null
 group by upper(email)
having count(*) > 1
 order by repeticiones desc;


select estado, count(*) as usuarios
  from usuario
 group by estado
 order by estado;


-- ============================================================
-- 12. Empresas y roles referenciados
-- ============================================================
select 'USUARIO con id_empresa inexistente' as control, count(*) as filas
  from usuario u
 where u.id_empresa is not null
   and not exists (select 1 from empresas e where e.id_empresa = u.id_empresa)
union all
select 'USUARIO con rol inexistente', count(*)
  from usuario u
 where u.rol_id is not null
   and not exists (select 1 from syn_roles r where r.id_rol = u.rol_id)
union all
select 'PRESUPUESTOS con id_empresa inexistente', count(*)
  from presupuestos p
 where not exists (select 1 from empresas e where e.id_empresa = p.id_empresa)
union all
select 'FACTURAS con id_empresa inexistente', count(*)
  from facturas f
 where not exists (select 1 from empresas e where e.id_empresa = f.id_empresa);


-- ============================================================
-- 13. Distribucion de estados (validar CHECK constraints)
-- ============================================================
select 'PRESUPUESTOS' as tabla, estado, count(*) as filas
  from presupuestos
 group by estado
union all
select 'FACTURAS', estado, count(*)
  from facturas
 group by estado
 order by 1, 2;


-- ============================================================
-- 14. Secuencias ISEQ$$ huerfanas (limpieza P2)
-- ============================================================
select s.sequence_name, s.last_number
  from user_sequences s
 where s.sequence_name like 'ISEQ$$_%'
   and not exists (select 1
                     from user_tab_identity_cols i
                    where i.sequence_name = s.sequence_name)
 order by s.sequence_name;
