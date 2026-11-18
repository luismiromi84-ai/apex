-- =============================================================================
-- 20261118_pagina9_guardar_verificacion.sql
--
-- Guardar una factura fallaba con
--   «El identificador de elemento (P9_COBRADO) no corresponde a ningún elemento
--    definido en la página actual.»
-- y NO se guardaba nada (el POST se rechazaba antes de cualquier proceso).
--
-- Causa (medida el 2026-11-18 con el p_json del POST y APEX_APPLICATION_PAGE_ITEMS):
-- «Cobrado» y «Saldo» se crearon por import SIN atributos de plugin. A un
-- «Display Only» le faltaba `send_on_page_submit`, así que APEX lo pintaba como
-- campo oculto con checksum y lo incluía en la lista de ítems protegidos del
-- envío, pero el servidor no lo consideraba un ítem de la página para ese POST
-- y abortaba. Los mismos ítems en las otras páginas sí lo declaran.
--
--   G1  P9_COBRADO y P9_SALDO existen, son Display Only y están en la región del
--       formulario (la misma de los demás campos)
--   G2  los dos declaran `send_on_page_submit` (la causa del fallo)
--   G3  NINGÚN ítem Display Only de la app queda sin `send_on_page_submit`
--       (avisa de un ítem nuevo creado igual de mal antes de que reviente)
--   G4  el proceso «Carga cobrado y saldo» sigue rellenando los dos ítems
--   G5  Cobrado y Saldo ocupan media fila cada uno (6 columnas)
--   G6  no quedan procesos de sonda en la app
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261118_pagina9_guardar_verificacion.sql
-- FALLAS=0 = EXITO (el runner sale con 1 a propósito: -20100).
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

begin
    begin execute immediate 'drop table tmp_p9guardar_fallas purge'; exception when others then null; end;
end;
/

create table tmp_p9guardar_fallas (caso varchar2(300))
/

declare
    v_n         number;
    v_attrs     clob;
    v_src       clob;
    v_region    varchar2(30) := '32589573944518258';

    procedure falla(p varchar2) is
    begin
        insert into tmp_p9guardar_fallas (caso) values (p);
    end;
begin
    -- G1: los dos ítems existen, son Display Only y cuelgan de la región del formulario
    for r in (select item_name, display_as_code, to_char(region_id) as reg, column_span
                from apex_application_page_items
               where application_id = 100 and page_id = 9
                 and item_name in ('P9_COBRADO', 'P9_SALDO'))
    loop
        if r.display_as_code <> 'NATIVE_DISPLAY_ONLY' then
            falla('G1 ' || r.item_name || ' ya no es Display Only (' || r.display_as_code || ')');
        end if;
        if r.reg <> v_region then
            falla('G1 ' || r.item_name || ' no esta en la region del formulario (' || r.reg || ')');
        end if;
        if nvl(r.column_span, 0) <> 6 then
            falla('G5 ' || r.item_name || ' ocupa ' || nvl(r.column_span, 1) || ' columnas, no 6');
        end if;
    end loop;

    select count(*) into v_n
      from apex_application_page_items
     where application_id = 100 and page_id = 9
       and item_name in ('P9_COBRADO', 'P9_SALDO');
    if v_n <> 2 then
        falla('G1 faltan items de cobrado/saldo en la pagina 9 (hay ' || v_n || ')');
    end if;

    -- G2: los dos declaran send_on_page_submit (sin esto el POST se rechaza)
    for r in (select item_name, attributes
                from apex_application_page_items
               where application_id = 100 and page_id = 9
                 and item_name in ('P9_COBRADO', 'P9_SALDO'))
    loop
        v_attrs := r.attributes;
        if v_attrs is null or dbms_lob.instr(v_attrs, 'send_on_page_submit') = 0 then
            falla('G2 ' || r.item_name || ' no declara send_on_page_submit');
        end if;
    end loop;

    -- G3: barrido: ningún Display Only de la app sin send_on_page_submit
    for r in (select page_id, item_name, attributes
                from apex_application_page_items
               where application_id = 100
                 and display_as_code = 'NATIVE_DISPLAY_ONLY')
    loop
        v_attrs := r.attributes;
        if v_attrs is null or dbms_lob.instr(v_attrs, 'send_on_page_submit') = 0 then
            falla('G3 pagina ' || r.page_id || ': ' || r.item_name || ' sin send_on_page_submit');
        end if;
    end loop;

    -- G4: el proceso sigue existiendo y rellena los dos ítems
    select count(*) into v_n
      from apex_application_page_proc
     where application_id = 100 and page_id = 9
       and static_id = 'carga-cobrado-saldo';
    if v_n <> 1 then
        falla('G4 falta el proceso carga-cobrado-saldo');
    else
        select process_source into v_src
          from apex_application_page_proc
         where application_id = 100 and page_id = 9
           and static_id = 'carga-cobrado-saldo';
        if dbms_lob.instr(v_src, 'P9_COBRADO') = 0 or dbms_lob.instr(v_src, 'P9_SALDO') = 0 then
            falla('G4 el proceso ya no rellena P9_COBRADO/P9_SALDO');
        end if;
    end if;

    -- G6: sin procesos de sonda
    select count(*) into v_n
      from apex_application_page_proc
     where application_id = 100
       and (lower(process_name) like 'probe%' or lower(static_id) like 'probe%');
    if v_n > 0 then
        falla('G6 quedan ' || v_n || ' proceso(s) de sonda en la app');
    end if;
end;
/

declare
    v_fallas number;
    v_lista  varchar2(3000);
begin
    select count(*) into v_fallas from tmp_p9guardar_fallas;
    select substrb(listagg(caso, ' | ' on overflow truncate) within group (order by caso), 1, 3000)
      into v_lista from tmp_p9guardar_fallas;
    execute immediate 'drop table tmp_p9guardar_fallas purge';
    raise_application_error(-20100, substrb('RESULTADO: FALLAS=' || v_fallas || ' | ' || v_lista, 1, 3000));
end;
/
