-- =============================================================================
-- 20261123_quitar_fn_tasa_cambio.sql
--
-- Borra fn_tasa_cambio(fecha, moneda). Decision del dueno (2026-11-23).
--
-- Por que: no la usa nadie (medido ese dia: 0 dependencias en
-- ALL_DEPENDENCIES, 0 grants, 0 sinonimos y 0 menciones en las regiones,
-- procesos, acciones dinamicas y LOV de la app) y su semantica es la
-- CONTRARIA de la regla del sistema:
--   * fn_tasa_cambio devuelve un FACTOR A USD y devuelve 1 para USD y para
--     VES/BS.
--   * El sistema guarda BOLIVARES POR UNIDAD de la moneda (fn_tasa_ves):
--     USD->VES ~918, MXN->VES ~48, VES = 1.
-- Ese malentendido ya causo dos bugs (el tipo de cambio 1 de la pagina 7 y el
-- gasto real que convertia 100 Bs en 100 USD). Dejarla viva era dejar el cebo:
-- un nombre que suena correcto y da numeros equivocados.
--
-- Alternativa que se conserva: fn_tasa_ves(fecha, moneda), que es la que usan
-- las paginas 7, 9, 25 y 28, los impresos, el libro y la validacion de la tasa
-- de los documentos (fn_validar_tasa_documento).
--
-- Idempotente: si no existe, no hace nada.
--
-- REVERSA: no hay. Su cuerpo esta en el historial de git
--          (funciones/fn_tasa_cambio.sql) y en
--          instalacion y migracion/SypexSystem_DDL_COMPLETO.sql. Si algun dia
--          hiciera falta un factor a USD, se escribe contra fn_tasa_ves:
--          factor_usd = fn_tasa_ves(fecha, moneda) / fn_tasa_ves(fecha, 'USD').
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;
/

declare
    v_n number;
begin
    select count(*) into v_n
      from all_objects
     where owner = 'WKSP_SYPEXWS' and object_name = 'FN_TASA_CAMBIO'
       and object_type = 'FUNCTION';

    if v_n > 0 then
        execute immediate 'drop function fn_tasa_cambio';
        dbms_output.put_line('fn_tasa_cambio eliminada');
    else
        dbms_output.put_line('fn_tasa_cambio no existe: no se toca');
    end if;
end;
/

-- Validacion: no debe quedar, y no debe haber objetos invalidos por el drop.
select 'FALLA: fn_tasa_cambio sigue existiendo' as caso from dual
 where exists (select 1 from all_objects
                where owner = 'WKSP_SYPEXWS' and object_name = 'FN_TASA_CAMBIO');
/

select 'FALLA: ' || object_name || ' quedo invalido' as caso
  from all_objects
 where owner = 'WKSP_SYPEXWS' and status <> 'VALID'
   and object_type in ('FUNCTION','PROCEDURE','PACKAGE','PACKAGE BODY','TRIGGER','VIEW');
/

commit;
/
