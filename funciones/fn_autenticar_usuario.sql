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
--   * Mensajes (cambio del 2026-11-08, pedido por el dueno):
--       - clave mala  -> "Usuario o contrasena incorrectos. Intento N de 5."
--       - al llegar a 5 -> "Cuenta bloqueada por 5 intentos fallidos. Comuniquese
--                          con el administrador del sistema..."
--       - ya bloqueada -> el mismo aviso, con la hora en que se libera sola.
--     El resto de motivos (usuario inexistente, inactivo, sin empresa) siguen
--     con el mensaje generico: no conviene decir si la cuenta existe.
--   * El intento se registra en SYN_LOGIN_LOG en transaccion autonoma.
-- =============================================================================

create or replace function fn_autenticar_usuario (
    p_username in varchar2,
    p_password in varchar2
) return boolean is
    c_generico  constant varchar2(200) := 'Usuario o contraseña incorrectos.';
    c_max       constant number := 5;
    v_usuario   varchar2(50);
    v_id        number;
    v_hash      varchar2(512);
    v_estado    varchar2(20);
    v_bloq      date;
    v_empresa   number;
    v_rol       number;
    v_intentos  number;
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

    -- Cuenta bloqueada: se avisa con detalle y con la hora en que se libera sola.
    if v_bloq is not null and v_bloq > sysdate then
        prc_auth_registrar(v_id, 'BLOQUEADO', v_usuario);
        apex_util.set_custom_auth_status(p_status =>
            'Cuenta bloqueada por ' || c_max || ' intentos fallidos. '
            || 'Comuníquese con el administrador del sistema para que la desbloquee; '
            || 'si no, se libera sola el ' || to_char(v_bloq, 'DD/MM/YYYY') || ' a las '
            || to_char(v_bloq, 'HH24:MI') || '.');
        return false;
    end if;

    if v_empresa is null or v_rol is null then
        prc_auth_registrar(v_id, 'SIN_EMPRESA', v_usuario);
        apex_util.set_custom_auth_status(p_status => c_generico);
        return false;
    end if;

    if not fn_verificar_password(p_password, v_hash) then
        prc_auth_registrar(v_id, 'CLAVE_MALA', v_usuario);

        -- El registro va en transaccion autonoma y ya esta confirmado: se puede
        -- leer el contador que dejo este mismo intento.
        begin
            select nvl(reintentos_fallidos, 0), bloqueado_hasta
              into v_intentos, v_bloq
              from usuario
             where usuario_id = v_id;
        exception
            when others then
                v_intentos := null;
        end;

        if v_bloq is not null and v_bloq > sysdate then
            apex_util.set_custom_auth_status(p_status =>
                'Cuenta bloqueada por ' || c_max || ' intentos fallidos. '
                || 'Comuníquese con el administrador del sistema para que la desbloquee; '
                || 'si no, se libera sola el ' || to_char(v_bloq, 'DD/MM/YYYY') || ' a las '
                || to_char(v_bloq, 'HH24:MI') || '.');
        elsif v_intentos is not null then
            apex_util.set_custom_auth_status(p_status =>
                'Usuario o contraseña incorrectos. Intento ' || v_intentos || ' de ' || c_max
                || case when v_intentos >= c_max - 1
                        then '. Si falla una vez más, la cuenta se bloquea.'
                        else '.' end);
        else
            apex_util.set_custom_auth_status(p_status => c_generico);
        end if;

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
