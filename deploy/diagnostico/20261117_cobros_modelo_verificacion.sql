-- =============================================================================
-- 20261117_cobros_modelo_verificacion.sql
--
-- Modelo de la fase de cobros (2026-11-17):
--   M1  existe RECIBOS con sus columnas
--   M2  FACTURAS admite el estado PARCIAL
--   M3  EMPRESAS.ES_SPE existe y arranca en 'N'
--   M4  IMPUESTOS.APLICA_EN existe y la fila IGTF de VE es 'CABECERA'
--   M5  FORMA_PAGO.GENERA_IGTF existe y DIVISAS es 'S'
--   M6  los indices y la FK de RECIBOS estan
--   M7  el ESTADO de RECIBOS solo admite ACTIVO/ANULADO
--
-- Todo el DML va dentro de un SAVEPOINT y se revierte.
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261117_cobros_modelo_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

begin
    begin execute immediate 'drop table tmp_cobmod_fallas purge'; exception when others then null; end;
end;
/

create table tmp_cobmod_fallas (caso varchar2(300))
/

declare
    type t_lista is table of varchar2(300);
    v_fallas t_lista := t_lista();
    v_msg    varchar2(300);
    v_n      number;
    v_txt    varchar2(4000);
    v_fac    number;

    procedure falla(p_texto varchar2) is
    begin
        v_fallas.extend;
        v_fallas(v_fallas.last) := substrb(p_texto, 1, 300);
    end;

    procedure exige_columna(p_tabla varchar2, p_columna varchar2) is
    begin
        select count(*) into v_n from all_tab_columns
         where owner = 'WKSP_SYPEXWS' and table_name = p_tabla and column_name = p_columna;
        if v_n = 0 then falla('M1: falta ' || p_tabla || '.' || p_columna); end if;
    end;
begin
    savepoint sp_cobmod;

    -- M1: tabla y columnas del spec
    select count(*) into v_n from all_tables
     where owner = 'WKSP_SYPEXWS' and table_name = 'RECIBOS';
    if v_n = 0 then
        falla('M1: no existe la tabla RECIBOS');
    else
        exige_columna('RECIBOS', 'ID_RECIBO');
        exige_columna('RECIBOS', 'ID_EMPRESA');
        exige_columna('RECIBOS', 'ID_FACTURA');
        exige_columna('RECIBOS', 'FECHA_COBRO');
        exige_columna('RECIBOS', 'ID_FORMA_PAGO');
        exige_columna('RECIBOS', 'COD_MONEDA');
        exige_columna('RECIBOS', 'TIPO_CAMBIO');
        exige_columna('RECIBOS', 'MONTO_COBRADO');
        exige_columna('RECIBOS', 'MONTO_BS');
        exige_columna('RECIBOS', 'MONTO_FACTURA');
        exige_columna('RECIBOS', 'APLICA_IGTF');
        exige_columna('RECIBOS', 'IGTF_MONTO');
        exige_columna('RECIBOS', 'IGTF_BS');
        exige_columna('RECIBOS', 'RETENCION_IVA_BS');
        exige_columna('RECIBOS', 'NRO_COMPROBANTE_RETENCION');
        exige_columna('RECIBOS', 'MONTO_NETO');
        exige_columna('RECIBOS', 'REFERENCIA');
        exige_columna('RECIBOS', 'CONCILIADO');
        exige_columna('RECIBOS', 'FECHA_CONCILIACION');
        exige_columna('RECIBOS', 'ESTADO');
        exige_columna('RECIBOS', 'OBSERVACIONES');
        exige_columna('RECIBOS', 'CREADO_POR');
        exige_columna('RECIBOS', 'FECHA_CREACION');
        exige_columna('RECIBOS', 'MODIFICADO_POR');
        exige_columna('RECIBOS', 'FECHA_MODIFICACION');
    end if;

    -- M2: FACTURAS admite PARCIAL (se prueba de verdad, con una fila y rollback)
    begin
        insert into facturas (id_empresa, id_cliente, tipo_documento, folio_factura,
                              cod_moneda, tipo_cambio, fecha_emision, subtotal,
                              monto_impuesto, monto_total, estado, creado_por)
        values (1, (select min(id_cliente) from clientes where id_empresa = 1),
                'FAC', 'CHK-PARCIAL-ZZ', 'VES', 1, sysdate, 0, 0, 0, 'PARCIAL', 'test')
        returning id_factura into v_fac;
        delete from facturas where id_factura = v_fac;
    exception
        when others then
            falla('M2: FACTURAS no admite el estado PARCIAL: ' || substrb(sqlerrm, 1, 160));
    end;

    -- M3: SPE de la empresa
    select count(*) into v_n from all_tab_columns
     where owner = 'WKSP_SYPEXWS' and table_name = 'EMPRESAS' and column_name = 'ES_SPE';
    if v_n = 0 then
        falla('M3: falta EMPRESAS.ES_SPE');
    else
        execute immediate 'select nvl(max(es_spe), ''#'') from empresas' into v_txt;
        if v_txt <> 'N' then falla('M3: ES_SPE deberia arrancar en N y vale ' || v_txt); end if;
    end if;

    -- M4: alicuota configurable
    select count(*) into v_n from all_tab_columns
     where owner = 'WKSP_SYPEXWS' and table_name = 'IMPUESTOS' and column_name = 'APLICA_EN';
    if v_n = 0 then
        falla('M4: falta IMPUESTOS.APLICA_EN');
    else
        execute immediate 'select aplica_en from impuestos
                             where cod_pais = ''VE'' and cod_impuesto = ''IGTF''' into v_txt;
        if v_txt <> 'CABECERA' then falla('M4: el IGTF de VE tiene APLICA_EN=' || v_txt); end if;
    end if;

    -- M5: forma de pago en divisas
    select count(*) into v_n from all_tab_columns
     where owner = 'WKSP_SYPEXWS' and table_name = 'FORMA_PAGO' and column_name = 'GENERA_IGTF';
    if v_n = 0 then
        falla('M5: falta FORMA_PAGO.GENERA_IGTF');
    else
        execute immediate 'select genera_igtf from forma_pago where codigo = ''DIVISAS''' into v_txt;
        if v_txt <> 'S' then falla('M5: DIVISAS tiene GENERA_IGTF=' || v_txt); end if;
    end if;

    -- M6: indices y FK
    select count(*) into v_n from all_indexes
     where owner = 'WKSP_SYPEXWS' and table_name = 'RECIBOS'
       and index_name in ('IX_RECIBOS_FACTURA', 'IX_RECIBOS_EMPRESA_FECHA');
    if v_n <> 2 then falla('M6: faltan indices de RECIBOS (' || v_n || '/2)'); end if;

    select count(*) into v_n from all_constraints
     where owner = 'WKSP_SYPEXWS' and table_name = 'RECIBOS'
       and constraint_name = 'FK_RECIBOS_FACTURA' and constraint_type = 'R';
    if v_n = 0 then falla('M6: falta FK_RECIBOS_FACTURA'); end if;

    -- M7: el CHECK del estado del recibo
    begin
        execute immediate 'insert into recibos
                     (id_empresa, id_factura, fecha_cobro, cod_moneda, tipo_cambio,
                      monto_cobrado, monto_bs, monto_factura, aplica_igtf, igtf_monto,
                      igtf_bs, retencion_iva_bs, monto_neto, conciliado, estado, creado_por)
                     values (1, (select min(id_factura) from facturas where id_empresa = 1),
                             sysdate, ''VES'', 1, 1, 1, 1, ''N'', 0, 0, 0, 1, ''N'', ''BORRADO'', ''test'')';
        falla('M7: RECIBOS acepto un ESTADO que no es ACTIVO/ANULADO');
    exception
        when others then null;   -- lo esperado: ORA-02290
    end;

    rollback to sp_cobmod;

    for i in 1 .. v_fallas.count loop
        insert into tmp_cobmod_fallas values (v_fallas(i));
    end loop;
exception
    when others then
        rollback to sp_cobmod;
        v_msg := substrb('M?: el caso revento: ' || sqlerrm, 1, 300);
        insert into tmp_cobmod_fallas values (v_msg);
end;
/

declare
    v_fallas number;
    v_lista  varchar2(3000);
begin
    select count(*) into v_fallas from tmp_cobmod_fallas;
    select substrb(listagg(caso, ' | ' on overflow truncate) within group (order by caso), 1, 3000)
      into v_lista from tmp_cobmod_fallas;
    execute immediate 'drop table tmp_cobmod_fallas purge';
    raise_application_error(-20100, substrb('RESULTADO: FALLAS=' || v_fallas || ' | ' || v_lista, 1, 3000));
end;
/
