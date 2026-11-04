-- =============================================================================
-- prc_log_reset_password.sql
--
-- Registra un intento de recuperacion de contrasena. Transaccion autonoma: el
-- proceso de la pagina 14 hace raise_application_error cuando los datos no
-- coinciden, y sin PRAGMA AUTONOMOUS_TRANSACTION ese rollback se llevaria el
-- registro del intento fallido.
--
-- Nunca propaga errores: el registro es auxiliar y no debe romper el flujo.
-- =============================================================================

create or replace procedure prc_log_reset_password (
    p_usuario   in varchar2,
    p_correo    in varchar2,
    p_ip        in varchar2 default null,
    p_resultado in varchar2
) is
    pragma autonomous_transaction;
begin
    insert into syn_reset_password_log (
        usuario_intentado, correo_intentado, ip, fecha, resultado
    ) values (
        substr(p_usuario, 1, 100),
        substr(p_correo, 1, 255),
        substr(p_ip, 1, 64),
        sysdate,
        p_resultado
    );
    commit;
exception
    when others then
        -- El log no debe impedir el cambio de contrasena ni ocultar el error real.
        rollback;
end prc_log_reset_password;
/
