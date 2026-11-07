-- =============================================================================
-- tabla/syn_parametros.sql
--
-- Parametros de operacion del sistema (clave/valor). Hoy solo USD_MXN, que se
-- usa para derivar MXN->VES cuando la API de BCV no publica el par.
--
-- Nacio en deploy/migrations/20261104_tasas_bcv_mxn_job.sql. Se movio aqui el
-- 2026-11-07 porque install.sql no lo cargaba y prc_actualizar_tasas_diarias
-- fallaba con ORA-00942 en una instalacion limpia.
-- =============================================================================

create table syn_parametros (
    clave       varchar2(50) constraint pk_syn_parametros primary key,
    valor       number,
    descripcion varchar2(200)
);

insert into syn_parametros (clave, valor, descripcion)
values ('USD_MXN', null, 'Pesos mexicanos por dolar. Se usa para derivar MXN->VES si la API no trae MXN');

commit;
