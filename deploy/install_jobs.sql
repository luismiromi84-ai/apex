-- =============================================================================
-- deploy/install_jobs.sql
--
-- Los dos jobs del scheduler que la app necesita. Se incluye desde install.sql
-- (bloque 6) y tambien se puede ejecutar solo sobre una base ya instalada:
--
--   python deploy/conexion/importar_export.py deploy/install_jobs.sql
--
-- Idempotente: hace drop_job (ignorando el error si no existe) y create_job.
--
-- OJO: JOB_ACTUALIZA_TASAS_BCV se crea DESHABILITADO a proposito, igual que en
-- su migracion original. Antes de habilitarlo hay que dar salida HTTP (ACL) al
-- esquema y validar una ejecucion manual:
--   begin prc_job_tasas_bcv; end;
--   /
--   begin dbms_scheduler.enable('JOB_ACTUALIZA_TASAS_BCV'); end;
--   /
-- Si no, el job fallara cada dia y llenara LOG_TASAS_BCV de errores.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Purga diaria de los logs de acceso (90 dias de retencion)
-- -----------------------------------------------------------------------------
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
-- Tasas BCV (USD, EUR, MXN) diarias a las 18:00 de Caracas. DESHABILITADO.
-- -----------------------------------------------------------------------------
begin
    dbms_scheduler.drop_job('JOB_ACTUALIZA_TASAS_BCV', force => true);
exception
    when others then null;
end;
/

begin
    dbms_scheduler.create_job(
        job_name        => 'JOB_ACTUALIZA_TASAS_BCV',
        job_type        => 'STORED_PROCEDURE',
        job_action      => 'PRC_JOB_TASAS_BCV',
        start_date      => systimestamp at time zone 'America/Caracas',
        -- OJO: NO admite BYTIMEZONE en esta version (ORA-27412, medido el
        -- 2026-11-07). La hora se ancla con la zona del start_date: 18:00 de
        -- Caracas. La definicion que funciona en produccion es esta.
        repeat_interval => 'FREQ=DAILY;BYHOUR=18;BYMINUTE=0;BYSECOND=0',
        enabled         => false,
        comments        => 'Tasas BCV (USD, EUR, MXN) diarias a las 18:00 de Caracas, 3 intentos');
end;
/

prompt JOB_PURGA_LOGS creado y habilitado.
prompt JOB_ACTUALIZA_TASAS_BCV creado DESHABILITADO: ver la cabecera de este script.

commit;
