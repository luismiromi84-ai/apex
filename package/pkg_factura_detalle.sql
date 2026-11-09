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

    -- Reconstruye todo el detalle de una factura a partir de un presupuesto,
    -- aplicando el factor de la tasa. Lo usa PKG_FACTURACION al facturar, para
    -- que TODO lo que escribe en FACTURAS_DET pase por este package.
    PROCEDURE reemplazar_desde_presupuesto (
        p_id_factura     IN NUMBER,
        p_id_presupuesto IN NUMBER,
        p_factor         IN NUMBER,
        p_tasa_cambio    IN NUMBER,
        p_usuario        IN VARCHAR2
    );

    -- Copia TODAS las lineas de una factura a una nota de credito o debito
    -- (nota completa). Para una nota parcial se agregan las lineas a mano.
    -- Falla si la nota ya tiene lineas: no duplica.
    PROCEDURE copiar_desde_factura (
        p_id_factura        IN NUMBER,
        p_id_factura_origen IN NUMBER,
        p_usuario           IN VARCHAR2
    );

END pkg_factura_detalle;
/