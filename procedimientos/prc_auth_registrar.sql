-- =============================================================================
-- prc_auth_registrar.sql
--
-- Registra un intento de login en transaccion autonoma: escribe el log y
-- actualiza contador, bloqueo y (si el login fue bueno) el hash nuevo.
--
-- Por que autonoma: APEX descarta el DML de una autenticacion fallida, asi que
-- dentro de la transaccion normal el contador nunca subiria y el bloqueo no se
-- activaria nunca.
--
-- OJO al editar: deploy/conexion/importar_export.py descarta las lineas que
-- empiezan por "set " (las confunde con comandos de SQL*Plus). Por eso los
-- UPDATE llevan "set" al final de la linea anterior.
-- =============================================================================

create or replace procedure prc_auth_registrar (
    p_usuario_id        in number,
    p_resultado         in varchar2,
    p_usuario_intentado in varchar2,
    p_nuevo_hash        in varchar2 default null
) is
    pragma autonomous_transaction;
    c_max_intentos    constant number := 5;
    c_minutos_bloqueo constant number := 15;
    v_reintentos      number;
    v_bloqueado       date;
    v_ip              varchar2(64);
begin
    begin
        v_ip := substr(owa_util.get_cgi_env('REMOTE_ADDR'), 1, 64);
    exception
        when others then
            v_ip := null;  -- fuera de una peticion web no hay CGI env
    end;

    if p_usuario_id is not null then
        begin
            select nvl(reintentos_fallidos, 0), bloqueado_hasta
              into v_reintentos, v_bloqueado
              from usuario
             where usuario_id = p_usuario_id
               for update;

            if p_resultado = 'OK' then
                update usuario set
                       reintentos_fallidos  = 0,
                       bloqueado_hasta      = null,
                       ultimo_intento_login = sysdate,
                       password_hash        = nvl(p_nuevo_hash, password_hash)
                 where usuario_id = p_usuario_id;
            else
                v_reintentos := v_reintentos + 1;
                update usuario set
                       reintentos_fallidos  = v_reintentos,
                       bloqueado_hasta      = case
                           when v_bloqueado is not null then v_bloqueado
                           when v_reintentos >= c_max_intentos
                               then sysdate + c_minutos_bloqueo / 1440
                           else null
                       end,
                       ultimo_intento_login = sysdate
                 where usuario_id = p_usuario_id;
            end if;
        exception
            when no_data_found then
                null;  -- el usuario desaparecio entre autenticar y registrar
        end;
    end if;

    insert into syn_login_log (usuario_intentado, ip, fecha, resultado)
    values (substr(p_usuario_intentado, 1, 100),
            v_ip,
            sysdate,
            p_resultado);

    commit;
end prc_auth_registrar;
/
