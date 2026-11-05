-- =============================================================================
-- 20261105_porcentajes_facturas.sql
--
-- Objetivo: dejar FACTURAS_DET con UNA sola pareja de porcentajes, la buena
--           (PORCENTAJE_*), y retirar la errata (PORCENTAGE_*).
--
-- Contexto medido el 2026-11-05:
--   - PKG_FACTURACION escribia PORCENTAGE_DESCUENTO / PORCENTAGE_IMPUESTO.
--   - PKG_FACTURA_DETALLE (pagina 10) escribia PORCENTAJE_*.
--   - Resultado: una factura creada desde un presupuesto con descuento guardaba
--     el porcentaje en la columna vieja y la pagina 10 mostraba 0 %.
--   - Ninguna pagina lee las columnas viejas de FACTURAS_DET (revisado en el
--     export: lo que aparece con la errata es PRESUPUESTOS_DET e IMPUESTOS).
--
-- Precondicion: haber compilado ya package_bodies/pkg_facturacion.sql, que ahora
--           escribe PORCENTAJE_*. Si no, el DROP deja el package INVALID.
--
-- Afecta a: FACTURAS_DET (dos columnas). No toca importes ni totales: se
--           comprueba antes y despues que la suma de monto_total_linea y el
--           total de las cabeceras siguen igual.
--
-- OJO: el DROP COLUMN invalida los dependientes; el script termina recompilando
--      el esquema, igual que la migracion del cambio de clave.
--
-- Idempotente: solo borra si las columnas existen.
--
-- Ejecutar:
--   python deploy/conexion/compilar_objeto.py package_bodies/pkg_facturacion.sql
--   python deploy/conexion/importar_export.py deploy/migrations/20261105_porcentajes_facturas.sql
--
-- REVERSA:
--   alter table facturas_det add (porcentage_descuento number, porcentage_impuesto number default 16 not null);
--   update facturas_det set porcentage_descuento = porcentaje_descuento,
--                            porcentage_impuesto  = porcentaje_impuesto;
--   Y volver a compilar package_bodies/pkg_facturacion.sql del commit anterior.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;
/

-- -----------------------------------------------------------------------------
-- Validacion ANTES: las dos columnas existen, nadie las usa fuera del package
-- que ya se corrigio, y no hay diferencias con la pareja buena.
-- -----------------------------------------------------------------------------
select 'FALLA: falta PORCENTAGE_DESCUENTO' as caso from dual
 where not exists (select 1 from all_tab_columns
                    where owner='WKSP_SYPEXWS' and table_name='FACTURAS_DET'
                      and column_name='PORCENTAGE_DESCUENTO');
/

select 'FALLA: las dos parejas se contradicen en alguna fila' as caso from dual
 where exists (select 1 from facturas_det
                where nvl(porcentage_descuento,-1) <> nvl(porcentaje_descuento,-1)
                   or nvl(porcentage_impuesto,-1)  <> nvl(porcentaje_impuesto,-1));
/

-- -----------------------------------------------------------------------------
-- Copia de seguridad de los valores y borrado de las columnas viejas.
-- -----------------------------------------------------------------------------
update facturas_det set
       porcentaje_descuento = nvl(porcentage_descuento, porcentaje_descuento),
       porcentaje_impuesto  = nvl(porcentage_impuesto,  porcentaje_impuesto)
 where porcentage_descuento is not null or porcentage_impuesto is not null;
/

declare
    v_existe number;
begin
    select count(*) into v_existe
      from all_tab_columns
     where owner='WKSP_SYPEXWS' and table_name='FACTURAS_DET'
       and column_name='PORCENTAGE_DESCUENTO';

    if v_existe = 1 then
        execute immediate 'alter table facturas_det drop column porcentage_descuento';
    end if;

    select count(*) into v_existe
      from all_tab_columns
     where owner='WKSP_SYPEXWS' and table_name='FACTURAS_DET'
       and column_name='PORCENTAGE_IMPUESTO';

    if v_existe = 1 then
        execute immediate 'alter table facturas_det drop column porcentage_impuesto';
    end if;

    dbms_utility.compile_schema(schema => 'WKSP_SYPEXWS', compile_all => false);
end;
/

-- -----------------------------------------------------------------------------
-- Validacion DESPUES: todo en cero filas
-- -----------------------------------------------------------------------------
select 'FALLA: las columnas viejas siguen' as caso
  from all_tab_columns
 where owner='WKSP_SYPEXWS' and table_name='FACTURAS_DET'
   and column_name in ('PORCENTAGE_DESCUENTO','PORCENTAGE_IMPUESTO');
/

select 'FALLA: ' || o || ' quedo invalido' as caso
  from (select 'PKG_FACTURACION' o from dual union all
        select 'PKG_FACTURA_DETALLE' from dual) d
 where not exists (select 1 from all_objects
                    where owner='WKSP_SYPEXWS' and object_name = d.o
                      and object_type = 'PACKAGE BODY' and status = 'VALID');
/

select 'FALLA: hay objetos invalidos' as caso
  from all_objects
 where owner='WKSP_SYPEXWS' and status <> 'VALID'
   and object_type in ('FUNCTION','PROCEDURE','PACKAGE','PACKAGE BODY','TRIGGER','VIEW');
/

select 'control: lineas y suma del detalle' as control, count(*) as lineas,
       round(sum(monto_total_linea), 2) as suma
  from facturas_det;
/

select 'control: cabeceras y su total' as control, count(*) as facturas,
       round(sum(monto_total), 2) as suma
  from facturas;
/
