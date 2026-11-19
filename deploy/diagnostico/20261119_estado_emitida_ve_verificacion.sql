-- =============================================================================
-- 20261119_estado_emitida_ve_verificacion.sql
--
-- En Venezuela la factura no se timbra: para una empresa venezolana el estado
-- TIMBRADA se MUESTRA como EMITIDA. El codigo interno no cambia (lo comparan el
-- saldo, los cobros, el libro y los reportes), solo lo que se lee.
--
--   V1 fn_estado_factura: TIMBRADA+VE -> EMITIDA
--   V2 fn_estado_factura: TIMBRADA+MX -> TIMBRADA (Mexico si timbra)
--   V3 fn_estado_factura: los demas estados no cambian (ni en VE)
--   V4 las tres regiones que lo muestran usan la funcion
--      (lista de Facturacion, reporte de facturas y libro)
--   V5 las paginas 8 y 17 tienen el estilo de la insignia EMITIDA
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261119_estado_emitida_ve_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000) := '';
    v_n      number;
    v_txt    varchar2(40);

    procedure falla(p_caso varchar2, p_detalle varchar2) is
    begin
        v_fallas := v_fallas + 1;
        v_lista  := v_lista || ' | ' || p_caso || ': ' || p_detalle;
    end;
begin
    -- V1 / V2 / V3
    select fn_estado_factura('TIMBRADA', 'VE') into v_txt from dual;
    if v_txt <> 'EMITIDA' then
        falla('V1', 'TIMBRADA en VE se muestra «' || v_txt || '» en vez de EMITIDA');
    end if;

    select fn_estado_factura('TIMBRADA', 'MX') into v_txt from dual;
    if v_txt <> 'TIMBRADA' then
        falla('V2', 'TIMBRADA en MX se muestra «' || v_txt || '» (deberia seguir TIMBRADA)');
    end if;

    for f in (select 'PAGADA' e from dual union all select 'PARCIAL' from dual
              union all select 'ANULADA' from dual union all select 'PENDIENTE' from dual) loop
        select fn_estado_factura(f.e, 'VE') into v_txt from dual;
        if v_txt <> f.e then
            falla('V3', f.e || ' en VE se muestra «' || v_txt || '»');
        end if;
    end loop;

    -- V4: las regiones que lo pintan usan la funcion. Se mira el texto guardado
    -- por APEX (region_source), no una copia a mano.
    select count(*) into v_n
      from apex_260100.apex_application_page_regions
     where application_id = 100
       and page_id in (8, 17, 18)
       and lower(region_source) like '%fn_estado_factura%';
    if v_n < 3 then
        falla('V4', 'solo ' || v_n || ' regiones de 3 usan fn_estado_factura');
    end if;

    -- V5: la insignia EMITIDA tiene color en las dos listas
    select count(*) into v_n
      from apex_260100.apex_application_pages
     where application_id = 100 and page_id in (8, 17)
       and lower(inline_css) like '%status-emitida%';
    if v_n <> 2 then
        falla('V5', 'solo ' || v_n || ' de 2 paginas tienen el estilo .status-EMITIDA');
    end if;

    raise_application_error(-20100,
        substrb('RESULTADO: FALLAS=' || v_fallas || v_lista, 1, 3000));
end;
/
