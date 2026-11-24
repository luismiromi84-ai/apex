-- =============================================================================
-- 20261124_inventario_modelo_verificacion.sql
--
-- Modelo del inventario con kardex valorado (2026-11-24). Comprueba el MODELO,
-- no el codigo que lo usa:
--
--   M1  existen KARDEX_MOV (20 columnas) y KARDEX_SALDO (9), con su nombre
--   M2  la PK de KARDEX_SALDO es (id_empresa, id_producto_servicio)
--   M3  KARDEX_MOV tiene el CHECK con los 11 tipos de movimiento
--   M4  PRODUCTO_SERVICIO.STOCK_MINIMO existe, NUMBER, default 0
--   M5  fn_asignar_folio(n,'KARDEX') devuelve K-000001 y es correlativo
--   M6  FOLIO_CONTADOR admite la serie KARDEX
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261124_inventario_modelo_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000) := '';
    v_n      number;
    v_txt    clob;
    v_col    number;

    procedure falla(p_caso varchar2, p_detalle varchar2) is
    begin
        v_fallas := v_fallas + 1;
        v_lista  := v_lista || ' | ' || p_caso || ': ' || substrb(p_detalle, 1, 170);
    end;

    procedure espera_num(p_caso varchar2, p_valor number, p_esperado number) is
    begin
        if p_valor is null or p_valor <> p_esperado then
            falla(p_caso, 'esperaba ' || p_esperado || ' y hay ' || nvl(to_char(p_valor), 'NULL'));
        end if;
    end;
begin
    ------------------------------------------------------------------ M1
    select count(*) into v_n
      from all_tab_columns
     where owner = 'WKSP_SYPEXWS' and table_name = 'KARDEX_MOV';
    espera_num('M1 KARDEX_MOV con 20 columnas', v_n, 20);

    if v_n = 20 then
        for c in (select column_name from (select 'ID_MOVIMIENTO' column_name from dual
                                           union all select 'ID_EMPRESA' from dual
                                           union all select 'NUM_MOVIMIENTO' from dual
                                           union all select 'ID_PRODUCTO_SERVICIO' from dual
                                           union all select 'FECHA_MOVIMIENTO' from dual
                                           union all select 'TIPO_MOVIMIENTO' from dual
                                           union all select 'CANTIDAD' from dual
                                           union all select 'COSTO_UNIT_BS' from dual
                                           union all select 'COSTO_TOTAL_BS' from dual
                                           union all select 'TASA_CAMBIO' from dual
                                           union all select 'MONEDA_DOCUMENTO' from dual
                                           union all select 'COSTO_UNIT_REF' from dual
                                           union all select 'COSTO_TOTAL_REF' from dual
                                           union all select 'DOC_TIPO' from dual
                                           union all select 'ID_DOC' from dual
                                           union all select 'ID_DETALLE_ORIGEN' from dual
                                           union all select 'ID_MOVIMIENTO_REVERSA' from dual
                                           union all select 'MOTIVO' from dual
                                           union all select 'CREADO_POR' from dual
                                           union all select 'CREADO_EL' from dual))
        loop
            select count(*) into v_col
              from all_tab_columns
             where owner = 'WKSP_SYPEXWS' and table_name = 'KARDEX_MOV'
               and column_name = c.column_name;
            if v_col = 0 then
                falla('M1 falta la columna', 'KARDEX_MOV.' || c.column_name);
            end if;
        end loop;
    end if;

    select count(*) into v_n
      from all_tab_columns
     where owner = 'WKSP_SYPEXWS' and table_name = 'KARDEX_SALDO';
    espera_num('M1 KARDEX_SALDO con 9 columnas', v_n, 9);

    ------------------------------------------------------------------ M2
    select count(*) into v_n
      from (select cc.column_name
              from all_constraints c
              join all_cons_columns cc on cc.owner = c.owner
                                      and cc.constraint_name = c.constraint_name
             where c.owner = 'WKSP_SYPEXWS' and c.table_name = 'KARDEX_SALDO'
               and c.constraint_type = 'P'
               and cc.column_name in ('ID_EMPRESA', 'ID_PRODUCTO_SERVICIO'));
    espera_num('M2 PK de KARDEX_SALDO en empresa+articulo', v_n, 2);

    ------------------------------------------------------------------ M3
    v_txt := null;
    declare
        v_con varchar2(128);
    begin
        select constraint_name into v_con
          from all_constraints
         where owner = 'WKSP_SYPEXWS' and table_name = 'KARDEX_MOV'
           and constraint_type = 'C' and constraint_name like 'CK_KARDEX_MOV_TIPO%'
           and rownum = 1;
        v_txt := dbms_metadata.get_ddl('CONSTRAINT', v_con, 'WKSP_SYPEXWS');
    exception
        when no_data_found then v_txt := null;
        when others then v_txt := null;
    end;

    if v_txt is null then
        falla('M3 no existe el CHECK de tipo_movimiento', 'CK_KARDEX_MOV_TIPO');
    else
        for t in (select 'ENTRADA_COMPRA' tipo from dual
                  union all select 'SALIDA_FACTURA' from dual
                  union all select 'ENTRADA_NC_CLIENTE' from dual
                  union all select 'SALIDA_ND_CLIENTE' from dual
                  union all select 'SALIDA_NC_PROVEEDOR' from dual
                  union all select 'ENTRADA_ND_PROVEEDOR' from dual
                  union all select 'AJUSTE_ENTRADA' from dual
                  union all select 'AJUSTE_SALIDA' from dual
                  union all select 'SALDO_INICIAL' from dual
                  union all select 'REVERSA_ENTRADA' from dual
                  union all select 'REVERSA_SALIDA' from dual)
        loop
            if instr(upper(to_char(v_txt)), t.tipo) = 0 then
                falla('M3 el CHECK no admite el tipo', t.tipo);
            end if;
        end loop;
    end if;

    ------------------------------------------------------------------ M4
    select count(*) into v_n
      from all_tab_columns
     where owner = 'WKSP_SYPEXWS' and table_name = 'PRODUCTO_SERVICIO'
       and column_name = 'STOCK_MINIMO' and data_type = 'NUMBER';
    espera_num('M4 PRODUCTO_SERVICIO.STOCK_MINIMO', v_n, 1);

    select count(*) into v_n
      from all_tab_columns
     where owner = 'WKSP_SYPEXWS' and table_name = 'PRODUCTO_SERVICIO'
       and column_name = 'STOCK_MINIMO' and trim(nvl(data_default_vc, '0')) = '0';
    espera_num('M4 STOCK_MINIMO con default 0', v_n, 1);

    ------------------------------------------------------------------ M5
    declare
        v_1 varchar2(20);
        v_2 varchar2(20);
    begin
        savepoint m5;
        v_1 := fn_asignar_folio(1, 'KARDEX');
        v_2 := fn_asignar_folio(1, 'KARDEX');
        rollback to savepoint m5;

        if not regexp_like(v_1, '^K-[0-9]{6}$') then
            falla('M5 formato del folio de kardex', nvl(v_1, 'NULL'));
        end if;
        if v_1 = v_2 then
            falla('M5 el folio de kardex no avanza', v_1 || ' = ' || v_2);
        end if;
    exception
        when others then
            falla('M5 no se puede numerar el kardex', sqlerrm);
    end;

    ------------------------------------------------------------------ M6
    v_txt := dbms_metadata.get_ddl('CONSTRAINT', 'CK_FOLIO_CONTADOR_TIPO', 'WKSP_SYPEXWS');
    if v_txt is null or instr(upper(to_char(v_txt)), 'KARDEX') = 0 then
        falla('M6 FOLIO_CONTADOR no admite KARDEX', substrb(nvl(to_char(v_txt), 'NULL'), 1, 120));
    end if;

    ------------------------------------------------------------------ resultado
    if v_fallas > 0 then
        raise_application_error(-20101, 'RESULTADO: FALLAS=' || v_fallas || v_lista);
    end if;
    raise_application_error(-20100, 'RESULTADO: FALLAS=0');
end;
/
