-- =============================================================================
-- 20261118_compra_lineas_verificacion.sql
--
-- La region «Lineas de la compra» de la pagina 28 (2026-11-18).
--
-- Sintoma: la pagina mostraba el CODIGO PL/SQL de la region como si fuera texto.
-- Causa: la region estaba guardada como contenido ESTATICO (`NATIVE_STATIC`) con
-- el PL/SQL dentro, aunque tenia `function_body_language='PLSQL'`. APEX solo
-- evalua la fuente cuando el tipo de origen es contenido dinamico.
--
--   C1 la region compra-lineas es contenido dinamico con lenguaje PLSQL
--   C2 barrido: NINGUNA region de la app tiene function_body_language sin ser
--      contenido dinamico (el mismo error en cualquier otra pagina)
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261118_compra_lineas_verificacion.sql
-- FALLAS=0 = EXITO (el runner sale con codigo 1 igual: el detalle va en -20100).
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000) := '';
    v_n      number;
    v_det    varchar2(500);

    procedure falla(p_caso varchar2, p_detalle varchar2) is
    begin
        v_fallas := v_fallas + 1;
        v_lista  := v_lista || ' | ' || p_caso || ': ' || p_detalle;
    end;
begin
    -- C1: la region de las lineas
    select count(*) into v_n
      from apex_260100.apex_application_page_regions
     where application_id = 100 and page_id = 28
       and region_static_id = 'compra-lineas'
       and source_type_plugin_static_id = 'NATIVE_DYNAMIC_CONTENT'
       and function_body_language = 'PLSQL';
    if v_n <> 1 then
        select source_type_plugin_static_id || '/' || nvl(function_body_language, '(sin lenguaje)')
          into v_det
          from apex_260100.apex_application_page_regions
         where application_id = 100 and page_id = 28 and region_static_id = 'compra-lineas';
        falla('C1', 'la region compra-lineas no es contenido dinamico PLSQL (' || v_det || ')');
    end if;

    -- C2: barrido de toda la app
    select count(*) into v_n
      from apex_260100.apex_application_page_regions
     where application_id = 100
       and function_body_language is not null
       and nvl(source_type_plugin_static_id, '#') <> 'NATIVE_DYNAMIC_CONTENT';
    if v_n > 0 then
        select listagg(page_id || ':' || region_name, ', ')
               within group (order by page_id) into v_det
          from apex_260100.apex_application_page_regions
         where application_id = 100
           and function_body_language is not null
           and nvl(source_type_plugin_static_id, '#') <> 'NATIVE_DYNAMIC_CONTENT'
           and rownum <= 5;
        falla('C2', v_n || ' region(es) con lenguaje pero sin contenido dinamico: ' || v_det);
    end if;

    raise_application_error(-20100, substrb('RESULTADO: FALLAS=' || v_fallas || v_lista, 1, 3000));
end;
/
