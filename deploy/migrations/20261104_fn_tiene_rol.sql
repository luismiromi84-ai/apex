-- =============================================================================
-- 20261104_fn_tiene_rol.sql
--
-- Funcion de autorizacion por rol. Es la que usa la autorizacion
-- «Administration Rights» y los procesos «Valida rol administrador» de las
-- paginas 3 y 4.
--
-- Faltaba en el repositorio: se creo directamente en Sypex_SQL el 2026-11-03
-- y solo existia en la base. Se versiona aqui junto con su fuente canonica en
-- funciones/fn_tiene_rol.sql.
--
-- Requiere APEX instalado (lee apex_application.g_user).
-- No cambia datos ni el comportamiento de nada existente.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;

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

-- Validacion: la funcion debe compilar y el usuario LUIS debe tener un rol
-- que la autorizacion acepte.
select object_name, object_type, status
  from user_objects
 where object_name = 'FN_TIENE_ROL';

select u.username, r.codigo_rol,
       case when r.codigo_rol in ('ADMIN', 'GERENCIA', 'PRUEBA') then 'OK' else 'REVISAR' end as resultado
  from usuario u
  join syn_roles r on r.id_rol = u.rol_id
 where upper(u.username) = 'LUIS';

-- Reversa
--   drop function fn_tiene_rol;
