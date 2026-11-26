-- =============================================================================
-- 20261124_tres_arreglos2_verificacion.sql
--
-- Tres cosas mas que reporto el dueno el 2026-11-24:
--   1. en la factura NUEVA (9) se veia la tarjeta «Lineas de la factura que
--      acredita», vacia, y el icono de Guardar giraba (se veia «distorsionado»)
--   2. en la lista de Facturacion (8) «Editar» salia antes que «Seleccionar»
--   3. en Administracion > Secuencias no dejaba escribir el correlativo con su
--      formato (F-1051, 00-000132): el campo era numerico
--
--   E1 el JS de la 9 esconde la tarjeta segun los items (tipo y factura origen)
--   E2 ningun boton de la app gira el icono al pasar/enfocar
--   E3 en la 8 el checkbox «Seleccionar» va antes que «Editar»
--   E4 P19S_ULTIMO es un campo de texto (acepta el formato)
--   E5 el proceso «Fijar el correlativo» se queda con los digitos
--   E6 el parseo da el numero correcto en los cuatro formatos
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261124_tres_arreglos2_verificacion.sql
-- FALLAS=0 = EXITO. El runner sale con codigo 1 aunque sea verde: se lee el mensaje.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000) := '';
    v_n      number;
    v_txt    varchar2(32767);
    v_cols   varchar2(4000);
    v_num    number;

    procedure falla(p_caso varchar2, p_detalle varchar2) is
    begin
        v_fallas := v_fallas + 1;
        v_lista  := v_lista || ' | ' || p_caso || ': ' || p_detalle;
    end;

    procedure espera_num(p_caso varchar2, p_obtenido number, p_esperado number) is
    begin
        if p_obtenido is null or p_obtenido <> p_esperado then
            falla(p_caso, 'se esperaba ' || p_esperado || ' y dio ' || nvl(to_char(p_obtenido), 'NULL'));
        end if;
    end;
begin
    -- ------------------------------------------------------------------ E1
    select javascript_code_onload into v_txt
      from apex_260100.apex_application_pages
     where application_id = 100 and page_id = 9;

    if instr(v_txt, 'NC') = 0 or instr(v_txt, 'P9_ID_FACTURA_ORIGEN') = 0 then
        falla('E1', 'el JS de la 9 no decide por el tipo de documento y la factura origen');
    end if;
    if instr(v_txt, 'P9_TIPO_DOCUMENTO') = 0 and instr(v_txt, 'tipo') = 0 then
        falla('E1', 'el JS de la 9 no mira el tipo de documento');
    end if;

    -- ------------------------------------------------------------------ E2
    select count(*) into v_n
      from apex_260100.apex_application_page_buttons
     where application_id = 100
       and instr(nvl(button_template_options, 'x'), 'hoverIconSpin') > 0;
    if v_n > 0 then
        falla('E2', 'quedan ' || v_n || ' botones que giran el icono (hoverIconSpin)');
    end if;

    -- ------------------------------------------------------------------ E3
    select report_columns into v_cols
      from apex_260100.apex_application_page_ir_rpt
     where application_id = 100 and page_id = 8 and status = 'PUBLIC'
       and report_columns like '%DETALLE_LINK%'
       and report_columns not like 'ID_DETALLE%'
       and rownum = 1;

    if instr(v_cols, 'DETALLE_LINK') = 0 or instr(v_cols, 'ID_FACTURA') = 0 then
        falla('E3', 'la vista por defecto de la 8 no trae las dos columnas: ' || v_cols);
    elsif instr(v_cols, 'DETALLE_LINK') > instr(v_cols, 'ID_FACTURA') then
        falla('E3', 'en la 8 «Editar» sigue antes que «Seleccionar»: ' || substr(v_cols, 1, 60));
    end if;

    select display_order into v_n
      from apex_260100.apex_application_page_ir_col
     where application_id = 100 and page_id = 8 and column_alias = 'DETALLE_LINK';
    espera_num('E3', v_n, 10);

    select display_order into v_n
      from apex_260100.apex_application_page_ir_col
     where application_id = 100 and page_id = 8 and column_alias = 'ID_FACTURA'
       and report_label = 'Editar';
    espera_num('E3', v_n, 15);

    -- ------------------------------------------------------------------ E4
    select display_as_code into v_txt
      from apex_260100.apex_application_page_items
     where application_id = 100 and page_id = 19 and item_name = 'P19S_ULTIMO';
    if v_txt <> 'NATIVE_TEXT_FIELD' then
        falla('E4', 'P19S_ULTIMO sigue siendo ' || v_txt || ' (tiene que aceptar texto)');
    end if;

    -- ------------------------------------------------------------------ E5
    select process_source into v_txt
      from apex_260100.apex_application_page_proc
     where application_id = 100 and page_id = 19 and static_id = 'fija-siguiente';
    if instr(upper(v_txt), 'REGEXP_REPLACE') = 0 then
        falla('E5', 'el proceso no se queda con los digitos del valor tecleado');
    end if;
    if instr(upper(v_txt), 'FN_CLEAN_NUM(:P19S_ULTIMO)') > 0 then
        falla('E5', 'el proceso sigue usando fn_clean_num sobre el valor (devuelve 0 con texto)');
    end if;

    -- ------------------------------------------------------------------ E6
    espera_num('E6', to_number(regexp_replace('F-1051', '[^0-9]', '')), 1051);
    espera_num('E6', to_number(regexp_replace('00-000132', '[^0-9]', '')), 132);
    espera_num('E6', to_number(regexp_replace('PRE-3', '[^0-9]', '')), 3);
    espera_num('E6', to_number(regexp_replace('PROD-00009', '[^0-9]', '')), 9);
    espera_num('E6', to_number(regexp_replace('10000010', '[^0-9]', '')), 10000010);

    raise_application_error(-20100,
        substrb('RESULTADO: FALLAS=' || v_fallas || v_lista, 1, 3000));
end;
/
