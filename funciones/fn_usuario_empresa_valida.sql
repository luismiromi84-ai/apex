-- =============================================================================
-- fn_usuario_empresa_valida.sql
--
-- Comprueba que una empresa pertenece a un usuario activo. Es el filtro
-- centralizado que usan los packages para no confiar en el id_empresa que
-- llega del navegador (semana 3 del cronograma).
--
-- Devuelve FALSE si alguno de los parametros es nulo o si no hay coincidencia.
-- =============================================================================

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
