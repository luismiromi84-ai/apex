-- =============================================================================
-- fn_empresas_del_usuario.sql
--
-- Devuelve la lista de id_empresa del usuario, separados por coma, para
-- restringir LOVs y consultas por empresa. Solo considera usuarios activos.
-- Devuelve NULL si el usuario no existe o no tiene empresa.
-- =============================================================================

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
