-- =============================================================================
-- 20261107_quitar_items_f_no_usados.sql
--
-- Objetivo: dejar de publicar cuatro items de aplicacion que nadie lee.
--
-- Defecto medido el 2026-11-07: prc_post_login escribia F_ID_EMPRESA,
-- F_NOMBRE_EMPRESA, F_ID_ROL y F_NOMBRE_ROL en cada login, y el resto de la app
-- no los leia NUNCA (0 lecturas en pagina_apex/f100.sql fuera de su propia
-- declaracion, 0 en packages, funciones, JavaScript y HTML). La empresa y el rol
-- se resuelven por pagina con los items Pn_ID_EMPRESA y las funciones
-- fn_usuario_empresa_valida / fn_tiene_rol.
--
-- Por que no se dejan "preparados" para multiempresa: se escriben solo en el
-- login y en multiempresa la empresa activa cambia DURANTE la sesion, asi que
-- ese valor congelado es el sitio equivocado; ademas su significado cambiaria en
-- silencio (de "la unica empresa del usuario" a "la empresa seleccionada"), que
-- es peor que no tenerlos. El trabajo real de multiempresa son la tabla n:m y
-- los 14 filtros por empresa, no estos items.
--
-- Que hace:
--   1. Recompila prc_post_login sin las cuatro llamadas a set_session_state.
--      Se conservan los JOIN a EMPRESAS y SYN_ROLES a proposito: son los que
--      detectan la cuenta sin empresa o sin rol y la cortan con -20013.
--   2. Recompila el esquema y valida que no quede nada invalido.
--
-- Los items en si los elimina el import del export (delete_application +
-- create_application). En APEX 26.1 no hay apex_util.delete_flow_item, asi que
-- este script no los borra de la definicion: hasta que se reimporte el export
-- siguen declarados, pero ya nadie los escribe ni los lee (inofensivo). El
-- ultimo SELECT de este script los lista solo como constancia.
--
-- Responsable: dueno del esquema (WKSP_SYPEXWS) o ADMIN.
-- Base: Sypex_SQL (GFD7E2575D251AE_SYPEXSQL).
--
-- Idempotente: recompilar el mismo procedimiento no cambia nada.
--
-- Ejecutar:
--   python deploy/conexion/importar_export.py deploy/migrations/20261107_quitar_items_f_no_usados.sql
--
-- REVERSA:
--   Volver a la version anterior de prc_post_login (git show 87d16a9:procedimientos/prc_post_login.sql)
--   y recompilarla, y reimportar el export anterior. No hay datos que revertir.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;
/

-- -----------------------------------------------------------------------------
-- Validacion ANTES: si el procedimiento todavia escribe los items, devuelve la
-- fila que lo dice (RED). Despues, 0 filas.
-- -----------------------------------------------------------------------------
select 'FALLA: prc_post_login todavia escribe ' || regexp_substr(upper(text), 'F_(ID|NOMBRE)_[A-Z_]+') as caso
  from all_source
 where owner = 'WKSP_SYPEXWS'
   and name = 'PRC_POST_LOGIN'
   and type = 'PROCEDURE'
   and regexp_like(upper(text), 'F_(ID_EMPRESA|ID_ROL|NOMBRE_EMPRESA|NOMBRE_ROL)')
 group by regexp_substr(upper(text), 'F_(ID|NOMBRE)_[A-Z_]+');
/

-- -----------------------------------------------------------------------------
-- Avance: el procedimiento, sin los cuatro items
-- -----------------------------------------------------------------------------
create or replace procedure prc_post_login is
    v_debe_cambiar    usuario.debe_cambiar_clave%type;
begin
    select nvl(u.debe_cambiar_clave, 'N')
      into v_debe_cambiar
      from usuario u
      join empresas e on e.id_empresa = u.id_empresa
      join syn_roles r on r.id_rol = u.rol_id
     where upper(u.username) = upper(v('APP_USER'))
       and u.estado in ('ACTIVO', 'A', '1');

    apex_util.set_session_state('F_DEBE_CAMBIAR_CLAVE', v_debe_cambiar);
exception
    when no_data_found then
        begin
            prc_auth_registrar(p_usuario_id        => null,
                               p_resultado         => 'SIN_EMPRESA',
                               p_usuario_intentado => v('APP_USER'));
        exception
            when others then null;
        end;

        raise_application_error(-20013,
            'Tu cuenta no tiene empresa o rol asignado. Contacta al administrador.');
end prc_post_login;
/

-- -----------------------------------------------------------------------------
-- Recompilar el esquema (por si el CREATE OR REPLACE invalido dependientes)
-- -----------------------------------------------------------------------------
begin
    dbms_utility.compile_schema(schema => 'WKSP_SYPEXWS', compile_all => false);
end;
/

-- -----------------------------------------------------------------------------
-- Validacion DESPUES: los cuatro SELECT deben devolver CERO filas (GREEN).
-- -----------------------------------------------------------------------------
select 'FALLA: prc_post_login sigue escribiendo items de empresa o rol' as caso
  from all_source
 where owner = 'WKSP_SYPEXWS'
   and name = 'PRC_POST_LOGIN'
   and type = 'PROCEDURE'
   and regexp_like(upper(text), 'F_(ID_EMPRESA|ID_ROL|NOMBRE_EMPRESA|NOMBRE_ROL)');
/

select 'FALLA: prc_post_login ya no publica F_DEBE_CAMBIAR_CLAVE' as caso
  from dual
 where not exists (select 1 from all_source
                    where owner = 'WKSP_SYPEXWS'
                      and name = 'PRC_POST_LOGIN'
                      and type = 'PROCEDURE'
                      and lower(text) like '%f_debe_cambiar_clave%');
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

-- Constancia (no es validacion): que items de aplicacion siguen declarados.
-- Tras reimportar el export debe quedar solo F_DEBE_CAMBIAR_CLAVE.
select item_name
  from apex_application_items
 where application_id = 100
 order by item_name;
/

commit;
/
