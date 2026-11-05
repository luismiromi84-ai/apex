-- Synpex - verificacion del esquema (version SIN comandos SQL*Plus)
--
-- Ejecutar en: APEX SQL Workshop > SQL Commands, APEX SQL Workshop > SQL Scripts,
--              SQL Developer, DBeaver, SQLcl u Oracle Cloud SQL Worksheet.
--
-- Este archivo NO usa SET, COLUMN, PROMPT, SHOW ni @.
-- Por eso funciona en cualquier cliente, incluida la consola web de APEX.
--
-- Dos formas de usarlo:
--   a) En SQL Commands: copiar y ejecutar UNA consulta a la vez.
--   b) En SQL Scripts: subir este archivo y pulsar "Run" (ejecuta todo de una).
--
-- IMPORTANTE: no pegar la salida de las consultas dentro de este archivo.
-- Las lineas de resultado se parsean como SQL y rompen el script.
-- Guardar la evidencia en deploy/resultados/AAAAAMMDD_verify.txt
--
-- Si todas las consultas devuelven 0 filas o errores de tabla inexistente,
-- verificar que estas conectado al esquema dueno de la app (WKSP_SYPEXWS).
-- En APEX SQL Commands el usuario de sesion es ORDS_PLSQL_GATEWAY; eso es normal,
-- porque USER_OBJECTS sigue el esquema actual, no el usuario de sesion.


-- ============================================================
-- 0. Esquema conectado
-- ============================================================
select user as usuario_conectado,
       sys_context('USERENV', 'DB_NAME') as base_datos
  from dual;


-- ============================================================
-- 1. RESUMEN  <-- consulta principal
--    Esperado: tablas=15, bodies_faltantes=0, invalidos=0, triggers=4, estado=OK
-- ============================================================
select bloque,
       tablas_encontradas,
       tablas_esperadas,
       bodies_instalados,
       bodies_faltantes,
       objetos_invalidos,
       triggers,
       case
         when tablas_encontradas = 15
          and bodies_faltantes = 0
          and objetos_invalidos = 0
         then 'OK'
         else 'REVISAR'
       end as estado_global
  from (
        select 'RESUMEN' as bloque,
               (select count(*)
                  from user_tables
                 where table_name in ('EMPRESAS', 'SYN_ROLES', 'USUARIO', 'CLIENTES',
                                      'IMPUESTOS', 'TIPO_CAMBIO', 'TIPO_DOCUMENTO',
                                      'FORMA_PAGO', 'CONDICION_PAGO', 'PRODUCTO_SERVICIO',
                                      'PRESUPUESTOS', 'PRESUPUESTOS_DET', 'FACTURAS',
                                      'FACTURAS_DET', 'GASTO_REAL')) as tablas_encontradas,
               15 as tablas_esperadas,
               (select count(*)
                  from user_objects
                 where object_type = 'PACKAGE BODY') as bodies_instalados,
               (select count(*)
                  from user_objects p
                 where p.object_type = 'PACKAGE'
                   and not exists (select 1
                                     from user_objects b
                                    where b.object_type = 'PACKAGE BODY'
                                      and b.object_name = p.object_name)) as bodies_faltantes,
               (select count(*)
                  from user_objects
                 where status <> 'VALID'
                   and object_type in ('PACKAGE', 'PACKAGE BODY', 'PROCEDURE',
                                       'FUNCTION', 'TRIGGER', 'VIEW')) as objetos_invalidos,
               (select count(*)
                  from user_triggers) as triggers
          from dual
       );


-- ============================================================
-- 2. Tablas esperadas que NO existen
--    Esperado: 0 filas
-- ============================================================
with esperadas(tabla) as (
  select 'EMPRESAS'          from dual union all
  select 'SYN_ROLES'         from dual union all
  select 'USUARIO'           from dual union all
  select 'CLIENTES'          from dual union all
  select 'IMPUESTOS'         from dual union all
  select 'TIPO_CAMBIO'       from dual union all
  select 'TIPO_DOCUMENTO'    from dual union all
  select 'FORMA_PAGO'        from dual union all
  select 'CONDICION_PAGO'    from dual union all
  select 'PRODUCTO_SERVICIO' from dual union all
  select 'PRESUPUESTOS'      from dual union all
  select 'PRESUPUESTOS_DET'  from dual union all
  select 'FACTURAS'          from dual union all
  select 'FACTURAS_DET'      from dual union all
  select 'GASTO_REAL'        from dual
)
select e.tabla as tabla_faltante
  from esperadas e
 where not exists (select 1
                     from user_tables t
                    where t.table_name = e.tabla)
 order by e.tabla;


-- ============================================================
-- 3. Packages sin body  (o bodies invalidos)
--    Esperado: 0 filas
-- ============================================================
select 'SIN BODY' as problema,
       p.object_name,
       cast(null as varchar2(10)) as estado
  from user_objects p
 where p.object_type = 'PACKAGE'
   and not exists (select 1
                     from user_objects b
                    where b.object_type = 'PACKAGE BODY'
                      and b.object_name = p.object_name)
union all
select object_type as problema,
       object_name,
       status as estado
  from user_objects
 where object_type in ('PACKAGE', 'PACKAGE BODY', 'PROCEDURE',
                       'FUNCTION', 'TRIGGER', 'VIEW')
   and status <> 'VALID'
 order by 1, 2;


-- ============================================================
-- 4. Objetos invalidos
--    Esperado: 0 filas
--    Si aparece un trigger INVALID: ejecutar
--      alter trigger <NOMBRE> compile;
--    y volver a consultar. Un trigger solo desactualizado por DDL
--    se revalida sin cambiar su logica.
-- ============================================================
select object_type, object_name, status, last_ddl_time
  from user_objects
 where status <> 'VALID'
   and object_type in ('PACKAGE', 'PACKAGE BODY', 'PROCEDURE',
                       'FUNCTION', 'TRIGGER', 'VIEW')
 order by object_type, object_name;


-- ============================================================
-- 5. Triggers y su estado
--    Esperado: 4 filas, todas ENABLED
--    TRG_ACTUALIZA_TOTALES_FACTURA, TRG_ACTUALIZA_TOTALES_PRESUPUESTO,
--    TRG_CONDICION_PAGO_BI, TRG_FORMA_PAGO_BI
-- ============================================================
select trigger_name, trigger_type, status
  from user_triggers
 order by trigger_name;


-- ============================================================
-- 6. Conteo de objetos por tipo
-- ============================================================
select object_type, count(*) as cantidad
  from user_objects
 where object_type in ('TABLE', 'SEQUENCE', 'INDEX', 'TRIGGER',
                       'FUNCTION', 'PROCEDURE', 'PACKAGE', 'PACKAGE BODY')
 group by object_type
 order by object_type;


-- ============================================================
-- 7. Funciones y procedimientos sueltos
--    Esperado: FN_AUTENTICAR_USUARIO, FN_CLEAN_NUM, FN_EMPRESAS_DEL_USUARIO,
--              FN_PASSWORD_ES_LEGADO, FN_TASA_CAMBIO, FN_TIENE_ROL,
--              FN_USUARIO_EMPRESA_VALIDA, FN_VERIFICAR_PASSWORD,
--              SYPEX_HASH_PASSWORD, PRC_ACTUALIZAR_TASAS_DIARIAS,
--              PRC_AUTH_REGISTRAR, PRC_LOG_RESET_PASSWORD, PRC_POST_LOGIN
--    (Requiere el grant sobre SYS.DBMS_CRYPTO; ver deploy/migrations/20261104_auth_propia.sql)
-- ============================================================
select object_type, object_name, status
  from user_objects
 where object_type in ('FUNCTION', 'PROCEDURE')
 order by object_type, object_name;


-- ============================================================
-- 8. Secuencias
--    Esperado: SEQ_PRODUCTO_SERVICIO, SEQ_FORMA_PAGO, SEQ_CONDICION_PAGO
--    mas una ISEQ$$_<n> por cada columna IDENTITY.
--    Cualquier ISEQ$$_ sin tabla asociada es basura de tablas recreadas.
-- ============================================================
select sequence_name, last_number, increment_by
  from user_sequences
 order by sequence_name;
