-- =============================================================================
-- 20261104_validacion_empresa.sql
--
-- Primer paso del bloque de seguridad (semana 3 del cronograma):
-- una función única para comprobar que una empresa pertenece a un usuario.
--
-- Es solo adición: no cambia el comportamiento de nada existente. Los packages
-- y las páginas la irán usando para dejar de confiar en el id_empresa que
-- llega del navegador.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;

create or replace function fn_usuario_empresa_valida (
    p_username   in varchar2,
    p_id_empresa in number
) return boolean is
    v_count pls_integer;
begin
    if p_username is null or p_id_empresa is null then
        return false;
    end if;

    select count(*)
      into v_count
      from usuario u
     where upper(u.username) = upper(p_username)
       and u.id_empresa = p_id_empresa
       and u.estado in ('ACTIVO', 'A', '1');

    return v_count > 0;
end fn_usuario_empresa_valida;
/

create or replace function fn_empresas_del_usuario (
    p_username in varchar2
) return varchar2 is
    v_lista varchar2(4000);
begin
    select listagg(u.id_empresa, ',') within group (order by u.id_empresa)
      into v_lista
      from usuario u
     where upper(u.username) = upper(p_username)
       and u.estado in ('ACTIVO', 'A', '1');

    return v_lista;
end fn_empresas_del_usuario;
/

grant execute on fn_usuario_empresa_valida to public;
grant execute on fn_empresas_del_usuario   to public;

select 'prueba LUIS/1  ' as caso, case when fn_usuario_empresa_valida('LUIS', 1)   then 'OK' else 'FALLA' end as resultado from dual
union all
select 'prueba LUIS/999', case when fn_usuario_empresa_valida('LUIS', 999)  then 'FALLA' else 'OK' end from dual
union all
select 'prueba nadie/1 ', case when fn_usuario_empresa_valida('nadie', 1)  then 'FALLA' else 'OK' end from dual;

-- Reversa
--   drop function fn_usuario_empresa_valida;
--   drop function fn_empresas_del_usuario;
