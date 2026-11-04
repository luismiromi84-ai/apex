-- =============================================================================
-- fn_tiene_rol.sql
--
-- Autorización por rol (semana 3 del cronograma). Comprueba si el usuario de la
-- sesión APEX (apex_application.g_user) tiene alguno de los roles indicados.
--
-- p_roles: lista de codigos_rol separados por coma, por ejemplo
--          'ADMIN,GERENCIA'. No distingue mayusculas ni espacios.
--
-- Devuelve FALSE si no hay usuario autenticado, si el usuario no esta activo
-- o si ningun rol coincide. Nunca lanza excepcion por datos faltantes.
--
-- Usada por la autorizacion «Administration Rights» y por los procesos
-- «Valida rol administrador» de las paginas 3 y 4.
-- =============================================================================

create or replace function fn_tiene_rol (p_roles in varchar2) return boolean is
    v_count pls_integer;
begin
    if p_roles is null then return false; end if;

    select count(*) into v_count
      from usuario u
      join syn_roles r on r.id_rol = u.rol_id
     where upper(u.username) = upper(apex_application.g_user)
       and u.estado in ('ACTIVO','A','1')
       and instr(',' || upper(replace(p_roles,' ','')) || ',', ',' || upper(r.codigo_rol) || ',') > 0;

    return v_count > 0;
end fn_tiene_rol;
/
