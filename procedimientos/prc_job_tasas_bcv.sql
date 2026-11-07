-- =============================================================================
-- procedimientos/prc_job_tasas_bcv.sql
--
-- Wrapper del job de tasas: es el dueno de la transaccion y de los reintentos.
-- prc_actualizar_tasas_diarias NO hace COMMIT (a proposito): lo hace este
-- procedimiento, que reintenta 3 veces y deja constancia en LOG_TASAS_BCV.
--
-- Este archivo no existia en el repo: el procedimiento solo vivia dentro de
-- deploy/migrations/20261104_tasas_bcv_mxn_job.sql, asi que una instalacion
-- limpia no lo creaba y el job no tenia que ejecutar. Creado el 2026-11-07.
--
-- Requiere salida HTTP (ACL) para apex_web_service: ver deploy/MANUAL_DESPLIEGUE.md.
-- =============================================================================

create or replace procedure prc_job_tasas_bcv is
    c_intentos constant number := 3;
    v_error    varchar2(400);
begin
    for i in 1 .. c_intentos loop
        begin
            prc_actualizar_tasas_diarias;
            commit;
            insert into log_tasas_bcv (origen, resultado, monedas, mensaje)
            values ('JOB', 'OK', 'USD, EUR, MXN', 'intento ' || i || ' correcto');
            commit;
            return;
        exception
            when others then
                rollback;
                v_error := substr(sqlerrm, 1, 400);
                insert into log_tasas_bcv (origen, resultado, monedas, mensaje)
                values ('JOB', 'REINTENTO', null, 'intento ' || i || ': ' || v_error);
                commit;
        end;
    end loop;

    insert into log_tasas_bcv (origen, resultado, mensaje)
    values ('JOB', 'ERROR', 'agotados ' || c_intentos || ' intentos: ' || v_error);
    commit;
end prc_job_tasas_bcv;
/
