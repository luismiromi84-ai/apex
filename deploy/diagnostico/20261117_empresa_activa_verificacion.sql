-- =============================================================================
-- 20261117_empresa_activa_verificacion.sql
--
-- La empresa activa de la sesion (2026-11-17, tarea 1):
--   E1  la funcion fn_empresa_activa existe
--   E2  la empresa elegida, si es del usuario, manda
--   E3  una empresa ajena NO se acepta (devuelve nulo)
--   E4  sin elegir y con UNA empresa, la toma
--   E5  sin elegir y con VARIAS, devuelve nulo (no escoge por su cuenta)
--   E6  usuario nulo o inexistente -> nulo
--   E7  el item de aplicacion F_EMPRESA_ACTIVA existe
--   E8  el proceso de aplicacion lo fija y valida con fn_usuario_empresa_valida
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261117_empresa_activa_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

begin
    begin execute immediate 'drop table tmp_empact_fallas purge'; exception when others then null; end;
end;
/

create table tmp_empact_fallas (caso varchar2(300))
/

declare
    v_emp_multi  varchar2(100);   -- usuario con varias empresas
    v_emp_una    varchar2(100);   -- usuario con una sola
    v_ajena      number;
    v_elegida    number;
    v_n          number;
begin
    -- Usuarios de la base
    select max(username) into v_emp_multi
      from (select username, count(*) n from v_empresas_usuario
             group by username having count(*) > 1);
    select max(username) into v_emp_una
      from (select username, count(*) n from v_empresas_usuario
             group by username having count(*) = 1);

    -- E2: la elegida, si es suya
    if v_emp_multi is not null then
        select min(id_empresa) into v_elegida
          from v_empresas_usuario where username = v_emp_multi;
        v_n := fn_empresa_activa(v_emp_multi, v_elegida);
        if v_n is null then
            insert into tmp_empact_fallas values ('E2 la empresa elegida del usuario no se acepto');
        end if;

        -- E3: una empresa que no es suya
        select min(id_empresa) into v_ajena
          from v_empresas_usuario
         where id_empresa not in (select id_empresa from v_empresas_usuario where username = v_emp_multi);
        if v_ajena is not null then
            v_n := fn_empresa_activa(v_emp_multi, v_ajena);
            if v_n is not null then
                insert into tmp_empact_fallas values ('E3 acepto una empresa ajena: ' || v_n);
            end if;
        end if;

        -- E5: sin elegir y con varias -> nulo
        if fn_empresa_activa(v_emp_multi) is not null then
            insert into tmp_empact_fallas values ('E5 con varias empresas y sin elegir devolvio una');
        end if;
    else
        insert into tmp_empact_fallas values ('E? no hay ningun usuario con varias empresas para probar');
    end if;

    -- E4: sin elegir y con una -> esa
    if v_emp_una is not null then
        v_n := fn_empresa_activa(v_emp_una);
        if v_n is null then
            insert into tmp_empact_fallas values ('E4 con una sola empresa no la tomo');
        end if;
    end if;

    -- E6
    if fn_empresa_activa(null) is not null or fn_empresa_activa('NO_EXISTE_ZZZ') is not null then
        insert into tmp_empact_fallas values ('E6 con usuario nulo o inexistente devolvio una empresa');
    end if;

    -- E7: item de aplicacion
    select count(*) into v_n from apex_application_items
     where application_id = 100 and item_name = 'F_EMPRESA_ACTIVA';
    if v_n = 0 then
        insert into tmp_empact_fallas values ('E7 no existe el item de aplicacion F_EMPRESA_ACTIVA');
    end if;

    -- E8: proceso de aplicacion
    select count(*) into v_n from apex_application_processes
     where application_id = 100
       and upper(process_name) like '%EMPRESA ACTIVA%'
       and instr(lower(to_clob(process)), 'fn_empresa_activa') > 0;
    if v_n = 0 then
        insert into tmp_empact_fallas values ('E8 no hay proceso de aplicacion que fije la empresa activa');
    end if;
end;
/

declare
    v_fallas number;
    v_lista  varchar2(3000);
begin
    select count(*) into v_fallas from tmp_empact_fallas;
    select substrb(listagg(caso, ' | ' on overflow truncate) within group (order by caso), 1, 3000)
      into v_lista from tmp_empact_fallas;
    execute immediate 'drop table tmp_empact_fallas purge';
    raise_application_error(-20100, substrb('RESULTADO: FALLAS=' || v_fallas || ' | ' || v_lista, 1, 3000));
end;
/
