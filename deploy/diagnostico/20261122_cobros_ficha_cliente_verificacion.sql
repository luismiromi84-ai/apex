-- =============================================================================
-- 20261122_cobros_ficha_cliente_verificacion.sql
--
-- La ficha del cliente (32) muestra lo que debe y lo vencido, pero no sus COBROS
-- (2026-11-22). Se agrega la region «Cobros del cliente», espejo de «Pagos al
-- proveedor» de la ficha 33.
--
--   C1  la region existe, es informe clasico y lee RECIBOS con la factura
--   C2  trae las columnas pedidas (fecha, factura, monto, forma, referencia,
--       IGTF, retencion, conciliado y estado)
--   C3  ejecutando la consulta GUARDADA: un cliente con cobros devuelve sus
--       cobros y uno sin cobros no devuelve nada (y ninguno de otra empresa)
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261122_cobros_ficha_cliente_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000) := '';
    v_src    clob;
    v_txt    varchar2(32767);
    v_sql    clob;
    v_n      number;
    v_con    number;
    v_sin    number;

    procedure falla(p_caso varchar2, p_detalle varchar2) is
    begin
        v_fallas := v_fallas + 1;
        v_lista  := v_lista || ' | ' || p_caso || ': ' || substrb(p_detalle, 1, 170);
    end;
begin
    ------------------------------------------------------------------ C1 / C2
    begin
        select region_source into v_src
          from apex_application_page_regions
         where application_id = 100 and page_id = 32
           and region_id = 43000000000001698;
        v_txt := v_src;
        if instr(upper(v_txt), 'FROM RECIBOS') = 0 then
            falla('C1', 'la region no lee RECIBOS');
        end if;
        if instr(upper(v_txt), 'JOIN FACTURAS') = 0 then
            falla('C1', 'la region no cruza con FACTURAS');
        end if;
        if instr(v_txt, ':P32_ID_CLIENTE') = 0 or instr(v_txt, ':F_EMPRESA_ACTIVA') = 0 then
            falla('C1', 'la consulta no filtra por el cliente y la empresa activa');
        end if;

        -- Los rotulos de un informe clasico viven en REPORT_COLUMN_HEADINGS.
        select report_column_headings into v_txt
          from apex_application_page_regions
         where application_id = 100 and page_id = 32
           and region_id = 43000000000001698;
        for c in (select column_value as t from table(sys.odcivarchar2list(
                      'Fecha', 'Factura', 'Monto', 'Forma', 'Referencia', 'IGTF',
                      'Ret. IVA', 'Conciliado', 'Estado'))) loop
            if instr(v_txt, c.t) = 0 then
                falla('C2', 'falta el rotulo: ' || c.t);
            end if;
        end loop;
    exception
        when others then
            falla('C1', sqlerrm);
    end;

    ------------------------------------------------------------------ C3
    begin
        select min(f.id_cliente) into v_con
          from recibos r join facturas f on f.id_factura = r.id_factura;

        select min(c.id_cliente) into v_sin
          from clientes c
         where c.id_empresa = 1
           and not exists (select 1 from facturas f
                             join recibos r on r.id_factura = f.id_factura
                            where f.id_cliente = c.id_cliente);

        select region_source into v_src
          from apex_application_page_regions
         where application_id = 100 and page_id = 32
           and region_id = 43000000000001698;
        v_sql := replace(v_src, ':P32_ID_CLIENTE', to_char(v_con));
        v_sql := replace(v_sql, ':F_EMPRESA_ACTIVA', '1');

        execute immediate 'select count(*) from (' || v_sql || ')' into v_n;
        if nvl(v_n, 0) = 0 then
            falla('C3', 'el cliente ' || v_con || ' tiene cobros y la region no devuelve ninguno');
        end if;

        if v_sin is not null then
            v_sql := replace(v_src, ':P32_ID_CLIENTE', to_char(v_sin));
            v_sql := replace(v_sql, ':F_EMPRESA_ACTIVA', '1');
            execute immediate 'select count(*) from (' || v_sql || ')' into v_n;
            if nvl(v_n, 0) <> 0 then
                falla('C3', 'el cliente ' || v_sin || ' no tiene cobros y la region devuelve ' || v_n);
            end if;
        end if;
    exception
        when others then
            falla('C3', sqlerrm);
    end;

    raise_application_error(-20100,
        substrb('RESULTADO: FALLAS=' || v_fallas || v_lista, 1, 3000));
end;
/
