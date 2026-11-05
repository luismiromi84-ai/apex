-- =============================================================================
-- 20261105_fk_faltantes.sql
--
-- Objetivo: crear las cinco claves foraneas que faltaban en el modelo, mas su
--           indice (Oracle no indexa el lado hijo de una FK por su cuenta).
--
-- Medido el 2026-11-05 antes de escribir esto:
--   PRESUPUESTOS.ID_CLIENTE              0 huerfanos, 0 nulos
--   PRESUPUESTOS_DET.ID_PRODUCTO_SERVICIO 0 huerfanos
--   PRESUPUESTOS_DET.ID_IMPUESTO           0 huerfanos
--   FACTURAS_DET.ID_PRODUCTO               0 huerfanos
--   FACTURAS.CONDICION_PAGO                0 huerfanos
--
-- Afecta a: cinco restricciones y cinco indices. No toca datos.
--
-- OJO: la FK de PRESUPUESTOS.ID_CLIENTE garantiza que el cliente exista, NO que
--      sea de la misma empresa. Para eso haria falta una FK compuesta
--      (id_empresa, id_cliente) y un unico en CLIENTES(id_empresa, id_cliente).
--      Hoy no hay ningun caso cruzado, pero la regla no esta en la base.
--
-- PENDIENTE (medido el 2026-11-05): FACTURAS.CONDICION_PAGO es VARCHAR2(50) y
--      CONDICION_PAGO.ID_CONDICION_PAGO es NUMBER, asi que la FK se rechaza con
--      ORA-02267. Son 40 filas de la empresa 1 con NULL y 6 de Mexico con '1' y
--      '4' como texto. Para cerrarla hay que cambiar el tipo de la columna a
--      NUMBER (los valores actuales son numericos) y revisar la pagina 9 y su
--      LOV. No se hace aqui porque toca UI.
--
-- Idempotente: cada restriccion y cada indice se crean solo si no existen.
--
-- Ejecutar:
--   python deploy/conexion/importar_export.py deploy/migrations/20261105_fk_faltantes.sql
--
-- REVERSA:
--   alter table presupuestos     drop constraint fk_presupuesto_cliente;
--   alter table presupuestos_det drop constraint fk_presup_det_producto;
--   alter table presupuestos_det drop constraint fk_presup_det_impuesto;
--   alter table facturas_det     drop constraint fk_fact_det_producto;
--   alter table facturas         drop constraint fk_factura_condicion;
--   drop index ix_presupuestos_cliente;
--   drop index ix_presup_det_producto;
--   drop index ix_presup_det_impuesto;
--   drop index ix_fact_det_producto;
--   drop index ix_facturas_condicion;
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;
/

-- -----------------------------------------------------------------------------
-- Validacion ANTES: ninguna debe devolver filas
-- -----------------------------------------------------------------------------
select 'FALLA: hay presupuestos sin cliente valido' as caso from dual
 where exists (select 1 from presupuestos p
                where p.id_cliente is null
                   or not exists (select 1 from clientes c where c.id_cliente = p.id_cliente));
/

select 'FALLA: hay detalle de presupuesto con producto inexistente' as caso from dual
 where exists (select 1 from presupuestos_det d
                where d.id_producto_servicio is not null
                  and not exists (select 1 from producto_servicio x
                                   where x.id_producto_servicio = d.id_producto_servicio));
/

select 'FALLA: hay detalle de presupuesto con impuesto inexistente' as caso from dual
 where exists (select 1 from presupuestos_det d
                where d.id_impuesto is not null
                  and not exists (select 1 from impuestos i where i.id_impuesto = d.id_impuesto));
/

select 'FALLA: hay detalle de factura con producto inexistente' as caso from dual
 where exists (select 1 from facturas_det d
                where d.id_producto is not null
                  and not exists (select 1 from producto_servicio x
                                   where x.id_producto_servicio = d.id_producto));
/

select 'FALLA: hay facturas con condicion de pago inexistente' as caso from dual
 where exists (select 1 from facturas f
                where f.condicion_pago is not null
                  and not exists (select 1 from condicion_pago c
                                   where c.id_condicion_pago = f.condicion_pago));
/

-- -----------------------------------------------------------------------------
-- Creacion idempotente de restricciones e indices
-- -----------------------------------------------------------------------------
declare
    type t_fk is record (
        p_tabla      varchar2(30),
        p_nombre     varchar2(30),
        p_columna    varchar2(30),
        p_ref_tabla  varchar2(30),
        p_ref_col    varchar2(30),
        p_indice     varchar2(30)
    );
    type t_lista is table of t_fk;
    v_fks t_lista := t_lista(
        t_fk('PRESUPUESTOS',     'FK_PRESUPUESTO_CLIENTE', 'ID_CLIENTE',             'CLIENTES',          'ID_CLIENTE',             'IX_PRESUPUESTOS_CLIENTE'),
        t_fk('PRESUPUESTOS_DET', 'FK_PRESUP_DET_PRODUCTO', 'ID_PRODUCTO_SERVICIO',   'PRODUCTO_SERVICIO', 'ID_PRODUCTO_SERVICIO',   'IX_PRESUP_DET_PRODUCTO'),
        t_fk('PRESUPUESTOS_DET', 'FK_PRESUP_DET_IMPUESTO', 'ID_IMPUESTO',            'IMPUESTOS',         'ID_IMPUESTO',             'IX_PRESUP_DET_IMPUESTO'),
        t_fk('FACTURAS_DET',     'FK_FACT_DET_PRODUCTO',   'ID_PRODUCTO',            'PRODUCTO_SERVICIO', 'ID_PRODUCTO_SERVICIO',   'IX_FACT_DET_PRODUCTO')
        -- NO va FACTURAS.CONDICION_PAGO -> CONDICION_PAGO: la columna es
        -- VARCHAR2(50) y la referenciada es NUMBER, asi que Oracle la rechaza
        -- con ORA-02267. Ver la nota al final del archivo.
    );
    v_n number;
begin
    for i in 1 .. v_fks.count loop
        -- indice del lado hijo. Si la columna ya tiene un indice, Oracle
        -- devuelve ORA-01408 y no hay nada que hacer.
        select count(*) into v_n
          from all_indexes
         where owner = 'WKSP_SYPEXWS' and index_name = v_fks(i).p_indice;

        if v_n = 0 then
            begin
                execute immediate 'create index ' || v_fks(i).p_indice
                               || ' on ' || v_fks(i).p_tabla || ' (' || v_fks(i).p_columna || ')';
            exception
                when others then
                    if sqlcode <> -1408 then
                        raise;
                    end if;
            end;
        end if;

        -- clave foranea
        select count(*) into v_n
          from all_constraints
         where owner = 'WKSP_SYPEXWS' and table_name = v_fks(i).p_tabla
           and constraint_name = v_fks(i).p_nombre;

        if v_n = 0 then
            execute immediate 'alter table ' || v_fks(i).p_tabla
                           || ' add constraint ' || v_fks(i).p_nombre
                           || ' foreign key (' || v_fks(i).p_columna || ')'
                           || ' references ' || v_fks(i).p_ref_tabla
                           || ' (' || v_fks(i).p_ref_col || ')';
        end if;
    end loop;

    dbms_utility.compile_schema(schema => 'WKSP_SYPEXWS', compile_all => false);
end;
/

-- -----------------------------------------------------------------------------
-- Validacion DESPUES: ninguna debe devolver filas
-- -----------------------------------------------------------------------------
select 'FALLA: ' || c || ' no existe o no esta habilitada' as caso
  from (select 'FK_PRESUPUESTO_CLIENTE' c from dual union all
        select 'FK_PRESUP_DET_PRODUCTO'       from dual union all
        select 'FK_PRESUP_DET_IMPUESTO'       from dual union all
        select 'FK_FACT_DET_PRODUCTO'         from dual) d
 where not exists (select 1 from all_constraints
                    where owner = 'WKSP_SYPEXWS' and constraint_name = d.c
                      and constraint_type = 'R' and status = 'ENABLED');
/

select 'FALLA: ' || i || ' no existe' as caso
  from (select 'IX_PRESUPUESTOS_CLIENTE' i from dual union all
        select 'IX_PRESUP_DET_PRODUCTO'     from dual union all
        select 'IX_PRESUP_DET_IMPUESTO'     from dual union all
        select 'IX_FACT_DET_PRODUCTO'       from dual) d
 where not exists (select 1 from all_indexes
                    where owner = 'WKSP_SYPEXWS' and index_name = d.i);
/

select 'FALLA: hay objetos invalidos' as caso
  from all_objects
 where owner = 'WKSP_SYPEXWS' and status <> 'VALID'
   and object_type in ('FUNCTION','PROCEDURE','PACKAGE','PACKAGE BODY','TRIGGER','VIEW');
/

select 'control: facturas y su detalle' as control,
       (select count(*) from facturas) as facturas,
       (select count(*) from facturas_det) as lineas
  from dual;
/
