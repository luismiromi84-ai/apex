-- =============================================================================
-- 20261110_multiempresa_guardas.sql
--
-- Tarea 2 del plan multiempresa: la guarda fn_usuario_empresa_valida y el
-- login preguntan por la asociacion (USUARIO_EMPRESA), no por la columna unica
-- USUARIO.ID_EMPRESA.
--
--   fn_usuario_empresa_valida: true si el usuario esta ACTIVO y el par
--                              (usuario, empresa) existe en USUARIO_EMPRESA.
--                              No exige que la empresa este ACTIVA.
--   fn_autenticar_usuario:     exige rol y al menos un par en USUARIO_EMPRESA.
--   prc_post_login:            idem; se quita el join a EMPRESAS.
--
-- Se ejecuta sentencia por sentencia:
--   python deploy/conexion/importar_export.py deploy/migrations/20261110_multiempresa_guardas.sql
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;
/

-- -----------------------------------------------------------------------------
-- fn_usuario_empresa_valida
-- -----------------------------------------------------------------------------
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
      join usuario_empresa ue on ue.usuario_id = u.usuario_id
     where upper(u.username) = upper(p_username)
       and ue.id_empresa = p_id_empresa
       and u.estado in ('ACTIVO', 'A', '1');

    return v_count > 0;
end fn_usuario_empresa_valida;
/

-- -----------------------------------------------------------------------------
-- fn_autenticar_usuario
-- -----------------------------------------------------------------------------
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

    -- Desde el 2026-11-10 la empresa se valida contra USUARIO_EMPRESA (tabla de
    -- asociacion multiempresa): basta con al menos un par. La columna
    -- USUARIO.ID_EMPRESA queda como 'empresa principal' y puede ser nula.
    --
    -- El 'exists' va dentro de un SELECT (no puede usarse como condicion
    -- PL/SQL: PLS-00204).
    select count(*)
      into v_empresa
      from usuario_empresa ue
     where ue.usuario_id = v_id;

    if v_rol is null or v_empresa = 0 then
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

-- -----------------------------------------------------------------------------
-- prc_post_login
-- -----------------------------------------------------------------------------
create or replace procedure prc_post_login is
    v_debe_cambiar    usuario.debe_cambiar_clave%type;
begin
    select nvl(u.debe_cambiar_clave, 'N')
      into v_debe_cambiar
      from usuario u
      join syn_roles r on r.id_rol = u.rol_id
     where upper(u.username) = upper(v('APP_USER'))
       and u.estado in ('ACTIVO', 'A', '1')
       and exists (select 1 from usuario_empresa ue where ue.usuario_id = u.usuario_id);

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

-- -----------------------------------------------------------------------------
-- Cierre obligatorio: recompilar el esquema entero.
--
-- Sin esto, una migracion que toca USUARIO (o recompila un body) puede dejar
-- objetos INVALID en silencio (incidente medido el 2026-11-05: 8 objetos
-- INVALID, incluido FN_AUTENTICAR_USUARIO, que tumbaba el login).
-- dbms_utility.compile_schema deja los objetos VALID y hace que el fallo
-- aparece al ejecutar la migracion, no meses despues.
-- -----------------------------------------------------------------------------
begin
    dbms_utility.compile_schema('WKSP_SYPEXWS', false);
end;
/

