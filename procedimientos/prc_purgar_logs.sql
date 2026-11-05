-- =============================================================================
-- prc_purgar_logs.sql
--
-- Recorta las tablas de auditoria de acceso, que hoy crecen sin limite:
--   SYN_LOGIN_LOG           (un registro por intento de login)
--   SYN_RESET_PASSWORD_LOG  (un registro por intento de recuperacion)
--
-- No hace COMMIT: lo decide quien llama. El job diario lo deja el scheduler.
--
-- p_dias es la retencion en dias. Se exige >= 1 a proposito: con 0 o nulo se
-- borraria todo el historial y no hay forma de recuperarlo.
-- =============================================================================

create or replace procedure prc_purgar_logs (
    p_dias            in  number  default 90,
    p_borrados_login  out number,
    p_borrados_reset  out number
) is
begin
    if p_dias is null or p_dias < 1 then
        raise_application_error(-20030,
            'La retencion debe ser de al menos 1 dia.');
    end if;

    delete from syn_login_log
     where fecha < sysdate - p_dias;
    p_borrados_login := sql%rowcount;

    delete from syn_reset_password_log
     where fecha < sysdate - p_dias;
    p_borrados_reset := sql%rowcount;
end prc_purgar_logs;
/
