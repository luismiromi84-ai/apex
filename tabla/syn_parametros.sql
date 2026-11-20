-- =============================================================================
-- tabla/syn_parametros.sql
--
-- Parametros de operacion del sistema (clave/valor).
--   USD_MXN  se usa para derivar MXN->VES cuando la API de BCV no publica el par.
--   UT_ISLR  unidad tributaria con la que se calcula el sustraendo del ISLR; el
--            sustraendo de cada concepto esta en UT y se lleva a bolivares con
--            este valor. El dueño la fija en 43,00 Bs (G.O. 43.140, 2025).
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

insert into syn_parametros (clave, valor, descripcion)
values ('UT_ISLR', 43, 'Unidad Tributaria del ISLR en bolivares (43,00 desde 2025, G.O. 43.140)');

commit;
