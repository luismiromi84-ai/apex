-- =============================================================================
-- 20261118_menu_compras_verificacion.sql
--
-- El menu «Compras» agrupa a «Proveedores» como subentrada (2026-11-18).
-- Solo cambia el menu: las paginas 22/23/27/28/29 no se tocan.
--
-- Casos:
--   V1 existe la entrada padre compras-grupo (id 43000000000001092, seq 12)
--   V2 'compras' y 'proveedores' cuelgan del padre, con secuencia 1 y 2
--   V3 'compras' conserva destino 27, «Ver Compras», icono de carrito y
--      resaltado en 27,28,29
--   V4 'proveedores' conserva destino 22, «Ver Proveedores», icono de camion y
--      resaltado en 22,23
--   V5 el padre apunta a la 27, usa «Ver Compras» y no lleva resaltado propio
--   V6 solo esas dos entradas del menu tienen padre
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261118_menu_compras_verificacion.sql
-- FALLAS=0 = EXITO (el runner sale con codigo 1 igual: el detalle va en -20100).
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000) := '';
    v_n      number;
    v_padre  number := 43000000000001092;

    procedure falla(p_caso varchar2, p_detalle varchar2) is
    begin
        v_fallas := v_fallas + 1;
        v_lista  := v_lista || ' | ' || p_caso || ': ' || p_detalle;
    end;
begin
    -- V1: la entrada padre
    select count(*) into v_n
      from apex_260100.apex_application_list_entries
     where application_id = 100 and list_name = 'Navigation Menu'
       and static_id = 'compras-grupo'
       and list_entry_id = 43000000000001092
       and entry_text = 'Compras'
       and display_sequence = 12;
    if v_n <> 1 then
        falla('V1', 'no existe la entrada padre compras-grupo como se espera');
    end if;

    -- V2: las dos hijas
    select count(*) into v_n
      from apex_260100.apex_application_list_entries
     where application_id = 100 and list_name = 'Navigation Menu'
       and list_entry_parent_id = v_padre
       and (   (static_id = 'compras'     and display_sequence = 1)
            or (static_id = 'proveedores' and display_sequence = 2));
    if v_n <> 2 then
        falla('V2', 'cuelgan del padre ' || v_n || ' de 2 entradas');
    end if;

    -- V3: la hija «Facturas de compras» (static_id 'compras') conserva lo suyo.
    -- El rotulo cambia el 2026-11-18 para no repetir «Compras» dos veces en el menu.
    select count(*) into v_n
      from apex_260100.apex_application_list_entries
     where application_id = 100 and list_name = 'Navigation Menu'
       and static_id = 'compras'
       and entry_text = 'Facturas de compras'
       and instr(entry_target, ':27:') > 0
       and authorization_scheme = 'Ver Compras'
       and entry_image = 'fa-shopping-cart'
       and current_for_pages_type_code = 'COLON_DELIMITED_PAGE_LIST'
       and current_for_pages_expression = '27,28,29';
    if v_n <> 1 then
        falla('V3', 'la entrada Facturas de compras perdio rotulo, destino, esquema, icono o resaltado');
    end if;

    -- V4: la hija Proveedores conserva lo suyo
    select count(*) into v_n
      from apex_260100.apex_application_list_entries
     where application_id = 100 and list_name = 'Navigation Menu'
       and static_id = 'proveedores'
       and instr(entry_target, ':22:') > 0
       and authorization_scheme = 'Ver Proveedores'
       and entry_image = 'fa-truck'
       and current_for_pages_type_code = 'COLON_DELIMITED_PAGE_LIST'
       and current_for_pages_expression = '22,23';
    if v_n <> 1 then
        falla('V4', 'la entrada Proveedores perdio destino, esquema, icono o resaltado');
    end if;

    -- V5: el padre. Sin resaltado propio (NEVER): en la 27 se marcaba el padre Y la
    -- hija «Compras» a la vez, y el padre no navega. Medido el 2026-11-18 en navegador.
    select count(*) into v_n
      from apex_260100.apex_application_list_entries
     where application_id = 100 and list_name = 'Navigation Menu'
       and static_id = 'compras-grupo'
       and instr(entry_target, ':27:') > 0
       and authorization_scheme = 'Ver Compras'
       and current_for_pages_type_code = 'NEVER'
       and current_for_pages_expression is null;
    if v_n <> 1 then
        falla('V5', 'el padre no apunta a la 27, no usa Ver Compras o lleva resaltado propio');
    end if;

    -- V6: nadie mas cuelga de nadie
    select count(*) into v_n
      from apex_260100.apex_application_list_entries
     where application_id = 100 and list_name = 'Navigation Menu'
       and list_entry_parent_id is not null;
    if v_n <> 2 then
        falla('V6', 'hay ' || v_n || ' entradas con padre (se esperaban 2)');
    end if;

    -- V7: el padre usa «Ver Compras» y de él cuelga «Proveedores» con «Ver Proveedores».
    -- Si algun dia se recorta Ver Compras, Proveedores desaparece del menu. Hoy las dos
    -- listas de roles son identicas; que sigan siendolo.
    select count(*) into v_n
      from apex_260100.apex_application_authorization a
     where a.application_id = 100
       and a.static_id = 'ver-compras'
       and json_value(a.attributes, '$.plsql_function_body') =
           (select json_value(b.attributes, '$.plsql_function_body')
              from apex_260100.apex_application_authorization b
             where b.application_id = 100 and b.static_id = 'ver-proveedores');
    if v_n <> 1 then
        falla('V7', 'Ver Compras y Ver Proveedores ya no tienen los mismos roles');
    end if;

    -- V8: la pagina 27 se titula «Facturas de Compras» (antes «Compras», que se
    -- repetia con el nombre del grupo del menu). La URL (alias COMPRAS) no cambia.
    select count(*) into v_n
      from apex_application_pages
     where application_id = 100 and page_id = 27
       and page_name = 'Facturas de Compras'
       and page_title = 'Facturas de Compras';
    if v_n <> 1 then
        falla('V8', 'la pagina 27 no se titula Facturas de Compras');
    end if;

    raise_application_error(-20100, substrb('RESULTADO: FALLAS=' || v_fallas || v_lista, 1, 3000));
end;
/
