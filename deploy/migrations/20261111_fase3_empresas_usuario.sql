-- =============================================================================
-- 20261111_fase3_empresas_usuario.sql
--
-- Fase 3 de multiempresa: la pagina 4 asigna VARIAS empresas por usuario.
--
-- Trae tres cosas, y hay que aplicarlas juntas antes de importar el export:
--   1. trg_usuario_empresa_principal, corregido: mira antes de insertar. Con
--      "insert + cuando duplicado", el par que ya existe en la MISMA
--      transaccion (la pagina 4 lo inserta y luego actualiza ID_EMPRESA) daba
--      ORA-12860 (deadlock de fila hermana) en esta ADB, no un duplicado limpio.
--   2. fn_usuario_administrable: la guarda de la pagina 4 pasa de "es de mi
--      empresa" a "comparte al menos una", y admite al usuario sin ninguna.
--   3. prc_empresas_usuario: sincroniza USUARIO_EMPRESA y decide el estado.
--
-- Idempotente (create or replace). Al final recompila el esquema: tocar USUARIO
-- deja objetos INVALID sin nada en ALL_ERRORS (paso el 2026-11-05).
--
-- REVERSA:
--   drop procedure prc_empresas_usuario;
--   drop function  fn_usuario_administrable;
--   y volver a la version anterior del trigger (deploy/migrations/
--   20261110_usuario_empresa_principal.sql, bloque 2).
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;
/

create or replace trigger trg_usuario_empresa_principal
    after insert or update of id_empresa on usuario
    for each row
    when (new.id_empresa is not null)
declare
    v_existe number;
begin
    select count(*) into v_existe
      from usuario_empresa
     where usuario_id = :new.usuario_id
       and id_empresa  = :new.id_empresa;

    if v_existe = 0 then
        insert into usuario_empresa (usuario_id, id_empresa)
        values (:new.usuario_id, :new.id_empresa);
    end if;
exception
    when dup_val_on_index then
        null;
end;
/

create or replace function fn_usuario_administrable (
    p_admin      in varchar2,
    p_usuario_id in number
) return boolean is
    v_existe   number;
    v_pares    number;
    v_comparte number;
begin
    if p_admin is null or p_usuario_id is null then
        return false;
    end if;

    select count(*) into v_existe from usuario where usuario_id = p_usuario_id;
    if v_existe = 0 then
        return false;
    end if;

    select count(*) into v_pares from usuario_empresa where usuario_id = p_usuario_id;
    if v_pares = 0 then
        return true;
    end if;

    select count(*) into v_comparte
      from usuario_empresa objetivo
      join usuario_empresa mia      on mia.id_empresa = objetivo.id_empresa
      join usuario         admin    on admin.usuario_id = mia.usuario_id
     where objetivo.usuario_id = p_usuario_id
       and upper(admin.username) = upper(p_admin)
       and nvl(upper(admin.estado), '#') in ('ACTIVO', 'A', '1');

    return v_comparte > 0;
end fn_usuario_administrable;
/

create or replace procedure prc_empresas_usuario (
    p_usuario_id in number,
    p_empresas   in varchar2,
    p_admin      in varchar2,
    p_estado     out varchar2,
    p_mensaje    out varchar2
) is
    type t_numeros is table of number;
    v_nums      t_numeros := t_numeros();
    v_ids       varchar2(4000) := ',';
    v_empresa   number;
    v_suyas     number;
    v_min       number;
    v_estado    usuario.estado%type;
begin
    p_estado  := null;
    p_mensaje := null;

    if not fn_usuario_administrable(p_admin, p_usuario_id) then
        raise_application_error(-20003, 'Solo puede administrar usuarios de su empresa.');
    end if;

    -- OJO: en Oracle '' ES NULL. Escribir "r.valor <> ''" deja la condicion en
    -- UNKNOWN y el bucle no entra nunca (medido el 2026-11-11).
    for r in (select trim(column_value) as valor
                from table(apex_string.split(nvl(p_empresas, ':'), ':'))) loop
        if r.valor is not null then
            v_empresa := fn_clean_num(r.valor);
            select count(*) into v_suyas
              from v_empresas_usuario
             where upper(username) = upper(p_admin)
               and id_empresa = v_empresa;
            if v_suyas = 0 then
                raise_application_error(-20003, 'Solo puede asignar empresas suyas.');
            end if;
            v_nums.extend;
            v_nums(v_nums.count) := v_empresa;
            v_ids := v_ids || v_empresa || ',';
            v_min := least(nvl(v_min, v_empresa), v_empresa);
        end if;
    end loop;

    if v_nums.count = 0 then
        select estado into v_estado from usuario where usuario_id = p_usuario_id;
        if nvl(upper(v_estado), '#') in ('ACTIVO', 'A', '1') then
            update usuario set estado = 'INACTIVO' where usuario_id = p_usuario_id;
            p_estado  := 'INACTIVO';
            p_mensaje := 'El usuario quedo INACTIVO porque no tiene ninguna empresa asignada. '
                      || 'Sus empresas se conservan para auditoria.';
        else
            p_estado := v_estado;
        end if;
        return;
    end if;

    delete from usuario_empresa
     where usuario_id = p_usuario_id
       and instr(v_ids, ',' || id_empresa || ',') = 0
       and id_empresa in (select id_empresa from v_empresas_usuario
                           where upper(username) = upper(p_admin));

    for i in 1 .. v_nums.count loop
        insert into usuario_empresa (usuario_id, id_empresa)
        select p_usuario_id, v_nums(i) from dual
         where not exists (select 1
                             from usuario_empresa
                            where usuario_id = p_usuario_id
                              and id_empresa  = v_nums(i));
    end loop;

    update usuario set id_empresa = v_min where usuario_id = p_usuario_id;

    select estado into v_estado from usuario where usuario_id = p_usuario_id;
    p_estado := v_estado;
end prc_empresas_usuario;
/

begin
    dbms_utility.compile_schema('WKSP_SYPEXWS', false);
end;
/

-- Validacion: los tres objetos VALID y ningun objeto invalido.
select 'FALLA: ' || object_name || ' quedo invalido' as caso
  from all_objects
 where owner = 'WKSP_SYPEXWS' and status <> 'VALID'
   and object_type in ('FUNCTION', 'PROCEDURE', 'PACKAGE', 'PACKAGE BODY', 'TRIGGER', 'VIEW');
/

select 'FALLA: falta ' || faltante as caso
  from (select 'FN_USUARIO_ADMINISTRABLE' faltante from dual
        union all select 'PRC_EMPRESAS_USUARIO' from dual
        union all select 'TRG_USUARIO_EMPRESA_PRINCIPAL' from dual) o
 where not exists (select 1 from all_objects a
                    where a.owner = 'WKSP_SYPEXWS' and a.object_name = o.faltante);
/

commit;
/
