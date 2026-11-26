-- =============================================================================
-- 20261125_costos_excel.sql
--
-- Excel de Costos de inventario (pagina 45): fn_costos_excel, servida por la pagina 49.
--
--   python deploy/conexion/importar_export.py deploy/migrations/20261125_costos_excel.sql
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

create or replace function fn_costos_excel (
    p_informe  in varchar2,
    p_desde    in date,
    p_hasta    in date,
    p_articulo in number,
    p_empresa  in number
) return clob is
    v_html  clob;
    v_emp   varchar2(200);
    v_rif   varchar2(40);
    v_tit   varchar2(200);
    v_per   varchar2(200);
    v_t1    number := 0;
    v_t2    number := 0;
    v_t3    number := 0;
    v_t4    number := 0;
    v_tasa  number;
    v_hasta date := nvl(trunc(p_hasta), trunc(sysdate));
    v_desde date := trunc(p_desde);

    function txt(s varchar2) return varchar2 is
    begin
        return '<td style="mso-number-format:''\@''">' || sys.htf.escape_sc(s) || '</td>';
    end;

    function num(n number, dec pls_integer default 2) return varchar2 is
    begin
        return '<td style="mso-number-format:''#\,##0\.' || rpad('0', dec, '0') || '''">'
            || to_char(nvl(n, 0), 'TM9', 'NLS_NUMERIC_CHARACTERS=''.,''') || '</td>';
    end;
begin
    select e.nombre_empresa, e.rfc into v_emp, v_rif from empresas e where e.id_empresa = p_empresa;
    v_tasa := nullif(fn_tasa_ves(v_hasta, 'USD'), 0);

    if upper(p_informe) = 'VALORADO' then
        v_tit := 'Inventario valorado al corte';
        v_per := 'Al ' || to_char(v_hasta, 'DD/MM/YYYY');
    else
        v_tit := 'Costo de ventas del periodo';
        v_per := 'Del ' || nvl(to_char(v_desde, 'DD/MM/YYYY'), 'inicio') || ' al ' || to_char(v_hasta, 'DD/MM/YYYY');
    end if;

    v_html := '<html><head><meta charset="utf-8"></head><body><table border="1">'
        || '<tr><td colspan="7" style="font-weight:bold;font-size:14pt">' || sys.htf.escape_sc(v_emp)
        || '</td></tr><tr><td colspan="7">RIF: ' || sys.htf.escape_sc(v_rif) || '</td></tr>'
        || '<tr><td colspan="7" style="font-weight:bold">' || v_tit || '</td></tr>'
        || '<tr><td colspan="7">' || v_per || ' - generado el ' || to_char(sysdate, 'DD/MM/YYYY HH24:MI')
        || '</td></tr><tr></tr>';

    if upper(p_informe) = 'VALORADO' then
        v_html := v_html || '<tr style="font-weight:bold;background:#dbeafe"><td>C&oacute;digo</td>'
            || '<td>Art&iacute;culo</td><td>Existencia</td><td>Costo promedio (Bs)</td><td>Valor (Bs)</td>'
            || '<td>Valor (USD)</td><td>Valor (moneda doc.)</td></tr>';
        for r in (select a.codigo, a.nombre,
                         sum(pkg_inventario.fn_signo(m.tipo_movimiento) * m.cantidad) cantidad,
                         sum(pkg_inventario.fn_signo(m.tipo_movimiento) * m.costo_total_bs) valor_bs,
                         sum(pkg_inventario.fn_signo(m.tipo_movimiento) * m.costo_total_ref) valor_ref
                    from kardex_mov m
                    join producto_servicio a on a.id_producto_servicio = m.id_producto_servicio
                   where m.id_empresa = p_empresa
                     and m.fecha_movimiento < v_hasta + 1
                     and (p_articulo is null or m.id_producto_servicio = p_articulo)
                   group by a.codigo, a.nombre
                   order by a.nombre) loop
            v_html := v_html || '<tr>' || txt(r.codigo) || txt(r.nombre) || num(r.cantidad)
                || num(case when abs(r.cantidad) > 0.00005 then r.valor_bs / r.cantidad else 0 end, 4)
                || num(r.valor_bs) || num(round(r.valor_bs / v_tasa, 2)) || num(r.valor_ref) || '</tr>';
            v_t1 := v_t1 + nvl(r.cantidad, 0);
            v_t2 := v_t2 + nvl(r.valor_bs, 0);
            v_t3 := v_t3 + nvl(round(r.valor_bs / v_tasa, 2), 0);
            v_t4 := v_t4 + nvl(r.valor_ref, 0);
        end loop;
        v_html := v_html || '<tr style="font-weight:bold"><td>TOTALES</td><td></td>' || num(v_t1)
            || '<td></td>' || num(v_t2) || num(v_t3) || num(v_t4) || '</tr>';
    else
        v_html := v_html || '<tr style="font-weight:bold;background:#dbeafe"><td>C&oacute;digo</td>'
            || '<td>Art&iacute;culo</td><td>Unidades</td><td>Costo (Bs)</td><td>Costo (USD)</td>'
            || '<td>Costo (moneda doc.)</td><td></td></tr>';
        for r in (select a.codigo, a.nombre,
                         sum(-pkg_inventario.fn_signo(m.tipo_movimiento) * m.cantidad) unidades,
                         sum(-pkg_inventario.fn_signo(m.tipo_movimiento) * m.costo_total_bs) costo_bs,
                         sum(-pkg_inventario.fn_signo(m.tipo_movimiento) * m.costo_total_ref) costo_ref
                    from kardex_mov m
                    join producto_servicio a on a.id_producto_servicio = m.id_producto_servicio
                   where m.id_empresa = p_empresa
                     and m.tipo_movimiento in ('SALIDA_FACTURA', 'SALIDA_ND_CLIENTE', 'ENTRADA_NC_CLIENTE')
                     and m.fecha_movimiento >= nvl(v_desde, date '1900-01-01')
                     and m.fecha_movimiento < v_hasta + 1
                     and (p_articulo is null or m.id_producto_servicio = p_articulo)
                   group by a.codigo, a.nombre
                   order by a.nombre) loop
            v_html := v_html || '<tr>' || txt(r.codigo) || txt(r.nombre) || num(r.unidades)
                || num(r.costo_bs) || num(round(r.costo_bs / v_tasa, 2)) || num(r.costo_ref) || '<td></td></tr>';
            v_t1 := v_t1 + nvl(r.unidades, 0);
            v_t2 := v_t2 + nvl(r.costo_bs, 0);
            v_t3 := v_t3 + nvl(round(r.costo_bs / v_tasa, 2), 0);
            v_t4 := v_t4 + nvl(r.costo_ref, 0);
        end loop;
        v_html := v_html || '<tr style="font-weight:bold"><td>TOTALES</td><td></td>' || num(v_t1)
            || num(v_t2) || num(v_t3) || num(v_t4) || '<td></td></tr>';
    end if;

    return v_html || '</table><p>Valor (USD) a la tasa BCV del ' || to_char(v_hasta, 'DD/MM/YYYY')
        || '. Valor (moneda doc.): a la tasa de cada movimiento.</p></body></html>';
exception
    when no_data_found then
        return null;
end fn_costos_excel;
/

declare
    v_n number;
begin
    select count(*) into v_n from all_objects
     where owner = 'WKSP_SYPEXWS' and object_name = 'FN_COSTOS_EXCEL' and status = 'VALID';
    if v_n <> 1 then
        raise_application_error(-20100, 'FN_COSTOS_EXCEL no quedo VALID');
    end if;
end;
/
