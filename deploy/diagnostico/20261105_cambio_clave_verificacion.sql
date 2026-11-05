-- Verificacion del cambio de clave obligatorio.
-- Ejecutar: python deploy/conexion/importar_export.py deploy/diagnostico/20261105_cambio_clave_verificacion.sql
-- Los SELECT devuelven filas solo cuando algo FALLA.

alter session set current_schema = WKSP_SYPEXWS;
/

select 'FALLA: prc_post_login no publica F_DEBE_CAMBIAR_CLAVE' as caso from dual
 where not exists (select 1 from all_source
                    where owner='WKSP_SYPEXWS' and name='PRC_POST_LOGIN'
                      and lower(text) like '%f_debe_cambiar_clave%');
/
