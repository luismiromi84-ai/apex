-- =============================================================================
-- 20261122_saldo_lista_verificacion.sql
--
-- La columna "Saldo" de la lista de compras (27) mostraba deuda en un BORRADOR y
-- en una NOTA: solo una factura procesada debe plata. Con las notas de credito y
-- los borradores en la misma lista, el saldo se calculaba para todos.
--
--   S1  la consulta guardada del informe limita el saldo a FAC procesadas
--       (REGISTRADA/PARCIAL/PAGADA) y sigue usando fn_saldo_compra
--   S2  ejecutando la CONSULTA GUARDADA: el saldo es nulo exactamente en las
--       filas que no son una FAC procesada (invariante sobre todos los datos)
--   S3  caso controlado (proveedor de prueba): BORRADOR -> nulo, ANULADA -> nulo,
--       NC -> nulo, FAC REGISTRADA -> su importe
--   S4  la columna SALDO sigue declarada en el informe con su mascara
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261122_saldo_lista_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000) := '';
    v_src    clob;
    v_sql    clob;
    v_n      number;
    v_cur    sys_refcursor;
    v_id     number;
    v_prov_f number;
    v_tipo   varchar2(10);
    v_est    varchar2(20);
    v_sal    number;
    v_debe   boolean;

    type t_num  is table of number;
    type t_txt  is table of varchar2(20);
    v_ids    t_num;
    v_tipos  t_txt;
    v_ests   t_txt;
    v_sals   t_num;
    v_c_bor  number;
    v_c_anu  number;
    v_c_nc   number;
    v_c_fac  number;

    procedure falla(p_caso varchar2, p_detalle varchar2) is
    begin
        v_fallas := v_fallas + 1;
        v_lista  := v_lista || ' | ' || p_caso || ': ' || substrb(p_detalle, 1, 170);
    end;
begin
    -- La fuente guardada, tal como la ejecuta APEX.
    select region_source into v_src
      from apex_application_page_regions
     where application_id = 100 and page_id = 27
       and region_id = 43000000000001000;

    ------------------------------------------------------------------ S1
    begin
        if instr(lower(v_src), 'fn_saldo_compra') = 0 then
            falla('S1', 'la consulta ya no usa fn_saldo_compra');
        end if;
        if instr(lower(v_src), 'tipo_documento') = 0 then
            falla('S1', 'la consulta no mira el tipo de documento');
        end if;
        if instr(upper(v_src), 'BORRADOR') = 0 then
            falla('S1', 'la consulta no declara los estados con deuda');
        end if;
    exception
        when others then
            falla('S1', sqlerrm);
    end;

    savepoint sp_saldo;
    begin
        -- S3: datos controlados.
        insert into proveedores (id_empresa, rif, razon_social)
        values (1, 'SALDO-TEST-1', 'Proveedor de prueba del saldo')
        returning id_proveedor into v_prov_f;

        insert into compras (id_empresa, id_proveedor, tipo_documento, folio_factura,
                             fecha_emision, cod_moneda, tipo_cambio, monto_total, estado)
        values (1, v_prov_f, 'FAC', 'SALDO-BOR', sysdate, 'VES', 1, 100, 'BORRADOR')
        returning id_compra into v_c_bor;

        insert into compras (id_empresa, id_proveedor, tipo_documento, folio_factura,
                             fecha_emision, cod_moneda, tipo_cambio, monto_total, estado)
        values (1, v_prov_f, 'FAC', 'SALDO-ANU', sysdate, 'VES', 1, 100, 'ANULADA')
        returning id_compra into v_c_anu;

        insert into compras (id_empresa, id_proveedor, tipo_documento, folio_factura,
                             fecha_emision, cod_moneda, tipo_cambio, monto_total, estado)
        values (1, v_prov_f, 'NC', 'SALDO-NC', sysdate, 'VES', 1, 100, 'REGISTRADA')
        returning id_compra into v_c_nc;

        insert into compras (id_empresa, id_proveedor, tipo_documento, folio_factura,
                             fecha_emision, cod_moneda, tipo_cambio, monto_total, estado)
        values (1, v_prov_f, 'FAC', 'SALDO-FAC', sysdate, 'VES', 1, 100, 'REGISTRADA')
        returning id_compra into v_c_fac;

        -- S2/S3: se ejecuta la consulta guardada con los binds sustituidos.
        -- OJO medido: una consulta a COMPRAS que llama a fn_saldo_compra NO ve las
        -- filas sin commitear de esta misma transaccion (devuelve 0 por el
        -- no_data_found de fn_importe_compra), asi que el caso controlado aisla el
        -- CASE sustituyendo la funcion por un 100: lo que se mide es la guarda.
        v_sql := replace(replace(v_src, ':F_EMPRESA_ACTIVA', '1'),
                                    ':P27_FILTRO', '''TODOS''');
        v_sql := replace(v_sql, 'fn_saldo_compra(c.id_compra)', '100');
        v_sql := 'select id_compra, tipo_documento, estado_cod, saldo from ('
                 || v_sql || ')';
        execute immediate v_sql bulk collect into v_ids, v_tipos, v_ests, v_sals;

        if v_ids.count = 0 then
            falla('S3', 'la consulta guardada no devolvio filas');
        end if;

        for i in 1 .. v_ids.count loop
            -- El caso controlado, con su valor exacto.
            if v_ids(i) = v_c_fac and nvl(v_sals(i), -1) <> 100 then
                falla('S3', 'la FAC registrada muestra ' || v_sals(i) || ' y deberia ser 100');
            end if;
            if v_ids(i) in (v_c_bor, v_c_anu, v_c_nc) and v_sals(i) is not null then
                falla('S3', 'la compra ' || v_ids(i) || ' (' || v_tipos(i) || '/'
                          || v_ests(i) || ') muestra saldo ' || v_sals(i));
            end if;
        end loop;

        rollback to sp_saldo;
    exception
        when others then
            rollback to sp_saldo;
            falla('S3', sqlerrm);
    end;

    ------------------------------------------------------------------ S2
    begin
        -- La consulta guardada REAL sobre los datos ya guardados: el saldo solo
        -- puede venir en una FAC procesada.
        v_sql := replace(replace(v_src, ':F_EMPRESA_ACTIVA', '1'),
                                    ':P27_FILTRO', '''TODOS''');
        v_sql := 'select id_compra, tipo_documento, estado_cod, saldo from ('
                 || v_sql || ')';
        execute immediate v_sql bulk collect into v_ids, v_tipos, v_ests, v_sals;

        if v_ids.count = 0 then
            falla('S2', 'la consulta guardada no devolvio filas');
        end if;

        for i in 1 .. v_ids.count loop
            v_debe := (v_tipos(i) = 'FAC' and v_ests(i) in ('REGISTRADA', 'PARCIAL', 'PAGADA'));
            if (v_sals(i) is not null) <> v_debe then
                falla('S2', 'la compra ' || v_ids(i) || ' (' || v_tipos(i) || '/' || v_ests(i)
                          || ') muestra saldo ' || v_sals(i));
            end if;
        end loop;
    exception
        when others then
            falla('S2', sqlerrm);
    end;

    ------------------------------------------------------------------ S4
    begin
        select count(*) into v_n
          from apex_application_page_ir_col
         where application_id = 100 and page_id = 27
           and column_alias = 'SALDO'
           and format_mask is not null;
        if v_n <> 1 then
            falla('S4', 'la columna SALDO perdio su mascara');
        end if;
    exception
        when others then
            falla('S4', sqlerrm);
    end;

    raise_application_error(-20100,
        substrb('RESULTADO: FALLAS=' || v_fallas || v_lista, 1, 3000));
end;
/
