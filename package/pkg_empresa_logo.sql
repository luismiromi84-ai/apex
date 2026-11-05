create or replace PACKAGE pkg_empresa_logo AS
    -- Logo por empresa cliente: se guarda en EMPRESA_LOGO y se incrusta en los
    -- reportes como data URI, para que el impreso no dependa de una URL.

    c_max_bytes constant number := 2 * 1024 * 1024;   -- 2 MB

    PROCEDURE prc_guardar_logo (
        p_id_empresa IN NUMBER,
        p_imagen     IN BLOB,
        p_nombre     IN VARCHAR2,
        p_mime       IN VARCHAR2,
        p_usuario    IN VARCHAR2 DEFAULT NULL);

    PROCEDURE prc_eliminar_logo (p_id_empresa IN NUMBER);

    -- Devuelve la etiqueta <img> lista para pegar en el HTML, o NULL si la
    -- empresa no tiene logo.
    FUNCTION fn_logo_img (
        p_id_empresa IN NUMBER,
        p_estilo     IN VARCHAR2 DEFAULT NULL) RETURN CLOB;
END pkg_empresa_logo;
/
