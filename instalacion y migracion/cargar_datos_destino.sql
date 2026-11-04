-- =============================================================================
-- cargar_datos_destino.sql
-- Carga en la base DESTINO (Sypex_SQL) los datos extraídos con
-- extraer_datos_origen.sql. Ejecutar en SQLcl, conectado a Sypex_SQL,
-- desde esta misma carpeta:
--
--   sql -name SYPEX_SQL_MCP @cargar_datos_destino.sql
--
-- No usar el MCP de Oracle para esto: la conexión del MCP tiene autocommit a
-- nivel de conexión y una carga a medias no se puede revertir.
--
-- Orden de carga (respeta las claves foráneas):
--   DEPT, EMP, SYN_ROLES, USUARIO, TIPO_CAMBIO, PRODUCTO_SERVICIO,
--   PRESUPUESTOS, PRESUPUESTOS_DET, FACTURAS, FACTURAS_DET
--
-- Totales: los triggers compound de PRESUPUESTOS y FACTURAS recalculan las
-- cabeceras al insertar el detalle. Es el mismo comportamiento que en la base
-- original, así que los totales deben coincidir al final.
-- =============================================================================

set define off
set feedback on
set verify off
set serveroutput on
set sqlformat default
whenever sqlerror exit sql.sqlcode rollback

alter session set current_schema = WKSP_SYPEXWS;

-- ===== INICIO datos_origen.sql =====
--
-- Opcion A (recomendada): ejecutar el archivo generado, en esta ruta relativa.
-- @datos_origen.sql
--
-- Opcion B: pegar aqui el contenido completo de datos_origen.sql.
--
-- ===== FIN datos_origen.sql =====

commit;

-- -----------------------------------------------------------------------------
-- Reajuste de secuencias.
--
-- Los INSERT traen IDs explícitos, que no avanzan las secuencias. Sin este paso
-- el próximo INSERT de la app intentaría reutilizar un ID ya ocupado.
--
-- Columnas IDENTITY: no se puede alterar su secuencia ISEQ$$_ (ORA-32793).
-- La forma soportada es START WITH LIMIT VALUE, que la deja en max(columna)+1.
-- -----------------------------------------------------------------------------
declare
    v_want number;
    v_cur  number;
    v_diff number;

    procedure realinear_secuencia(p_seq varchar2, p_tabla varchar2, p_columna varchar2) is
    begin
        execute immediate 'select nvl(max("' || p_columna || '"),0)+1 from "WKSP_SYPEXWS"."' || p_tabla || '"'
            into v_want;
        execute immediate 'select "WKSP_SYPEXWS"."' || p_seq || '".nextval from dual' into v_cur;
        if v_want > v_cur then
            v_diff := v_want - v_cur;
            execute immediate 'alter sequence "WKSP_SYPEXWS"."' || p_seq || '" increment by ' || v_diff;
            execute immediate 'select "WKSP_SYPEXWS"."' || p_seq || '".nextval from dual' into v_cur;
        end if;
        execute immediate 'alter sequence "WKSP_SYPEXWS"."' || p_seq || '" increment by 1';
        dbms_output.put_line('secuencia ' || p_seq || ' -> proximo ' || v_want);
    end;
begin
    for r in (select table_name, column_name, generation_type
                from all_tab_identity_cols
               where owner = 'WKSP_SYPEXWS')
    loop
        execute immediate 'alter table "WKSP_SYPEXWS"."' || r.table_name || '" modify ("' || r.column_name
                       || '" GENERATED ' || r.generation_type || ' AS IDENTITY (START WITH LIMIT VALUE))';
        dbms_output.put_line('identity realineada: ' || r.table_name || '.' || r.column_name);
    end loop;

    -- Secuencias explícitas usadas por DEFAULT o por triggers BEFORE INSERT.
    realinear_secuencia('SEQ_PRODUCTO_SERVICIO', 'PRODUCTO_SERVICIO', 'ID_PRODUCTO_SERVICIO');
    realinear_secuencia('SEQ_CONDICION_PAGO',    'CONDICION_PAGO',    'ID_CONDICION_PAGO');
    realinear_secuencia('SEQ_FORMA_PAGO',        'FORMA_PAGO',        'ID_FORMA_PAGO');
    realinear_secuencia('DEPT_SEQ',              'DEPT',              'DEPTNO');
    realinear_secuencia('EMP_SEQ',               'EMP',               'EMPNO');
end;
/

-- -----------------------------------------------------------------------------
-- Validación: filas por tabla contra los conteos de la base original.
-- Total esperado: 216.
-- -----------------------------------------------------------------------------
select e.tabla,
       e.esperado,
       x.c as filas,
       case when x.c = e.esperado then 'OK' else 'DIFERENCIA' end as estado
  from (select 'CLIENTES' as tabla, 3 as esperado from dual union all
        select 'CONDICION_PAGO', 7 from dual union all
        select 'DEPT', 4 from dual union all
        select 'EMP', 14 from dual union all
        select 'EMPRESAS', 1 from dual union all
        select 'FACTURAS', 22 from dual union all
        select 'FACTURAS_DET', 40 from dual union all
        select 'FORMA_PAGO', 6 from dual union all
        select 'GASTO_REAL', 0 from dual union all
        select 'IMPUESTOS', 5 from dual union all
        select 'PRESUPUESTOS', 40 from dual union all
        select 'PRESUPUESTOS_DET', 18 from dual union all
        select 'PRODUCTO_SERVICIO', 4 from dual union all
        select 'SYN_ROLES', 4 from dual union all
        select 'TIPO_CAMBIO', 36 from dual union all
        select 'TIPO_DOCUMENTO', 4 from dual union all
        select 'USUARIO', 8 from dual) e,
       xmltable('/ROWSET/ROW'
                passing xmltype(dbms_xmlgen.getxml('select count(*) c from "WKSP_SYPEXWS"."' || e.tabla || '"'))
                columns c number path 'C') x
 order by e.tabla;

select count(*) as tablas,
       sum(filas) as filas_total,
       sum(esperado) as esperado_total,
       case when sum(filas) = sum(esperado) then 'TOTAL OK' else 'TOTAL DIFERENTE' end as estado
  from (select e.tabla,
               e.esperado,
               x.c as filas
          from (select 'CLIENTES' as tabla, 3 as esperado from dual union all
                select 'CONDICION_PAGO', 7 from dual union all
                select 'DEPT', 4 from dual union all
                select 'EMP', 14 from dual union all
                select 'EMPRESAS', 1 from dual union all
                select 'FACTURAS', 22 from dual union all
                select 'FACTURAS_DET', 40 from dual union all
                select 'FORMA_PAGO', 6 from dual union all
                select 'GASTO_REAL', 0 from dual union all
                select 'IMPUESTOS', 5 from dual union all
                select 'PRESUPUESTOS', 40 from dual union all
                select 'PRESUPUESTOS_DET', 18 from dual union all
                select 'PRODUCTO_SERVICIO', 4 from dual union all
                select 'SYN_ROLES', 4 from dual union all
                select 'TIPO_CAMBIO', 36 from dual union all
                select 'TIPO_DOCUMENTO', 4 from dual union all
                select 'USUARIO', 8 from dual) e,
               xmltable('/ROWSET/ROW'
                        passing xmltype(dbms_xmlgen.getxml('select count(*) c from "WKSP_SYPEXWS"."' || e.tabla || '"'))
                        columns c number path 'C') x);
