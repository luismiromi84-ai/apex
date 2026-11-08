-- =============================================================================
-- 20261108_quitar_fn_empresas_del_usuario.sql
--
-- Borra fn_empresas_del_usuario: se escribio para multiempresa y **nadie la
-- llama** (medido el 2026-11-07: 0 usos en el export, en los packages y en el
-- JavaScript). Decision del dueno: dejar solo lo que se usa.
--
-- Idempotente: si no existe, no hace nada.
--
-- REVERSA: volver a crearla desde deploy/migrations/20261104_validacion_empresa.sql
--          (lineas 35-47) si algun dia se implementa multiempresa.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;
/

declare
    v_n number;
begin
    select count(*) into v_n
      from all_objects
     where owner = 'WKSP_SYPEXWS' and object_name = 'FN_EMPRESAS_DEL_USUARIO'
       and object_type = 'FUNCTION';

    if v_n > 0 then
        execute immediate 'drop function fn_empresas_del_usuario';
        dbms_output.put_line('fn_empresas_del_usuario eliminada');
    else
        dbms_output.put_line('fn_empresas_del_usuario no existe: no se toca');
    end if;
end;
/

-- Validacion: no debe quedar, y no debe haber objetos invalidos por el drop.
select 'FALLA: fn_empresas_del_usuario sigue existiendo' as caso from dual
 where exists (select 1 from all_objects
                where owner = 'WKSP_SYPEXWS' and object_name = 'FN_EMPRESAS_DEL_USUARIO');
/

select 'FALLA: ' || object_name || ' quedo invalido' as caso
  from all_objects
 where owner = 'WKSP_SYPEXWS' and status <> 'VALID'
   and object_type in ('FUNCTION','PROCEDURE','PACKAGE','PACKAGE BODY','TRIGGER','VIEW');
/

commit;
/
