-- =============================================================================
-- 20261118_folios_verificacion.sql
--
-- Los correlativos siguen a los documentos (2026-11-18):
--   F1  cada contador de FOLIO_CONTADOR esta EXACTAMENTE en el maximo real
--   F2  el siguiente folio de cada serie no existe todavia
--   F3  el siguiente control cabe en el rango de la providencia
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261118_folios_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000) := '';
    v_max    number;
    v_sig    varchar2(40);
    v_n      number;

    procedure falla(p_caso varchar2, p_detalle varchar2) is
    begin
        v_fallas := v_fallas + 1;
        v_lista  := v_lista || ' | ' || p_caso || ': ' || p_detalle;
    end;
begin
    -- F1: contador = maximo real, serie por serie
    for f in (select id_empresa, tipo, ultimo from folio_contador
               where tipo in ('PRESUPUESTO', 'FAC', 'NC', 'ND')) loop
        if f.tipo = 'PRESUPUESTO' then
            select nvl(max(to_number(regexp_substr(folio, '[0-9]+$'))), 0) into v_max
              from presupuestos where id_empresa = f.id_empresa;
        else
            select nvl(max(to_number(regexp_substr(folio_factura, '[0-9]+$'))), 0) into v_max
              from facturas where id_empresa = f.id_empresa and tipo_documento = f.tipo;
        end if;

        if f.ultimo <> v_max then
            falla('F1', 'empresa ' || f.id_empresa || ' ' || f.tipo || ': contador ' || f.ultimo
                       || ' y el maximo real es ' || v_max);
        end if;
    end loop;

    -- F2: el siguiente folio no existe
    for f in (select id_empresa, tipo, ultimo from folio_contador
               where tipo in ('PRESUPUESTO', 'FAC', 'NC', 'ND')) loop
        if f.tipo = 'PRESUPUESTO' then
            select count(*) into v_n from presupuestos
             where id_empresa = f.id_empresa and folio = to_char(f.ultimo + 1);
        else
            select count(*) into v_n from facturas
             where id_empresa = f.id_empresa and tipo_documento = f.tipo
               and to_number(regexp_substr(folio_factura, '[0-9]+$')) = f.ultimo + 1;
        end if;
        if v_n > 0 then
            falla('F2', 'empresa ' || f.id_empresa || ' ' || f.tipo
                       || ': el folio ' || (f.ultimo + 1) || ' ya existe');
        end if;
    end loop;

    -- F3: el siguiente control cabe en el rango de la providencia
    for f in (select id_empresa, ultimo from folio_contador where tipo = 'CONTROL') loop
        begin
            select to_number(regexp_substr(control_hasta, '[0-9]+$'))
              into v_max
              from empresa_fiscal
             where id_empresa = f.id_empresa;

            if f.ultimo + 1 > v_max then
                falla('F3', 'empresa ' || f.id_empresa || ': el control ' || (f.ultimo + 1)
                           || ' pasa el rango (hasta ' || v_max || ')');
            end if;
        exception
            when no_data_found then null;   -- empresa sin datos fiscales: no aplica
        end;
    end loop;

    raise_application_error(-20100, substrb('RESULTADO: FALLAS=' || v_fallas || v_lista, 1, 3000));
end;
/
