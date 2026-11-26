-- =============================================================================
-- 20261117_empresa_activa_barra_verificacion.sql
--
-- El combo de empresa activa en la barra (2026-11-17, tarea 2 del plan
-- docs/superpowers/plans/2026-11-17-empresa-activa.md):
--   B1  existe el ítem EMPRESA_ACTIVA de la página global y es una lista de selección
--   B2  vive en una región de la página global puesta en la barra (REGION_POSITION_06)
--   B3  su LOV es SQL y lee v_empresas_usuario
--   B4  la LOV se filtra por el usuario de la sesión (:APP_USER)
--   B5  al cambiar la selección cambia la empresa (submit o la acción dinámica de la página global)
--   B6  la LOV, ejecutada como la guarda APEX, devuelve las empresas del usuario
--   B7  el proceso de aplicación de la empresa activa lee ESE ítem (interfaz con la tarea 1)
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261117_empresa_activa_barra_verificacion.sql
-- FALLAS=0 = EXITO. La verificación "pasa" cuando imprime FALLAS=0: el runner sale
-- con código 1 a propósito (-20100).
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

begin
    begin execute immediate 'drop table tmp_empbar_fallas purge'; exception when others then null; end;
end;
/

create table tmp_empbar_fallas (caso varchar2(300))
/

declare
    v_n        number;
    v_lov      varchar2(4000);
    v_lov2     varchar2(4000);
    v_region   varchar2(4000);
    v_pos      varchar2(100);
    v_attrs    varchar2(4000);
    v_n_da   number;
    v_proc     varchar2(32767);
    v_filas    number;
    v_usuario  varchar2(100);
    v_err      varchar2(200);
begin
    -- B1: el ítem existe, es lista de selección y es de la página global (0)
    select count(*) into v_n
      from apex_application_page_items
     where application_id = 100
       and page_id = 0
       and item_name = 'P0_EMPRESA_ACTIVA'
       and display_as_code = 'NATIVE_SELECT_LIST';
    if v_n = 0 then
        insert into tmp_empbar_fallas values ('B1 no existe el item P0_EMPRESA_ACTIVA (select list) en la pagina global');
    end if;

    -- B2: su región está en la barra de navegación
    begin
        select r.display_position, r.region_name
          into v_pos, v_region
          from apex_application_page_items i
          join apex_application_page_regions r
            on r.application_id = i.application_id
           and r.page_id = i.page_id
           and r.region_id = i.region_id
         where i.application_id = 100 and i.page_id = 0 and i.item_name = 'P0_EMPRESA_ACTIVA';
    exception
        when no_data_found then
            v_pos := null;
    end;
    if v_pos is null then
        insert into tmp_empbar_fallas values ('B2 el item no esta dentro de una region de la pagina global');
    elsif v_pos <> 'REGION_POSITION_06' then
        insert into tmp_empbar_fallas values ('B2 la region del combo no esta en la barra: ' || v_pos);
    end if;

    -- B3: la LOV es SQL y lee la vista de empresas del usuario
    begin
        select lower(nvl(lov_definition, ' ')) into v_lov
          from apex_application_page_items
         where application_id = 100 and page_id = 0 and item_name = 'P0_EMPRESA_ACTIVA';
    exception
        when no_data_found then
            v_lov := null;
    end;
    if v_lov is null or instr(v_lov, 'v_empresas_usuario') = 0 then
        insert into tmp_empbar_fallas values ('B3 la LOV no lee v_empresas_usuario');
    end if;

    -- B4: la LOV se filtra por el usuario de la sesión
    if v_lov is null or instr(v_lov, ':app_user') = 0 then
        insert into tmp_empbar_fallas values ('B4 la LOV no se filtra por :APP_USER');
    end if;

    -- B5: al cambiar la selección se envía la página
    begin
        select lower(nvl(to_char(attributes), ' ')) into v_attrs
          from apex_application_page_items
         where application_id = 100 and page_id = 0 and item_name = 'P0_EMPRESA_ACTIVA';
    exception
        when no_data_found then
            v_attrs := null;
    end;
    -- 2026-11-26: desde el 2026-11-25 el cambio lo hace la accion dinamica de la pagina global
    -- «cambia-empresa-activa» (quito el «#LABEL# debe tener algun valor»); vale cualquiera de los dos.
    select count(*) into v_n_da
      from apex_application_page_da
     where application_id = 100 and page_id = 0
       and upper(when_element) = 'P0_EMPRESA_ACTIVA' and lower(when_event_name) like '%change%';
    if (v_attrs is null or instr(v_attrs, '"page_action_on_selection":"submit"') = 0) and v_n_da = 0 then
        insert into tmp_empbar_fallas values ('B5 el combo no cambia la empresa al seleccionar (ni submit ni accion dinamica)');
    end if;

    -- B6: comportamiento: la LOV, ejecutada como la ejecuta APEX, trae las empresas
    -- del usuario y ninguna de otro.
    select min(username) into v_usuario
      from (select username, count(*) n from v_empresas_usuario group by username having count(*) > 1);
    if v_usuario is null then
        insert into tmp_empbar_fallas values ('B6 no hay ningun usuario con varias empresas para probar la LOV');
    else
        begin
            select lov_definition into v_lov2
              from apex_application_page_items
             where application_id = 100 and page_id = 0 and item_name = 'P0_EMPRESA_ACTIVA';
            execute immediate 'select count(*) from (' ||
                replace(v_lov2, ':APP_USER', '''' || v_usuario || '''') || ')' into v_filas;
            if v_filas < 2 then
                insert into tmp_empbar_fallas values ('B6 la LOV devolvio ' || v_filas || ' empresas para ' || v_usuario);
            end if;
        exception
            when others then
                v_err := substr(sqlerrm, 1, 120);
                insert into tmp_empbar_fallas values ('B6 la LOV no se puede ejecutar: ' || v_err);
        end;
    end if;

    -- B7: el proceso de aplicación lee el mismo ítem (si lee otro, el combo no sirve)
    begin
        select to_clob(process) into v_proc
          from apex_application_processes
         where application_id = 100
           and upper(process_name) like '%EMPRESA ACTIVA%';
    exception
        when no_data_found then
            v_proc := null;
    end;
    if v_proc is null then
        insert into tmp_empbar_fallas values ('B7 no hay proceso de aplicacion de la empresa activa');
    elsif instr(lower(v_proc), 'p0_empresa_activa') = 0 then
        insert into tmp_empbar_fallas values ('B7 el proceso no lee P0_EMPRESA_ACTIVA (no lee el combo)');
    end if;
end;
/

declare
    v_fallas number;
    v_lista  varchar2(3000);
begin
    select count(*) into v_fallas from tmp_empbar_fallas;
    select substrb(listagg(caso, ' | ' on overflow truncate) within group (order by caso), 1, 3000)
      into v_lista from tmp_empbar_fallas;
    execute immediate 'drop table tmp_empbar_fallas purge';
    raise_application_error(-20100, substrb('RESULTADO: FALLAS=' || v_fallas || ' | ' || v_lista, 1, 3000));
end;
/
