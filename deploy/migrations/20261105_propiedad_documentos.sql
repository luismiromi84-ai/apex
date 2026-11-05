-- =============================================================================
-- 20261105_propiedad_documentos.sql
--
-- Objetivo: que ningun proceso pueda tocar un presupuesto o una factura de otra
-- empresa. Hoy el id del documento llega del navegador y se pasa al package tal
-- cual, asi que un usuario de la empresa 1 puede procesar, anular o modificar
-- lineas de un documento de la empresa 2.
--
-- Responsable: agente, sesion 2026-11-05 (brief propiedad-documentos).
--
-- Precondiciones: existe fn_usuario_empresa_valida (migracion
-- 20261104_validacion_empresa.sql) y las tablas PRESUPUESTOS y FACTURAS tienen
-- ID_EMPRESA.
--
-- Es solo adicion: crea dos funciones y no cambia el comportamiento de nada
-- existente. Las guardas que las usan viven en pagina_apex/f100.sql (paginas 5,
-- 6, 8, 9 y 10) y se aplican al importar el export.
--
-- Se puede ejecutar varias veces (create or replace).
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;
/

create or replace function fn_presupuesto_propio (
    p_id_presupuesto in number,
    p_username       in varchar2
) return boolean is
    v_id_empresa number;
begin
    if p_id_presupuesto is null or p_username is null then
        return false;
    end if;

    begin
        select p.id_empresa
          into v_id_empresa
          from presupuestos p
         where p.id_presupuesto = p_id_presupuesto;
    exception
        when no_data_found then
            return false;
    end;

    return fn_usuario_empresa_valida(p_username, v_id_empresa);
end fn_presupuesto_propio;
/

create or replace function fn_factura_propio (
    p_id_factura in number,
    p_username   in varchar2
) return boolean is
    v_id_empresa number;
begin
    if p_id_factura is null or p_username is null then
        return false;
    end if;

    begin
        select f.id_empresa
          into v_id_empresa
          from facturas f
         where f.id_factura = p_id_factura;
    exception
        when no_data_found then
            return false;
    end;

    return fn_usuario_empresa_valida(p_username, v_id_empresa);
end fn_factura_propio;
/

grant execute on fn_presupuesto_propio to public;
/
grant execute on fn_factura_propio     to public;
/

-- Validacion: las dos funciones compilan.
select 'fn_presupuesto_propio VALID' as caso,
       case when status = 'VALID' then 'OK' else 'FALLA' end as resultado
  from all_objects
 where owner = 'WKSP_SYPEXWS'
   and object_name = 'FN_PRESUPUESTO_PROPIO'
 union all
select 'fn_factura_propio VALID',
       case when status = 'VALID' then 'OK' else 'FALLA' end
  from all_objects
 where owner = 'WKSP_SYPEXWS'
   and object_name = 'FN_FACTURA_PROPIO';
/

-- Toda migracion debe terminar con el esquema compilado: los dependientes de
-- un objeto recreado pueden quedar INVALID sin dejar rastro en ALL_ERRORS.
begin
    dbms_utility.compile_schema('WKSP_SYPEXWS', false);
end;
/

declare
    v_invalidos number;
    v_inv_lista varchar2(2000);
    v_fallas    number := 0;
    v_lista     varchar2(2000) := '';
    v_p1        number;
    v_f1        number;
    v_user      varchar2(100);

    procedure falla (p_caso in varchar2, p_detalle in varchar2) is
    begin
        v_fallas := v_fallas + 1;
        v_lista  := v_lista || ' | ' || p_caso || ': ' || p_detalle;
    end falla;
begin
    select count(*), listagg(object_name || ' (' || object_type || ')', ', ')
      into v_invalidos, v_inv_lista
      from all_objects
     where owner = 'WKSP_SYPEXWS'
       and status <> 'VALID'
       and object_type in ('FUNCTION', 'PROCEDURE', 'PACKAGE', 'PACKAGE BODY', 'TRIGGER', 'VIEW');

    if nvl(v_invalidos, 0) > 0 then
        falla('objetos INVALIDOS', v_inv_lista);
    end if;

    -- Casos que no dependen de los datos cargados: id nulo, id inexistente y
    -- usuario que no existe. Si alguna funcion devolviera TRUE aqui, la guarda
    -- dejaria pasar a cualquiera.
    if fn_presupuesto_propio(null, 'admin.demo') or fn_factura_propio(null, 'admin.demo') then
        falla('id nulo', 'alguna funcion devolvio TRUE');
    end if;
    if fn_presupuesto_propio(999999, 'admin.demo') or fn_factura_propio(999999, 'admin.demo') then
        falla('id 999999', 'alguna funcion devolvio TRUE');
    end if;
    if fn_presupuesto_propio(1, 'usuario_inexistente') or fn_factura_propio(1, 'usuario_inexistente') then
        falla('usuario inexistente', 'alguna funcion devolvio TRUE');
    end if;

    -- Casos con datos: el primer usuario activo de la empresa 1 con un
    -- documento de esa empresa. Si el esquema no tiene documentos (por ejemplo
    -- despues de purgar el demo) se omiten.
    select min(u.username)
      into v_user
      from usuario u
     where u.id_empresa = 1
       and u.estado in ('ACTIVO', 'A', '1');

    select min(p.id_presupuesto) into v_p1 from presupuestos p where p.id_empresa = 1;
    select min(f.id_factura)     into v_f1 from facturas f     where f.id_empresa = 1;

    if v_user is not null and v_p1 is not null and not fn_presupuesto_propio(v_p1, v_user) then
        falla('presupuesto ' || v_p1 || ' / ' || v_user, 'devolvio FALSE para su empresa');
    end if;
    if v_user is not null and v_f1 is not null and not fn_factura_propio(v_f1, v_user) then
        falla('factura ' || v_f1 || ' / ' || v_user, 'devolvio FALSE para su empresa');
    end if;

    if v_fallas = 0 then
        commit;
    else
        -- raise_application_error admite 2048 bytes: se recorta la lista para
        -- no enmascarar el resultado con un ORA-06502.
        raise_application_error(-20100, substr('RESULTADO: MIGRACION CON FALLAS, FALLAS=' || v_fallas
            || ', OBJETOS INVALIDOS=' || nvl(v_invalidos, 0) || v_lista, 1, 1900));
    end if;
end;
/

-- Reversa
--   drop function fn_presupuesto_propio;
--   drop function fn_factura_propio;
