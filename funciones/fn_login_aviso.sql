-- =============================================================================
-- fn_login_aviso.sql
--
-- Devuelve el mensaje que la pagina de login debe mostrar cuando el intento
-- NO debe llegar a la autenticacion de APEX, o NULL si el intento es correcto
-- (y entonces el login sigue su curso normal).
--
-- Por que existe: APEX ignora `apex_util.set_custom_auth_status` y muestra
-- siempre su propio "Usuario o contrasena incorrectos". Ademas, cuando el
-- proceso de login de APEX ve varios fallos seguidos aplica SU propio freno
-- ("El intento de conexion se ha bloqueado / Espere N segundos"), que tapa el
-- contador de la app. Con esta funcion, un intento fallido se corta ANTES del
-- proceso de login (pagina 9999, proceso 'Aviso de intentos de conexion'), asi
-- que el usuario ve el contador de la app y el freno de APEX no interviene.
--
-- Reglas (2026-11-08):
--   * Clave mala  -> "Usuario o contrasena incorrectos. Intento N de 5."
--   * Al llegar a 5 -> "Cuenta bloqueada por 5 intentos fallidos. Comuniquese
--                      con el administrador del sistema..."
--   * Ya bloqueada -> el mismo aviso, con la fecha y hora en que se libera.
--   * Clave buena, usuario inexistente o inactivo -> NULL (sigue el login
--     normal, que dara el mensaje generico).
--
-- El contador y el bloqueo los lleva prc_auth_registrar (transaccion autonoma).
-- =============================================================================

create or replace function fn_login_aviso (
    p_username in varchar2,
    p_password in varchar2
) return varchar2 is
    c_max      constant number := 5;
    v_usuario  varchar2(50);
    v_id       number;
    v_hash     varchar2(512);
    v_estado   varchar2(20);
    v_bloq     date;
    v_intentos number;

    function texto_bloqueo(p_hasta date) return varchar2 is
    begin
        return 'Cuenta bloqueada por ' || c_max || ' intentos fallidos. '
            || 'Comuníquese con el administrador del sistema para que la desbloquee; '
            || 'si no, se libera sola el ' || to_char(p_hasta, 'DD/MM/YYYY')
            || ' a las ' || to_char(p_hasta, 'HH24:MI') || '.';
    end texto_bloqueo;
begin
    v_usuario := trim(p_username);

    if v_usuario is null or p_password is null then
        return null;
    end if;

    begin
        select usuario_id, password_hash, estado, bloqueado_hasta
          into v_id, v_hash, v_estado, v_bloq
          from usuario
         where upper(username) = upper(v_usuario);
    exception
        when others then
            return null;   -- inexistente o duplicado: mensaje generico de APEX
    end;

    if nvl(upper(v_estado), '#') not in ('ACTIVO', 'A', '1') then
        return null;
    end if;

    -- Ya bloqueada: se avisa sin gastar una verificacion de clave.
    if v_bloq is not null and v_bloq > sysdate then
        prc_auth_registrar(v_id, 'BLOQUEADO', v_usuario);
        return texto_bloqueo(v_bloq);
    end if;

    -- Clave correcta: que siga el login normal.
    if fn_verificar_password(p_password, v_hash) then
        return null;
    end if;

    -- Clave mala: cuenta el intento (autonoma, ya confirmado) y devuelve el aviso.
    prc_auth_registrar(v_id, 'CLAVE_MALA', v_usuario);

    begin
        select nvl(reintentos_fallidos, 0), bloqueado_hasta
          into v_intentos, v_bloq
          from usuario
         where usuario_id = v_id;
    exception
        when others then
            return 'Usuario o contraseña incorrectos.';
    end;

    if v_bloq is not null and v_bloq > sysdate then
        return texto_bloqueo(v_bloq);
    end if;

    return 'Usuario o contraseña incorrectos. Intento ' || v_intentos || ' de ' || c_max
        || case when v_intentos >= c_max - 1
                then '. Si falla una vez más, la cuenta se bloquea.'
                else '.' end;
end fn_login_aviso;
/
