create or replace FUNCTION fn_autenticar_usuario (
    p_username IN VARCHAR2,
    p_password IN VARCHAR2
) RETURN BOOLEAN IS
    v_password_hash VARCHAR2(255);
    v_input_hash    VARCHAR2(255);
    v_estado        VARCHAR2(20);
BEGIN
    -- 1. Buscar usuario
    BEGIN
        SELECT password_hash, estado
          INTO v_password_hash, v_estado
          FROM usuario
         WHERE LOWER(username) = LOWER(p_username);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            APEX_UTIL.SET_CUSTOM_AUTH_STATUS(p_status => 'Usuario o contraseña incorrectos.');
            RETURN FALSE;
    END;

    -- 2. Validar si el usuario está activo
    IF UPPER(v_estado) NOT IN ('ACTIVO', 'A', '1') THEN
        APEX_UTIL.SET_CUSTOM_AUTH_STATUS(
            p_status => 'El usuario no está activo. Por favor, contacta al administrador.'
        );
        RETURN FALSE;
    END IF;

    -- 3. Generar Hash de la contraseña ingresada
    v_input_hash := sypex_hash_password(p_password);

    -- 4. Comparar
    IF v_password_hash = v_input_hash THEN
        RETURN TRUE;
    ELSE
        APEX_UTIL.SET_CUSTOM_AUTH_STATUS(p_status => 'Usuario o contraseña incorrectos.');
        RETURN FALSE;
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        APEX_UTIL.SET_CUSTOM_AUTH_STATUS(p_status => 'Error al procesar la autenticación.');
        RETURN FALSE;
END fn_autenticar_usuario;
/