-- =============================================================================
-- funciones/fn_imprimir_retencion.sql
--
-- Los DOS comprobantes de retencion de una factura de compra, en HTML listo
-- para imprimir o guardar como PDF desde el navegador:
--
--   p_tipo = 'IVA'   Comprobante de Retencion I.V.A., con el formato de la
--                    Providencia Administrativa SNAT/2025/000054 del 02/07/2025
--                    (Gaceta Oficial N. 43.177 del 16/07/2025). Es el papel que
--                    el contador del cliente usa y el que cruza el SENIAT con el
--                    libro de compras.
--   p_tipo = 'ISLR'  Comprobante de Retencion de Impuesto sobre la Renta, con el
--                    layout operativo simple (Decreto 1.808, G.O. 36.203 del
--                    12/05/1997).
--
-- Devuelve NULL si no hay comprobante de ESE tipo: la pagina que lo use no debe
-- inventarse un documento vacio (es la leccion de los reportes de 2026-11-05: un
-- documento en blanco parece valido).
--
-- LA FUNCION NO CALCULA NADA. Lee la cabecera de RETENCIONES y las lineas de
-- RETENCIONES_DET tal como quedaron guardadas al emitir, y no vuelve a mirar
-- ISLR_CONCEPTOS, SYN_PARAMETROS ni COMPRAS: si manana cambia la UT o se corrige
-- la tarifa de un concepto, el papel reimpreso sigue diciendo lo que se emitio.
-- Lo vigila el caso R11b de deploy/diagnostico/20261119_retenciones_verificacion.sql.
--
-- Los importes van en bolivares y con el formato venezolano (miles con punto y
-- decimales con coma) por el NLS explicito de f_num, sin depender del NLS de la
-- sesion. El RIF y el N. de control son texto y no se tocan.
--
-- LLEVA EL LOGO DE LA EMPRESA QUE EMITE (2026-11-21), en los DOS tipos, arriba a
-- la izquierda y con el mismo trato que la factura: pkg_empresa_logo.fn_logo_img
-- lo devuelve como data URI. Si la empresa no tiene logo cargado devuelve NULL y
-- el documento conserva su maqueta tal cual: no queda caja vacia ni imagen rota.
--
-- La pagina 31 lo llama con UN solo argumento (IVA), de ahi el default.
-- =============================================================================

create or replace function fn_imprimir_retencion (
    p_id_compra in number,
    p_tipo      in varchar2 default 'IVA'
) return clob is
    v_tipo    varchar2(10);
    v_ret     retenciones%rowtype;
    v_emp     varchar2(200);
    v_rif_emp varchar2(30);
    v_dir_emp varchar2(300);
    v_prov    varchar2(200);
    v_rif_pro varchar2(30);
    v_dir_pro varchar2(300);
    v_html    clob;
    v_logo    clob;
    v_oper    number := 0;
    v_lineas  number;
    v_tot_tot number := 0;
    v_tot_sin number := 0;
    v_tot_bas number := 0;
    v_tot_imp number := 0;
    v_tot_ret number := 0;
    v_tot_sus number := 0;

    -- Todo texto que llega a la pantalla pasa por aqui: escape_sc corta el HTML
    -- que alguien meta en una razon social, y un nulo deja la celda vacia.
    function f_txt(p_valor varchar2) return varchar2 is
    begin
        return nvl(sys.htf.escape_sc(p_valor), '&nbsp;');
    end f_txt;

    -- Importes en bolivares con el formato de la factura venezolana: miles con
    -- punto y decimales con coma. OJO con el par de NLS_NUMERIC_CHARACTERS: es
    -- "decimal, miles", asi que el formato de aqui es ',.' (con '.,' sale el
    -- americano 1,067,106.36, que es un papel invalido). Va explicito para no
    -- depender del NLS de la sesion.
    function f_num(p_valor number) return varchar2 is
    begin
        return to_char(nvl(p_valor, 0), 'FM999G999G999G990D00',
                       'NLS_NUMERIC_CHARACTERS='',.''');
    end f_num;

    function f_fecha(p_fecha date) return varchar2 is
    begin
        return nvl(to_char(p_fecha, 'DD/MM/YYYY'), '&nbsp;');
    end f_fecha;

    -- Un comprobante anulado no se puede entregar como si valiera: el papel lo
    -- dice en grande. No es un calculo, es el estado guardado.
    function f_anulado return varchar2 is
    begin
        if v_ret.estado = 'ANULADO' then
            return '<div class="rt-anulado">COMPROBANTE ANULADO</div>';
        end if;
        return '';
    end f_anulado;
begin
    if p_id_compra is null then
        return null;
    end if;

    v_tipo := upper(trim(nvl(p_tipo, 'IVA')));
    if v_tipo not in ('IVA', 'ISLR') then
        return null;
    end if;

    begin
        select * into v_ret
          from retenciones
         where id_compra = p_id_compra
           and tipo = v_tipo;
    exception
        when no_data_found then
            return null;
    end;

    -- Una cabecera sin lineas no es un comprobante: imprimirla daria una tabla
    -- vacia con totales en 0,00, o sea un papel en blanco que parece valido. Si
    -- no hay lineas no hay documento y se devuelve NULL, igual que cuando no hay
    -- cabecera.
    select count(*) into v_lineas
      from retenciones_det
     where id_retencion = v_ret.id_retencion;
    if v_lineas = 0 then
        return null;
    end if;

    -- El agente de retencion es la empresa (la que retiene); el sujeto retenido
    -- es el proveedor. La fila fiscal puede no existir: se imprime en blanco.
    select e.nombre_empresa, nvl(e.rfc, '-'), f.direccion_fiscal
      into v_emp, v_rif_emp, v_dir_emp
      from empresas e
      left join empresa_fiscal f on f.id_empresa = e.id_empresa
     where e.id_empresa = v_ret.id_empresa;

    select p.razon_social, nvl(p.rif, '-'), p.direccion
      into v_prov, v_rif_pro, v_dir_pro
      from proveedores p
     where p.id_proveedor = v_ret.id_proveedor;

    -- El CSS viaja con el documento: la pagina 31 es una pagina normal de APEX y
    -- al imprimir hay que esconder su cromo sin depender del tema ni del CSS de la
    -- pagina (el mismo patron de los impresos de las paginas 11 y 12).
    v_html := '<style>'
        || '@page{size:A4 landscape;margin:8mm}'
        || '.spx-ret{font-family:Arial,Helvetica,sans-serif;color:#111;font-size:11px;'
        || 'line-height:1.25;background:#fff;max-width:1120px;margin:0 auto}'
        || '.spx-ret .rt-tit{font-size:16px;font-weight:bold;text-align:center;margin-top:4px}'
        || '.spx-ret .rt-logo{margin:0 0 6px 0}'
        || '.spx-ret .rt-sub{font-size:12px;font-weight:bold;text-align:center;margin-bottom:3px}'
        || '.spx-ret .rt-leg{font-size:9px;text-align:center;margin:0 auto 10px;max-width:900px}'
        || '.spx-ret table{width:100%;border-collapse:collapse;margin-bottom:8px}'
        || '.spx-ret td,.spx-ret th{border:1px solid #555;padding:3px 5px;vertical-align:top}'
        || '.spx-ret .rt-lab{font-size:9px;text-transform:uppercase;color:#333;background:#f2f2f2}'
        || '.spx-ret .rt-val{font-size:11px;font-weight:bold}'
        || '.spx-ret .rt-tabla th{font-size:9px;text-align:center;background:#f2f2f2}'
        || '.spx-ret .rt-tabla td{font-size:10px}'
        || '.spx-ret .rt-num{text-align:right;white-space:nowrap}'
        || '.spx-ret .rt-cen{text-align:center}'
        || '.spx-ret .rt-tot td{font-weight:bold;background:#fafafa}'
        || '.spx-ret .rt-firmas{margin-top:28px}'
        || '.spx-ret .rt-firmas td{border:none;padding:0 14px;font-size:10px;vertical-align:bottom}'
        || '.spx-ret .rt-linea{border-bottom:1px solid #111;height:32px;margin-bottom:3px}'
        || '.spx-ret .rt-pie{margin-top:12px;border-top:1px solid #111;padding-top:4px;'
        || 'font-size:9px;text-align:center}'
        || '.spx-ret .rt-anulado{margin:6px 0;padding:4px;border:2px solid #b00;color:#b00;'
        || 'font-size:14px;font-weight:bold;text-align:center;letter-spacing:2px}'
        || '@media print{body *{visibility:hidden}'
        || '.spx-ret,.spx-ret *{visibility:visible}'
        || '.spx-ret{position:absolute;left:0;top:0;width:100%;max-width:none}}'
        || '</style>'
        || '<div class="spx-ret">';

    -- El logo del agente de retencion (la empresa emisora), arriba a la izquierda.
    -- Mismo estilo que el de la factura. Si la empresa no tiene logo, fn_logo_img
    -- devuelve NULL: se omite el bloque entero para no dejar una caja vacia ni un
    -- <img> sin origen (que el navegador pinta como imagen rota).
    v_logo := pkg_empresa_logo.fn_logo_img(
        v_ret.id_empresa,
        'max-height:64px;max-width:220px;display:block;margin:0 0 8px 0;');
    if v_logo is not null then
        v_html := v_html || '<div class="rt-logo">' || v_logo || '</div>';
    end if;

    if v_tipo = 'IVA' then
        -- ---------------------------------------------------------------------
        -- Comprobante de Retencion I.V.A. (Providencia SNAT/2025/000054)
        -- La leyenda y los recuadros son los del formulario del cliente
        -- (libreria/FAC-6472 RET IVA ISLR INVERSORA MAYCA, C.A..pdf, pagina 2).
        -- ---------------------------------------------------------------------
        v_html := v_html
            || '<div class="rt-tit">Comprobante de Retenci&oacute;n I.V.A.</div>'
            || '<div class="rt-sub">Providencia Administrativa N&ordm; SNAT/2025/000054 '
            || 'de fecha 02 de julio de 2025</div>'
            || '<div class="rt-leg">Decreto Constituyente de Reforma Parcial del Decreto con Rango, '
            || 'Valor y Fuerza de Ley que establece el Impuesto al Valor Agregado del 29 de enero '
            || 'de 2020. Ley IVA - Art. 11: &quot;La Administraci&oacute;n Tributaria podr&aacute; '
            || 'designar como responsables del pago del impuesto en calidad de agentes de '
            || 'retenci&oacute;n, a quienes por sus funciones p&uacute;blicas o por raz&oacute;n de '
            || 'sus actividades privadas intervengan en operaciones gravadas con el impuesto '
            || 'establecido en esta Ley&quot;.</div>'
            || f_anulado()
            || '<table class="rt-boxes">'
            || '<tr><td class="rt-lab" style="width:40%">0. Nro. Comprobante</td>'
            || '<td class="rt-lab" style="width:30%">1. Fecha Emisi&oacute;n</td>'
            || '<td class="rt-lab" style="width:30%">4. Per&iacute;odo Fiscal</td></tr>'
            || '<tr><td class="rt-val">' || f_txt(v_ret.numero_comprobante) || '</td>'
            || '<td class="rt-val">' || f_fecha(v_ret.fecha_emision) || '</td>'
            || '<td class="rt-val">A&Ntilde;O: ' || to_char(v_ret.periodo_anio)
            || ' / MES: ' || to_char(v_ret.periodo_mes, 'FM00') || '</td></tr>'
            || '<tr><td class="rt-lab" colspan="2">2. Nombre o raz&oacute;n social del agente '
            || 'de retenci&oacute;n</td>'
            || '<td class="rt-lab">3. Registro de informaci&oacute;n fiscal del agente de '
            || 'retenci&oacute;n</td></tr>'
            || '<tr><td class="rt-val" colspan="2">' || f_txt(v_emp) || '</td>'
            || '<td class="rt-val">' || f_txt(v_rif_emp) || '</td></tr>'
            || '<tr><td class="rt-lab" colspan="3">5. Direcci&oacute;n fiscal del agente de '
            || 'retenci&oacute;n</td></tr>'
            || '<tr><td class="rt-val" colspan="3">' || f_txt(v_dir_emp) || '</td></tr>'
            || '<tr><td class="rt-lab" colspan="2">6. Nombre o raz&oacute;n social del sujeto '
            || 'retenido</td>'
            || '<td class="rt-lab">7. Registro de informaci&oacute;n fiscal del sujeto retenido '
            || '(R.I.F.)</td></tr>'
            || '<tr><td class="rt-val" colspan="2">' || f_txt(v_prov) || '</td>'
            || '<td class="rt-val">' || f_txt(v_rif_pro) || '</td></tr>'
            || '<tr><td class="rt-lab" colspan="3">Direcci&oacute;n fiscal del sujeto '
            || 'retenido</td></tr>'
            || '<tr><td class="rt-val" colspan="3">' || f_txt(v_dir_pro) || '</td></tr>'
            || '</table>';

        -- Una fila por linea del comprobante: una por alicuota (16 % y 8 % dejan
        -- dos), que es lo que el formulario espera en "% alic.".
        v_html := v_html
            || '<table class="rt-tabla"><thead><tr>'
            || '<th style="width:4%">Oper.<br>Nro.</th>'
            || '<th style="width:7%">Fecha</th>'
            || '<th style="width:7%">N&ordm; de<br>Factura</th>'
            || '<th style="width:7%">N&ordm; de<br>Control</th>'
            || '<th style="width:8%">N&ordm; de Nota<br>de D&eacute;bito</th>'
            || '<th style="width:8%">N&ordm; de Nota<br>de Cr&eacute;dito</th>'
            || '<th style="width:6%">Tipo de<br>Trans.</th>'
            || '<th style="width:11%">Total Compras<br>con I.V.A.</th>'
            || '<th style="width:11%">Compras sin derecho a Cr&eacute;dito</th>'
            || '<th style="width:10%">Base<br>Imponible</th>'
            || '<th style="width:6%">%<br>al&iacute;c.</th>'
            || '<th style="width:8%">Impuesto<br>I.V.A.</th>'
            || '<th style="width:8%">I.V.A.<br>Retenido</th>'
            || '</tr></thead><tbody>';

        for r in (select d.fecha_factura, d.nro_factura, d.nro_control,
                         d.nro_nota_debito, d.nro_nota_credito,
                         d.total_con_iva_bs, d.sin_derecho_credito_bs,
                         d.base_imponible_bs, d.porcentaje, d.impuesto_bs, d.retenido_bs
                    from retenciones_det d
                   where d.id_retencion = v_ret.id_retencion
                   order by d.id_linea) loop
            v_oper := v_oper + 1;
            v_html := v_html
                || '<tr>'
                || '<td class="rt-cen">' || to_char(v_oper) || '</td>'
                || '<td class="rt-cen">' || f_fecha(r.fecha_factura) || '</td>'
                || '<td>' || f_txt(r.nro_factura) || '</td>'
                || '<td class="rt-cen">' || f_txt(r.nro_control) || '</td>'
                || '<td>' || f_txt(r.nro_nota_debito) || '</td>'
                || '<td>' || f_txt(r.nro_nota_credito) || '</td>'
                || '<td class="rt-cen">01-Reg</td>'
                || '<td class="rt-num">' || f_num(r.total_con_iva_bs) || '</td>'
                || '<td class="rt-num">' || f_num(r.sin_derecho_credito_bs) || '</td>'
                || '<td class="rt-num">' || f_num(r.base_imponible_bs) || '</td>'
                || '<td class="rt-num">' || f_num(r.porcentaje) || '</td>'
                || '<td class="rt-num">' || f_num(r.impuesto_bs) || '</td>'
                || '<td class="rt-num">' || f_num(r.retenido_bs) || '</td>'
                || '</tr>';

            v_tot_tot := v_tot_tot + r.total_con_iva_bs;
            v_tot_sin := v_tot_sin + r.sin_derecho_credito_bs;
            v_tot_bas := v_tot_bas + r.base_imponible_bs;
            v_tot_imp := v_tot_imp + r.impuesto_bs;
            v_tot_ret := v_tot_ret + r.retenido_bs;
        end loop;

        -- La fila de totales suma LAS LINEAS, no la cabecera: es lo que el papel
        -- muestra arriba y lo que el contador cuadra a mano.
        v_html := v_html
            || '<tr class="rt-tot">'
            || '<td class="rt-cen" colspan="7">Totales</td>'
            || '<td class="rt-num">' || f_num(v_tot_tot) || '</td>'
            || '<td class="rt-num">' || f_num(v_tot_sin) || '</td>'
            || '<td class="rt-num">' || f_num(v_tot_bas) || '</td>'
            || '<td class="rt-cen">&nbsp;</td>'
            || '<td class="rt-num">' || f_num(v_tot_imp) || '</td>'
            || '<td class="rt-num">' || f_num(v_tot_ret) || '</td>'
            || '</tr></tbody></table>';

        v_html := v_html
            || '<table class="rt-firmas"><tr>'
            || '<td style="width:50%"><div class="rt-linea"></div>'
            || '<div>Firma del Agente de Retenci&oacute;n: '
            || f_txt(v_emp) || ' &middot; RIF ' || f_txt(v_rif_emp) || '</div>'
            || '<div style="margin-top:16px">Fecha de Entrega: ______ / ______ / ____________</div>'
            || '</td>'
            || '<td style="width:50%"><div class="rt-linea"></div>'
            || '<div>Firma del Sujeto Retenido: ' || f_txt(v_prov) || '</div>'
            || '<div style="margin-top:16px">Fecha de Recepci&oacute;n: ______ / ______ / ____________</div>'
            || '</td></tr></table>'
            || '<div class="rt-pie">Este comprobante se emite seg&uacute;n lo establecido en el '
            || 'Art&iacute;culo N&ordm; 16 de la Providencia Administrativa SNAT/2025/000054 de '
            || 'fecha 02 de julio de 2025, publicada en Gaceta Oficial N&ordm; 43.177 de fecha 16 '
            || 'de julio de 2025.</div>';
    else
        -- ---------------------------------------------------------------------
        -- Comprobante de Retencion de Impuesto sobre la Renta (layout simple)
        -- ---------------------------------------------------------------------
        v_html := v_html
            || '<div class="rt-tit">Comprobante de Retenci&oacute;n de Impuesto sobre la '
            || 'Renta</div>'
            || '<div class="rt-sub">Decreto 1.808 &middot; Gaceta Oficial N&ordm; 36.203 del '
            || '12/05/1997</div>'
            || '<div class="rt-leg">Para dar cumplimiento con la normativa establecida en el '
            || 'Art&iacute;culo 24 del Decreto 1.808 en materia de retenci&oacute;n del impuesto '
            || 'sobre la renta, publicado en Gaceta Oficial N&ordm; 36.203 del 12 de mayo de '
            || '1997.</div>'
            || f_anulado()
            || '<table class="rt-boxes">'
            || '<tr><td class="rt-lab" style="width:40%">Nro. Comprobante</td>'
            || '<td class="rt-lab" style="width:30%">Fecha de Emisi&oacute;n</td>'
            || '<td class="rt-lab" style="width:30%">Per&iacute;odo Fiscal</td></tr>'
            || '<tr><td class="rt-val">' || f_txt(v_ret.numero_comprobante) || '</td>'
            || '<td class="rt-val">' || f_fecha(v_ret.fecha_emision) || '</td>'
            || '<td class="rt-val">A&Ntilde;O: ' || to_char(v_ret.periodo_anio)
            || ' / MES: ' || to_char(v_ret.periodo_mes, 'FM00') || '</td></tr>'
            || '<tr><td class="rt-lab" colspan="2">Agente de retenci&oacute;n: nombre o '
            || 'raz&oacute;n social</td>'
            || '<td class="rt-lab">Registro de informaci&oacute;n fiscal (R.I.F.)</td></tr>'
            || '<tr><td class="rt-val" colspan="2">' || f_txt(v_emp) || '</td>'
            || '<td class="rt-val">' || f_txt(v_rif_emp) || '</td></tr>'
            || '<tr><td class="rt-lab" colspan="3">Direcci&oacute;n fiscal del agente de '
            || 'retenci&oacute;n</td></tr>'
            || '<tr><td class="rt-val" colspan="3">' || f_txt(v_dir_emp) || '</td></tr>'
            || '<tr><td class="rt-lab" colspan="2">Beneficiario: nombre o raz&oacute;n '
            || 'social</td>'
            || '<td class="rt-lab">Registro de informaci&oacute;n fiscal (R.I.F.)</td></tr>'
            || '<tr><td class="rt-val" colspan="2">' || f_txt(v_prov) || '</td>'
            || '<td class="rt-val">' || f_txt(v_rif_pro) || '</td></tr>'
            || '<tr><td class="rt-lab" colspan="3">Direcci&oacute;n fiscal del '
            || 'beneficiario</td></tr>'
            || '<tr><td class="rt-val" colspan="3">' || f_txt(v_dir_pro) || '</td></tr>'
            || '<tr><td class="rt-lab" style="width:20%">C&oacute;digo SENIAT</td>'
            || '<td class="rt-lab" colspan="2">Concepto / actividad</td></tr>'
            || '<tr><td class="rt-val rt-cen">' || f_txt(v_ret.codigo_concepto) || '</td>'
            || '<td class="rt-val" colspan="2">' || f_txt(v_ret.actividad) || '</td></tr>'
            || '</table>';

        v_html := v_html
            || '<table class="rt-tabla"><thead><tr>'
            || '<th style="width:8%">Operaci&oacute;n<br>N&ordm;</th>'
            || '<th style="width:10%">Fecha de<br>emisi&oacute;n</th>'
            || '<th style="width:10%">N&ordm;<br>Factura</th>'
            || '<th style="width:11%">N&ordm;<br>Control</th>'
            || '<th style="width:14%">Total factura<br>Bs.</th>'
            || '<th style="width:14%">Base retenci&oacute;n<br>Bs.</th>'
            || '<th style="width:9%">%<br>Retenci&oacute;n</th>'
            || '<th style="width:12%">Sustraendo<br>Bs.</th>'
            || '<th style="width:12%">Valor retenci&oacute;n<br>Bs.</th>'
            || '</tr></thead><tbody>';

        for r in (select d.fecha_factura, d.nro_factura, d.nro_control,
                         d.total_con_iva_bs, d.base_imponible_bs, d.porcentaje,
                         d.sustraendo_bs, d.retenido_bs
                    from retenciones_det d
                   where d.id_retencion = v_ret.id_retencion
                   order by d.id_linea) loop
            v_oper := v_oper + 1;
            v_html := v_html
                || '<tr>'
                || '<td class="rt-cen">' || to_char(v_oper) || '</td>'
                || '<td class="rt-cen">' || f_fecha(r.fecha_factura) || '</td>'
                || '<td>' || f_txt(r.nro_factura) || '</td>'
                || '<td class="rt-cen">' || f_txt(r.nro_control) || '</td>'
                || '<td class="rt-num">' || f_num(r.total_con_iva_bs) || '</td>'
                || '<td class="rt-num">' || f_num(r.base_imponible_bs) || '</td>'
                || '<td class="rt-num">' || f_num(r.porcentaje) || '</td>'
                || '<td class="rt-num">' || f_num(r.sustraendo_bs) || '</td>'
                || '<td class="rt-num">' || f_num(r.retenido_bs) || '</td>'
                || '</tr>';

            v_tot_tot := v_tot_tot + r.total_con_iva_bs;
            v_tot_bas := v_tot_bas + r.base_imponible_bs;
            v_tot_sus := v_tot_sus + r.sustraendo_bs;
            v_tot_ret := v_tot_ret + r.retenido_bs;
        end loop;

        v_html := v_html
            || '<tr class="rt-tot">'
            || '<td class="rt-cen" colspan="4">Totales</td>'
            || '<td class="rt-num">' || f_num(v_tot_tot) || '</td>'
            || '<td class="rt-num">' || f_num(v_tot_bas) || '</td>'
            || '<td class="rt-cen">&nbsp;</td>'
            || '<td class="rt-num">' || f_num(v_tot_sus) || '</td>'
            || '<td class="rt-num">' || f_num(v_tot_ret) || '</td>'
            || '</tr></tbody></table>';

        v_html := v_html
            || '<table class="rt-firmas"><tr>'
            || '<td style="width:50%"><div class="rt-linea"></div>'
            || '<div>Firma del Beneficiario: ' || f_txt(v_prov) || '</div>'
            || '<div>RIF ' || f_txt(v_rif_pro) || '</div>'
            || '</td>'
            || '<td style="width:50%"><div class="rt-linea"></div>'
            || '<div>Firma del Agente de Retenci&oacute;n: ' || f_txt(v_emp) || '</div>'
            || '<div>RIF ' || f_txt(v_rif_emp) || '</div>'
            || '</td></tr></table>';
    end if;

    v_html := v_html || '</div>';

    return v_html;
end fn_imprimir_retencion;
/
