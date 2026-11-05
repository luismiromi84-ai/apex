-- =============================================================================
-- 20261105_condicion_pago_number.sql
--
-- Objetivo: cerrar la ultima clave foranea del repaso, la que quedo bloqueada
--           porque FACTURAS.CONDICION_PAGO era VARCHAR2(50) y
--           CONDICION_PAGO.ID_CONDICION_PAGO es NUMBER (ORA-02267).
--
-- Contexto medido el 2026-11-05:
--   - 40 facturas de la empresa 1 con CONDICION_PAGO nula y 6 de Mexico con '1'
--     y '4' guardados como texto. Ningun valor no numerico.
--   - La LOV de la pagina 9 (P9_CONDICION_PAGO) ya devuelve id_condicion_pago,
--     que es NUMBER: la columna solo lo guardaba como texto.
--   - PKG_FACTURACION recibe p_condicion_pago como VARCHAR2 y lo inserta: seguira
--     funcionando por conversion implicita, pero a partir de ahora un valor no
--     numerico falla en vez de guardarse.
--
-- Afecta a: FACTURAS.CONDICION_PAGO (tipo) y una restriccion. No toca importes.
--
-- Precondicion: haber aplicado 20261105_fk_faltantes.sql.
--
-- Idempotente: solo cambia el tipo si sigue siendo VARCHAR2 y solo crea la FK
--           si no existe.
--
-- Ejecutar:
--   python deploy/conexion/importar_export.py deploy/migrations/20261105_condicion_pago_number.sql
--
-- REVERSA:
--   alter table facturas drop constraint fk_factura_condicion;
--   alter table facturas modify (condicion_pago varchar2(50));
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;
/

-- -----------------------------------------------------------------------------
-- Validacion ANTES: ningun valor que no sea numerico
-- -----------------------------------------------------------------------------
select 'FALLA: hay condiciones de pago no numericas' as caso from dual
 where exists (select 1 from facturas
                where condicion_pago is not null
                  and not regexp_like(trim(condicion_pago), '^[0-9]+$'));
/

select 'FALLA: hay condiciones de pago que no existen en el catalogo' as caso from dual
 where exists (select 1 from facturas f
                where f.condicion_pago is not null
                  and not exists (select 1 from condicion_pago c
                                   where to_char(c.id_condicion_pago) = trim(f.condicion_pago)));
/

select 'control antes: tipo de la columna' as control,
       data_type || '(' || data_length || ')' as tipo
  from all_tab_columns
 where owner = 'WKSP_SYPEXWS' and table_name = 'FACTURAS' and column_name = 'CONDICION_PAGO';
/

-- -----------------------------------------------------------------------------
-- Cambio de tipo y creacion de la FK
-- -----------------------------------------------------------------------------
declare
    v_tipo varchar2(30);
    v_n    number;
begin
    select data_type into v_tipo
      from all_tab_columns
     where owner='WKSP_SYPEXWS' and table_name='FACTURAS' and column_name='CONDICION_PAGO';

    -- Oracle no cambia VARCHAR2 a NUMBER si la columna tiene filas (ORA-01439),
    -- asi que se hace el baile: columna nueva, copia, borrar la vieja, renombrar.
    if v_tipo = 'VARCHAR2' then
        select count(*) into v_n from all_tab_columns
         where owner='WKSP_SYPEXWS' and table_name='FACTURAS' and column_name='CONDICION_PAGO_NUM';
        if v_n > 0 then
            execute immediate 'alter table facturas drop column condicion_pago_num';
        end if;

        execute immediate 'alter table facturas add (condicion_pago_num number)';

        execute immediate 'update facturas set condicion_pago_num = to_number(trim(condicion_pago))';

        execute immediate 'alter table facturas drop column condicion_pago';

        execute immediate 'alter table facturas rename column condicion_pago_num to condicion_pago';
    end if;

    select count(*) into v_n
      from all_constraints
     where owner='WKSP_SYPEXWS' and table_name='FACTURAS'
       and constraint_name='FK_FACTURA_CONDICION';

    if v_n = 0 then
        execute immediate 'alter table facturas add constraint fk_factura_condicion '
                       || 'foreign key (condicion_pago) references condicion_pago (id_condicion_pago)';
    end if;

    -- el drop de la columna vieja se lleva por delante su indice
    select count(*) into v_n from all_indexes
     where owner='WKSP_SYPEXWS' and index_name='IX_FACTURAS_CONDICION';
    if v_n = 0 then
        execute immediate 'create index ix_facturas_condicion on facturas (condicion_pago)';
    end if;

    dbms_utility.compile_schema(schema => 'WKSP_SYPEXWS', compile_all => false);
end;
/

-- -----------------------------------------------------------------------------
-- Validacion DESPUES
-- -----------------------------------------------------------------------------
select 'control despues: tipo de la columna' as control,
       data_type as tipo
  from all_tab_columns
 where owner = 'WKSP_SYPEXWS' and table_name = 'FACTURAS' and column_name = 'CONDICION_PAGO';
/

select 'FALLA: falta FK_FACTURA_CONDICION' as caso from dual
 where not exists (select 1 from all_constraints
                    where owner='WKSP_SYPEXWS' and table_name='FACTURAS'
                      and constraint_name='FK_FACTURA_CONDICION' and status='ENABLED');
/

select 'FALLA: ' || o || ' invalido' as caso
  from (select 'PKG_FACTURACION' o from dual union all
        select 'PKG_REPORTES_FACTURA'    from dual) d
 where not exists (select 1 from all_objects
                    where owner='WKSP_SYPEXWS' and object_name = d.o
                      and object_type = 'PACKAGE BODY' and status = 'VALID');
/

select 'FALLA: hay objetos invalidos' as caso
  from all_objects
 where owner='WKSP_SYPEXWS' and status <> 'VALID'
   and object_type in ('FUNCTION','PROCEDURE','PACKAGE','PACKAGE BODY','TRIGGER','VIEW');
/

select 'control: facturas y su total' as control, count(*) as facturas,
       round(sum(monto_total), 2) as suma
  from facturas;
/
