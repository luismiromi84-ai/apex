create or replace PACKAGE pkg_factura_detalle IS

    -- Procedimiento para guardar, actualizar o insertar el detalle
    PROCEDURE guardar_detalle (
        p_id_factura           IN NUMBER,
        p_id_detalle           IN OUT NUMBER,
        p_id_producto          IN VARCHAR2,
        p_id_impuesto          IN VARCHAR2,
        p_cantidad             IN VARCHAR2,
        p_precio_unitario      IN VARCHAR2,
        p_porc_descuento       IN VARCHAR2,
        p_monto_descuento      IN VARCHAR2,
        p_porc_impuesto        IN VARCHAR2,
        p_monto_impuesto       IN VARCHAR2,
        p_subtotal_linea       IN VARCHAR2,
        p_monto_total_linea    IN VARCHAR2,
        p_codigo_producto      IN VARCHAR2,
        p_descripcion          IN VARCHAR2,
        p_usuario              IN VARCHAR2
    );

    -- Procedimiento para eliminar el detalle
    PROCEDURE eliminar_detalle (
        p_id_factura           IN NUMBER,
        p_id_detalle           IN NUMBER
    );

END pkg_factura_detalle;
/