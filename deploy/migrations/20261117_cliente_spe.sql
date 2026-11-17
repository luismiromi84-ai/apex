-- =============================================================================
-- 20261117_cliente_spe.sql
--
-- El IGTF es una transaccion entre dos Sujetos Pasivos Especiales: ademas de la
-- empresa (que lo percibe), el cliente tiene que estar marcado como SPE.
--
-- Idempotente. Verificacion: deploy/diagnostico/20261117_cobros_registrar_verificacion.sql
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_n number;
begin
    select count(*) into v_n from all_tab_columns
     where owner = 'WKSP_SYPEXWS' and table_name = 'CLIENTES' and column_name = 'ES_SPE';
    if v_n = 0 then
        execute immediate 'alter table clientes add (es_spe char(1) default ''N'')';
        execute immediate 'alter table clientes add constraint chk_clientes_spe check (es_spe in (''S'', ''N''))';
    end if;
end;
/

begin
    dbms_utility.compile_schema('WKSP_SYPEXWS', false);
end;
/
