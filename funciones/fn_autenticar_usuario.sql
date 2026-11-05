-- =============================================================================
-- fn_autenticar_usuario.sql
--
-- Funcion de autenticacion de la app (esquema NATIVE_CUSTOM de APEX).
-- Reemplaza la version retirada el 2026-11-04: ahora usa PBKDF2, aplica bloqueo
-- por intentos y convierte el hash legado en el primer login correcto.
--
-- Reglas:
--   * Estados que entran: ACTIVO, A, 1 (un estado nulo NO entra).
--   * Sin empresa o sin rol -> no entra (no se crea sesion a medias).
--   * Al usuario se le da SIEMPRE el mismo mensaje: el motivo real (usuario
--     inexistente, inactivo, bloqueado, sin empresa, clave mala) va a
--     SYN_LOGIN_LOG, nunca a la pantalla.
-- =============================================================================

create or replace function fn_autenticar_usuario (
    p_username in varchar2,
    p_password in varchar2
) return boolean is
    c_generico constant varchar2(120) := 'Usuario o contraseña incorrectos.';
    v_usuario  varchar2(50);
    v_id       number;
    v_hash     varchar2(512);
    v_estado   varchar2(20);
    v_bloq     date;
    v_empresa  number;
    v_rol      number;
begin
    v_usuario := trim(p_username);

    if v_usuario is null or p_password is null then
        prc_auth_registrar(p_usuario_id        => null,
                           p_resultado         => 'ERROR',
                           p_usuario_intentado => nvl(v_usuario, '(vacio)'));
        apex_util.set_custom_auth_status(p_status => c_generico);
        return false;
    end if;

    begin
        select usuario_id, password_hash, estado, bloqueado_hasta, id_empresa, rol_id
          into v_id, v_hash, v_estado, v_bloq, v_empresa, v_rol
          from usuario
         where upper(username) = upper(v_usuario);
    exception
        when no_data_found then
            prc_auth_registrar(null, 'NO_EXISTE', v_usuario);
            apex_util.set_custom_auth_status(p_status => c_generico);
            return false;
        when too_many_rows then
            prc_auth_registrar(null, 'ERROR', v_usuario);
            apex_util.set_custom_auth_status(p_status => c_generico);
            return false;
    end;

    if nvl(upper(v_estado), '#') not in ('ACTIVO', 'A', '1') then
        prc_auth_registrar(v_id, 'INACTIVO', v_usuario);
        apex_util.set_custom_auth_status(p_status => c_generico);
        return false;
    end if;

    if v_bloq is not null and v_bloq > sysdate then
        prc_auth_registrar(v_id, 'BLOQUEADO', v_usuario);
        apex_util.set_custom_auth_status(p_status => c_generico);
        return false;
    end if;

    if v_empresa is null or v_rol is null then
        prc_auth_registrar(v_id, 'SIN_EMPRESA', v_usuario);
        apex_util.set_custom_auth_status(p_status => c_generico);
        return false;
    end if;

    if not fn_verificar_password(p_password, v_hash) then
        prc_auth_registrar(v_id, 'CLAVE_MALA', v_usuario);
        apex_util.set_custom_auth_status(p_status => c_generico);
        return false;
    end if;

    prc_auth_registrar(
        p_usuario_id        => v_id,
        p_resultado         => 'OK',
        p_usuario_intentado => v_usuario,
        p_nuevo_hash        => case when fn_password_es_legado(v_hash)
                                    then sypex_hash_password(p_password) end);

    return true;
exception
    when others then
        begin
            prc_auth_registrar(null, 'ERROR', v_usuario);
        exception
            when others then null;
        end;
        apex_util.set_custom_auth_status(p_status => c_generico);
        return false;
end fn_autenticar_usuario;
/
