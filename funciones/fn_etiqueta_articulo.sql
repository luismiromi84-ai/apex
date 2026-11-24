-- =============================================================================
-- fn_etiqueta_articulo
--
-- Devuelve el HTML de las etiquetas de un articulo (2026-11-23): nombre, codigo
-- interno, codigo de barras Code 128 y precio. Lo pinta la pagina 41
-- "Etiquetas de articulo" y el navegador hace "Imprimir".
--
-- El Code 128 lo genera APEX (apex_barcode.get_code128_svg, disponible desde
-- APEX 23.2): no hace falta ninguna libreria de JavaScript ni salida a red.
--
-- Devuelve NULL si el articulo no existe: no se inventa una etiqueta en blanco.
-- p_copias se recorta a 1..60 para que un dedazo no mande 5.000 hojas a la
-- impresora.
-- =============================================================================

create or replace function fn_etiqueta_articulo (
    p_id_articulo in number,
    p_copias      in number default 1
) return clob is
    v_html clob;
    v_nom  producto_servicio.nombre%type;
    v_cod  producto_servicio.codigo%type;
    v_cb   producto_servicio.codigo_barras%type;
    v_pre  producto_servicio.precio_sugerido%type;
    v_tipo producto_servicio.tipo%type;
    v_cop  number := least(greatest(nvl(p_copias, 1), 1), 60);
    v_svg  clob;
    v_imp  varchar2(40);
    v_mon  varchar2(10) := 'Bs';
begin
    begin
        select nombre, codigo, codigo_barras, precio_sugerido, tipo
          into v_nom, v_cod, v_cb, v_pre, v_tipo
          from producto_servicio
         where id_producto_servicio = p_id_articulo;
    exception
        when no_data_found then
            return null;
    end;

    -- La moneda de la etiqueta es la LOCAL del pais de la empresa del articulo
    -- (en Mexico es MXN, no bolivares).
    begin
        select nvl(p.moneda_local, 'Bs') into v_mon
          from producto_servicio a
          join empresas e on e.id_empresa = a.id_empresa
          left join paises p on p.cod_pais = e.cod_pais
         where a.id_producto_servicio = p_id_articulo;
    exception
        when others then
            v_mon := 'Bs';
    end;

    begin
        v_svg := apex_barcode.get_code128_svg(p_value => v_cb, p_size => 220);
    exception
        when others then
            v_svg := null;
    end;

    v_imp := to_char(nvl(v_pre, 0), 'FM999G999G990D00', 'NLS_NUMERIC_CHARACTERS='', ''');

    v_html := q'~<!DOCTYPE html><html lang="es"><head><meta charset="utf-8">
<title>Etiquetas - ~' || apex_escape.html(v_nom) || q'~</title>
<style>
  @page { size: A4; margin: 8mm; }
  body { margin: 0; font-family: Arial, Helvetica, sans-serif; background: #fff; }
  .spx-etq { display: flex; flex-wrap: wrap; gap: 2mm; }
  .spx-etq .etq {
      width: 62mm; height: 30mm; box-sizing: border-box;
      border: 0.3mm solid #c9d2de; border-radius: 2mm;
      padding: 2mm 3mm; display: flex; flex-direction: column;
      justify-content: space-between; page-break-inside: avoid;
  }
  .spx-etq .nom { font-size: 8pt; font-weight: 700; line-height: 1.15;
                  height: 9mm; overflow: hidden; }
  .spx-etq .bc { text-align: center; }
  .spx-etq .bc svg { width: 52mm; height: 10mm; }
  .spx-etq .pie { display: flex; justify-content: space-between;
                  font-size: 7.5pt; color: #333; }
  .spx-etq .sin { font-size: 7.5pt; color: #b00; }
  @media print {
    body * { visibility: hidden; }
    .spx-etq, .spx-etq * { visibility: visible; }
    .spx-etq { position: absolute; left: 0; top: 0; }
    .u-no-print { display: none !important; }
  }
</style></head><body>
<div class="spx-etq">~';

    for i in 1 .. v_cop loop
        v_html := v_html || q'~<div class="etq">
  <div class="nom">~' || apex_escape.html(v_nom) || q'~</div>
  <div class="bc">~'
            || case when v_svg is not null then v_svg
                    else '<span class="sin">(sin codigo de barras)</span>' end
            || q'~</div>
  <div class="pie"><span>~' || apex_escape.html(v_cod) || q'~ &middot; ~'
            || apex_escape.html(v_tipo) || q'~</span><span>~'
            || apex_escape.html(v_cb) || q'~</span><span>~'
            || apex_escape.html(v_mon) || ' ' || v_imp || q'~</span></div>
</div>~';
    end loop;

    v_html := v_html || '</div></body></html>';
    return v_html;
end fn_etiqueta_articulo;
/
