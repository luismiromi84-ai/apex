-- =============================================================================
-- package/pkg_compras.sql
--
-- Cabecera de las facturas de compra: alta/edicion en BORRADOR, registro (que
-- cierra el documento y emite el comprobante) y anulacion.
--
-- Codigos de error:
--   -20003 empresa que no es del usuario
--   -20080 folio del proveedor repetido en la misma empresa
--   -20082 porcentaje de retencion fuera de 0..100
--   -20083 la compra no esta en BORRADOR (ya registrada o anulada)
--   -20084 proveedor de otra empresa
--   -20085 sin lineas (o la compra no existe)
--   -20087 datos obligatorios incompletos
--
-- CONCEPTO DE ISLR (p_id_concepto_islr), con CENTINELA: un mismo numero no puede
-- significar a la vez "borralo" y "no lo mande", y confundirlos deja el comprobante
-- de ISLR sin emitir sin que nadie se entere.
--   -1         NO SE ENVIO (es el DEFECTO). En el ALTA se HEREDA del proveedor
--              (PROVEEDORES.ID_CONCEPTO_ISLR); en la ACTUALIZACION se CONSERVA el
--              que ya tenia. Es lo que impide que guardar un borrador desde una
--              pantalla que no manda el item borre el concepto.
--    0 o nulo  sin concepto: se guarda NULL. La pantalla manda 0 cuando el usuario
--              elige "sin concepto"; nulo tambien borra al actualizar (en el alta,
--              nulo se trata como -1 y hereda).
--   otro       ese concepto (id de ISLR_CONCEPTOS).
-- La emision del comprobante de ISLR lee COMPRAS.ID_CONCEPTO_ISLR.
-- =============================================================================

create or replace package pkg_compras as

    procedure prc_guardar_compra(
        p_id_compra            in out number,
        p_id_empresa           in number,
        p_id_proveedor         in number,
        p_tipo_documento       in varchar2 default 'FAC',
        p_folio_factura        in varchar2,
        p_nro_control          in varchar2 default null,
        p_fecha_emision        in date,
        p_cod_moneda           in varchar2 default 'VES',
        p_tipo_cambio          in number default 1,
        p_porcentaje_retencion in number default null,
        p_id_compra_origen     in number default null,
        p_observaciones        in varchar2 default null,
        p_id_forma_pago        in number default null,
        p_id_concepto_islr     in number default -1,
        p_usuario              in varchar2);

    procedure prc_registrar_compra(p_id_compra in number, p_usuario in varchar2);

    procedure prc_anular_compra(p_id_compra in number, p_usuario in varchar2);

end pkg_compras;
/
