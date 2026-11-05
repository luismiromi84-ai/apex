-- =============================================================================
-- prc_post_login.sql
--
-- Proceso de post-autenticacion: deja en la sesion la empresa, el rol y la
-- bandera de cambio de clave obligatorio del usuario. Lo llama el esquema de
-- autenticacion (p_post_auth_process).
--
-- Deja cinco items de aplicacion: F_ID_EMPRESA, F_NOMBRE_EMPRESA, F_ID_ROL,
-- F_NOMBRE_ROL y F_DEBE_CAMBIAR_CLAVE ('S' o 'N'; nulo en la tabla se trata
-- como 'N'). La bandera la consumen la pagina 14 y la guarda de la pagina 0.
--
-- Acepta los mismos estados que fn_autenticar_usuario (ACTIVO, A, 1); antes
-- solo miraba ACTIVO y con 'A'/'1' el login entraba pero F_* quedaban nulos.
--
-- Si el usuario no tiene empresa o rol se lanza error en vez de silenciar
-- NO_DATA_FOUND. fn_autenticar_usuario ya lo rechaza antes de crear sesion, asi
-- que esto solo deberia alcanzarse si los datos cambian entre ambos pasos.
-- =============================================================================

create or replace procedure prc_post_login is
    v_id_empresa      usuario.id_empresa%type;
    v_nombre_empresa  empresas.nombre_empresa%type;
    v_id_rol          usuario.rol_id%type;
    v_nombre_rol      syn_roles.nombre_rol%type;
    v_debe_cambiar    usuario.debe_cambiar_clave%type;
begin
    select u.id_empresa,
           e.nombre_empresa,
           u.rol_id,
           r.nombre_rol,
           nvl(u.debe_cambiar_clave, 'N')
      into v_id_empresa,
           v_nombre_empresa,
           v_id_rol,
           v_nombre_rol,
           v_debe_cambiar
      from usuario u
      join empresas e on e.id_empresa = u.id_empresa
      join syn_roles r on r.id_rol = u.rol_id
     where upper(u.username) = upper(v('APP_USER'))
       and u.estado in ('ACTIVO', 'A', '1');

    apex_util.set_session_state('F_ID_EMPRESA', v_id_empresa);
    apex_util.set_session_state('F_NOMBRE_EMPRESA', v_nombre_empresa);
    apex_util.set_session_state('F_ID_ROL', v_id_rol);
    apex_util.set_session_state('F_NOMBRE_ROL', v_nombre_rol);
    apex_util.set_session_state('F_DEBE_CAMBIAR_CLAVE', v_debe_cambiar);
exception
    when no_data_found then
        -- Falla controlada: se deja constancia del motivo y se corta la entrada
        -- con un mensaje entendible. No se sigue con F_* nulos (era el bug viejo).
        begin
            prc_auth_registrar(p_usuario_id        => null,
                               p_resultado         => 'SIN_EMPRESA',
                               p_usuario_intentado => v('APP_USER'));
        exception
            when others then null;
        end;

        raise_application_error(-20013,
            'Tu cuenta no tiene empresa o rol asignado. Contacta al administrador.');
end prc_post_login;
/
