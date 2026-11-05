-- =============================================================================
-- 20261105_cambio_clave_obligatorio.sql
--
-- Objetivo: marcar en USUARIO las cuentas cuya clave la eligio un administrador
--           (alta desde la pagina 2, alta/reseteo desde la pagina 4), para
--           obligar a cambiarla en el primer login.
--
-- Responsable: dueno del esquema (WKSP_SYPEXWS) o ADMIN con ALTER ANY TABLE.
-- Base: Sypex_SQL (GFD7E2575D251AE_SYPEXSQL).
--
-- Afecta a: USUARIO (solo metadatos: una columna con DEFAULT 'N' NOT NULL y su
--           CHECK) y, a continuacion, recompila el esquema. No toca datos: las
--           14 filas existentes quedan en 'N' por el DEFAULT (medido el
--           2026-11-05 antes y despues).
--
-- OJO (medido el 2026-11-05): el `alter table ... add column` deja INVALIDOS los
--     objetos que dependen de USUARIO (5 programas y 3 package bodies, entre
--     ellos FN_AUTENTICAR_USUARIO, PRC_AUTH_REGISTRAR y PRC_POST_LOGIN) y NO
--     deja rastro en ALL_ERRORS: son invalidaciones por dependencia, no errores
--     de compilacion. Si no se recompilan, la app no puede autenticar. Por eso
--     el script termina con DBMS_UTILITY.COMPILE_SCHEMA y valida que no quede
--     ningun objeto fuera de VALID ni ningun error de compilacion.
--     Mismo sintoma ya anotado en `deploy/migrations/20261104_auth_propia.sql`.
--
-- Idempotente: la columna y el CHECK solo se crean si no existen, asi que
--     reejecutar el script completo no falla con ORA-01430 (columna ya existe)
--     ni con ORA-02264 (nombre de constraint ya usado).
--
-- Ejecutar:
--   python deploy/conexion/importar_export.py deploy/migrations/20261105_cambio_clave_obligatorio.sql
--
-- REVERSA:
--   alter table usuario drop column debe_cambiar_clave;
--   (el DROP COLUMN se lleva por delante el CHECK ck_usuario_debe_cambiar;
--    no hay otra tabla ni indice que dependa de la columna)
--   Despues del DROP, volver a ejecutar
--   dbms_utility.compile_schema('WKSP_SYPEXWS', false) por el mismo motivo.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;
/

-- -----------------------------------------------------------------------------
-- Validacion ANTES: si la columna no existe, devuelve la fila que lo dice.
-- En una base sin la migracion devuelve 1 fila (RED); despues, 0.
-- -----------------------------------------------------------------------------
select 'FALLA: falta DEBE_CAMBIAR_CLAVE' as caso from dual
 where not exists (select 1 from all_tab_columns
                    where owner='WKSP_SYPEXWS' and table_name='USUARIO'
                      and column_name='DEBE_CAMBIAR_CLAVE');
/

-- -----------------------------------------------------------------------------
-- Avance 1: la columna, solo si falta
-- -----------------------------------------------------------------------------
declare
    v_existe number;
begin
    select count(*) into v_existe
      from all_tab_columns
     where owner = 'WKSP_SYPEXWS'
       and table_name = 'USUARIO'
       and column_name = 'DEBE_CAMBIAR_CLAVE';

    if v_existe = 0 then
        execute immediate 'alter table usuario add (debe_cambiar_clave char(1) default ''N'' not null enable)';
        dbms_output.put_line('USUARIO.DEBE_CAMBIAR_CLAVE creada');
    else
        dbms_output.put_line('USUARIO.DEBE_CAMBIAR_CLAVE ya existe: no se toca');
    end if;
end;
/

-- -----------------------------------------------------------------------------
-- Avance 2: el CHECK, solo si falta
-- -----------------------------------------------------------------------------
declare
    v_existe number;
begin
    select count(*) into v_existe
      from all_constraints
     where owner = 'WKSP_SYPEXWS'
       and table_name = 'USUARIO'
       and constraint_name = 'CK_USUARIO_DEBE_CAMBIAR';

    if v_existe = 0 then
        execute immediate 'alter table usuario add constraint ck_usuario_debe_cambiar check (debe_cambiar_clave in (''S'',''N'')) enable';
        dbms_output.put_line('CK_USUARIO_DEBE_CAMBIAR creado');
    else
        dbms_output.put_line('CK_USUARIO_DEBE_CAMBIAR ya existe: no se toca');
    end if;
end;
/

-- -----------------------------------------------------------------------------
-- Avance 3: recompilar el esquema. El ALTER de arriba invalida los dependientes
-- de USUARIO y sin esto la app se queda sin autenticacion hasta que alguien
-- recompile a mano.
-- -----------------------------------------------------------------------------
begin
    dbms_utility.compile_schema(schema => 'WKSP_SYPEXWS', compile_all => false);
end;
/

-- -----------------------------------------------------------------------------
-- Validacion DESPUES: los cinco select deben devolver CERO filas (GREEN).
-- -----------------------------------------------------------------------------
select 'FALLA: columna ausente' as caso from dual
 where not exists (select 1 from all_tab_columns
                    where owner='WKSP_SYPEXWS' and table_name='USUARIO'
                      and column_name='DEBE_CAMBIAR_CLAVE');
/

select 'FALLA: quedan nulos' as caso from dual
 where exists (select 1 from usuario where debe_cambiar_clave is null);
/

select 'FALLA: valores raros' as caso from dual
 where exists (select 1 from usuario where debe_cambiar_clave not in ('S','N'));
/

select 'FALLA: ' || object_name || ' quedo invalido' as caso
  from all_objects
 where owner = 'WKSP_SYPEXWS' and status <> 'VALID'
   and object_type in ('FUNCTION','PROCEDURE','PACKAGE','PACKAGE BODY','TRIGGER','VIEW');
/

select 'FALLA: errores de compilacion en ' || name as caso
  from all_errors where owner = 'WKSP_SYPEXWS'
 group by name;
/

-- Constancia de como quedo la columna y el CHECK (no es una validacion).
select column_name, data_type, data_length, nullable, data_default
  from all_tab_columns
 where owner = 'WKSP_SYPEXWS' and table_name = 'USUARIO'
   and column_name = 'DEBE_CAMBIAR_CLAVE';
/

select constraint_name, constraint_type, status, validated, search_condition
  from all_constraints
 where owner = 'WKSP_SYPEXWS' and table_name = 'USUARIO'
   and constraint_name = 'CK_USUARIO_DEBE_CAMBIAR';
/

commit;
/
