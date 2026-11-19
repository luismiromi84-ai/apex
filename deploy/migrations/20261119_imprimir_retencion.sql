-- =============================================================================
-- 20261119_imprimir_retencion.sql
--
-- El comprobante de retencion de IVA en papel: fn_imprimir_retencion(compra)
-- devuelve el HTML listo para imprimir (o guardar como PDF) y la pagina 31 lo
-- sirve. Se llega desde el boton «Imprimir comprobante» de la compra (28).
--
-- Reversa: drop function fn_imprimir_retencion.
-- Verificacion: deploy/diagnostico/20261119_imprimir_retencion_verificacion.sql
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

create or replace function fn_imprimir_retencion (
    p_id_compra in number
) return clob is
    r      compras%rowtype;
    v_ret  retenciones_iva%rowtype;
    v_html clob;
    v_prov varchar2(200);
    v_rif  varchar2(30);
    v_emp  varchar2(200);
    v_rif_emp varchar2(30);
    v_dir  varchar2(300);
    v_tel  varchar2(60);
    v_mail varchar2(120);
    v_imp  varchar2(200);
    v_prov_seniat varchar2(60);
begin
    if p_id_compra is null then
        return null;
    end if;

    begin
        select * into r from compras where id_compra = p_id_compra;
    exception
        when no_data_found then return null;
    end;

    begin
        select * into v_ret from retenciones_iva where id_compra = p_id_compra;
    exception
        when no_data_found then return null;
    end;

    select p.razon_social, nvl(p.rif, '-')
      into v_prov, v_rif
      from proveedores p where p.id_proveedor = r.id_proveedor;

    select e.nombre_empresa, nvl(e.rfc, '-')
      into v_emp, v_rif_emp
      from empresas e where e.id_empresa = r.id_empresa;

    begin
        select f.direccion_fiscal, f.telefono, f.email,
               f.nro_providencia, f.imprenta_nombre
          into v_dir, v_tel, v_mail, v_prov_seniat, v_imp
          from empresa_fiscal f where f.id_empresa = r.id_empresa;
    exception
        when others then
            v_dir := null; v_tel := null; v_mail := null;
            v_prov_seniat := null; v_imp := null;
    end;

    v_html := '<div style="max-width:820px;margin:0 auto;font-family:Arial,sans-serif;color:#222">';

    v_html := v_html || '<table style="width:100%;border-bottom:2px solid #0076ce;"><tr>'
        || '<td style="padding-bottom:8px;">'
        || '<div style="font-size:20px;font-weight:bold;color:#005291;">COMPROBANTE DE RETENCION DE IVA</div>'
        || '<div style="font-size:13px;color:#444;">' || sys.htf.escape_sc(v_emp)
        || ' &middot; RIF ' || sys.htf.escape_sc(v_rif_emp) || '</div>'
        || '<div style="font-size:12px;color:#666;">'
        || nvl(sys.htf.escape_sc(v_dir), ' ') || '</div>'
        || '</td>'
        || '<td align="right" style="padding-bottom:8px;">'
        || '<div style="font-size:18px;font-weight:bold;">N&ordm; '
        || sys.htf.escape_sc(v_ret.numero_comprobante) || '</div>'
        || '<div style="font-size:13px;">' || to_char(v_ret.fecha_emision, 'DD/MM/YYYY') || '</div>'
        || '</td></tr></table>';

    v_html := v_html || '<table style="width:100%;font-size:14px;margin-top:16px;">'
        || '<tr><td style="width:170px;color:#666;">Proveedor</td><td><b>'
        || sys.htf.escape_sc(v_prov) || '</b></td></tr>'
        || '<tr><td style="color:#666;">RIF</td><td>' || sys.htf.escape_sc(v_rif) || '</td></tr>'
        || '<tr><td style="color:#666;">Factura</td><td>'
        || sys.htf.escape_sc(r.folio_factura)
        || ' &nbsp;&middot;&nbsp; N&ordm; control '
        || nvl(sys.htf.escape_sc(r.nro_control), '-') || '</td></tr>'
        || '<tr><td style="color:#666;">Fecha de la factura</td><td>'
        || to_char(r.fecha_emision, 'DD/MM/YYYY') || '</td></tr>'
        || '<tr><td style="color:#666;">Periodo fiscal</td><td>'
        || to_char(v_ret.periodo_mes, 'FM00') || '/' || to_char(v_ret.periodo_anio)
        || '</td></tr></table>';

    v_html := v_html || '<table style="width:100%;font-size:15px;margin-top:20px;border-collapse:collapse;">'
        || '<thead><tr>'
        || '<th align="left" style="border-bottom:1px solid #bbb;padding:8px;">Concepto</th>'
        || '<th align="right" style="border-bottom:1px solid #bbb;padding:8px;">Bolivares</th>'
        || '</tr></thead><tbody>'
        || '<tr><td style="padding:8px;">Base imponible</td><td align="right">'
        || to_char(v_ret.base_imponible_bs, 'FM999G999G999G990D00') || '</td></tr>'
        || '<tr><td style="padding:8px;">IVA causado</td><td align="right">'
        || to_char(v_ret.iva_causado_bs, 'FM999G999G999G990D00') || '</td></tr>'
        || '<tr><td style="padding:8px;">IVA retenido ('
        || to_char(v_ret.porcentaje_retencion) || ' %)</td>'
        || '<td align="right" style="font-weight:bold;">'
        || to_char(v_ret.iva_retenido_bs, 'FM999G999G999G990D00') || '</td></tr>'
        || '</tbody></table>';

    v_html := v_html || '<p style="margin-top:24px;font-size:12px;color:#555;">'
        || 'Comprobante emitido conforme a la providencia del SENIAT'
        || case when v_prov_seniat is not null
                then ' N&ordm; ' || sys.htf.escape_sc(v_prov_seniat) else '' end
        || '. Se entrega al proveedor como constancia de la retencion de IVA practicada.</p>';

    if v_imp is not null then
        v_html := v_html || '<p style="font-size:11px;color:#777;">Imprenta: '
            || sys.htf.escape_sc(v_imp) || '</p>';
    end if;

    v_html := v_html || '<p style="margin-top:34px;font-size:12px;color:#555;">'
        || 'Recibi conforme: ____________________________</p>';
    v_html := v_html || '</div>';

    return v_html;
end fn_imprimir_retencion;
/

begin
    dbms_utility.compile_schema('WKSP_SYPEXWS', false);
end;
/

declare
    v_n   number;
    v_txt clob;
begin
    select count(*) into v_n from all_objects
     where owner = 'WKSP_SYPEXWS' and object_name = 'FN_IMPRIMIR_RETENCION'
       and status = 'VALID';
    if v_n < 1 then
        raise_application_error(-20112, 'FN_IMPRIMIR_RETENCION quedo invalida');
    end if;

    select max(id_compra) into v_n from retenciones_iva;
    if v_n is not null then
        v_txt := fn_imprimir_retencion(v_n);
        if v_txt is null or instr(v_txt, 'COMPROBANTE DE RETENCION') = 0 then
            raise_application_error(-20112, 'la funcion no arma el comprobante');
        end if;
    end if;
end;
/
