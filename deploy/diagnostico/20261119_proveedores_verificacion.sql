-- =============================================================================
-- 20261119_proveedores_verificacion.sql
--
-- Modulo de Proveedores (paginas 22 y 23, 2026-11-19):
--   P1  existen las dos paginas y la 23 es un dialogo modal
--   P2  la 22 es un Interactive Report filtrado por la empresa activa
--   P3  el menu trae «Proveedores» con su esquema de autorizacion
--   P4  la 23 tiene los campos del maestro (RIF, retencion, SPE, dias de credito)
--   P5  la guarda de la 22 admite CONSULTA y la escritura no
--   P6  el RIF es unico por empresa
--   P7  la consulta de la lista trae los de la empresa activa y no los de otra
--   P8  el combo del RIF guarda la LETRA (J/V/E) y el proceso la convierte a J/N
--   P9  el concepto de ISLR por defecto: item en la 23, carga, guardado con 0 -> null
--       y lista de los activos con la tarifa en la etiqueta
--
-- Todo el DML va dentro de un SAVEPOINT y se revierte.
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261119_proveedores_verificacion.sql
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

begin
    begin execute immediate 'drop table tmp_prov_fallas purge'; exception when others then null; end;
end;
/

create table tmp_prov_fallas (caso varchar2(300))
/

declare
    type t_lista is table of varchar2(300);
    v_fallas t_lista := t_lista();
    v_msg    varchar2(300);
    v_n      number;
    v_sql    clob;
    v_id     number;

    procedure falla(p_texto varchar2) is
    begin
        v_fallas.extend;
        v_fallas(v_fallas.count) := substrb(p_texto, 1, 300);
    end;
begin
    savepoint sp_prov;

    -- P1
    select count(*) into v_n from apex_260100.apex_application_pages
     where application_id = 100 and page_id in (22, 23);
    if v_n <> 2 then falla('P1: faltan las paginas 22 o 23'); end if;

    select count(*) into v_n from apex_260100.apex_application_pages
     where application_id = 100 and page_id = 23 and upper(page_mode) like 'MODAL%';
    if v_n = 0 then falla('P1: la 23 no es un dialogo modal'); end if;

    -- P2
    select count(*) into v_n from apex_260100.apex_application_page_regions
     where application_id = 100 and page_id = 22 and region_static_id = 'proveedores-lista'
       and source_type_plugin_static_id = 'NATIVE_IR'
       and instr(upper(region_source), 'F_EMPRESA_ACTIVA') > 0;
    if v_n = 0 then falla('P2: la lista no es un IR filtrado por la empresa activa'); end if;

    select count(*) into v_n from apex_260100.apex_application_page_ir_col
     where application_id = 100 and page_id = 22
       and column_alias in ('ID_PROVEEDOR', 'RIF', 'RAZON_SOCIAL', 'RETENCION', 'SPE', 'DIAS_CREDITO', 'ESTADO');
    if v_n < 7 then falla('P2: faltan columnas en la lista (' || v_n || '/7)'); end if;

    -- P3
    select count(*) into v_n from apex_260100.apex_application_list_entries
     where application_id = 100 and static_id = 'proveedores';
    if v_n = 0 then falla('P3: el menu no trae Proveedores'); end if;

    select count(*) into v_n from apex_260100.apex_application_authorization
     where application_id = 100 and static_id = 'ver-proveedores';
    if v_n = 0 then falla('P3: falta el esquema ver-proveedores'); end if;

    -- P4
    select count(*) into v_n from apex_260100.apex_application_page_items
     where application_id = 100 and page_id = 23
       and item_name in ('P23_ID_PROVEEDOR', 'P23_RAZON_SOCIAL', 'P23_RIF', 'P23_TIPO_RIF',
                         'P23_COD_PAIS', 'P23_ESTADO', 'P23_RETENER_IVA',
                         'P23_PORCENTAJE_RETENCION', 'P23_ES_SPE', 'P23_DIAS_CREDITO');
    if v_n <> 10 then falla('P4: faltan campos en el dialogo (' || v_n || '/10)'); end if;

    -- P5
    select count(*) into v_n from apex_260100.apex_application_page_proc
     where application_id = 100 and page_id = 22 and static_id = 'valida-rol-proveedores'
       and instr(process_source, 'CONSULTA') > 0;
    if v_n = 0 then falla('P5: la guarda de la lista no admite CONSULTA'); end if;

    select count(*) into v_n from apex_260100.apex_application_page_buttons
     where application_id = 100 and page_id = 23 and button_name = 'BTN_GUARDAR_PROVEEDOR'
       and instr(upper(condition_expression1), 'FN_TIENE_ROL') > 0;
    if v_n = 0 then falla('P5: el boton Guardar no esta condicionado por rol'); end if;

    -- P6: RIF unico por empresa
    insert into proveedores (id_empresa, rif, razon_social, tipo_persona, cod_pais,
                             estado, retener_iva, porcentaje_retencion, es_spe, dias_credito)
    values (1, 'J-VERIF-PROV-1', 'Proveedor verificacion', 'J', 'VE', 'ACTIVO', 'S', 75, 'N', 30)
    returning id_proveedor into v_id;

    begin
        insert into proveedores (id_empresa, rif, razon_social, tipo_persona, cod_pais,
                                 estado, retener_iva, porcentaje_retencion, es_spe, dias_credito)
        values (1, 'J-VERIF-PROV-1', 'Otro con el mismo RIF', 'J', 'VE', 'ACTIVO', 'S', 75, 'N', 0);
        falla('P6: se pudo repetir el RIF en la misma empresa');
    exception
        when dup_val_on_index then null;
    end;

    -- P7: la consulta de la lista
    select region_source into v_sql
      from apex_260100.apex_application_page_regions
     where application_id = 100 and page_id = 22 and region_static_id = 'proveedores-lista';

    execute immediate 'select count(*) from ('
        || replace(v_sql, ':F_EMPRESA_ACTIVA', '1') || ')' into v_n;
    if v_n < 1 then
        falla('P7: la lista no trae el proveedor de la empresa 1');
    end if;

    execute immediate 'select count(*) from ('
        || replace(v_sql, ':F_EMPRESA_ACTIVA', '2') || ')' into v_n;
    if v_n <> 0 then
        falla('P7: la lista trae proveedores de otra empresa (' || v_n || ')');
    end if;

    -- P8 (2026-11-19): el combo del dialogo guarda la LETRA del RIF (J/V/E), pero
    -- TIPO_PERSONA y fn_rif_cliente_valido esperan J (juridica) o N (natural). Al
    -- pasar 'V' la funcion no entraba en ninguna rama y rechazaba SIEMPRE el RIF
    -- de una persona natural (lo reporto el dueno con V-4666778-9).
    select count(*) into v_n
      from apex_260100.apex_application_page_proc
     where application_id = 100 and page_id = 23 and static_id = 'guardar-proveedor'
       and instr(upper(process_source), 'THEN ''J'' ELSE ''N'' END') > 0;
    if v_n = 0 then
        falla('P8: el guardado no convierte la letra del RIF en J/N');
    end if;

    select count(*) into v_n
      from apex_260100.apex_application_page_proc
     where application_id = 100 and page_id = 23 and static_id = 'carga-proveedor'
       and instr(upper(process_source), 'IN (''V'', ''E'')') > 0;
    if v_n = 0 then
        falla('P8: la carga del proveedor no deriva la letra del RIF');
    end if;

    -- P9 (2026-11-20): el concepto de ISLR por defecto del proveedor. Sin item en la
    -- 23 solo se podia rellenar por SQL y la mitad "por defecto en el proveedor" del
    -- modelo aprobado era inalcanzable desde la app.
    select count(*) into v_n from apex_260100.apex_application_page_items
     where application_id = 100 and page_id = 23 and item_name = 'P23_ID_CONCEPTO_ISLR';
    if v_n <> 1 then
        falla('P9: la pagina 23 no tiene el concepto de ISLR');
    end if;

    select count(*) into v_n from apex_260100.apex_application_page_proc
     where application_id = 100 and page_id = 23 and static_id = 'carga-proveedor'
       and instr(lower(process_source), 'p23_id_concepto_islr') > 0;
    if v_n = 0 then
        falla('P9: la carga de la 23 no trae el concepto del proveedor');
    end if;

    -- El guardado escribe el concepto en las DOS ramas (alta y edicion) y convierte
    -- el 0 de "sin concepto" en NULL.
    select count(*) into v_n from apex_260100.apex_application_page_proc
     where application_id = 100 and page_id = 23 and static_id = 'guardar-proveedor'
       and instr(lower(process_source), 'id_concepto_islr') > 0
       and instr(lower(process_source), 'nullif(fn_clean_num(:p23_id_concepto_islr)') > 0;
    if v_n = 0 then
        falla('P9: el guardado de la 23 no escribe el concepto con 0 -> null');
    end if;

    -- La lista ofrece los conceptos ACTIVOS y ensena la tarifa en la etiqueta.
    select count(*) into v_n from apex_260100.apex_application_page_items
     where application_id = 100 and page_id = 23 and item_name = 'P23_ID_CONCEPTO_ISLR'
       and lower(lov_definition) like '%activo%'
       and lower(lov_definition) like '%tarifa%';
    if v_n <> 1 then
        falla('P9: la lista de conceptos no filtra los activos o no ensena la tarifa');
    end if;

    rollback to sp_prov;

    for i in 1 .. v_fallas.count loop
        insert into tmp_prov_fallas values (v_fallas(i));
    end loop;
exception
    when others then
        rollback to sp_prov;
        v_msg := substrb('?: el caso revento: ' || sqlerrm, 1, 300);
        insert into tmp_prov_fallas values (v_msg);
end;
/

declare
    v_fallas number;
    v_lista  varchar2(3000);
begin
    select count(*) into v_fallas from tmp_prov_fallas;
    select substrb(listagg(caso, ' | ' on overflow truncate) within group (order by caso), 1, 3000)
      into v_lista from tmp_prov_fallas;
    execute immediate 'drop table tmp_prov_fallas purge';
    raise_application_error(-20100, substrb('RESULTADO: FALLAS=' || v_fallas || ' | ' || v_lista, 1, 3000));
end;
/
