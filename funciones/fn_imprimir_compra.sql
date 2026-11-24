-- =============================================================================
-- funciones/fn_imprimir_compra.sql
--
-- La FACTURA DE COMPRA en papel (2026-11-23). Era el ultimo documento del modulo
-- de compras sin impresion propia: la pagina 31 imprime el COMPROBANTE DE
-- RETENCION, que es otra cosa.
--
-- OJO CON LO QUE ES: esta factura la emitio el PROVEEDOR y aqui solo se registra.
-- El papel lo dice en una nota al pie, para que nadie lo confunda con una factura
-- nuestra ni lo entregue como si la hubieramos emitido.
--
-- Devuelve el HTML listo para imprimir o guardar como PDF desde el navegador, o
-- NULL si la compra no existe: la pagina 39 no debe inventarse un documento en
-- blanco (es la leccion de los reportes de 2026-11-05).
--
-- LA FUNCION NO CALCULA EL IGTF NI LAS RETENCIONES: lee la foto guardada en la
-- compra (COMPRAS.IGTF_BS, RETENCION_IVA_BS, RETENCION_ISLR_BS), la misma que
-- usan la pantalla 28, el libro y los pagos. Si manana cambia la alicuota o el
-- porcentaje de retencion, el papel reimpreso sigue diciendo lo que se registro.
-- Lo unico que se convierte son los importes que la tabla guarda en BOLIVARES
-- (retenciones e IGTF), que pasan a la moneda del documento por TIPO_CAMBIO,
-- igual que hace el resumen de la pantalla 28.
--
-- Lleva el logo de la empresa que recibe (pkg_empresa_logo.fn_logo_img). Si no
-- hay logo devuelve NULL y el documento conserva su maqueta: ni caja vacia ni
-- imagen rota.
--
-- El CSS viaja con el documento y esconde el cromo de APEX al imprimir, el mismo
-- patron de las paginas 11, 12, 30, 31, 35 y 38.
-- =============================================================================

create or replace function fn_imprimir_compra (
    p_id_compra in number
) return clob is
    v_co      compras%rowtype;
    v_emp      varchar2(200);
    v_rif_emp  varchar2(40);
    v_pais     varchar2(2);
    v_dir_emp  varchar2(300);
    v_tel_emp  varchar2(60);
    v_mail_emp varchar2(120);
    v_prov     varchar2(200);
    v_rif_prov varchar2(40);
    v_dir_prov varchar2(300);
    v_tel_prov varchar2(60);
    v_mail_prov varchar2(120);
    v_dias     number;
    v_forma    varchar2(120);
    v_estado   varchar2(30);
    v_moneda   varchar2(5);
    v_titulo   varchar2(60);
    v_tasa     number := 1;
    v_logo     clob;
    v_html     clob;
    v_filas    clob := '';
    v_origen   varchar2(250);
    v_comp_iva  varchar2(40);
    v_comp_islr varchar2(40);
    v_n        number := 0;
    v_base     number := 0;
    v_exento   number := 0;
    v_desc     number := 0;
    v_iva      number := 0;
    v_sub      number := 0;
    v_total    number := 0;
    v_igtf_bs  number := 0;
    v_igtf     number := 0;
    v_ret_bs   number := 0;
    v_ret      number := 0;
    v_islr_bs  number := 0;
    v_islr     number := 0;
    v_neto_bs  number := 0;
    v_neto     number := 0;

    function f_txt(p_valor varchar2) return varchar2 is
    begin
        return nvl(sys.htf.escape_sc(p_valor), '&nbsp;');
    end f_txt;

    -- Miles con punto y decimales con coma: el par de NLS es "decimal, miles".
    function f_num(p_valor number) return varchar2 is
    begin
        return to_char(nvl(p_valor, 0), 'FM999G999G999G990D00',
                       'NLS_NUMERIC_CHARACTERS='',.''');
    end f_num;

    function f_cant(p_valor number) return varchar2 is
    begin
        return to_char(nvl(p_valor, 0), 'FM999G999G990D00',
                       'NLS_NUMERIC_CHARACTERS='',.''');
    end f_cant;

    function f_tasa(p_valor number) return varchar2 is
    begin
        return to_char(nvl(p_valor, 1), 'FM999G999G999G990D0000',
                       'NLS_NUMERIC_CHARACTERS='',.''');
    end f_tasa;

    function f_fecha(p_fecha date) return varchar2 is
    begin
        return nvl(to_char(p_fecha, 'DD/MM/YYYY'), '&nbsp;');
    end f_fecha;

    -- Una compra anulada no se puede presentar como un documento valido.
    function f_anulado return varchar2 is
    begin
        if upper(nvl(v_co.estado, '#')) = 'ANULADA' then
            return '<div class="pc-anulado">COMPRA ANULADA</div>';
        end if;
        return '';
    end f_anulado;

    -- Una fila de la tabla de importes: moneda del documento y bolivares.
    function f_fila(p_lbl varchar2, p_val number, p_bs number,
                    p_clase varchar2 default '') return varchar2 is
    begin
        return '<tr class="' || p_clase || '"><td>' || p_lbl || '</td>'
            || '<td class="pc-der">' || f_num(p_val) || '</td>'
            || '<td class="pc-der">' || f_num(p_bs) || '</td></tr>';
    end f_fila;
begin
    if p_id_compra is null then
        return null;
    end if;

    begin
        select * into v_co
          from compras
         where id_compra = p_id_compra;
    exception
        when no_data_found then
            return null;
    end;

    v_tasa := nvl(v_co.tipo_cambio, 1);
    if v_tasa <= 0 then
        v_tasa := 1;
    end if;
    v_moneda := upper(nvl(v_co.cod_moneda, 'VES'));

    select e.nombre_empresa, nvl(fn_formato_rif(e.rfc), '-'), nvl(e.cod_pais, 'VE'),
           f.direccion_fiscal, f.telefono, f.email
      into v_emp, v_rif_emp, v_pais, v_dir_emp, v_tel_emp, v_mail_emp
      from empresas e
      left join empresa_fiscal f on f.id_empresa = e.id_empresa
     where e.id_empresa = v_co.id_empresa;

    begin
        select pr.razon_social, pr.rif, pr.direccion, pr.telefono, pr.email,
               pr.dias_credito
          into v_prov, v_rif_prov, v_dir_prov, v_tel_prov, v_mail_prov, v_dias
          from proveedores pr
         where pr.id_proveedor = v_co.id_proveedor;
    exception
        when no_data_found then
            v_prov := '(proveedor no encontrado)';
    end;

    begin
        select descripcion into v_forma
          from forma_pago where id_forma_pago = v_co.id_forma_pago;
    exception
        when no_data_found then
            v_forma := null;
    end;

    -- El estado se lee como en la pantalla: BORRADOR = Pendiente.
    v_estado := fn_estado_compra(v_co.estado);

    v_titulo := case upper(nvl(v_co.tipo_documento, 'FAC'))
                    when 'NC' then 'NOTA DE CR&Eacute;DITO DE COMPRA'
                    when 'ND' then 'NOTA DE D&Eacute;BITO DE COMPRA'
                    else 'FACTURA DE COMPRA'
                end;

    -- Una nota de compra dice que factura del proveedor acredita o debita.
    if v_co.id_compra_origen is not null then
        begin
            select 'Factura ' || nvl(co.folio_factura, '-')
                   || case when co.nro_control is not null
                           then ' &middot; N&ordm; de control ' || co.nro_control end
                   || ' del ' || to_char(co.fecha_emision, 'DD/MM/YYYY')
              into v_origen
              from compras co
             where co.id_compra = v_co.id_compra_origen;
        exception
            when no_data_found then
                v_origen := null;
        end;
    end if;

    -- Los numeros de comprobante SOLO si ya se emitieron: en un pendiente no hay
    -- nada que enseñar (y no se inventa).
    begin
        select numero_comprobante into v_comp_iva
          from retenciones
         where id_compra = v_co.id_compra and tipo = 'IVA' and estado = 'EMITIDO';
    exception
        when others then
            v_comp_iva := null;
    end;
    begin
        select numero_comprobante into v_comp_islr
          from retenciones
         where id_compra = v_co.id_compra and tipo = 'ISLR' and estado = 'EMITIDO';
    exception
        when others then
            v_comp_islr := null;
    end;

    -- Las lineas del documento del proveedor.
    for r in (select d.* from compras_det d
               where d.id_compra = v_co.id_compra
               order by d.num_linea) loop
        v_n := v_n + 1;
        v_filas := v_filas
            || '<tr><td class="pc-cen">' || to_char(r.num_linea) || '</td>'
            || '<td>' || f_txt(r.descripcion) || '</td>'
            || '<td class="pc-cen">' || f_cant(r.cantidad) || '</td>'
            || '<td class="pc-der">' || f_num(r.precio_unitario) || '</td>'
            || '<td class="pc-der">' || f_num(r.monto_descuento) || '</td>'
            || '<td class="pc-cen">' || to_char(nvl(r.porcentaje_impuesto, 0))
            || ' %</td>'
            || '<td class="pc-der">' || f_num(r.monto_impuesto) || '</td>'
            || '<td class="pc-der">' || f_num(r.total_linea) || '</td></tr>';
        v_sub  := v_sub + nvl(r.subtotal_linea, 0);
        v_desc := v_desc + nvl(r.monto_descuento, 0);
        v_iva  := v_iva + nvl(r.monto_impuesto, 0);
        if nvl(r.porcentaje_impuesto, 0) > 0 then
            v_base := v_base + nvl(r.subtotal_linea, 0);
        else
            v_exento := v_exento + nvl(r.subtotal_linea, 0);
        end if;
    end loop;

    -- El total del documento: la suma de sus lineas. Si no hubiera lineas (una
    -- compra recien capturada) se usa el total guardado, que es lo unico que hay.
    if v_n = 0 then
        v_total := nvl(v_co.monto_total, 0);
    else
        v_total := v_sub + v_iva;
    end if;

    v_igtf_bs  := nvl(v_co.igtf_bs, 0);
    v_igtf     := round(v_igtf_bs / v_tasa, 2);
    v_ret_bs   := nvl(v_co.retencion_iva_bs, 0);
    v_ret      := round(v_ret_bs / v_tasa, 2);
    v_islr_bs  := nvl(v_co.retencion_islr_bs, 0);
    v_islr     := round(v_islr_bs / v_tasa, 2);

    -- Lo que sale del banco: total - retenciones + IGTF.
    v_neto_bs := round(v_total * v_tasa, 2) - v_ret_bs - v_islr_bs + v_igtf_bs;
    v_neto    := round(v_neto_bs / v_tasa, 2);

    v_html := '<style>'
        || '@page{size:A4 portrait;margin:10mm}'
        || '.spx-cmp{font-family:Arial,Helvetica,sans-serif;color:#111;'
        || 'font-size:11px;line-height:1.3;background:#fff;max-width:780px;'
        || 'margin:0 auto}'
        || '.spx-cmp .pc-logo{margin:0 0 8px 0}'
        || '.spx-cmp .pc-cab{width:100%;border-collapse:collapse;margin-bottom:8px}'
        || '.spx-cmp .pc-cab td{border:none;padding:0;vertical-align:top}'
        || '.spx-cmp .pc-emp{font-size:15px;font-weight:bold}'
        || '.spx-cmp .pc-datos{font-size:9px;color:#333}'
        || '.spx-cmp .pc-tit{font-size:15px;font-weight:bold;text-align:right;'
        || 'color:#005b96;letter-spacing:1px}'
        || '.spx-cmp .pc-num{font-size:11px;text-align:right;margin-top:2px}'
        || '.spx-cmp table.pc-caja{width:100%;border-collapse:collapse;'
        || 'margin-bottom:8px}'
        || '.spx-cmp table.pc-caja td{border:1px solid #555;padding:3px 6px;'
        || 'vertical-align:top}'
        || '.spx-cmp .pc-lab{font-size:9px;text-transform:uppercase;color:#333;'
        || 'background:#f2f2f2}'
        || '.spx-cmp .pc-val{font-size:11px;font-weight:bold}'
        || '.spx-cmp table.pc-montos{width:100%;border-collapse:collapse;'
        || 'margin-bottom:8px}'
        || '.spx-cmp table.pc-montos th{border:1px solid #555;padding:3px 6px;'
        || 'font-size:9px;text-transform:uppercase;background:#f2f2f2;'
        || 'text-align:left}'
        || '.spx-cmp table.pc-montos td{border:1px solid #555;padding:4px 6px;'
        || 'font-size:11px}'
        || '.spx-cmp .pc-der{text-align:right;white-space:nowrap}'
        || '.spx-cmp .pc-cen{text-align:center}'
        || '.spx-cmp .pc-tot td{font-weight:bold;background:#fafafa}'
        || '.spx-cmp .pc-neto{margin:0 0 10px 0;padding:6px 10px;'
        || 'border:2px solid #0f766e;background:#f0fdfa;font-size:13px;'
        || 'font-weight:bold;text-align:right;color:#0f766e}'
        || '.spx-cmp .pc-chip{display:inline-block;margin:0 8px 4px 0;'
        || 'padding:2px 8px;border:1px solid #005b96;border-radius:10px;'
        || 'font-size:10px;color:#005b96;background:#f4f9ff}'
        || '.spx-cmp .pc-obs{margin:0 0 8px 0;font-size:10px}'
        || '.spx-cmp .pc-nota{margin-top:6px;padding:5px 8px;background:#fff8e6;'
        || 'border-left:3px solid #d9a300;font-size:9px;color:#3a2f00}'
        || '.spx-cmp .pc-pie{margin-top:10px;border-top:1px solid #111;'
        || 'padding-top:4px;font-size:9px;text-align:center}'
        || '.spx-cmp .pc-anulado{margin:6px 0;padding:4px;border:2px solid #b00;'
        || 'color:#b00;font-size:14px;font-weight:bold;text-align:center;'
        || 'letter-spacing:2px}'
        || '@media print{body *{visibility:hidden}'
        || '.spx-cmp,.spx-cmp *{visibility:visible}'
        || '.spx-cmp{position:absolute;left:0;top:0;width:100%;max-width:none}}'
        || '</style>'
        || '<div class="spx-cmp">';

    v_logo := pkg_empresa_logo.fn_logo_img(
        v_co.id_empresa,
        'max-height:64px;max-width:220px;display:block;margin:0 0 8px 0;');
    if v_logo is not null then
        v_html := v_html || '<div class="pc-logo">' || v_logo || '</div>';
    end if;

    -- Cabecera: la empresa que RECIBE a la izquierda; el titulo y el numero que
    -- puso el proveedor a la derecha.
    v_html := v_html
        || '<table class="pc-cab"><tr>'
        || '<td style="width:52%">'
        || '<div class="pc-emp">' || f_txt(v_emp) || '</div>'
        || '<div class="pc-datos">'
        || case when v_pais = 'MX' then 'RFC: ' else 'RIF: ' end || f_txt(v_rif_emp)
        || case when v_dir_emp is not null then '<br>' || f_txt(v_dir_emp) end
        || case when v_tel_emp is not null then '<br>Tel.: ' || f_txt(v_tel_emp) end
        || case when v_mail_emp is not null then ' &middot; ' || f_txt(v_mail_emp) end
        || '</div></td>'
        || '<td style="width:48%">'
        || '<div class="pc-tit">' || v_titulo || '</div>'
        || '<div class="pc-num"><strong>N&ordm;:</strong> '
        || f_txt(v_co.folio_factura) || '</div>'
        || '<div class="pc-num"><strong>N&ordm; de control:</strong> '
        || case when v_co.nro_control is not null then f_txt(v_co.nro_control)
                else '&mdash;' end || '</div>'
        || '<div class="pc-num"><strong>Fecha:</strong> '
        || f_fecha(v_co.fecha_emision) || '</div>'
        || '<div class="pc-num"><strong>Estado:</strong> ' || f_txt(v_estado)
        || '</div></td></tr></table>'
        || f_anulado();

    -- El proveedor que emitio y, al lado, quien lo recibe.
    v_html := v_html
        || '<table class="pc-caja"><tr>'
        || '<td class="pc-lab" style="width:50%">Proveedor (emisor)</td>'
        || '<td class="pc-lab" style="width:50%">Receptor</td></tr>'
        || '<tr><td class="pc-val">' || f_txt(v_prov) || '</td>'
        || '<td>' || f_txt(v_emp) || '</td></tr>'
        || '<tr><td class="pc-datos">'
        || case when v_pais = 'MX' then 'RFC: ' else 'RIF: ' end
        || f_txt(fn_formato_rif(v_rif_prov))
        || case when v_dir_prov is not null then '<br>' || f_txt(v_dir_prov) end
        || case when v_tel_prov is not null then '<br>Tel.: ' || f_txt(v_tel_prov) end
        || case when v_mail_prov is not null then ' &middot; ' || f_txt(v_mail_prov) end
        || '</td>'
        || '<td class="pc-datos">'
        || case when v_pais = 'MX' then 'RFC: ' else 'RIF: ' end || f_txt(v_rif_emp)
        || '</td></tr></table>';

    -- Datos del documento y condiciones.
    v_html := v_html
        || '<table class="pc-caja"><tr>'
        || '<td class="pc-lab" style="width:20%">Recepci&oacute;n</td>'
        || '<td class="pc-lab" style="width:20%">Vencimiento</td>'
        || '<td class="pc-lab" style="width:20%">Forma de pago</td>'
        || '<td class="pc-lab" style="width:20%">Moneda</td>'
        || '<td class="pc-lab" style="width:20%">Tasa</td></tr>'
        || '<tr><td>' || f_fecha(v_co.fecha_recepcion) || '</td>'
        || '<td>' || case when v_co.fecha_vencimiento is not null
                          then f_fecha(v_co.fecha_vencimiento)
                          when v_dias is not null
                          then f_fecha(v_co.fecha_emision + v_dias)
                          else '&mdash;' end || '</td>'
        || '<td>' || case when v_forma is null then '&mdash;' else f_txt(v_forma) end
        || '</td>'
        || '<td class="pc-cen">' || f_txt(v_moneda) || '</td>'
        || '<td class="pc-der">' || f_tasa(v_tasa) || ' Bs / '
        || f_txt(v_moneda) || '</td></tr></table>';

    if v_origen is not null then
        v_html := v_html || '<div class="pc-obs"><strong>Documento que afecta:</strong> '
            || v_origen || '</div>';
    end if;

    -- Las lineas.
    if v_n > 0 then
        v_html := v_html
            || '<table class="pc-montos"><thead><tr>'
            || '<th style="width:5%">#</th>'
            || '<th style="width:39%">Descripci&oacute;n</th>'
            || '<th style="width:9%" class="pc-cen">Cant.</th>'
            || '<th style="width:12%" class="pc-der">Precio</th>'
            || '<th style="width:11%" class="pc-der">Descuento</th>'
            || '<th style="width:8%" class="pc-cen">IVA</th>'
            || '<th style="width:8%" class="pc-der">Impuesto</th>'
            || '<th style="width:8%" class="pc-der">Total</th>'
            || '</tr></thead><tbody>' || v_filas || '</tbody></table>';
    else
        v_html := v_html || '<div class="pc-obs">Esta compra no tiene lineas '
            || 'capturadas.</div>';
    end if;

    -- Totales en la moneda del documento y en bolivares.
    v_html := v_html
        || '<table class="pc-montos"><thead><tr>'
        || '<th style="width:46%">Concepto</th>'
        || '<th style="width:27%" class="pc-der">En ' || f_txt(v_moneda) || '</th>'
        || '<th style="width:27%" class="pc-der">En bol&iacute;vares</th>'
        || '</tr></thead><tbody>'
        || f_fila('Base imponible', v_base, round(v_base * v_tasa, 2))
        || f_fila('Monto exento', v_exento, round(v_exento * v_tasa, 2))
        || case when v_desc > 0
                then f_fila('Descuento', v_desc, round(v_desc * v_tasa, 2)) end
        || f_fila('IVA', v_iva, round(v_iva * v_tasa, 2))
        || f_fila('Total del documento', v_total, round(v_total * v_tasa, 2), 'pc-tot')
        || case when v_ret_bs <> 0
                then f_fila('(-) Retenci&oacute;n de IVA', v_ret, v_ret_bs) end
        || case when v_islr_bs <> 0
                then f_fila('(-) Retenci&oacute;n de ISLR', v_islr, v_islr_bs) end
        || case when v_igtf_bs <> 0
                then f_fila('(+) IGTF', v_igtf, v_igtf_bs) end
        || f_fila('Neto a pagar', v_neto, v_neto_bs, 'pc-tot')
        || '</tbody></table>'
        || '<div class="pc-neto">NETO A PAGAR: ' || f_num(v_neto) || ' '
        || f_txt(v_moneda) || ' &nbsp;&middot;&nbsp; Bs ' || f_num(v_neto_bs)
        || '</div>';

    -- Los comprobantes de retencion, si ya se emitieron.
    if v_comp_iva is not null or v_comp_islr is not null then
        v_html := v_html || '<div class="pc-obs"><strong>Comprobantes de '
            || 'retenci&oacute;n emitidos:</strong> ';
        if v_comp_iva is not null then
            v_html := v_html || '<span class="pc-chip">IVA N&ordm; '
                || f_txt(v_comp_iva) || ' &middot; Bs ' || f_num(v_ret_bs)
                || '</span>';
        end if;
        if v_comp_islr is not null then
            v_html := v_html || '<span class="pc-chip">ISLR N&ordm; '
                || f_txt(v_comp_islr) || ' &middot; Bs ' || f_num(v_islr_bs)
                || '</span>';
        end if;
        v_html := v_html || '</div>';
    end if;

    if v_co.observaciones is not null then
        v_html := v_html || '<div class="pc-obs"><strong>Observaciones:</strong> '
            || f_txt(v_co.observaciones) || '</div>';
    end if;

    -- La nota que evita el malentendido: el documento es del proveedor.
    v_html := v_html
        || '<div class="pc-nota">Documento emitido por el proveedor y registrado '
        || 'en el sistema. No sustituye al original.</div>'
        || '<div class="pc-pie">Registro N&ordm; '
        || f_txt(to_char(v_co.id_compra))
        || case when v_co.creado_por is not null
                then ' &middot; Registrado por ' || f_txt(v_co.creado_por) end
        || case when v_co.fecha_creacion is not null
                then ' el ' || to_char(v_co.fecha_creacion, 'DD/MM/YYYY HH24:MI') end
        || '</div>'
        || '</div>';

    return v_html;
end fn_imprimir_compra;
/
