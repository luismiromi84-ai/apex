-- =============================================================================
-- 20261105_porcentajes_presupuestos.sql
--
-- Objetivo: quitar la ultima errata del modelo. PRESUPUESTOS_DET solo tenia
--           PORCENTAGE_DESCUENTO y PORCENTAGE_IMPUESTO; se renombran a
--           PORCENTAJE_* para que coincidan con FACTURAS_DET y con los
--           parametros de los packages (que ya se llaman p_porcentaje_*).
--
-- Afecta a: dos nombres de columna en PRESUPUESTOS_DET. Es metadato: no mueve
--           datos ni cambia importes.
--
-- OJO, orden de ejecucion. Renombrar invalida a quien las usa, asi que despues
--      de este script hay que:
--        1. recompilar package_bodies/pkg_presupuesto_detalle.sql
--        2. recompilar package_bodies/pkg_facturacion.sql
--        3. reimportar pagina_apex/f100.sql (la region de detalle de la pagina 5
--           y los dos items de la pagina 6 citan las columnas viejas)
--        4. dbms_utility.compile_schema
--
-- Idempotente: solo renombra si todavia existe el nombre viejo.
--
-- Ejecutar:
--   python deploy/conexion/importar_export.py deploy/migrations/20261105_porcentajes_presupuestos.sql
--
-- REVERSA:
--   alter table presupuestos_det rename column porcentaje_descuento to porcentage_descuento;
--   alter table presupuestos_det rename column porcentaje_impuesto  to porcentage_impuesto;
--   y volver a compilar los dos packages del commit anterior.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;
/

select 'control antes' as control, column_name
  from all_tab_columns
 where owner='WKSP_SYPEXWS' and table_name='PRESUPUESTOS_DET'
   and column_name like 'PORCENTA%'
 order by column_name;
/

declare
    v_n number;
begin
    select count(*) into v_n from all_tab_columns
     where owner='WKSP_SYPEXWS' and table_name='PRESUPUESTOS_DET'
       and column_name='PORCENTAGE_DESCUENTO';
    if v_n = 1 then
        execute immediate 'alter table presupuestos_det rename column porcentage_descuento to porcentaje_descuento';
    end if;

    select count(*) into v_n from all_tab_columns
     where owner='WKSP_SYPEXWS' and table_name='PRESUPUESTOS_DET'
       and column_name='PORCENTAGE_IMPUESTO';
    if v_n = 1 then
        execute immediate 'alter table presupuestos_det rename column porcentage_impuesto to porcentaje_impuesto';
    end if;
end;
/

select 'control despues' as control, column_name
  from all_tab_columns
 where owner='WKSP_SYPEXWS' and table_name='PRESUPUESTOS_DET'
   and column_name like 'PORCENTA%'
 order by column_name;
/

select 'control: lineas y suma del detalle' as control, count(*) as lineas,
       round(sum(monto_total_linea), 2) as suma
  from presupuestos_det;
/
