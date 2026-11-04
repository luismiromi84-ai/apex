create or replace PROCEDURE prc_post_login IS
    v_id_empresa     usuario.id_empresa%TYPE;
    v_nombre_empresa empresas.nombre_empresa%TYPE;
    v_id_rol         usuario.rol_id%TYPE;
    v_nombre_rol     syn_roles.nombre_rol%TYPE;
BEGIN
    -- Obtiene el usuario actual leyendo la sesión de APEX mediante v('APP_USER')
    SELECT u.id_empresa,
           e.nombre_empresa,
           u.rol_id,
           r.nombre_rol
      INTO v_id_empresa,
           v_nombre_empresa,
           v_id_rol,
           v_nombre_rol
      FROM usuario u
      JOIN empresas e ON e.id_empresa = u.id_empresa
      JOIN syn_roles r    ON r.id_rol     = u.rol_id
     WHERE UPPER(u.username) = UPPER(v('APP_USER'))
       AND u.estado = 'ACTIVO';

    -- Asigna el valor a los Application Items de APEX
    apex_util.set_session_state('F_ID_EMPRESA', v_id_empresa);
    apex_util.set_session_state('F_NOMBRE_EMPRESA', v_nombre_empresa);
    apex_util.set_session_state('F_ID_ROL', v_id_rol);
    apex_util.set_session_state('F_NOMBRE_ROL', v_nombre_rol);
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        NULL;
END prc_post_login;
/