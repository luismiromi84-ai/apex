-- =============================================================================
-- 20261119_proveedores_spe_credito.sql
--
-- La maestra de proveedores gana los dos datos que faltaban para compras
-- (2026-11-19):
--   ES_SPE         Sujeto Pasivo Especial: sus pagos en divisa causan IGTF.
--   DIAS_CREDITO   plazo con el que factura, para calcular el vencimiento de la
--                  factura de compra.
--
-- Idempotente: solo agrega las columnas si no existen (all_tab_columns, no
-- user_tab_columns: en esta base el usuario de conexion es ADMIN).
--
-- Reversa: alter table proveedores drop column es_spe; ... drop column dias_credito;
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_n number;
begin
    select count(*) into v_n from all_tab_columns
     where owner = 'WKSP_SYPEXWS' and table_name = 'PROVEEDORES' and column_name = 'ES_SPE';
    if v_n = 0 then
        execute immediate 'alter table proveedores add (es_spe char(1) default ''N'' not null)';
        execute immediate 'alter table proveedores add constraint chk_proveedores_spe check (es_spe in (''S'',''N''))';
    end if;

    select count(*) into v_n from all_tab_columns
     where owner = 'WKSP_SYPEXWS' and table_name = 'PROVEEDORES' and column_name = 'DIAS_CREDITO';
    if v_n = 0 then
        execute immediate 'alter table proveedores add (dias_credito number(3) default 0 not null)';
        execute immediate 'alter table proveedores add constraint chk_proveedores_credito check (dias_credito between 0 and 365)';
    end if;
end;
/

begin
    dbms_utility.compile_schema('WKSP_SYPEXWS', false);
end;
/
