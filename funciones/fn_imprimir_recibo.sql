-- =============================================================================
-- funciones/fn_imprimir_recibo.sql
--
-- El RECIBO DE COBRO en papel (2026-11-21). Es el documento que se le entrega
-- al cliente cuando paga: no existia impreso hasta hoy, solo la pantalla (25).
--
-- Devuelve el HTML listo para imprimir o guardar como PDF desde el navegador, o
-- NULL si el recibo no existe: la pagina 35 no debe inventarse un documento en
-- blanco (es la leccion de los reportes de 2026-11-05).
--
-- LA FUNCION NO CALCULA NADA. Lee las columnas guardadas del recibo
-- (MONTO_COBRADO, MONTO_BS, IGTF_MONTO, IGTF_BS, RETENCION_IVA_BS,
-- MONTO_NETO) y no vuelve a mirar pkg_cobros, fn_igtf_sugerido ni la factura.
-- Lo unico que se convierte es lo que la tabla guarda en UNA sola moneda:
-- el neto en bolivares (por TIPO_CAMBIO, igual que la pantalla 25) y la
-- retencion en la moneda del cobro (por la misma tasa). Nada se recalcula:
-- si manana cambia la alicuota del IGTF, el recibo reimpreso sigue diciendo
-- lo que se cobro.
--
-- Los importes van con el formato venezolano de la factura (miles con punto y
-- decimales con coma) por el NLS explicito de f_num. El RIF, el N. de control y
-- la referencia bancaria son texto y no se tocan.
--
-- LLEVA EL LOGO de la empresa que cobra, arriba a la izquierda y con el mismo
-- trato que la factura (pkg_empresa_logo.fn_logo_img). Si la empresa no tiene
-- logo cargado devuelve NULL y el documento conserva su maqueta: ni caja vacia
-- ni imagen rota.
--
-- El CSS viaja con el documento y esconde el cromo de APEX al imprimir, el
-- mismo patron de las paginas 11, 12 y 31.
-- =============================================================================

create or replace function fn_imprimir_recibo (
    p_id_recibo in number
) return clob is
    v_rec      recibos%rowtype;
    v_emp      varchar2(200);
    v_rif_emp  varchar2(40);
    v_pais     varchar2(2);
    v_dir_emp  varchar2(300);
    v_tel_emp  varchar2(60);
    v_mail_emp varchar2(120);
    v_cli      varchar2(200);
    v_rif_cli  varchar2(30);
    v_folio    varchar2(60);
    v_control  varchar2(40);
    v_fec_fac  date;
    v_tot_fac  number;
    v_mon_fac  varchar2(5);
    v_forma    varchar2(120);
    v_estado   varchar2(20);
    v_moneda   varchar2(5);
    v_logo     clob;
    v_html     clob;
    v_neto_bs  number;

    -- Todo texto que llega a la pantalla pasa por aqui: escape_sc corta el HTML
    -- que alguien meta en una razon social, y un nulo deja la celda vacia.
    function f_txt(p_valor varchar2) return varchar2 is
    begin
        return nvl(sys.htf.escape_sc(p_valor), '&nbsp;');
    end f_txt;

    -- Importes en bolivares con el formato de la factura venezolana: miles con
    -- punto y decimales con coma. OJO con el par de NLS_NUMERIC_CHARACTERS: es
    -- "decimal, miles", asi que el formato de aqui es ',.'. Va explicito para no
    -- depender del NLS de la sesion.
    function f_num(p_valor number) return varchar2 is
    begin
        return to_char(nvl(p_valor, 0), 'FM999G999G999G990D00',
                       'NLS_NUMERIC_CHARACTERS='',.''');
    end f_num;

    -- La tasa se imprime con sus decimales (una tasa de 916,6477 redondeada a
    -- 2 decimales deja de cuadrar con el neto del papel).
    function f_tasa(p_valor number) return varchar2 is
    begin
        return to_char(nvl(p_valor, 1), 'FM999G999G999G990D0000',
                       'NLS_NUMERIC_CHARACTERS='',.''');
    end f_tasa;

    function f_fecha(p_fecha date) return varchar2 is
    begin
        return nvl(to_char(p_fecha, 'DD/MM/YYYY'), '&nbsp;');
    end f_fecha;

    -- Un recibo anulado no se puede entregar como si valiera: el papel lo dice
    -- en grande. No es un calculo, es el estado guardado.
    function f_anulado return varchar2 is
    begin
        if v_rec.estado = 'ANULADO' then
            return '<div class="rc-anulado">RECIBO ANULADO</div>';
        end if;
        return '';
    end f_anulado;
begin
    if p_id_recibo is null then
        return null;
    end if;

    begin
        select * into v_rec
          from recibos
         where id_recibo = p_id_recibo;
    exception
        when no_data_found then
            return null;
    end;

    -- La empresa que cobra. La fila fiscal puede no existir: se imprime vacia.
    select e.nombre_empresa, nvl(fn_formato_rif(e.rfc), '-'),
           nvl(e.cod_pais, 'VE'), f.direccion_fiscal, f.telefono, f.email
      into v_emp, v_rif_emp, v_pais, v_dir_emp, v_tel_emp, v_mail_emp
      from empresas e
      left join empresa_fiscal f on f.id_empresa = e.id_empresa
     where e.id_empresa = v_rec.id_empresa;

    -- La factura que se cobra y su cliente. Son datos guardados del documento;
    -- no se suman ni se convierten.
    select fa.folio_factura, fa.nro_control, fa.fecha_emision, fa.monto_total,
           fa.cod_moneda, c.razon_social, c.rif
      into v_folio, v_control, v_fec_fac, v_tot_fac, v_mon_fac, v_cli, v_rif_cli
      from facturas fa
      join clientes c on c.id_cliente = fa.id_cliente
     where fa.id_factura = v_rec.id_factura;

    begin
        select descripcion into v_forma
          from forma_pago where id_forma_pago = v_rec.id_forma_pago;
    exception
        when no_data_found then
            v_forma := null;
    end;

    v_moneda := upper(nvl(v_rec.cod_moneda, 'VES'));

    -- El estado se lee como lo lee la pantalla del recibo: ACTIVO = EMITIDO.
    v_estado := case when v_rec.estado = 'ACTIVO' then 'EMITIDO'
                     else nvl(v_rec.estado, 'ANULADO') end;

    -- El neto en bolivares no se guarda (lo mismo que hace la pantalla 25): es
    -- el neto por la tasa guardada del recibo.
    v_neto_bs := round(nvl(v_rec.monto_neto, 0) * nvl(v_rec.tipo_cambio, 1), 2);

    v_html := '<style>'
        || '@page{size:A4 portrait;margin:10mm}'
        || '.spx-rec{font-family:Arial,Helvetica,sans-serif;color:#111;font-size:11px;'
        || 'line-height:1.3;background:#fff;max-width:780px;margin:0 auto}'
        || '.spx-rec .rc-logo{margin:0 0 8px 0}'
        || '.spx-rec .rc-cab{width:100%;border-collapse:collapse;margin-bottom:8px}'
        || '.spx-rec .rc-cab td{border:none;padding:0;vertical-align:top}'
        || '.spx-rec .rc-emp{font-size:15px;font-weight:bold}'
        || '.spx-rec .rc-datos{font-size:9px;color:#333}'
        || '.spx-rec .rc-tit{font-size:16px;font-weight:bold;text-align:right;'
        || 'color:#005b96;letter-spacing:1px}'
        || '.spx-rec .rc-num{font-size:12px;text-align:right;margin-top:2px}'
        || '.spx-rec table.rc-caja{width:100%;border-collapse:collapse;margin-bottom:8px}'
        || '.spx-rec table.rc-caja td{border:1px solid #555;padding:3px 6px;vertical-align:top}'
        || '.spx-rec .rc-lab{font-size:9px;text-transform:uppercase;color:#333;background:#f2f2f2}'
        || '.spx-rec .rc-val{font-size:11px;font-weight:bold}'
        || '.spx-rec table.rc-montos{width:100%;border-collapse:collapse;margin-bottom:8px}'
        || '.spx-rec table.rc-montos th{border:1px solid #555;padding:3px 6px;'
        || 'font-size:9px;text-transform:uppercase;background:#f2f2f2;text-align:left}'
        || '.spx-rec table.rc-montos td{border:1px solid #555;padding:4px 6px;font-size:11px}'
        || '.spx-rec .rc-der{text-align:right;white-space:nowrap}'
        || '.spx-rec .rc-cen{text-align:center}'
        || '.spx-rec .rc-tot td{font-weight:bold;background:#fafafa}'
        || '.spx-rec .rc-neto{margin:0 0 10px 0;padding:6px 10px;border:2px solid #0f766e;'
        || 'background:#f0fdfa;font-size:13px;font-weight:bold;text-align:right;color:#0f766e}'
        || '.spx-rec .rc-firmas{margin-top:34px;width:100%;border-collapse:collapse}'
        || '.spx-rec .rc-firmas td{border:none;padding:0 14px;font-size:10px;vertical-align:bottom}'
        || '.spx-rec .rc-linea{border-bottom:1px solid #111;height:34px;margin-bottom:3px}'
        || '.spx-rec .rc-pie{margin-top:12px;border-top:1px solid #111;padding-top:4px;'
        || 'font-size:9px;text-align:center}'
        || '.spx-rec .rc-anulado{margin:6px 0;padding:4px;border:2px solid #b00;color:#b00;'
        || 'font-size:14px;font-weight:bold;text-align:center;letter-spacing:2px}'
        || '@media print{body *{visibility:hidden}'
        || '.spx-rec,.spx-rec *{visibility:visible}'
        || '.spx-rec{position:absolute;left:0;top:0;width:100%;max-width:none}}'
        || '</style>'
        || '<div class="spx-rec">';

    -- El logo de la empresa que cobra, arriba a la izquierda. Mismo estilo que el
    -- de la factura. Sin logo cargado, fn_logo_img devuelve NULL: se omite el
    -- bloque entero (ni caja vacia ni <img> sin origen).
    v_logo := pkg_empresa_logo.fn_logo_img(
        v_rec.id_empresa,
        'max-height:64px;max-width:220px;display:block;margin:0 0 8px 0;');
    if v_logo is not null then
        v_html := v_html || '<div class="rc-logo">' || v_logo || '</div>';
    end if;

    -- Cabecera: emisor a la izquierda, titulo y numero a la derecha.
    v_html := v_html
        || '<table class="rc-cab"><tr>'
        || '<td style="width:55%">'
        || '<div class="rc-emp">' || f_txt(v_emp) || '</div>'
        || '<div class="rc-datos">'
        || case when v_pais = 'MX' then 'RFC: ' else 'RIF: ' end || f_txt(v_rif_emp)
        || case when v_dir_emp is not null then '<br>' || f_txt(v_dir_emp) end
        || case when v_tel_emp is not null then '<br>Tel.: ' || f_txt(v_tel_emp) end
        || case when v_mail_emp is not null then ' &middot; ' || f_txt(v_mail_emp) end
        || '</div></td>'
        || '<td style="width:45%">'
        || '<div class="rc-tit">RECIBO DE COBRO</div>'
        || '<div class="rc-num"><strong>N&ordm;:</strong> ' || f_txt(to_char(v_rec.id_recibo)) || '</div>'
        || '<div class="rc-num"><strong>Fecha:</strong> ' || f_fecha(v_rec.fecha_cobro) || '</div>'
        || '<div class="rc-num"><strong>Estado:</strong> ' || f_txt(v_estado) || '</div>'
        || '</td></tr></table>'
        || f_anulado();

    -- La factura que este recibo cobra.
    v_html := v_html
        || '<table class="rc-caja">'
        || '<tr><td class="rc-lab" colspan="2">Factura que se cobra</td>'
        || '<td class="rc-lab">N&ordm; de control</td></tr>'
        || '<tr><td class="rc-val" colspan="2">' || f_txt(v_folio)
        || ' &nbsp;&middot;&nbsp; ' || f_fecha(v_fec_fac) || '</td>'
        || '<td class="rc-val rc-cen">' || f_txt(v_control) || '</td></tr>'
        || '<tr><td class="rc-lab" style="width:55%">Cliente</td>'
        || '<td class="rc-lab" style="width:20%">'
        || case when v_pais = 'MX' then 'RFC' else 'RIF' end || '</td>'
        || '<td class="rc-lab">Total de la factura</td></tr>'
        || '<tr><td class="rc-val">' || f_txt(v_cli) || '</td>'
        || '<td class="rc-val">' || f_txt(fn_formato_rif(v_rif_cli)) || '</td>'
        || '<td class="rc-val rc-der">' || f_num(v_tot_fac) || ' '
        || f_txt(upper(nvl(v_mon_fac, 'VES'))) || '</td></tr>'
        || '</table>';

    -- Forma de pago, referencia bancaria (cuando la hay) y la tasa guardada.
    v_html := v_html
        || '<table class="rc-caja"><tr>'
        || '<td class="rc-lab" style="width:35%">Forma de pago</td>'
        || '<td class="rc-lab" style="width:35%">Referencia bancaria</td>'
        || '<td class="rc-lab" style="width:30%">Tasa aplicada</td></tr>'
        || '<tr><td class="rc-val">' || f_txt(v_forma) || '</td>'
        || '<td class="rc-val">'
        || case when v_rec.referencia is not null then f_txt(v_rec.referencia)
                else '&mdash;' end || '</td>'
        || '<td class="rc-val">' || f_tasa(v_rec.tipo_cambio) || ' Bs / ' || f_txt(v_moneda)
        || '</td></tr></table>';

    -- Los cuatro importes, cada uno en la moneda del cobro y en bolivares.
    v_html := v_html
        || '<table class="rc-montos"><thead><tr>'
        || '<th style="width:46%">Concepto</th>'
        || '<th style="width:27%">En ' || f_txt(v_moneda) || '</th>'
        || '<th style="width:27%">En bol&iacute;vares</th>'
        || '</tr></thead><tbody>'
        || '<tr><td>Monto cobrado</td>'
        || '<td class="rc-der">' || f_num(v_rec.monto_cobrado) || '</td>'
        || '<td class="rc-der">' || f_num(v_rec.monto_bs) || '</td></tr>'
        || '<tr><td>IGTF'
        || case when nvl(v_rec.aplica_igtf, 'N') = 'S' and nvl(v_rec.igtf_monto, 0) > 0
                then ' (percibido)' end || '</td>'
        || '<td class="rc-der">' || f_num(v_rec.igtf_monto) || '</td>'
        || '<td class="rc-der">' || f_num(v_rec.igtf_bs) || '</td></tr>'
        || '<tr><td>Retenci&oacute;n de IVA'
        || case when v_rec.nro_comprobante_retencion is not null
                then ' &middot; comp. ' || f_txt(v_rec.nro_comprobante_retencion) end || '</td>'
        || '<td class="rc-der">'
        || case when v_moneda in ('VES', 'BS') then f_num(v_rec.retencion_iva_bs)
                when nvl(v_rec.retencion_iva_bs, 0) > 0
                then f_num(round(v_rec.retencion_iva_bs / nvl(v_rec.tipo_cambio, 1), 2))
                else f_num(0) end || '</td>'
        || '<td class="rc-der">' || f_num(v_rec.retencion_iva_bs) || '</td></tr>'
        || '<tr class="rc-tot"><td>Neto</td>'
        || '<td class="rc-der">' || f_num(v_rec.monto_neto) || '</td>'
        || '<td class="rc-der">' || f_num(v_neto_bs) || '</td></tr>'
        || '</tbody></table>'
        || '<div class="rc-neto">NETO COBRADO: ' || f_num(v_rec.monto_neto) || ' '
        || f_txt(v_moneda) || ' &nbsp;&middot;&nbsp; Bs ' || f_num(v_neto_bs) || '</div>';

    -- Una linea para las firmas: quien entrega (la empresa) y quien recibe.
    v_html := v_html
        || '<table class="rc-firmas"><tr>'
        || '<td style="width:50%"><div class="rc-linea"></div>'
        || '<div>Entregado por: ' || f_txt(v_emp) || ' &middot; '
        || case when v_pais = 'MX' then 'RFC ' else 'RIF ' end || f_txt(v_rif_emp) || '</div>'
        || '</td>'
        || '<td style="width:50%"><div class="rc-linea"></div>'
        || '<div>Recibido por: ' || f_txt(v_cli) || ' &middot; '
        || case when v_pais = 'MX' then 'RFC ' else 'RIF ' end
        || f_txt(fn_formato_rif(v_rif_cli)) || '</div>'
        || '</td></tr></table>'
        || '<div class="rc-pie">Recibo de cobro N&ordm; ' || f_txt(to_char(v_rec.id_recibo))
        || ' de la factura ' || f_txt(v_folio)
        || ' &middot; Documento generado por el sistema el '
        || to_char(sysdate, 'DD/MM/YYYY HH24:MI') || '</div>'
        || '</div>';

    return v_html;
end fn_imprimir_recibo;
/
