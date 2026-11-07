-- =============================================================================
-- prc_post_login.sql
--
-- Proceso de post-autenticacion: deja en la sesion la bandera de cambio de
-- clave obligatorio del usuario. Lo llama el esquema de autenticacion
-- (p_post_auth_process).
--
-- Deja UN item de aplicacion: F_DEBE_CAMBIAR_CLAVE ('S' o 'N'; nulo en la
-- tabla se trata como 'N'). Lo lee el proceso AFTER_SUBMIT de la pagina 14
-- ("Restablecer contrasena") para saber si el cambio es obligatorio. La guarda
-- que redirige a la 14 es un PROCESO DE APLICACION (BEFORE_HEADER,
-- static_id 'cambio-clave-obligatorio') y lee la bandera de la tabla, no del
-- item.
--
-- Los items F_ID_EMPRESA, F_NOMBRE_EMPRESA, F_ID_ROL y F_NOMBRE_ROL se
-- eliminaron el 2026-11-07: se publicaban aqui y no los leia nadie (medido: 0
-- lecturas en el export, en los packages y en el JavaScript). La empresa y el
-- rol se resuelven por pagina con los items Pn_ID_EMPRESA y las funciones
-- fn_usuario_empresa_valida / fn_tiene_rol, nunca por sesion. No volver a
-- publicarlos "por si acaso": en multiempresa la empresa activa cambia DURANTE
-- la sesion, y un valor escrito solo en el login seria el sitio equivocado.
--
-- Acepta los mismos estados que fn_autenticar_usuario (ACTIVO, A, 1); antes
-- solo miraba ACTIVO y con 'A'/'1' el login entraba pero la bandera quedaba
-- nula.
--
-- Si el usuario no tiene empresa o rol se lanza error en vez de silenciar
-- NO_DATA_FOUND. fn_autenticar_usuario ya lo rechaza antes de crear sesion,
-- asi que esto solo deberia alcanzarse si los datos cambian entre ambos pasos.
-- =============================================================================

create or replace procedure prc_post_login is
    v_debe_cambiar    usuario.debe_cambiar_clave%type;
begin
    select nvl(u.debe_cambiar_clave, 'N')
      into v_debe_cambiar
      from usuario u
      join empresas e on e.id_empresa = u.id_empresa
      join syn_roles r on r.id_rol = u.rol_id
     where upper(u.username) = upper(v('APP_USER'))
       and u.estado in ('ACTIVO', 'A', '1');

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
