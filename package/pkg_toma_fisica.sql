-- =============================================================================
-- pkg_toma_fisica (spec) - toma fisica de inventario (2026-11-25)
--
-- Errores: -20160 ya hay una toma abierta · -20161 la toma no esta en BORRADOR ·
--          -20162 conteo invalido · -20163 toma de otra empresa o inexistente ·
--          -20164 no hay nada que aplicar.
-- =============================================================================

create or replace package pkg_toma_fisica as

    -- Crea la toma con todos los PRODUCTOS activos de la empresa y su existencia de
    -- ese momento. Devuelve el id.
    function fn_crear(p_id_empresa in number, p_fecha in date, p_usuario in varchar2) return number;

    -- Guarda los conteos: JSON [{"id": id_producto, "conteo": 12.5}, ...]. Un conteo
    -- vacio (null) deja el articulo sin contar.
    procedure prc_guardar_conteo(p_id_toma in number, p_json in clob, p_usuario in varchar2);

    -- Aplica la toma: la diferencia entre el conteo y la existencia ACTUAL entra al
    -- kardex como ajuste de entrada o de salida. Devuelve cuantos ajustes hizo.
    procedure prc_aplicar(p_id_toma in number, p_usuario in varchar2, p_ajustes out number);

    -- Anula una toma en borrador (no toca el kardex).
    procedure prc_anular(p_id_toma in number, p_usuario in varchar2);

end pkg_toma_fisica;
/
