-- =============================================================================
-- 20261122_imprimir_pago.sql
--
-- fn_imprimir_pago: el COMPROBANTE DE PAGO en papel (pagina 38), espejo del
-- recibo de cobro (fn_imprimir_recibo, pagina 35) pero del dinero que sale.
-- No calcula nada: lee PAGOS, PAGOS_DETALLE y las facturas aplicadas.
--
-- Idempotente: recrea la funcion y valida.
--
-- Uso:
--   python deploy/conexion/importar_export.py deploy/migrations/20261122_imprimir_pago.sql
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

-- =============================================================================
-- funciones/fn_imprimir_pago.sql
--
-- El COMPROBANTE DE PAGO en papel (2026-11-22): el documento que se le entrega
-- al proveedor cuando se le paga. Es el espejo de fn_imprimir_recibo (recibo de
-- cobro, pagina 35) pero del dinero que sale.
--
-- Devuelve el HTML listo para imprimir o guardar como PDF desde el navegador, o
-- NULL si el pago no existe: la pagina 38 no debe inventarse un documento en
-- blanco (es la leccion de los reportes de 2026-11-05).
--
-- LA FUNCION NO CALCULA NADA. Lee las columnas guardadas del pago (MONTO,
-- MONTO_BS, IGTF_MONTO, IGTF_BS, TIPO_CAMBIO) y las facturas que aplico
-- (PAGOS_DETALLE.MONTO_APLICADO). Lo unico que se suma es lo que el papel
-- declara como total desembolsado: monto + IGTF, en las dos monedas. Nada se
-- recalcula: si manana cambia la alicuota del IGTF, el papel reimpreso sigue
-- diciendo lo que se pago.
--
-- Los importes van con el formato venezolano (miles con punto y decimales con
-- coma) por el NLS explicito de f_num. El RIF, el folio y la referencia
-- bancaria son texto y no se tocan.
--
-- LLEVA EL LOGO de la empresa que paga, arriba a la izquierda y con el mismo
-- trato que la factura (pkg_empresa_logo.fn_logo_img). Si la empresa no tiene
-- logo cargado devuelve NULL y el documento conserva su maqueta: ni caja vacia
-- ni imagen rota.
--
-- El CSS viaja con el documento y esconde el cromo de APEX al imprimir, el
-- mismo patron de las paginas 11, 12, 31 y 35.
-- =============================================================================

create or replace function fn_imprimir_pago (
    p_id_pago in number
) return clob is
    v_pag      pagos%rowtype;
    v_emp      varchar2(200);
    v_rif_emp  varchar2(40);
    v_pais     varchar2(2);
    v_dir_emp  varchar2(300);
    v_tel_emp  varchar2(60);
    v_mail_emp varchar2(120);
    v_prov     varchar2(200);
    v_rif_prov varchar2(30);
    v_forma    varchar2(120);
    v_estado   varchar2(20);
    v_moneda   varchar2(5);
    v_logo     clob;
    v_html     clob;
    v_filas    clob := '';
    v_total    number := 0;
    v_n        number := 0;

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

    function f_tasa(p_valor number) return varchar2 is
    begin
        return to_char(nvl(p_valor, 1), 'FM999G999G999G990D0000',
                       'NLS_NUMERIC_CHARACTERS='',.''');
    end f_tasa;

    function f_fecha(p_fecha date) return varchar2 is
    begin
        return nvl(to_char(p_fecha, 'DD/MM/YYYY'), '&nbsp;');
    end f_fecha;

    -- Un pago anulado no se puede entregar como si valiera.
    function f_anulado return varchar2 is
    begin
        if v_pag.estado = 'ANULADO' then
            return '<div class="pg-anulado">COMPROBANTE ANULADO</div>';
        end if;
        return '';
    end f_anulado;
begin
    if p_id_pago is null then
        return null;
    end if;

    begin
        select * into v_pag
          from pagos
         where id_pago = p_id_pago;
    exception
        when no_data_found then
            return null;
    end;

    -- La empresa que paga. La fila fiscal puede no existir: se imprime vacia.
    select e.nombre_empresa, nvl(fn_formato_rif(e.rfc), '-'),
           nvl(e.cod_pais, 'VE'), f.direccion_fiscal, f.telefono, f.email
      into v_emp, v_rif_emp, v_pais, v_dir_emp, v_tel_emp, v_mail_emp
      from empresas e
      left join empresa_fiscal f on f.id_empresa = e.id_empresa
     where e.id_empresa = v_pag.id_empresa;

    select pr.razon_social, pr.rif
      into v_prov, v_rif_prov
      from proveedores pr
     where pr.id_proveedor = v_pag.id_proveedor;

    begin
        select descripcion into v_forma
          from forma_pago where id_forma_pago = v_pag.id_forma_pago;
    exception
        when no_data_found then
            v_forma := null;
    end;

    v_moneda := upper(nvl(v_pag.cod_moneda, 'VES'));
    v_estado := case when v_pag.estado = 'ACTIVO' then 'EMITIDO'
                     else nvl(v_pag.estado, 'ANULADO') end;

    -- Las facturas de compra que este pago cancela o abona, con lo aplicado.
    -- El papel no suma importes de la deuda: muestra lo que el pago aplico.
    for r in (select co.folio_factura, co.fecha_emision, co.cod_moneda,
                     co.monto_total, d.monto_aplicado
                from pagos_detalle d
                join compras co on co.id_compra = d.id_compra
               where d.id_pago = v_pag.id_pago
               order by co.fecha_emision, co.id_compra) loop
        v_n := v_n + 1;
        v_total := v_total + nvl(r.monto_aplicado, 0);
        v_filas := v_filas
            || '<tr><td>' || f_txt(r.folio_factura) || '</td>'
            || '<td class="pg-cen">' || f_fecha(r.fecha_emision) || '</td>'
            || '<td class="pg-cen">' || f_txt(upper(nvl(r.cod_moneda, 'VES'))) || '</td>'
            || '<td class="pg-der">' || f_num(r.monto_total) || '</td>'
            || '<td class="pg-der">' || f_num(r.monto_aplicado) || '</td></tr>';
    end loop;

    v_html := '<style>'
        || '@page{size:A4 portrait;margin:10mm}'
        || '.spx-pag{font-family:Arial,Helvetica,sans-serif;color:#111;font-size:11px;'
        || 'line-height:1.3;background:#fff;max-width:780px;margin:0 auto}'
        || '.spx-pag .pg-logo{margin:0 0 8px 0}'
        || '.spx-pag .pg-cab{width:100%;border-collapse:collapse;margin-bottom:8px}'
        || '.spx-pag .pg-cab td{border:none;padding:0;vertical-align:top}'
        || '.spx-pag .pg-emp{font-size:15px;font-weight:bold}'
        || '.spx-pag .pg-datos{font-size:9px;color:#333}'
        || '.spx-pag .pg-tit{font-size:16px;font-weight:bold;text-align:right;'
        || 'color:#005b96;letter-spacing:1px}'
        || '.spx-pag .pg-num{font-size:12px;text-align:right;margin-top:2px}'
        || '.spx-pag table.pg-caja{width:100%;border-collapse:collapse;margin-bottom:8px}'
        || '.spx-pag table.pg-caja td{border:1px solid #555;padding:3px 6px;vertical-align:top}'
        || '.spx-pag .pg-lab{font-size:9px;text-transform:uppercase;color:#333;background:#f2f2f2}'
        || '.spx-pag .pg-val{font-size:11px;font-weight:bold}'
        || '.spx-pag table.pg-montos{width:100%;border-collapse:collapse;margin-bottom:8px}'
        || '.spx-pag table.pg-montos th{border:1px solid #555;padding:3px 6px;'
        || 'font-size:9px;text-transform:uppercase;background:#f2f2f2;text-align:left}'
        || '.spx-pag table.pg-montos td{border:1px solid #555;padding:4px 6px;font-size:11px}'
        || '.spx-pag .pg-der{text-align:right;white-space:nowrap}'
        || '.spx-pag .pg-cen{text-align:center}'
        || '.spx-pag .pg-tot td{font-weight:bold;background:#fafafa}'
        || '.spx-pag .pg-neto{margin:0 0 10px 0;padding:6px 10px;border:2px solid #0f766e;'
        || 'background:#f0fdfa;font-size:13px;font-weight:bold;text-align:right;color:#0f766e}'
        || '.spx-pag .pg-firmas{margin-top:34px;width:100%;border-collapse:collapse}'
        || '.spx-pag .pg-firmas td{border:none;padding:0 14px;font-size:10px;vertical-align:bottom}'
        || '.spx-pag .pg-linea{border-bottom:1px solid #111;height:34px;margin-bottom:3px}'
        || '.spx-pag .pg-pie{margin-top:12px;border-top:1px solid #111;padding-top:4px;'
        || 'font-size:9px;text-align:center}'
        || '.spx-pag .pg-anulado{margin:6px 0;padding:4px;border:2px solid #b00;color:#b00;'
        || 'font-size:14px;font-weight:bold;text-align:center;letter-spacing:2px}'
        || '.spx-pag .pg-obs{margin:0 0 8px 0;font-size:10px}'
        || '@media print{body *{visibility:hidden}'
        || '.spx-pag,.spx-pag *{visibility:visible}'
        || '.spx-pag{position:absolute;left:0;top:0;width:100%;max-width:none}}'
        || '</style>'
        || '<div class="spx-pag">';

    v_logo := pkg_empresa_logo.fn_logo_img(
        v_pag.id_empresa,
        'max-height:64px;max-width:220px;display:block;margin:0 0 8px 0;');
    if v_logo is not null then
        v_html := v_html || '<div class="pg-logo">' || v_logo || '</div>';
    end if;

    -- Cabecera: quien paga a la izquierda, titulo y numero a la derecha.
    v_html := v_html
        || '<table class="pg-cab"><tr>'
        || '<td style="width:55%">'
        || '<div class="pg-emp">' || f_txt(v_emp) || '</div>'
        || '<div class="pg-datos">'
        || case when v_pais = 'MX' then 'RFC: ' else 'RIF: ' end || f_txt(v_rif_emp)
        || case when v_dir_emp is not null then '<br>' || f_txt(v_dir_emp) end
        || case when v_tel_emp is not null then '<br>Tel.: ' || f_txt(v_tel_emp) end
        || case when v_mail_emp is not null then ' &middot; ' || f_txt(v_mail_emp) end
        || '</div></td>'
        || '<td style="width:45%">'
        || '<div class="pg-tit">COMPROBANTE DE PAGO</div>'
        || '<div class="pg-num"><strong>N&ordm;:</strong> ' || f_txt(to_char(v_pag.id_pago)) || '</div>'
        || '<div class="pg-num"><strong>Fecha:</strong> ' || f_fecha(v_pag.fecha_pago) || '</div>'
        || '<div class="pg-num"><strong>Estado:</strong> ' || f_txt(v_estado) || '</div>'
        || '</td></tr></table>'
        || f_anulado();

    -- El proveedor al que se le paga.
    v_html := v_html
        || '<table class="pg-caja"><tr>'
        || '<td class="pg-lab" style="width:60%">Proveedor</td>'
        || '<td class="pg-lab" style="width:20%">'
        || case when v_pais = 'MX' then 'RFC' else 'RIF' end || '</td>'
        || '<td class="pg-lab" style="width:20%">Conciliado</td></tr>'
        || '<tr><td class="pg-val">' || f_txt(v_prov) || '</td>'
        || '<td class="pg-val">' || f_txt(fn_formato_rif(v_rif_prov)) || '</td>'
        || '<td class="pg-val pg-cen">'
        || case when nvl(v_pag.conciliado, 'N') = 'S' then 'Si' else 'No' end
        || '</td></tr></table>';

    -- Forma de pago, referencia bancaria y la tasa guardada.
    v_html := v_html
        || '<table class="pg-caja"><tr>'
        || '<td class="pg-lab" style="width:35%">Forma de pago</td>'
        || '<td class="pg-lab" style="width:35%">Referencia bancaria</td>'
        || '<td class="pg-lab" style="width:30%">Tasa aplicada</td></tr>'
        || '<tr><td class="pg-val">' || f_txt(v_forma) || '</td>'
        || '<td class="pg-val">'
        || case when v_pag.referencia is not null then f_txt(v_pag.referencia)
                else '&mdash;' end || '</td>'
        || '<td class="pg-val">' || f_tasa(v_pag.tipo_cambio) || ' Bs / ' || f_txt(v_moneda)
        || '</td></tr></table>';

    -- Las facturas que se pagan con este comprobante.
    if v_n > 0 then
        v_html := v_html
            || '<table class="pg-montos"><thead><tr>'
            || '<th style="width:30%">Factura</th>'
            || '<th style="width:18%">Fecha</th>'
            || '<th style="width:14%">Moneda</th>'
            || '<th style="width:19%">Total factura</th>'
            || '<th style="width:19%">Aplicado</th>'
            || '</tr></thead><tbody>' || v_filas
            || '<tr class="pg-tot"><td colspan="4">Total aplicado</td>'
            || '<td class="pg-der">' || f_num(v_total) || '</td></tr>'
            || '</tbody></table>';
    else
        v_html := v_html
            || '<div class="pg-obs">Este pago no tiene facturas aplicadas: su importe completo '
            || 'queda como saldo a favor del proveedor.</div>';
    end if;

    -- Lo que sale del banco: el pago mas el IGTF, en las dos monedas.
    v_html := v_html
        || '<table class="pg-montos"><thead><tr>'
        || '<th style="width:46%">Concepto</th>'
        || '<th style="width:27%">En ' || f_txt(v_moneda) || '</th>'
        || '<th style="width:27%">En bol&iacute;vares</th>'
        || '</tr></thead><tbody>'
        || '<tr><td>Monto del pago</td>'
        || '<td class="pg-der">' || f_num(v_pag.monto) || '</td>'
        || '<td class="pg-der">' || f_num(v_pag.monto_bs) || '</td></tr>'
        || '<tr><td>IGTF'
        || case when nvl(v_pag.igtf_monto, 0) > 0 then ' (sujeto pasivo especial)' end
        || '</td>'
        || '<td class="pg-der">' || f_num(v_pag.igtf_monto) || '</td>'
        || '<td class="pg-der">' || f_num(v_pag.igtf_bs) || '</td></tr>'
        || '<tr class="pg-tot"><td>Total desembolsado</td>'
        || '<td class="pg-der">' || f_num(nvl(v_pag.monto, 0) + nvl(v_pag.igtf_monto, 0)) || '</td>'
        || '<td class="pg-der">' || f_num(nvl(v_pag.monto_bs, 0) + nvl(v_pag.igtf_bs, 0)) || '</td></tr>'
        || '</tbody></table>'
        || '<div class="pg-neto">TOTAL PAGADO: '
        || f_num(nvl(v_pag.monto, 0) + nvl(v_pag.igtf_monto, 0)) || ' '
        || f_txt(v_moneda) || ' &nbsp;&middot;&nbsp; Bs '
        || f_num(nvl(v_pag.monto_bs, 0) + nvl(v_pag.igtf_bs, 0)) || '</div>';

    if v_pag.observaciones is not null then
        v_html := v_html || '<div class="pg-obs"><strong>Observaciones:</strong> '
            || f_txt(v_pag.observaciones) || '</div>';
    end if;

    -- Firmas: quien paga (la empresa) y quien recibe (el proveedor).
    v_html := v_html
        || '<table class="pg-firmas"><tr>'
        || '<td style="width:50%"><div class="pg-linea"></div>'
        || '<div>Pagado por: ' || f_txt(v_emp) || ' &middot; '
        || case when v_pais = 'MX' then 'RFC ' else 'RIF ' end || f_txt(v_rif_emp) || '</div>'
        || '</td>'
        || '<td style="width:50%"><div class="pg-linea"></div>'
        || '<div>Recibido por: ' || f_txt(v_prov) || ' &middot; '
        || case when v_pais = 'MX' then 'RFC ' else 'RIF ' end
        || f_txt(fn_formato_rif(v_rif_prov)) || '</div>'
        || '</td></tr></table>'
        || '<div class="pg-pie">Comprobante de pago N&ordm; ' || f_txt(to_char(v_pag.id_pago))
        || ' &middot; Documento generado por el sistema el '
        || to_char(sysdate, 'DD/MM/YYYY HH24:MI') || '</div>'
        || '</div>';

    return v_html;
end fn_imprimir_pago;
/


declare
    v_lista varchar2(500) := '';
    v_n     number;
    v_id    number;
    v_html  clob;
begin
    select count(*) into v_n from all_objects
     where owner = 'WKSP_SYPEXWS' and object_name = 'FN_IMPRIMIR_PAGO'
       and object_type = 'FUNCTION' and status = 'VALID';
    if v_n <> 1 then
        v_lista := v_lista || ' | la funcion no esta VALID';
    end if;

    select min(id_pago) into v_id from pagos;
    if v_id is not null then
        v_html := fn_imprimir_pago(v_id);
        if v_html is null or instr(v_html, 'COMPROBANTE DE PAGO') = 0 then
            v_lista := v_lista || ' | no arma el documento del pago ' || v_id;
        end if;
    end if;

    if fn_imprimir_pago(-987654) is not null then
        v_lista := v_lista || ' | devuelve un documento para un pago que no existe';
    end if;

    if v_lista is null then
        raise_application_error(-20100, 'RESULTADO: FALLAS=0');
    else
        raise_application_error(-20100, substrb('RESULTADO: FALLAS=1' || v_lista, 1, 500));
    end if;
end;
/
