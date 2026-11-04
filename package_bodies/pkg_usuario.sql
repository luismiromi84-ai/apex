create or replace PACKAGE BODY              pkg_usuario AS

    --------------------------------------------------------------------------------
    -- 1. IMPLEMENTACIÓN DE INSERCIÓN
    --------------------------------------------------------------------------------
    PROCEDURE prc_insertar (
        p_usuario_id   OUT NUMBER,
        p_username     IN  VARCHAR2,
        p_email        IN  VARCHAR2,
        p_estado       IN  VARCHAR2,
        p_rol_id       IN  NUMBER,
        p_password     IN  VARCHAR2
    ) IS
    BEGIN
        INSERT INTO wksp_sypexws.usuario (
            username,
            email,
            estado,
            rol_id,
            password_hash,
            fecha_creacion
        ) VALUES (
            p_username,
            p_email,
            NVL(p_estado, 'ACTIVO'),
            p_rol_id,
            sypex_hash_password(p_password),
            SYSDATE
        ) RETURN usuario_id INTO p_usuario_id;
    END prc_insertar;

    --------------------------------------------------------------------------------
    -- 2. IMPLEMENTACIÓN DE ACTUALIZACIÓN
    --------------------------------------------------------------------------------
    PROCEDURE prc_actualizar (
        p_usuario_id   IN  NUMBER,
        p_username     IN  VARCHAR2,
        p_email        IN  VARCHAR2,
        p_estado       IN  VARCHAR2,
        p_rol_id       IN  NUMBER,
        p_password     IN  VARCHAR2
    ) IS
    BEGIN
        UPDATE wksp_sypexws.usuario
           SET username      = p_username,
               email         = p_email,
               estado        = p_estado,
               rol_id        = p_rol_id,
               password_hash = CASE 
                                   WHEN p_password IS NOT NULL AND TRIM(p_password) IS NOT NULL 
                                   THEN sypex_hash_password(p_password)
                                   ELSE password_hash
                               END
         WHERE usuario_id    = p_usuario_id;
    END prc_actualizar;

    --------------------------------------------------------------------------------
    -- 3. IMPLEMENTACIÓN DE ELIMINACIÓN
    --------------------------------------------------------------------------------
    PROCEDURE prc_eliminar (
        p_usuario_id   IN  NUMBER
    ) IS
    BEGIN
        DELETE FROM wksp_sypexws.usuario
         WHERE usuario_id = p_usuario_id;
    END prc_eliminar;

    --------------------------------------------------------------------------------
    -- 4. ORQUESTADOR DE GUARDADO
    --------------------------------------------------------------------------------
    PROCEDURE prc_guardar_usuario (
        p_usuario_id   IN OUT NUMBER,
        p_username     IN  VARCHAR2,
        p_email        IN  VARCHAR2,
        p_estado       IN  VARCHAR2,
        p_rol_id       IN  NUMBER,
        p_password     IN  VARCHAR2
    ) IS
        v_existe NUMBER := 0;
    BEGIN
        -- Verificar si el usuario ya existe en la base de datos
        IF p_usuario_id IS NOT NULL AND p_usuario_id > 0 THEN
            SELECT COUNT(1)
              INTO v_existe
              FROM wksp_sypexws.usuario
             WHERE usuario_id = p_usuario_id;
        END IF;

        IF v_existe > 0 THEN
            -- Actualizar registro existente
            prc_actualizar(
                p_usuario_id => p_usuario_id,
                p_username   => p_username,
                p_email      => p_email,
                p_estado     => p_estado,
                p_rol_id     => p_rol_id,
                p_password   => p_password
            );
        ELSE
            -- Insertar nuevo registro
            p_usuario_id := NULL;
            prc_insertar(
                p_usuario_id => p_usuario_id,
                p_username   => p_username,
                p_email      => p_email,
                p_estado     => p_estado,
                p_rol_id     => p_rol_id,
                p_password   => p_password
            );
        END IF;
    END prc_guardar_usuario;

END pkg_usuario;
/