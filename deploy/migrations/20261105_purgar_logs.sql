-- =============================================================================
-- 20261105_purgar_logs.sql
--
-- Objetivo: que las tablas de auditoria de acceso dejen de crecer sin limite.
--           Medido el 2026-11-05: SYN_LOGIN_LOG tenia 53 filas de un solo dia y
--           SYN_RESET_PASSWORD_LOG 0; ninguna de las dos tiene purga.
--
-- Que hace:
--   1. Crea PRC_PURGAR_LOGS(p_dias => 90), que borra de las dos tablas lo mas
--      antiguo que la retencion. Exige p_dias >= 1.
--   2. Programa JOB_PURGA_LOGS, diario a las 03:00.
--
-- Afecta a: solo procedimiento nuevo y un job. No toca tablas ni datos ahora
--           mismo (la primera purga borrara lo que tenga mas de 90 dias; hoy
--           no hay nada tan viejo).
--
-- Idempotente: el procedimiento se recrea y el job se elimina antes de crearlo.
--
-- Ejecutar:
--   python deploy/conexion/importar_export.py deploy/migrations/20261105_purgar_logs.sql
--
-- REVERSA:
--   begin dbms_scheduler.drop_job('JOB_PURGA_LOGS'); end;
--   drop procedure prc_purgar_logs;
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;
/

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

begin
    dbms_scheduler.drop_job('JOB_PURGA_LOGS', force => true);
exception
    when others then null;
end;
/

begin
    dbms_scheduler.create_job(
        job_name        => 'JOB_PURGA_LOGS',
        job_type        => 'PLSQL_BLOCK',
        job_action      => 'declare v_l number; v_r number; begin prc_purgar_logs(90, v_l, v_r); commit; end;',
        start_date      => trunc(sysdate) + 1 + 3/24,
        repeat_interval => 'FREQ=DAILY;BYHOUR=3;BYMINUTE=0;BYSECOND=0',
        enabled         => true,
        comments        => 'Borra los logs de acceso con mas de 90 dias.');
end;
/

-- -----------------------------------------------------------------------------
-- Validaciones: las tres deben devolver 0 filas
-- -----------------------------------------------------------------------------
select 'FALLA: falta PRC_PURGAR_LOGS' as caso from dual
 where not exists (select 1 from all_objects
                    where owner='WKSP_SYPEXWS' and object_name='PRC_PURGAR_LOGS'
                      and status='VALID');
/

select 'FALLA: falta el job JOB_PURGA_LOGS o esta parado' as caso from dual
 where not exists (select 1 from all_scheduler_jobs
                    where owner='WKSP_SYPEXWS' and job_name='JOB_PURGA_LOGS'
                      and enabled='TRUE');
/

select 'FALLA: errores de compilacion' as caso
  from all_errors where owner='WKSP_SYPEXWS';
/
