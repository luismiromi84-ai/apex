create or replace PACKAGE pkg_presupuesto_detalle IS

    -- Procedimiento para guardar (insertar o actualizar) el detalle y recalcular la cabecera
    PROCEDURE guardar_detalle (
        p_id_presupuesto         IN NUMBER,
        p_id_detalle             IN OUT NUMBER,
        p_id_producto_servicio   IN VARCHAR2,
        p_cantidad               IN VARCHAR2,
        p_precio_unitario        IN VARCHAR2,
        p_id_impuesto            IN VARCHAR2,
        p_porcentaje_descuento   IN VARCHAR2,
        p_monto_descuento        IN VARCHAR2,
        p_porcentaje_impuesto    IN VARCHAR2,
        p_subtotal_linea         IN VARCHAR2,
        p_descripcion            IN VARCHAR2
    );

    -- Procedimiento para eliminar el detalle y recalcular la cabecera
    PROCEDURE eliminar_detalle (
        p_id_presupuesto         IN NUMBER,
        p_id_detalle             IN NUMBER
    );

END pkg_presupuesto_detalle;
/