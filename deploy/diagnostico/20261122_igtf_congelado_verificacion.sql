-- =============================================================================
-- 20261122_igtf_congelado_verificacion.sql
--
-- El IGTF de una compra es una FOTO: se congela en COMPRAS.IGTF_BS al registrarla
-- (2026-11-21) y de ahi leen la lista de compras, los pagos y fn_importe_compra.
-- Faltaban dos pantallas que lo calculaban EN VIVO con la configuracion de hoy:
--
--   * el resumen de la compra (28) y
--   * el libro de compras y ventas (18), en la tabla y en los totales del mes.
--
-- Si manana se apaga ES_SPE o se cambia la forma de pago, esas dos pantallas decian
-- otra cosa que la lista y los pagos. Ahora, con la compra ya procesada, manda la
-- foto; en BORRADOR se sigue estimando (todavia no hay documento emitido).
--
--   G1  el resumen de la 28 lee igtf_bs de la compra y solo estima en BORRADOR
--   G2  el libro de Venezuela usa co.igtf_bs (y ya no fn_alicuota_igtf)
--   G3  los totales del mes usan co.igtf_bs
--   G4  de punta a punta: una compra REGISTRADA con igtf_bs = 2.700 Bs sigue
--       mostrando 2.700 en el libro AUNQUE la empresa deje de ser SPE (con el
--       calculo en vivo daria 0)
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261122_igtf_congelado_verificacion.sql
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
    v_val    number;

    procedure falla(p_caso varchar2, p_detalle varchar2) is
    begin
        v_fallas := v_fallas + 1;
        v_lista  := v_lista || ' | ' || p_caso || ': ' || substrb(p_detalle, 1, 170);
    end;
begin
    ------------------------------------------------------------------ G1
    begin
        select region_source into v_src
          from apex_application_page_regions
         where application_id = 100 and page_id = 28
           and region_id = 43000000000001170;
        v_txt := v_src;
        if instr(lower(v_txt), 'nvl(igtf_bs') = 0 then
            falla('G1', 'el resumen de la compra no lee IGTF_BS');
        end if;
        if instr(v_txt, 'v_estado = ''BORRADOR''') = 0 then
            falla('G1', 'el resumen no distingue el borrador (estimacion) de la foto');
        end if;
    exception
        when others then
            falla('G1', sqlerrm);
    end;

    ------------------------------------------------------------------ G2
    begin
        select region_source into v_src
          from apex_application_page_regions
         where application_id = 100 and page_id = 18
           and region_id = 43000000000000710;
        v_txt := v_src;
        if instr(lower(v_txt), 'co.igtf_bs') = 0 then
            falla('G2', 'el libro de Venezuela no usa COMPRAS.IGTF_BS');
        end if;
        if instr(lower(v_txt), 'fn_alicuota_igtf') > 0 then
            falla('G2', 'el libro de Venezuela sigue calculando el IGTF en vivo');
        end if;
    exception
        when others then
            falla('G2', sqlerrm);
    end;

    ------------------------------------------------------------------ G3
    begin
        select region_source into v_src
          from apex_application_page_regions
         where application_id = 100 and page_id = 18
           and region_id = 43000000000000730;
        v_txt := v_src;
        if instr(lower(v_txt), 'co.igtf_bs') = 0 then
            falla('G3', 'los totales del mes no usan COMPRAS.IGTF_BS');
        end if;
        if instr(lower(v_txt), 'fn_alicuota_igtf') > 0 then
            falla('G3', 'los totales del mes siguen calculando el IGTF en vivo');
        end if;
    exception
        when others then
            falla('G3', sqlerrm);
    end;

    ------------------------------------------------------------------ G4
    begin
        savepoint sp_igtf;
        declare
            v_prov number;
            v_comp number;
        begin
            insert into proveedores (id_empresa, rif, razon_social)
            values (1, 'IGTF-TEST-1', 'Proveedor de prueba del IGTF')
            returning id_proveedor into v_prov;

            insert into compras (id_empresa, id_proveedor, tipo_documento, folio_factura,
                                 fecha_emision, cod_moneda, tipo_cambio, monto_total,
                                 igtf_bs, estado)
            values (1, v_prov, 'FAC', 'IGTF-TEST-1', sysdate, 'USD', 900, 100,
                    2700, 'REGISTRADA')
            returning id_compra into v_comp;

            -- Con el calculo en vivo, al apagar SPE el IGTF daria 0: la foto tiene que
            -- aguantar. (La prueba deja la empresa como estaba con el rollback.)
            update empresas set es_spe = 'N' where id_empresa = 1;

            select region_source into v_src
              from apex_application_page_regions
             where application_id = 100 and page_id = 18
               and region_id = 43000000000000710;

            v_sql := v_src;
            v_sql := replace(v_sql, ':F_EMPRESA_ACTIVA', '1');
            v_sql := replace(v_sql, ':P18_ID_EMPRESA', 'null');
            v_sql := replace(v_sql, ':P18_LIBRO', '''COMPRAS''');
            v_sql := replace(v_sql, ':P18_MES', 'null');
            v_sql := replace(v_sql, ':P18_ANIO', 'null');
            v_sql := replace(v_sql, ':P18_PERIODO', '''MES''');
            v_sql := 'select igtf_compra from (' || v_sql || ') where ver_compra = '
                     || to_char(v_comp);

            execute immediate v_sql into v_val;
            if nvl(v_val, -1) <> 2700 then
                falla('G4', 'el libro muestra ' || v_val
                          || ' de IGTF con la empresa ya no SPE (se esperaba 2700, la foto)');
            end if;

            -- Y el resumen de la 28 tiene que leer la misma columna.
            select count(*) into v_n
              from compras
             where id_compra = v_comp and igtf_bs = 2700;
            if v_n <> 1 then
                falla('G4', 'la compra de prueba no guardo su IGTF_BS');
            end if;
        end;
        rollback to sp_igtf;
    exception
        when others then
            rollback to sp_igtf;
            falla('G4', sqlerrm);
    end;

    raise_application_error(-20100,
        substrb('RESULTADO: FALLAS=' || v_fallas || v_lista, 1, 3000));
end;
/
