-- =============================================================================
-- 20261117_empresa_activa_filtros_verificacion.sql
--
-- Task 3 del plan empresa-activa: las listas y los formularios leen la empresa activa.
--   L1  fuera de las páginas 0, 4 y 19 nadie menciona v_empresas_usuario
--       (la 0 es el combo, la 4 el alta de usuarios, la 19 la administración de empresas)
--   L2  las listas de 5, 8, 16, 17, 18, 20 y 24 filtran por F_EMPRESA_ACTIVA
--   L3  ningún ítem de empresa se pinta en las pantallas (7, 9, 13, 17, 18, 21, 24 son ocultos)
--   L4  los procesos que guardan documentos (7, 9, 16) usan F_EMPRESA_ACTIVA
--   L5  cada página con el ítem oculto tiene un proceso que lo fija desde F_EMPRESA_ACTIVA
--   L6  comportamiento: la lista de Presupuestos (5) devuelve 0 con la empresa activa nula
--       y solo los documentos de la empresa activa cuando la hay (y ninguno de una ajena)
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261117_empresa_activa_filtros_verificacion.sql
-- FALLAS=0 = EXITO (el runner sale con 1 a propósito: -20100).
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

begin
    begin execute immediate 'drop table tmp_empfiltro_fallas purge'; exception when others then null; end;
end;
/

create table tmp_empfiltro_fallas (caso varchar2(300))
/

declare
    v_n       number;
    v_sql     clob;
    v_reg     varchar2(32767);
    v_proc    clob;
    v_filas   number;
    v_mal     number;
    v_usuario varchar2(100);
    v_emp     number;
    v_err     varchar2(200);
    v_paginas sys.odcinumberlist := sys.odcinumberlist(5, 8, 16, 17, 18, 20, 24);
begin
    -- L1: v_empresas_usuario solo en las páginas 0, 4 y 19
    select count(*) into v_n
      from (
        select page_id from apex_application_page_regions
         where application_id = 100 and instr(lower(to_clob(nvl(region_source, ' '))), 'v_empresas_usuario') > 0
        union all
        select page_id from apex_application_page_items
         where application_id = 100
           and (instr(lower(nvl(lov_definition, ' ')), 'v_empresas_usuario') > 0
                or instr(lower(nvl(item_default, ' ')), 'v_empresas_usuario') > 0)
        union all
        select page_id from apex_application_page_proc
         where application_id = 100
           and instr(lower(to_clob(nvl(process_source, ' '))), 'v_empresas_usuario') > 0)
     where page_id not in (0, 4, 19);
    if v_n > 0 then
        insert into tmp_empfiltro_fallas
        values ('L1 quedan ' || v_n || ' componentes fuera de 0/4/19 que leen v_empresas_usuario');
    end if;

    -- L2: las listas filtran por la empresa activa
    for i in 1 .. v_paginas.count loop
        select count(*) into v_n
          from apex_application_page_regions
         where application_id = 100 and page_id = v_paginas(i)
           and instr(lower(to_clob(nvl(region_source, ' '))), 'f_empresa_activa') > 0;
        if v_n = 0 then
            insert into tmp_empfiltro_fallas
            values ('L2 la pagina ' || v_paginas(i) || ' no filtra por F_EMPRESA_ACTIVA');
        end if;
    end loop;

    -- L3: los ítems de empresa de las pantallas son ocultos (no se eligen a mano)
    for r in (select page_id, item_name, display_as_code
                from apex_application_page_items
               where application_id = 100
                 and item_name in ('P7_ID_EMPRESA', 'P9_ID_EMPRESA', 'P13_ID_EMPRESA',
                                   'P17_ID_EMPRESA', 'P18_ID_EMPRESA', 'P21_ID_EMPRESA',
                                   'P24_ID_EMPRESA'))
    loop
        if r.display_as_code <> 'NATIVE_HIDDEN' then
            insert into tmp_empfiltro_fallas
            values ('L3 ' || r.item_name || ' se sigue pudiendo elegir en pantalla (' || r.display_as_code || ')');
        end if;
    end loop;

    -- L4: los procesos que guardan documentos usan la empresa activa
    for r in (select page_id, process_name, to_clob(nvl(process_source, ' ')) src
                from apex_application_page_proc
               where application_id = 100 and page_id in (7, 9, 16)
                 and (upper(process_name) like '%INSERT%'
                      or upper(process_name) like '%GUARDAR%'
                      or upper(process_name) like '%ACTUALIZAR%'))
    loop
        if instr(lower(r.src), 'f_empresa_activa') = 0 then
            insert into tmp_empfiltro_fallas
            values ('L4 el proceso de la pagina ' || r.page_id || ' no usa F_EMPRESA_ACTIVA: ' || substr(r.process_name, 1, 40));
        end if;
    end loop;

    -- L5: cada página con ítem oculto lo fija desde la empresa activa
    for r in (select distinct page_id from apex_application_page_items
               where application_id = 100
                 and item_name in ('P7_ID_EMPRESA', 'P9_ID_EMPRESA', 'P13_ID_EMPRESA',
                                   'P17_ID_EMPRESA', 'P18_ID_EMPRESA', 'P21_ID_EMPRESA',
                                   'P24_ID_EMPRESA'))
    loop
        select count(*) into v_n
          from apex_application_page_proc
         where application_id = 100 and page_id = r.page_id
           and instr(lower(to_clob(nvl(process_source, ' '))), 'f_empresa_activa') > 0;
        if v_n = 0 then
            insert into tmp_empfiltro_fallas
            values ('L5 la pagina ' || r.page_id || ' no tiene proceso que fije su empresa desde la activa');
        end if;
    end loop;

    -- L6: comportamiento de la lista de Presupuestos con la empresa activa nula / propia / ajena
    select region_source into v_reg
      from apex_application_page_regions
     where application_id = 100 and page_id = 5 and region_name = 'Lista de Presupuestos';

    select min(username) into v_usuario
      from (select username, count(*) n from v_empresas_usuario group by username having count(*) > 1);
    if v_usuario is null then
        insert into tmp_empfiltro_fallas values ('L6 no hay un usuario con varias empresas para la prueba');
    else
        -- nula -> cero filas
        begin
            v_sql := replace(replace(v_reg, ':APP_USER', '''' || v_usuario || ''''),
                                        ':F_EMPRESA_ACTIVA', '0');
            execute immediate 'select count(*) from (' || v_sql || ')' into v_filas;
            if v_filas > 0 then
                insert into tmp_empfiltro_fallas
                values ('L6 con la empresa activa nula la lista devolvio ' || v_filas || ' filas');
            end if;
        exception
            when others then
                v_err := substr(sqlerrm, 1, 150);
                insert into tmp_empfiltro_fallas values ('L6 fallo con empresa nula: ' || v_err);
        end;

        -- propia -> exactamente los documentos de esa empresa que la lista muestra
        -- (la lista de Presupuestos excluye los CANCELADO y cruza con clientes)
        select min(id_empresa) into v_emp
          from v_empresas_usuario where username = v_usuario;
        begin
            v_sql := replace(replace(v_reg, ':APP_USER', '''' || v_usuario || ''''),
                                        ':F_EMPRESA_ACTIVA', to_char(v_emp));
            execute immediate 'select count(*) from (' || v_sql || ')' into v_filas;
            select count(*) into v_n
              from presupuestos p
             where p.id_empresa = v_emp
               and p.estado <> 'CANCELADO'
               and exists (select 1 from clientes c
                            where c.id_cliente = p.id_cliente
                              and c.id_empresa = p.id_empresa);
            if v_filas <> v_n then
                insert into tmp_empfiltro_fallas
                values ('L6 con la empresa ' || v_emp || ' la lista devolvio ' || v_filas
                        || ' y le corresponden ' || v_n);
            end if;
            -- y ninguna fila es de otra empresa
            execute immediate 'select count(*) from (' || v_sql || ') t '
                              || 'where t.seleccionar not in (select id_presupuesto from presupuestos '
                              || 'where id_empresa = ' || v_emp || ')' into v_mal;
            if v_mal > 0 then
                insert into tmp_empfiltro_fallas
                values ('L6 con la empresa ' || v_emp || ' activa la lista trajo ' || v_mal
                        || ' documentos de otra empresa');
            end if;
        exception
            when others then
                v_err := substr(sqlerrm, 1, 150);
                insert into tmp_empfiltro_fallas values ('L6 fallo con una empresa del usuario: ' || v_err);
        end;

        -- ajena -> no aplica: la región confía en el ítem de aplicación y quien valida que la
        -- empresa sea del usuario es fn_empresa_activa (caso E3 de la verificación de la tarea 1).
    end if;
end;
/

declare
    v_fallas number;
    v_lista  varchar2(3000);
begin
    select count(*) into v_fallas from tmp_empfiltro_fallas;
    select substrb(listagg(caso, ' | ' on overflow truncate) within group (order by caso), 1, 3000)
      into v_lista from tmp_empfiltro_fallas;
    execute immediate 'drop table tmp_empfiltro_fallas purge';
    raise_application_error(-20100, substrb('RESULTADO: FALLAS=' || v_fallas || ' | ' || v_lista, 1, 3000));
end;
/
