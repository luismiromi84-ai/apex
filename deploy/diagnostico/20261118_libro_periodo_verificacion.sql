-- =============================================================================
-- 20261118_libro_periodo_verificacion.sql
--
-- Libro de compras y ventas: quincenal/mensual y salida en PDF (2026-11-18).
--
--   F1  fn_periodo_desde/hasta dan los rangos exactos de mes y de cada quincena
--   F2  las regiones del libro filtran por fn_periodo_*
--   F3  la 18 tiene P18_PERIODO con sus tres opciones
--   F4  la 18 tiene el boton PDF y existe la pagina 30 con su proceso
--   F5  fn_libro_excel quiere el periodo y devuelve la version imprimible
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261118_libro_periodo_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000) := '';
    v_n      number;
    v_html   clob;
    v_mes    number := 11;
    v_anio   number := 2026;

    procedure falla(p_caso varchar2, p_detalle varchar2) is
    begin
        v_fallas := v_fallas + 1;
        v_lista  := v_lista || ' | ' || p_caso || ': ' || p_detalle;
    end;

    procedure exige_fecha(p_caso varchar2, p_valor date, p_esperado date) is
    begin
        if p_valor is null or trunc(p_valor) <> trunc(p_esperado) then
            falla(p_caso, 'devolvio ' || nvl(to_char(p_valor, 'DD/MM/YYYY'), '(nulo)')
                       || ' y se esperaba ' || to_char(p_esperado, 'DD/MM/YYYY'));
        end if;
    end;
begin
    -- F1: rangos
    exige_fecha('F1 mes desde',  fn_periodo_desde(v_mes, v_anio, 'MES'), date '2026-11-01');
    exige_fecha('F1 mes hasta',  fn_periodo_hasta(v_mes, v_anio, 'MES'), date '2026-12-01');
    exige_fecha('F1 Q1 desde',   fn_periodo_desde(v_mes, v_anio, 'Q1'),  date '2026-11-01');
    exige_fecha('F1 Q1 hasta',   fn_periodo_hasta(v_mes, v_anio, 'Q1'),  date '2026-11-16');
    exige_fecha('F1 Q2 desde',   fn_periodo_desde(v_mes, v_anio, 'Q2'),  date '2026-11-16');
    exige_fecha('F1 Q2 hasta',   fn_periodo_hasta(v_mes, v_anio, 'Q2'),  date '2026-12-01');
    -- sin mes ni anio no revienta
    begin
        v_n := to_number(to_char(fn_periodo_desde(null, null, 'MES'), 'MM'));
    exception
        when others then falla('F1 nulos', 'fn_periodo_desde(null, null) revento');
    end;

    -- F2: las regiones del libro
    select count(*) into v_n
      from apex_260100.apex_application_page_regions
     where application_id = 100
       and region_id in (43000000000000710, 43000000000000740,
                         43000000000000730, 43000000000000760)
       and instr(upper(region_source), 'FN_PERIODO_DESDE') > 0
       and instr(upper(region_source), ':P18_PERIODO') > 0;
    if v_n <> 4 then
        falla('F2', 'solo ' || v_n || ' de 4 regiones del libro filtran por el periodo');
    end if;

    -- F3: el item
    select count(*) into v_n
      from apex_260100.apex_application_page_items
     where application_id = 100 and page_id = 18 and item_name = 'P18_PERIODO'
       and instr(lov_definition, 'Q1') > 0
       and instr(lov_definition, 'Q2') > 0
       and instr(lov_definition, 'MES') > 0;
    if v_n <> 1 then
        falla('F3', 'falta P18_PERIODO o su lista de periodos');
    end if;

    -- F4: boton PDF y pagina 30
    select count(*) into v_n
      from apex_260100.apex_application_page_buttons
     where application_id = 100 and page_id = 18 and static_id = 'btn-pdf-libro';
    if v_n <> 1 then
        falla('F4', 'falta el boton PDF en la 18');
    end if;

    select count(*) into v_n
      from apex_260100.apex_application_page_proc
     where application_id = 100 and page_id = 30 and static_id = 'sirve-pdf-libro';
    if v_n <> 1 then
        falla('F4', 'falta la pagina 30 con el proceso que sirve el PDF');
    end if;

    -- F5: fn_libro_excel con periodo e imprimir
    v_html := fn_libro_excel('TODOS', v_mes, v_anio, 1, 'Q2', 'S');
    if v_html is null or dbms_lob.getlength(v_html) < 200 then
        falla('F5', 'fn_libro_excel devolvio un documento vacio');
    else
        if instr(v_html, 'window.print()') = 0 then
            falla('F5', 'la version imprimible no abre el dialogo de impresion');
        end if;
        if instr(v_html, '2da quincena') = 0 then
            falla('F5', 'el membrete no dice que es la 2da quincena');
        end if;
        if instr(v_html, '@page') = 0 then
            falla('F5', 'la version imprimible no trae las reglas de pagina');
        end if;
    end if;

    raise_application_error(-20100, substrb('RESULTADO: FALLAS=' || v_fallas || v_lista, 1, 3000));
end;
/
