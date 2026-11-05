-- =============================================================================
-- 20261104_drop_fn_autenticar_usuario.sql
--
-- Objetivo: retirar FN_AUTENTICAR_USUARIO del esquema WKSP_SYPEXWS.
-- Responsable: dueño del proyecto (decision tomada el 2026-11-04).
--
-- Contexto: el commit d35456a («PRUEBA A1») cambio el esquema de autenticacion
-- de la app 100 de NATIVE_CUSTOM a Oracle APEX Accounts (NATIVE_APEX_ACCOUNTS).
-- Desde entonces:
--   * APEX_APPLICATION_AUTH.VERIFICATION_FUNCTION esta vacia,
--   * pagina_apex/f100.sql no menciona fn_autenticar_usuario (0 apariciones),
--   * ALL_DEPENDENCIES no registra ningun consumidor.
-- El 2026-11-05 02:02:52 se verifico en APEX_WORKSPACE_ACTIVITY_LOG que el
-- login de la app funciona con la cuenta APEX `LUIS`. Decision: PRUEBA A1 se
-- queda como autenticacion definitiva y la funcion custom se retira.
--
-- Precondiciones (verificar antes de ejecutar):
--   1. El esquema de auth vigente de la app 100 es APEX Accounts:
--        select scheme_type_code from apex_application_auth
--         where application_id = 100 and is_current_authentication = 'Y';
--      debe devolver NATIVE_APEX_ACCOUNTS.
--   2. Una cuenta APEX del workspace entra a la app (probado con LUIS).
--
-- ATENCION: si algun dia se revierte A1 hay que recrear esta funcion ANTES de
-- reimportar pagina_apex/f100.sql, o el login falla con ORA-00904. El fuente
-- completo esta en la seccion REVERSA de este archivo.
--
-- No toca datos. No cambia el comportamiento de la app en ejecucion.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;

-- -----------------------------------------------------------------------------
-- Avance
-- -----------------------------------------------------------------------------
drop function fn_autenticar_usuario;

-- -----------------------------------------------------------------------------
-- Validacion despues del avance
-- -----------------------------------------------------------------------------
-- Debe devolver 0 filas.
select count(*) as objetos_restantes
  from user_objects
 where object_name = 'FN_AUTENTICAR_USUARIO';

-- Debe devolver NATIVE_APEX_ACCOUNTS y verification_function vacia.
select scheme_type_code, verification_function
  from apex_application_auth
 where application_id = 100
   and is_current_authentication = 'Y';

-- La app sigue con 15 paginas y sin objetos invalidos.
select count(*) as paginas from apex_application_pages where application_id = 100;
select object_name, object_type, status from user_objects where status <> 'VALID';

-- -----------------------------------------------------------------------------
-- Reversa
-- -----------------------------------------------------------------------------
-- Ejecutar como WKSP_SYPEXWS, y solo antes de reimportar un f100.sql que use
-- NATIVE_CUSTOM:
--
-- create or replace FUNCTION fn_autenticar_usuario (
--     p_username IN VARCHAR2,
--     p_password IN VARCHAR2
-- ) RETURN BOOLEAN IS
--     v_password_hash VARCHAR2(255);
--     v_input_hash    VARCHAR2(255);
--     v_estado        VARCHAR2(20);
-- BEGIN
--     -- 1. Buscar usuario
--     BEGIN
--         SELECT password_hash, estado
--           INTO v_password_hash, v_estado
--           FROM usuario
--          WHERE LOWER(username) = LOWER(p_username);
--     EXCEPTION
--         WHEN NO_DATA_FOUND THEN
--             APEX_UTIL.SET_CUSTOM_AUTH_STATUS(p_status => 'Usuario o contraseña incorrectos.');
--             RETURN FALSE;
--     END;
--
--     -- 2. Validar si el usuario está activo
--     IF UPPER(v_estado) NOT IN ('ACTIVO', 'A', '1') THEN
--         APEX_UTIL.SET_CUSTOM_AUTH_STATUS(
--             p_status => 'El usuario no está activo. Por favor, contacta al administrador.'
--         );
--         RETURN FALSE;
--     END IF;
--
--     -- 3. Generar Hash de la contraseña ingresada
--     v_input_hash := sypex_hash_password(p_password);
--
--     -- 4. Comparar
--     IF v_password_hash = v_input_hash THEN
--         RETURN TRUE;
--     ELSE
--         APEX_UTIL.SET_CUSTOM_AUTH_STATUS(p_status => 'Usuario o contraseña incorrectos.');
--         RETURN FALSE;
--     END IF;
--
-- EXCEPTION
--     WHEN OTHERS THEN
--         APEX_UTIL.SET_CUSTOM_AUTH_STATUS(p_status => 'Error al procesar la autenticación.');
--         RETURN FALSE;
-- END fn_autenticar_usuario;
-- /
--
-- Y despues volver a agregar la linea en deploy/install.sql y restaurar
-- funciones/fn_autenticar_usuario.sql desde el historial de git (commit db6a745
-- o anterior).
