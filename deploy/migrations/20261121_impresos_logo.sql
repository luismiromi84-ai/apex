-- =============================================================================
-- 20261121_impresos_logo.sql
--
-- El logo de la empresa en TODOS los impresos, y el recibo de cobro en papel.
--
--   1. fn_imprimir_retencion: pinta el logo de la empresa emisora arriba a la
--      izquierda, en los DOS tipos (IVA e ISLR). Si la empresa no tiene logo,
--      fn_logo_img devuelve NULL y el documento conserva su maqueta.
--   2. fn_libro_excel: pinta el logo en el membrete SOLO cuando p_imprimir='S'
--      (la version para papel/PDF). El Excel (p_imprimir='N') NO lo lleva a
--      proposito: un <img> con data URI dentro del HTML que abre Excel no es
--      fiable y romperia el archivo que el cliente ya usa a diario.
--   3. fn_imprimir_recibo: NUEVA. El recibo de cobro en papel. Lee las columnas
--      guardadas de RECIBOS (no recalcula nada) y devuelve NULL si el recibo no
--      existe.
--
-- No toca tablas ni datos. El cuerpo de cada funcion es el canonico del repo
-- (funciones/), copiado tal cual para no transcribirlo a mano.
--
-- Reversa: volver a compilar las funciones anteriores del repo (git) y
-- `drop function fn_imprimir_recibo`.
-- Verificacion: deploy/diagnostico/20261121_impresos_logo_verificacion.sql
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

-- ---------------------------------------------------------------------------
-- funciones/fn_imprimir_retencion.sql
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- funciones/fn_libro_excel.sql
-- ---------------------------------------------------------------------------
-- =============================================================================
-- fn_libro_excel.sql
--
-- Devuelve el «Excel fiscal» del Libro de compras y ventas (página 18) como un
-- documento HTML que Excel abre con formato: membrete (empresa, RIF y período),
-- cabecera, una fila por documento y una fila de TOTALES.
--
-- Por qué HTML y no XLSX: el botón nativo del informe (XLSX) exporta las columnas
-- del informe con sus máscaras, pero sin membrete ni totales. Este documento es
-- autónomo, trae los importes como NÚMEROS y deja el RIF y el N° de Control como
-- TEXTO (así Excel no se come los ceros a la izquierda).
--
-- La consulta NO se copia: se ejecuta la que tiene guardada el informe, con sus
-- binds sustituidos. Una sola fuente de verdad con la pantalla.
-- =============================================================================

create or replace function fn_libro_excel (
    p_libro      in varchar2,     -- 'VENTAS' | 'COMPRAS' | 'TODOS'
    p_mes        in number,
    p_anio       in number,
    p_id_empresa in number,
    p_periodo    in varchar2 default 'MES',   -- 'MES' | 'Q1' | 'Q2'
    p_imprimir   in varchar2 default 'N'      -- 'S' = versión para imprimir/PDF
) return clob is
    type t_suma is table of number index by binary_integer;

    v_region  number;
    v_sql     clob;
    v_html    clob;
    v_c       integer;
    v_ncols   number;
    v_dummy   number;
    v_desc    dbms_sql.desc_tab;
    v_vc      varchar2(4000);
    v_txt     varchar2(4000);
    v_num     number;
    v_empresa varchar2(200);
    v_rif     varchar2(40);
    v_pais    varchar2(2);
    v_cab     clob;
    v_logo    clob;
    v_filas   number := 0;
    v_hay     number;
    v_mes_tx  varchar2(20);
    v_sumas   t_suma;
    v_primera boolean := true;
begin
    -- 1. La consulta guardada del informe. El libro que se imprime depende del
    -- PAIS de la empresa (Venezuela o Mexico), no del filtro de tipo: son dos
    -- regiones distintas, con columnas fiscales distintas.
    select e.nombre_empresa, fn_formato_rif(e.rfc), nvl(e.cod_pais, 'VE')
      into v_empresa, v_rif, v_pais
      from empresas e
     where e.id_empresa = p_id_empresa;

    if v_pais = 'MX' then
        v_region := 43000000000000740;   -- Libro de Mexico
    else
        v_region := 43000000000000710;   -- Libro de Venezuela
    end if;

    select region_source into v_sql
      from apex_application_page_regions
     where application_id = 100 and region_id = v_region;

    v_sql := replace(v_sql, ':F_EMPRESA_ACTIVA', to_char(p_id_empresa));
    v_sql := replace(v_sql, ':P18_ID_EMPRESA', to_char(p_id_empresa));
    v_sql := replace(v_sql, ':P18_LIBRO', '''' || upper(nvl(p_libro, 'TODOS')) || '''');
    v_sql := replace(v_sql, ':P18_MES', to_char(p_mes));
    v_sql := replace(v_sql, ':P18_ANIO', to_char(p_anio));
    v_sql := replace(v_sql, ':P18_PERIODO', '''' || upper(nvl(p_periodo, 'MES')) || '''');
    v_sql := replace(v_sql, ':APP_USER', '''');

    -- 2. Membrete (la empresa ya se leyo arriba, para elegir el libro)
    v_mes_tx := lpad(to_char(p_mes), 2, '0') || '/' || to_char(p_anio);

    v_cab := '<div class="titulo">' || sys.htf.escape_sc(v_empresa) || '</div>'
          || '<div class="sub">'
          || case when v_pais = 'MX' then 'RFC: ' else 'RIF: ' end
          || sys.htf.escape_sc(v_rif)
          || ' &nbsp;&nbsp; Libro de compras y ventas - ' || v_mes_tx
          || case upper(nvl(p_periodo, 'MES'))
                 when 'Q1' then ' (1ra quincena: 1 al 15)'
                 when 'Q2' then ' (2da quincena: 16 al final)'
                 else ' (mes completo)'
             end
          || ' &nbsp;&nbsp; Documentos: '
          || case upper(nvl(p_libro, 'TODOS'))
                 when 'VENTAS'  then 'ventas'
                 when 'COMPRAS' then 'compras'
                 else 'compras y ventas'
             end
          || '</div>';

    -- EL LOGO SOLO EN LA VERSION IMPRIMIBLE (2026-11-21), al lado del nombre, el
    -- RIF y el periodo. En el Excel (p_imprimir='N') NO se pone a proposito: un
    -- <img> con data URI dentro del HTML que abre Excel no es fiable y romperia
    -- el archivo que el cliente ya usa a diario. Esa asimetria es deliberada.
    if upper(nvl(p_imprimir, 'N')) = 'S' then
        v_logo := pkg_empresa_logo.fn_logo_img(
            p_id_empresa,
            'max-height:64px;max-width:220px;display:block;');
        if v_logo is not null then
            v_cab := '<table style="border:none;margin:0 0 6px 0"><tr>'
                  || '<td style="border:none;padding:0 12px 0 0;vertical-align:middle">'
                  || v_logo || '</td>'
                  || '<td style="border:none;padding:0;vertical-align:middle">'
                  || v_cab || '</td></tr></table>';
        end if;
    end if;

    v_html := '<html><head><meta http-equiv="Content-Type" content="text/html; charset=utf-8">'
           || '<style>'
           || 'table { border-collapse: collapse; font-family: Arial, sans-serif; font-size: 11px; }'
           || 'td, th { border: 1px solid #b8c4cc; padding: 3px 6px; }'
           || 'th { background: #0076ce; color: #fff; font-weight: bold; }'
           || '.titulo { font-size: 16px; font-weight: bold; }'
           || '.sub { font-size: 12px; color: #334155; margin: 4px 0 8px 0; }'
           || '.num { mso-number-format:"#\,##0\.00"; text-align: right; }'
           || '.txt { mso-number-format:"\@"; }'
           || '.fec { mso-number-format:"dd\/mm\/yyyy"; }'
           || '.tot { background: #eaf3f6; font-weight: bold; }'
           || case when upper(nvl(p_imprimir, 'N')) = 'S' then
                  -- version para imprimir / PDF: A4 horizontal, la cabecera se repite
                  -- en cada pagina y el navegador abre el dialogo de impresion solo.
                  '@page { size: A4 landscape; margin: 8mm; }'
                  || 'body { margin: 0; }'
                  || 'thead { display: table-header-group; }'
                  || 'tr { page-break-inside: avoid; }'
                  || 'th { -webkit-print-color-adjust: exact; print-color-adjust: exact; }'
              else '' end
           || '</style>'
           || case when upper(nvl(p_imprimir, 'N')) = 'S' then
                  '<title>Libro de compras y ventas</title>'
                  || '<script>window.addEventListener("load", function () {'
                  || '  window.addEventListener("afterprint", function () { window.history.back(); });'
                  || '  window.print();});</script>'
              else '' end
           || '</head><body>'
           || v_cab;

    -- 3. La consulta, en un cursor dinámico
    v_c := dbms_sql.open_cursor;
    dbms_sql.parse(v_c, v_sql, dbms_sql.native);
    dbms_sql.describe_columns(v_c, v_ncols, v_desc);
    for i in 1 .. v_ncols loop
        if v_desc(i).col_type = dbms_sql.number_type then
            dbms_sql.define_column(v_c, i, v_num);
            v_sumas(i) := 0;
        else
            dbms_sql.define_column(v_c, i, v_vc, 4000);
        end if;
    end loop;
    v_dummy := dbms_sql.execute(v_c);

    -- 4. Cabecera
    v_html := v_html || '<table><thead><tr>';
    for i in 1 .. v_ncols loop
        -- Las columnas de enlace del informe («Ver» de la factura y «Ver compra»)
        -- no van en el Excel fiscal: se reconocen por su alias (VER_...), no por
        -- la posicion, para que un cambio en el informe no descuadre el archivo.
        if substr(upper(v_desc(i).col_name), 1, 4) <> 'VER_' then
            v_html := v_html || '<th>' || sys.htf.escape_sc(
                case upper(v_desc(i).col_name)
                    when 'LIBRO' then 'Libro'
                    when 'FECHA_EMISION' then 'Fecha'
                    when 'RIF' then case when v_pais = 'MX' then 'RFC' else 'RIF' end
                    when 'RAZON_SOCIAL' then 'Raz' || unistr('\00F3') || 'n social'
                    when 'TIPO' then 'Tipo'
                    when 'FOLIO' then 'N' || unistr('\00BA') || ' factura'
                    when 'NRO_CONTROL' then case when v_pais = 'MX' then 'UUID (CFDI)'
                                                 else 'N' || unistr('\00BA') || ' control' end
                    when 'MONEDA' then 'Moneda'
                    when 'TASA' then 'Tasa BCV'
                    when 'TOTAL_DIVISA' then 'Total en divisa'
                    when 'BASE16' then 'Base 16%'
                    when 'IVA16' then 'IVA 16%'
                    when 'BASE8' then 'Base 8%'
                    when 'IVA8' then 'IVA 8%'
                    when 'EXENTO' then 'Exento'
                    when 'BASE_IGTF' then 'Base IGTF'
                    when 'IGTF' then 'IGTF 3%'
                    when 'IGTF_COMPRA' then 'IGTF compra'
                    when 'OTRAS_BASE' then 'Otras base'
                    when 'OTRAS_IVA' then 'Otras IVA'
                    when 'TOTAL_BS' then 'Total Bs'
                    when 'COMPROBANTE' then 'N' || unistr('\00BA') || ' comp. retenci' || unistr('\00F3') || 'n'
                    when 'RETENCION_BS' then 'IVA retenido Bs'
                    when 'NETO' then 'Neto Bs'
                    when 'ESTADO' then 'Estado'
                    when 'AFECTADA' then 'Documento afectado'
                    else upper(v_desc(i).col_name)
                end) || '</th>';
        end if;
    end loop;
    v_html := v_html || '</tr></thead><tbody>';

    -- 5. Filas
    -- OJO: aqui no se usa "exit": importar_export.py descarta las lineas que empiezan
    -- por "exit" y el bucle quedaria SIN SALIDA (cuelgue medido el 2026-11-18). Se
    -- recorre con un while.
    v_hay := dbms_sql.fetch_rows(v_c);
    while v_hay > 0 loop
        v_filas := v_filas + 1;
        v_html := v_html || '<tr>';
        for i in 1 .. v_ncols loop
            continue when substr(upper(v_desc(i).col_name), 1, 4) = 'VER_';
            if v_desc(i).col_type = dbms_sql.number_type then
                dbms_sql.column_value(v_c, i, v_num);
                if v_num is not null then
                    v_sumas(i) := v_sumas(i) + v_num;
                end if;
                v_html := v_html || '<td class="num">'
                    || case when v_num is null then ''
                            else to_char(v_num, 'FM999999999999999990.00',
                                         'NLS_NUMERIC_CHARACTERS=''.,''') end
                    || '</td>';
            else
                dbms_sql.column_value(v_c, i, v_vc);
                if upper(v_desc(i).col_name) like '%FECHA%' then
                    -- La consulta del informe devuelve la fecha ya formateada por
                    -- TO_CHAR (p. ej. 07-NOV-26). Se normaliza a dd/mm/aaaa para
                    -- que Excel la reconozca como fecha y no dependa del idioma de
                    -- los nombres de mes de la sesion.
                    v_txt := v_vc;
                    if v_txt is not null then
                        begin
                            v_txt := to_char(to_date(v_txt, 'DD-MON-RR',
                                                     'NLS_DATE_LANGUAGE=SPANISH'), 'DD/MM/YYYY');
                        exception
                            when others then
                                begin
                                    v_txt := to_char(to_date(v_txt, 'DD-MON-RR',
                                                             'NLS_DATE_LANGUAGE=ENGLISH'), 'DD/MM/YYYY');
                                exception
                                    when others then null;   -- se deja tal cual
                                end;
                        end;
                    end if;
                    v_html := v_html || '<td class="fec">' || sys.htf.escape_sc(nvl(v_txt, ' ')) || '</td>';
                else
                    v_html := v_html || '<td class="txt">' || sys.htf.escape_sc(nvl(v_vc, ' ')) || '</td>';
                end if;
            end if;
        end loop;
        v_html := v_html || '</tr>';
        v_hay := dbms_sql.fetch_rows(v_c);
    end loop;

    dbms_sql.close_cursor(v_c);

    -- 6. Totales: la suma de cada columna de dinero, calculada al recorrer las
    -- filas. La etiqueta TOTALES va en la primera celda que se pinta.
    v_html := v_html || '</tbody><tfoot><tr class="tot">';
    v_primera := true;
    for i in 1 .. v_ncols loop
        if substr(upper(v_desc(i).col_name), 1, 4) = 'VER_' then
            continue;
        end if;
        if v_primera then
            v_html := v_html || '<td class="txt">TOTALES</td>';
            v_primera := false;
        elsif v_desc(i).col_type = dbms_sql.number_type
              and upper(v_desc(i).col_name) <> 'TASA' then
            v_html := v_html || '<td class="num">'
                || to_char(v_sumas(i), 'FM999999999999999990.00',
                           'NLS_NUMERIC_CHARACTERS=''.,''') || '</td>';
        else
            v_html := v_html || '<td class="txt"></td>';   -- una tasa o un texto no se suman
        end if;
    end loop;
    v_html := v_html || '</tr></tfoot></table>'
           || '<p class="sub">Documentos: ' || v_filas || ' - generado el '
           || to_char(sysdate, 'DD/MM/YYYY HH24:MI') || '</p>'
           || '</body></html>';

    return v_html;
exception
    when others then
        if dbms_sql.is_open(v_c) then
            dbms_sql.close_cursor(v_c);
        end if;
        raise;
end fn_libro_excel;
/

-- ---------------------------------------------------------------------------
-- funciones/fn_imprimir_recibo.sql
-- ---------------------------------------------------------------------------
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

begin
    dbms_utility.compile_schema('WKSP_SYPEXWS', false);
end;
/

declare
    v_n number;
begin
    select count(*) into v_n from all_objects
     where owner = 'WKSP_SYPEXWS'
       and object_name in ('FN_IMPRIMIR_RETENCION', 'FN_LIBRO_EXCEL', 'FN_IMPRIMIR_RECIBO')
       and status = 'VALID';
    if v_n <> 3 then
        raise_application_error(-20112, 'quedaron invalidas las funciones de los impresos');
    end if;

    -- El comprobante con logo lleva la imagen incrustada.
    select instr(fn_imprimir_retencion((select min(id_compra) from retenciones
                                         where id_compra is not null), 'IVA'), 'data:image')
      into v_n from dual;
    if v_n = 0 then
        raise_application_error(-20112, 'el comprobante de retencion no lleva el logo');
    end if;

    -- El libro imprimible si, el Excel no.
    select instr(fn_libro_excel('TODOS', extract(month from sysdate),
                                extract(year from sysdate), 1, 'MES', 'S'), 'data:image')
      into v_n from dual;
    if v_n = 0 then
        raise_application_error(-20112, 'el libro imprimible no lleva el logo');
    end if;
    select instr(fn_libro_excel('TODOS', extract(month from sysdate),
                                extract(year from sysdate), 1, 'MES', 'N'), '<img')
      into v_n from dual;
    if v_n > 0 then
        raise_application_error(-20112, 'el Excel lleva una imagen y rompe el archivo');
    end if;
end;
/
