-- =============================================================================
-- fn_maximo_real
--
-- El numero MAS ALTO que ya se uso en una serie de la empresa (2026-11-23).
-- Es el tope de la pantalla «Secuencias» (pestana de Administracion): el
-- contador de FOLIO_CONTADOR no se puede fijar por debajo de esto, o el sistema
-- volveria a entregar un numero ya emitido.
--
-- Por serie:
--   PRESUPUESTO  -> max(presupuestos.folio)
--   FAC / NC / ND -> maximo sufijo numerico de facturas.folio_factura con su prefijo
--   CONTROL      -> maximo control de NUESTRAS facturas con la forma de la providencia
--                   (00-000123); los valores tecleados a mano ('876', '002') no cuentan
--   ARTICULO     -> maximo codigo de barras MENOS la base 10000000 (el contador
--                   de FOLIO_CONTADOR guarda 11 para el codigo 10000011)
--   PROD / SERV  -> maximo sufijo de producto_servicio.codigo, solo con la forma
--                   nueva de 5 digitos (PROD-00001); los codigos viejos del
--                   catalogo (SERV-001, REP-002) NO son de esta serie
--   FAC_PROV / CONTROL_PROV -> NULL: ese numero lo pone el PROVEEDOR, no hay
--                   nada que comparar; el contador interno es la unica verdad.
--
-- Devuelve 0 cuando la serie no tiene nada emitido, y NULL cuando no aplica.
-- =============================================================================

create or replace function fn_maximo_real (
    p_id_empresa in number,
    p_tipo       in varchar2
) return number is
    v_tipo varchar2(20) := upper(trim(p_tipo));
    v_n    number;
begin
    if p_id_empresa is null or v_tipo is null then
        return null;
    end if;

    case v_tipo
        when 'PRESUPUESTO' then
            select nvl(max(folio), 0)
              into v_n
              from presupuestos
             where id_empresa = p_id_empresa
               and regexp_like(folio, '^[0-9]+$');

        when 'FAC' then
            select nvl(max(to_number(regexp_substr(folio_factura, '[0-9]+$'))), 0)
              into v_n
              from facturas
             where id_empresa = p_id_empresa
               and regexp_like(folio_factura, '^F-[0-9]+$');

        when 'NC' then
            select nvl(max(to_number(regexp_substr(folio_factura, '[0-9]+$'))), 0)
              into v_n
              from facturas
             where id_empresa = p_id_empresa
               and regexp_like(folio_factura, '^NC-[0-9]+$');

        when 'ND' then
            select nvl(max(to_number(regexp_substr(folio_factura, '[0-9]+$'))), 0)
              into v_n
              from facturas
             where id_empresa = p_id_empresa
               and regexp_like(folio_factura, '^ND-[0-9]+$');

        when 'CONTROL' then
            select nvl(max(to_number(regexp_substr(nro_control, '[0-9]+$'))), 0)
              into v_n
              from facturas
             where id_empresa = p_id_empresa
               and regexp_like(nro_control, '^[0-9]{2}-[0-9]{6}$');

        when 'ARTICULO' then
            -- El contador de la serie ARTICULO guarda n, y el codigo de barras
            -- es 10000000 + n: se devuelve en las unidades del contador.
            select nvl(max(to_number(codigo_barras)) - 10000000, 0)
              into v_n
              from producto_servicio
             where id_empresa = p_id_empresa
               and regexp_like(codigo_barras, '^[0-9]+$')
               and to_number(codigo_barras) > 10000000;

        when 'PROD' then
            select nvl(max(to_number(regexp_substr(codigo, '[0-9]+$'))), 0)
              into v_n
              from producto_servicio
             where id_empresa = p_id_empresa
               and regexp_like(codigo, '^PROD-[0-9]{5}$');

        when 'SERV' then
            select nvl(max(to_number(regexp_substr(codigo, '[0-9]+$'))), 0)
              into v_n
              from producto_servicio
             where id_empresa = p_id_empresa
               and regexp_like(codigo, '^SERV-[0-9]{5}$');

        else
            return null;
    end case;

    return v_n;
end fn_maximo_real;
/
