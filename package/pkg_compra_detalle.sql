-- =============================================================================
-- package/pkg_compra_detalle.sql
--
-- Lineas de la factura de compra. El paquete CALCULA los importes: la pantalla
-- manda cantidad, precio, descuento y alicuota, y aqui se derivan subtotal,
-- IVA, total y sus equivalentes en bolivares. Asi no hay dos sitios que puedan
-- calcular distinto (fue el bug de los porcentajes de facturacion).
--
-- SUBTOTAL_LINEA es NETO de descuento, igual que en FACTURAS_DET.
-- =============================================================================

create or replace package pkg_compra_detalle as

    procedure guardar_detalle(
        p_id_detalle           in out number,
        p_id_compra            in number,
        p_num_linea            in number,
        p_id_producto_servicio in number,
        p_descripcion          in varchar2,
        p_cantidad             in number,
        p_precio_unitario      in number,
        p_porcentaje_descuento in number,
        p_monto_descuento      in number,
        p_id_impuesto          in number,
        p_porcentaje_impuesto  in number,
        p_usuario              in varchar2);

    procedure eliminar_detalle(p_id_detalle in number, p_usuario in varchar2);

    procedure copiar_desde_compra(p_id_compra in number, p_id_compra_origen in number,
                                  p_usuario in varchar2);

end pkg_compra_detalle;
/
