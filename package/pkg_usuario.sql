create or replace PACKAGE              pkg_usuario AS

    -- Procedimiento para insertar un nuevo usuario
    PROCEDURE prc_insertar (
        p_usuario_id   OUT NUMBER,
        p_username     IN  VARCHAR2,
        p_email        IN  VARCHAR2,
        p_estado       IN  VARCHAR2,
        p_rol_id       IN  NUMBER,
        p_password     IN  VARCHAR2
    );

    -- Procedimiento para actualizar un usuario existente
    PROCEDURE prc_actualizar (
        p_usuario_id   IN  NUMBER,
        p_username     IN  VARCHAR2,
        p_email        IN  VARCHAR2,
        p_estado       IN  VARCHAR2,
        p_rol_id       IN  NUMBER,
        p_password     IN  VARCHAR2
    );

    -- Procedimiento para eliminar un usuario
    PROCEDURE prc_eliminar (
        p_usuario_id   IN  NUMBER
    );

    -- Orquestador de guardado (Ideal para Oracle APEX: detecta si inserta o actualiza)
    PROCEDURE prc_guardar_usuario (
        p_usuario_id   IN OUT NUMBER,
        p_username     IN  VARCHAR2,
        p_email        IN  VARCHAR2,
        p_estado       IN  VARCHAR2,
        p_rol_id       IN  NUMBER,
        p_password     IN  VARCHAR2
    );

END pkg_usuario;
/