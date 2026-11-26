-- =============================================================================
-- fn_ctb_libro
--
-- Libros contables (contabilidad, fase 3, 2026-11-25). Una sola funcion para la pantalla
-- (pagina 53, p_formato 'HTML') y para la descarga (pagina 54, p_formato 'XLS': .xls con
-- membrete y numeros con formato de Excel).
--
--   p_libro = 'DIARIO'   asientos del periodo con sus lineas
--   p_libro = 'MAYOR'    mayor analitico: por cuenta, saldo inicial, movimientos con saldo
--                        acumulado y saldo final (p_id_cuenta = una cuenta, o null = todas)
--   p_libro = 'BALANCE'  balance de comprobacion: saldo inicial, debe, haber y saldo actual
--                        por cuenta y por grupo, como el del contador
--   p_libro = 'RESULTADOS'  estado de resultados del periodo: ingresos - costos - gastos (sin el
--                        asiento de cierre anual, para que el ejercicio cerrado se siga viendo)
--   p_libro = 'SITUACION'   balance general al corte (p_hasta): activo = pasivo + patrimonio +
--                        resultado del ejercicio aun no cerrado
--   p_libro = 'IMPUESTOS'   resumen de impuestos del periodo, desde los documentos (IVA, retenciones, IGTF)
--   p_libro = 'RETENCIONES' retenciones de IVA recibidas y practicadas (IVA e ISLR) con su comprobante
--   p_libro = 'FLUJO'       flujo de efectivo, metodo directo (cuentas 1.1.1. por origen del asiento)
--   p_libro = 'PATRIMONIO'  cambios en el patrimonio (cuentas 3.) mas el resultado aun no cerrado
--   p_libro = 'INVENTARIOS' libro de inventarios: existencias y valor por articulo, contra la contabilidad
--
-- Saldos = debe - haber (los de naturaleza acreedora salen negativos, como en el balance del
-- contador). Cuentan los asientos CONFIRMADO y REVERSADO (el reversado sigue asentado; su
-- reverso lo compensa). Moneda funcional de la empresa.
-- =============================================================================

create or replace function fn_ctb_libro (
    p_libro     in varchar2,
    p_desde     in date,
    p_hasta     in date,
    p_id_cuenta in number,
    p_empresa   in number,
    p_formato   in varchar2 default 'HTML'
) return clob is
    v_xls   boolean := upper(p_formato) = 'XLS';
    v_lib   varchar2(20) := upper(nvl(p_libro, 'BALANCE'));
    v_desde date := trunc(nvl(p_desde, trunc(sysdate, 'YYYY')));
    v_hasta date := trunc(nvl(p_hasta, sysdate));
    v_html  clob;
    v_emp   varchar2(200);
    v_rif   varchar2(40);
    v_tit   varchar2(100);
    v_td    number := 0;
    v_th    number := 0;
    v_ts    number := 0;
    v_saldo number;
    v_cxx   number;
    v_hay   boolean := false;

    procedure w(s varchar2) is
    begin
        v_html := v_html || s;
    end w;

    -- celda de texto; p_css = estilo adicional (sangria, negrita)
    function t(s varchar2, p_css varchar2 default null) return varchar2 is
        v_css varchar2(200) := case when v_xls then 'mso-number-format:''\@'';' end || p_css;
    begin
        return '<td' || case when v_css is not null then ' style="' || v_css || '"' end || '>'
            || sys.htf.escape_sc(s) || '</td>';
    end t;

    function n(x number, p_negrita boolean default false) return varchar2 is
    begin
        if v_xls then
            return '<td style="mso-number-format:''#\,##0\.00''' || case when p_negrita then ';font-weight:bold' end
                || '">' || to_char(nvl(x, 0), 'TM9', 'NLS_NUMERIC_CHARACTERS=''.,''') || '</td>';
        end if;
        return '<td class="num"' || case when p_negrita then ' style="font-weight:600"' end || '>'
            || to_char(nvl(x, 0), 'FM999G999G999G990D00') || '</td>';
    end n;

    function asiento_ref(p_mes number, p_anio number, p_num number) return varchar2 is
    begin
        return lpad(p_mes, 2, '0') || '/' || p_anio || '-' || lpad(p_num, 4, '0');
    end asiento_ref;

    -- Saldo con signo de presentacion (p_signo = 1: debe - haber; -1: haber - debe) de las cuentas
    -- del prefijo entre p_d y p_h, con sus grupos; escribe las filas y devuelve el total.
    function seccion(p_pref varchar2, p_titulo varchar2, p_signo number, p_d date, p_h date,
                     p_sin_cierre boolean) return number is
        v_tot number := 0;
        v_sc  varchar2(1) := case when p_sin_cierre then 'S' else 'N' end;
    begin
        w('<tr class="spx-grp"><td colspan="3"><b>' || p_titulo || '</b></td></tr>');
        for b in (with mov as (
                      select d.id_cuenta_ctb, sum(d.debe - d.haber) s
                        from ctb_asiento_det d join ctb_asientos a on a.id_asiento = d.id_asiento
                       where a.id_empresa = p_empresa and a.estado in ('CONFIRMADO', 'REVERSADO')
                         and a.fecha between p_d and p_h
                         and (v_sc = 'N' or a.origen <> 'CIERRE')
                       group by d.id_cuenta_ctb),
                  hoja as (
                      select c.codigo, m.s from ctb_cuentas c join mov m on m.id_cuenta_ctb = c.id_cuenta_ctb
                       where c.codigo like p_pref || '%')
                  select c.codigo, c.nombre, c.nivel, c.acepta_movimiento, sum(h.s) s
                    from ctb_cuentas c
                    join hoja h on (h.codigo = c.codigo
                                    or (c.acepta_movimiento = 'N' and substr(h.codigo, 1, length(c.codigo)) = c.codigo))
                   where c.id_empresa = p_empresa and c.codigo like p_pref || '%' and c.codigo <> p_pref
                   group by c.codigo, c.nombre, c.nivel, c.acepta_movimiento
                  having sum(h.s) <> 0
                   order by c.codigo) loop
            w('<tr' || case when b.acepta_movimiento = 'N' then ' class="spx-grp"' end || '>' || t(b.codigo)
              || t(b.nombre, 'padding-left:' || to_char((b.nivel - 1) * 14 + 6) || 'px'
                   || case when b.acepta_movimiento = 'N' then ';font-weight:bold' end)
              || n(p_signo * b.s, b.acepta_movimiento = 'N') || '</tr>');
            if b.acepta_movimiento = 'S' then
                v_tot := v_tot + p_signo * b.s;
            end if;
        end loop;
        w('<tr class="spx-tot"><td colspan="2"><b>Total ' || lower(p_titulo) || '</b></td>' || n(v_tot, true) || '</tr>');
        return v_tot;
    end seccion;
begin
    select e.nombre_empresa, e.rfc into v_emp, v_rif from empresas e where e.id_empresa = p_empresa;
    v_tit := case v_lib when 'DIARIO' then 'Libro diario'
                        when 'MAYOR' then 'Mayor anal&iacute;tico'
                        when 'RESULTADOS' then 'Estado de resultados'
                        when 'SITUACION' then 'Balance general (estado de situaci&oacute;n financiera)'
                        when 'IMPUESTOS' then 'Resumen de impuestos del per&iacute;odo'
                        when 'RETENCIONES' then 'Retenciones de IVA e ISLR'
                        when 'FLUJO' then 'Estado de flujo de efectivo (m&eacute;todo directo)'
                        when 'PATRIMONIO' then 'Estado de cambios en el patrimonio'
                        when 'INVENTARIOS' then 'Libro de inventarios'
                        else 'Balance de comprobaci&oacute;n' end;

    if v_xls then
        w('<html><head><meta charset="utf-8"></head><body><table border="1">'
          || '<tr><td colspan="7" style="font-weight:bold;font-size:14pt">' || sys.htf.escape_sc(v_emp) || '</td></tr>'
          || '<tr><td colspan="7">RIF: ' || sys.htf.escape_sc(v_rif) || '</td></tr>'
          || '<tr><td colspan="7" style="font-weight:bold">' || v_tit || '</td></tr>'
          || '<tr><td colspan="7">' || case when v_lib = 'SITUACION' then 'Al ' || to_char(v_hasta, 'DD/MM/YYYY')
             else 'Del ' || to_char(v_desde, 'DD/MM/YYYY') || ' al ' || to_char(v_hasta, 'DD/MM/YYYY') end
          || ' - generado el ' || to_char(sysdate, 'DD/MM/YYYY HH24:MI') || '</td></tr><tr></tr>');
    else
        w('<table class="spx-cc spx-libro">');
    end if;

    if v_lib = 'DIARIO' then
        w('<tr class="spx-th"><th>Fecha</th><th>Asiento</th><th>C&oacute;digo</th><th>Cuenta</th>'
          || '<th>Descripci&oacute;n</th><th class="num">Debe</th><th class="num">Haber</th></tr>');
        for a in (select id_asiento, fecha, anio, mes, numero, concepto, estado
                    from ctb_asientos
                   where id_empresa = p_empresa and estado in ('CONFIRMADO', 'REVERSADO')
                     and fecha between v_desde and v_hasta
                   order by fecha, anio, mes, numero) loop
            v_hay := true;
            w('<tr class="spx-grp">' || t(to_char(a.fecha, 'DD/MM/YYYY')) || t(asiento_ref(a.mes, a.anio, a.numero))
              || '<td colspan="5"' || case when v_xls then ' style="font-weight:bold"' end || '>'
              || sys.htf.escape_sc(a.concepto) || case when a.estado = 'REVERSADO' then ' (reversado)' end
              || '</td></tr>');
            for l in (select c.codigo, c.nombre, d.descripcion, d.debe, d.haber
                        from ctb_asiento_det d join ctb_cuentas c on c.id_cuenta_ctb = d.id_cuenta_ctb
                       where d.id_asiento = a.id_asiento order by d.linea) loop
                w('<tr><td></td><td></td>' || t(l.codigo) || t(l.nombre) || t(l.descripcion)
                  || n(l.debe) || n(l.haber) || '</tr>');
                v_td := v_td + l.debe;
                v_th := v_th + l.haber;
            end loop;
        end loop;
        if not v_hay then
            w('<tr><td colspan="7">No hay asientos confirmados en el periodo.</td></tr>');
        end if;
        w('<tr class="spx-tot"><td colspan="5"><b>TOTALES</b></td>' || n(v_td, true) || n(v_th, true) || '</tr>');

    elsif v_lib = 'RESULTADOS' then
        w('<tr class="spx-th"><th>C&oacute;digo</th><th>Cuenta</th><th class="num">Importe</th></tr>');
        v_ts := seccion('4.', 'INGRESOS', -1, v_desde, v_hasta, true);
        v_td := seccion('5.', 'COSTOS', 1, v_desde, v_hasta, true);
        v_th := seccion('6.', 'GASTOS', 1, v_desde, v_hasta, true);
        -- clase 7 del codigo agrupador del SAT (Mexico): resultado integral de financiamiento
        v_cxx := 0;
        select count(*) into v_saldo from ctb_cuentas where id_empresa = p_empresa and codigo = '7.';
        if v_saldo > 0 then
            v_cxx := seccion('7.', 'RESULTADO INTEGRAL DE FINANCIAMIENTO', 1, v_desde, v_hasta, true);
        end if;
        w('<tr class="spx-tot"><td colspan="2"><b>' || case when v_ts - v_td - v_th - v_cxx >= 0 then 'UTILIDAD' else 'P&Eacute;RDIDA' end
          || ' DEL PER&Iacute;ODO</b> (ingresos - costos - gastos' || case when v_saldo > 0 then ' - financiamiento' end
          || ')</td>' || n(v_ts - v_td - v_th - v_cxx, true) || '</tr>');

    elsif v_lib = 'SITUACION' then
        w('<tr class="spx-th"><th>C&oacute;digo</th><th>Cuenta</th><th class="num">Saldo</th></tr>');
        v_ts := seccion('1.', 'ACTIVO', 1, date '1900-01-01', v_hasta, false);
        v_td := seccion('2.', 'PASIVO', -1, date '1900-01-01', v_hasta, false);
        v_th := seccion('3.', 'PATRIMONIO', -1, date '1900-01-01', v_hasta, false);
        -- resultado aun no llevado al patrimonio por el cierre anual
        select nvl(sum(d.haber - d.debe), 0) into v_saldo
          from ctb_asiento_det d join ctb_asientos a on a.id_asiento = d.id_asiento
          join ctb_cuentas c on c.id_cuenta_ctb = d.id_cuenta_ctb
         where a.id_empresa = p_empresa and a.estado in ('CONFIRMADO', 'REVERSADO') and a.fecha <= v_hasta
           and substr(c.codigo, 1, 1) in ('4', '5', '6', '7');
        w('<tr><td></td><td>Resultado del ejercicio a&uacute;n no cerrado</td>' || n(v_saldo, true) || '</tr>');
        w('<tr class="spx-tot"><td colspan="2"><b>Total pasivo + patrimonio + resultado</b></td>'
          || n(v_td + v_th + v_saldo, true) || '</tr>');
        w('<tr><td colspan="3">' || case when abs(v_ts - (v_td + v_th + v_saldo)) < 0.005 then 'Cuadra: activo = pasivo + patrimonio + resultado'
          else 'NO CUADRA: diferencia ' || to_char(v_ts - (v_td + v_th + v_saldo), 'FM999G999G999G990D00') end || '</td></tr>');

    elsif v_lib = 'IMPUESTOS' then
        -- desde los documentos del periodo (no hace falta haber contabilizado)
        declare
            v_bv number; v_iv number; v_bc number; v_ic number; v_rr number; v_ri number; v_rs number;
            v_gc number; v_gp number; v_nr number;
        begin
            select nvl(sum(case when f.tipo_documento = 'NC' then -1 else 1 end * round(abs(f.subtotal) * nvl(nullif(f.tipo_cambio, 0), 1), 2)), 0),
                   nvl(sum(case when f.tipo_documento = 'NC' then -1 else 1 end * round(abs(f.monto_impuesto) * nvl(nullif(f.tipo_cambio, 0), 1), 2)), 0)
              into v_bv, v_iv
              from facturas f
             where f.id_empresa = p_empresa and f.tipo_documento in ('FAC', 'ND', 'NC')
               and f.estado <> 'PENDIENTE' and not (f.estado = 'ANULADA' and f.nro_control is null)
               and trunc(f.fecha_emision) between v_desde and v_hasta;
            select nvl(sum(case when c.tipo_documento = 'NC' then -1 else 1 end * round(abs(c.subtotal) * nvl(nullif(c.tipo_cambio, 0), 1), 2)), 0),
                   nvl(sum(case when c.tipo_documento = 'NC' then -1 else 1 end * round(abs(c.monto_impuesto) * nvl(nullif(c.tipo_cambio, 0), 1), 2)), 0)
              into v_bc, v_ic
              from compras c
             where c.id_empresa = p_empresa and c.estado not in ('BORRADOR', 'ANULADA')
               and trunc(c.fecha_emision) between v_desde and v_hasta;
            select nvl(sum(r.retencion_iva_bs), 0), nvl(sum(r.igtf_bs), 0), count(case when r.retencion_iva_bs > 0 then 1 end)
              into v_rr, v_gc, v_nr
              from recibos r
             where r.id_empresa = p_empresa and r.estado = 'ACTIVO' and trunc(r.fecha_cobro) between v_desde and v_hasta;
            select nvl(sum(case when x.tipo = 'IVA' then x.retenido_bs end), 0), nvl(sum(case when x.tipo = 'ISLR' then x.retenido_bs end), 0)
              into v_ri, v_rs
              from retenciones x
             where x.id_empresa = p_empresa and x.estado not in ('ANULADO', 'ANULADA')
               and trunc(x.fecha_emision) between v_desde and v_hasta;
            select nvl(sum(p.igtf_bs), 0) into v_gp
              from pagos p
             where p.id_empresa = p_empresa and p.estado = 'ACTIVO' and trunc(p.fecha_pago) between v_desde and v_hasta;
            w('<tr class="spx-th"><th>Concepto</th><th class="num">Base (Bs)</th><th class="num">Impuesto (Bs)</th></tr>');
            w('<tr class="spx-grp"><td colspan="3"><b>IVA</b></td></tr>');
            w('<tr>' || '<td>Ventas (d&eacute;bito fiscal), notas de cr&eacute;dito restadas</td>' || n(v_bv) || n(v_iv) || '</tr>');
            w('<tr>' || '<td>Compras (cr&eacute;dito fiscal), notas de cr&eacute;dito restadas</td>' || n(v_bc) || n(v_ic) || '</tr>');
            w('<tr class="spx-tot"><td colspan="2"><b>Cuota del per&iacute;odo (d&eacute;bito - cr&eacute;dito)</b></td>' || n(v_iv - v_ic, true) || '</tr>');
            w('<tr>' || '<td>Retenciones de IVA que te hicieron los clientes (' || to_char(v_nr) || ' comprobantes)</td>' || '<td></td>' || n(v_rr) || '</tr>');
            w('<tr class="spx-tot"><td colspan="2"><b>'
              || case when v_iv - v_ic - v_rr >= 0 then 'IVA a pagar estimado' else 'Excedente de cr&eacute;dito estimado' end
              || '</b> (sin excedentes de meses anteriores)</td>' || n(abs(v_iv - v_ic - v_rr), true) || '</tr>');
            w('<tr class="spx-grp"><td colspan="3"><b>RETENCIONES QUE SE ENTERAN AL SENIAT</b></td></tr>');
            w('<tr>' || '<td>Retenciones de IVA practicadas a proveedores</td>' || '<td></td>' || n(v_ri) || '</tr>');
            w('<tr>' || '<td>Retenciones de ISLR practicadas a proveedores</td>' || '<td></td>' || n(v_rs) || '</tr>');
            w('<tr class="spx-grp"><td colspan="3"><b>IGTF</b></td></tr>');
            w('<tr>' || '<td>IGTF percibido en cobros en divisa</td>' || '<td></td>' || n(v_gc) || '</tr>');
            w('<tr>' || '<td>IGTF pagado en pagos a proveedores (gasto)</td>' || '<td></td>' || n(v_gp) || '</tr>');
        end;

    elsif v_lib = 'RETENCIONES' then
        w('<tr class="spx-grp"><td colspan="6"><b>RETENCIONES DE IVA RECIBIDAS (las que te hicieron los clientes)</b></td></tr>');
        w('<tr class="spx-th"><th>Fecha</th><th>Comprobante</th><th>RIF</th><th>Cliente</th><th>Factura</th><th class="num">Retenido (Bs)</th></tr>');
        for r in (select r.fecha_cobro, r.nro_comprobante_retencion, c.rif, c.razon_social, f.folio_factura, r.retencion_iva_bs
                    from recibos r join facturas f on f.id_factura = r.id_factura
                    left join clientes c on c.id_cliente = f.id_cliente
                   where r.id_empresa = p_empresa and r.estado = 'ACTIVO' and nvl(r.retencion_iva_bs, 0) > 0
                     and trunc(r.fecha_cobro) between v_desde and v_hasta
                   order by r.fecha_cobro, r.id_recibo) loop
            v_hay := true;
            v_td := v_td + r.retencion_iva_bs;
            w('<tr>' || t(to_char(r.fecha_cobro, 'DD/MM/YYYY')) || t(r.nro_comprobante_retencion) || t(r.rif)
              || t(r.razon_social) || t(r.folio_factura) || n(r.retencion_iva_bs) || '</tr>');
        end loop;
        w('<tr class="spx-tot"><td colspan="5"><b>Total recibidas</b></td>' || n(v_td, true) || '</tr>');
        w('<tr class="spx-grp"><td colspan="6"><b>RETENCIONES PRACTICADAS A PROVEEDORES (se enteran al SENIAT)</b></td></tr>');
        w('<tr class="spx-th"><th>Fecha</th><th>Tipo / comprobante</th><th>RIF</th><th>Proveedor</th><th class="num">Base (Bs)</th><th class="num">Retenido (Bs)</th></tr>');
        for x in (select x.fecha_emision, x.tipo, x.numero_comprobante, p.rif, p.razon_social, x.base_imponible_bs, x.retenido_bs
                    from retenciones x left join proveedores p on p.id_proveedor = x.id_proveedor
                   where x.id_empresa = p_empresa and x.estado not in ('ANULADO', 'ANULADA')
                     and trunc(x.fecha_emision) between v_desde and v_hasta
                   order by x.tipo, x.fecha_emision, x.numero_comprobante) loop
            v_hay := true;
            if x.tipo = 'IVA' then v_th := v_th + x.retenido_bs; else v_ts := v_ts + x.retenido_bs; end if;
            w('<tr>' || t(to_char(x.fecha_emision, 'DD/MM/YYYY')) || t(x.tipo || ' ' || x.numero_comprobante) || t(x.rif)
              || t(x.razon_social) || n(x.base_imponible_bs) || n(x.retenido_bs) || '</tr>');
        end loop;
        w('<tr class="spx-tot"><td colspan="5"><b>Total practicadas de IVA</b></td>' || n(v_th, true) || '</tr>');
        w('<tr class="spx-tot"><td colspan="5"><b>Total practicadas de ISLR</b></td>' || n(v_ts, true) || '</tr>');

    elsif v_lib = 'FLUJO' then
        -- metodo directo: los movimientos de las cuentas de caja y bancos (1.1.1.) por su origen
        select nvl(sum(d.debe - d.haber), 0) into v_saldo
          from ctb_asiento_det d join ctb_asientos a on a.id_asiento = d.id_asiento
          join ctb_cuentas c on c.id_cuenta_ctb = d.id_cuenta_ctb
         where a.id_empresa = p_empresa and a.estado in ('CONFIRMADO', 'REVERSADO') and a.fecha < v_desde
           and c.codigo like '1.1.1.%';
        w('<tr class="spx-th"><th>Concepto</th><th class="num">Entradas</th><th class="num">Salidas</th><th class="num">Neto</th></tr>');
        w('<tr class="spx-grp"><td><b>Efectivo al inicio (caja y bancos)</b></td><td></td><td></td>' || n(v_saldo, true) || '</tr>');
        for f in (select case a.doc_tipo when 'RECIBO' then '1 Cobros a clientes'
                                        when 'PAGO' then '2 Pagos a proveedores'
                                        when 'SENIAT' then '3 Pagos de impuestos (SENIAT)'
                                        else '4 Otros movimientos (asientos manuales y traspasos)' end grupo,
                         sum(d.debe) entra, sum(d.haber) sale
                    from ctb_asiento_det d join ctb_asientos a on a.id_asiento = d.id_asiento
                    join ctb_cuentas c on c.id_cuenta_ctb = d.id_cuenta_ctb
                   where a.id_empresa = p_empresa and a.estado in ('CONFIRMADO', 'REVERSADO')
                     and a.fecha between v_desde and v_hasta and c.codigo like '1.1.1.%'
                   group by case a.doc_tipo when 'RECIBO' then '1 Cobros a clientes'
                                           when 'PAGO' then '2 Pagos a proveedores'
                                           when 'SENIAT' then '3 Pagos de impuestos (SENIAT)'
                                           else '4 Otros movimientos (asientos manuales y traspasos)' end
                   order by 1) loop
            v_hay := true;
            v_td := v_td + f.entra;
            v_th := v_th + f.sale;
            w('<tr>' || t(substr(f.grupo, 3)) || n(f.entra) || n(f.sale) || n(f.entra - f.sale) || '</tr>');
        end loop;
        if not v_hay then
            w('<tr><td colspan="4">No hubo movimientos de caja ni de bancos en el per&iacute;odo.</td></tr>');
        end if;
        w('<tr class="spx-tot"><td><b>Variaci&oacute;n del per&iacute;odo</b></td>' || n(v_td, true) || n(v_th, true) || n(v_td - v_th, true) || '</tr>');
        w('<tr class="spx-tot"><td><b>Efectivo al final</b></td><td></td><td></td>' || n(v_saldo + v_td - v_th, true) || '</tr>');

    elsif v_lib = 'PATRIMONIO' then
        w('<tr class="spx-th"><th>C&oacute;digo</th><th>Cuenta</th><th class="num">Saldo inicial</th><th class="num">Aumentos</th>'
          || '<th class="num">Disminuciones</th><th class="num">Saldo final</th></tr>');
        for c in (select c.codigo, c.nombre,
                         nvl(sum(case when a.fecha < v_desde then d.haber - d.debe end), 0) ini,
                         nvl(sum(case when a.fecha >= v_desde then d.haber end), 0) aum,
                         nvl(sum(case when a.fecha >= v_desde then d.debe end), 0) dis
                    from ctb_cuentas c
                    join ctb_asiento_det d on d.id_cuenta_ctb = c.id_cuenta_ctb
                    join ctb_asientos a on a.id_asiento = d.id_asiento
                   where c.id_empresa = p_empresa and c.codigo like '3.%'
                     and a.estado in ('CONFIRMADO', 'REVERSADO') and a.fecha <= v_hasta
                   group by c.codigo, c.nombre
                   order by c.codigo) loop
            v_hay := true;
            v_ts := v_ts + c.ini;
            v_td := v_td + c.aum;
            v_th := v_th + c.dis;
            w('<tr>' || t(c.codigo) || t(c.nombre) || n(c.ini) || n(c.aum) || n(c.dis) || n(c.ini + c.aum - c.dis) || '</tr>');
        end loop;
        -- resultado aun no llevado al patrimonio (antes y durante el periodo)
        select nvl(sum(case when a.fecha < v_desde then d.haber - d.debe end), 0),
               nvl(sum(case when a.fecha >= v_desde then d.haber - d.debe end), 0)
          into v_saldo, v_cxx
          from ctb_asiento_det d join ctb_asientos a on a.id_asiento = d.id_asiento
          join ctb_cuentas c on c.id_cuenta_ctb = d.id_cuenta_ctb
         where a.id_empresa = p_empresa and a.estado in ('CONFIRMADO', 'REVERSADO') and a.fecha <= v_hasta
           and substr(c.codigo, 1, 1) in ('4', '5', '6', '7');
        w('<tr><td></td>' || '<td>Resultado del ejercicio a&uacute;n no cerrado</td>' || n(v_saldo) || n(greatest(v_cxx, 0)) || n(greatest(-v_cxx, 0))
          || n(v_saldo + v_cxx) || '</tr>');
        w('<tr class="spx-tot"><td colspan="2"><b>Total patrimonio</b></td>' || n(v_ts + v_saldo, true)
          || n(v_td + greatest(v_cxx, 0), true) || n(v_th + greatest(-v_cxx, 0), true)
          || n(v_ts + v_td - v_th + v_saldo + v_cxx, true) || '</tr>');

    elsif v_lib = 'INVENTARIOS' then
        w('<tr class="spx-th"><th>C&oacute;digo</th><th>Art&iacute;culo</th><th class="num">Exist. inicial</th><th class="num">Entradas</th>'
          || '<th class="num">Salidas</th><th class="num">Exist. final</th><th class="num">Valor inicial (Bs)</th>'
          || '<th class="num">Valor final (Bs)</th></tr>');
        for k in (select p.codigo, p.nombre,
                         nvl(sum(case when m.fecha_movimiento < v_desde then pkg_inventario.fn_signo(m.tipo_movimiento) * m.cantidad end), 0) qi,
                         nvl(sum(case when m.fecha_movimiento >= v_desde and pkg_inventario.fn_signo(m.tipo_movimiento) > 0 then m.cantidad end), 0) qe,
                         nvl(sum(case when m.fecha_movimiento >= v_desde and pkg_inventario.fn_signo(m.tipo_movimiento) < 0 then m.cantidad end), 0) qs,
                         nvl(sum(case when m.fecha_movimiento < v_desde then pkg_inventario.fn_signo(m.tipo_movimiento) * m.costo_total_bs end), 0) vi,
                         nvl(sum(pkg_inventario.fn_signo(m.tipo_movimiento) * m.costo_total_bs), 0) vf
                    from kardex_mov m join producto_servicio p on p.id_producto_servicio = m.id_producto_servicio
                   where m.id_empresa = p_empresa and m.fecha_movimiento < v_hasta + 1
                   group by p.codigo, p.nombre
                   order by p.nombre) loop
            v_hay := true;
            v_ts := v_ts + k.vi;
            v_td := v_td + k.vf;
            w('<tr>' || t(k.codigo) || t(k.nombre) || n(k.qi) || n(k.qe) || n(k.qs) || n(k.qi + k.qe - k.qs)
              || n(k.vi) || n(k.vf) || '</tr>');
        end loop;
        if not v_hay then
            w('<tr><td colspan="8">No hay movimientos de inventario hasta la fecha de corte.</td></tr>');
        end if;
        w('<tr class="spx-tot"><td colspan="6"><b>Total del inventario</b></td>' || n(v_ts, true) || n(v_td, true) || '</tr>');
        begin
            select nvl(sum(d.debe - d.haber), 0) into v_saldo
              from ctb_asiento_det d join ctb_asientos a on a.id_asiento = d.id_asiento
             where a.id_empresa = p_empresa and a.estado in ('CONFIRMADO', 'REVERSADO') and a.fecha <= v_hasta
               and d.id_cuenta_ctb = pkg_contabilidad.fn_cuenta(p_empresa, 'INVENTARIO');
            w('<tr><td colspan="7">Inventario seg&uacute;n la contabilidad (cuenta de inventario)'
              || case when abs(v_saldo - v_td) < 0.05 then ': coincide con el kardex'
                      else ': difiere del kardex (contabiliza los meses pendientes)' end || '</td>' || n(v_saldo, true) || '</tr>');
        exception
            when others then
                null;   -- sin plan de cuentas: solo el kardex
        end;

    elsif v_lib = 'MAYOR' then
        w('<tr class="spx-th"><th>Fecha</th><th>Asiento</th><th>Concepto</th><th>Descripci&oacute;n</th>'
          || '<th class="num">Debe</th><th class="num">Haber</th><th class="num">Saldo</th></tr>');
        for c in (select c.id_cuenta_ctb, c.codigo, c.nombre,
                         nvl(sum(case when a.fecha < v_desde then d.debe - d.haber end), 0) ini,
                         count(case when a.fecha >= v_desde then 1 end) movs
                    from ctb_cuentas c
                    join ctb_asiento_det d on d.id_cuenta_ctb = c.id_cuenta_ctb
                    join ctb_asientos a on a.id_asiento = d.id_asiento
                   where c.id_empresa = p_empresa
                     and (p_id_cuenta is null or c.id_cuenta_ctb = p_id_cuenta)
                     and a.estado in ('CONFIRMADO', 'REVERSADO') and a.fecha <= v_hasta
                   group by c.id_cuenta_ctb, c.codigo, c.nombre
                  having count(case when a.fecha >= v_desde then 1 end) > 0
                      or nvl(sum(case when a.fecha < v_desde then d.debe - d.haber end), 0) <> 0
                   order by c.codigo) loop
            v_hay := true;
            v_saldo := c.ini;
            w('<tr class="spx-grp"><td colspan="7"' || case when v_xls then ' style="font-weight:bold"' end || '>'
              || sys.htf.escape_sc(c.codigo || '  ' || c.nombre) || '</td></tr>');
            w('<tr><td colspan="4">Saldo inicial</td><td></td><td></td>' || n(c.ini) || '</tr>');
            v_td := 0;
            v_th := 0;
            for l in (select a.fecha, a.anio, a.mes, a.numero, a.concepto, d.descripcion, d.debe, d.haber
                        from ctb_asiento_det d join ctb_asientos a on a.id_asiento = d.id_asiento
                       where d.id_cuenta_ctb = c.id_cuenta_ctb and a.estado in ('CONFIRMADO', 'REVERSADO')
                         and a.fecha between v_desde and v_hasta
                       order by a.fecha, a.anio, a.mes, a.numero, d.linea) loop
                v_saldo := v_saldo + l.debe - l.haber;
                v_td := v_td + l.debe;
                v_th := v_th + l.haber;
                w('<tr>' || t(to_char(l.fecha, 'DD/MM/YYYY')) || t(asiento_ref(l.mes, l.anio, l.numero))
                  || t(l.concepto) || t(l.descripcion) || n(l.debe) || n(l.haber) || n(v_saldo) || '</tr>');
            end loop;
            w('<tr class="spx-tot"><td colspan="4"><b>Total ' || sys.htf.escape_sc(c.codigo) || '</b></td>'
              || n(v_td, true) || n(v_th, true) || n(v_saldo, true) || '</tr>');
        end loop;
        if not v_hay then
            w('<tr><td colspan="7">La cuenta no tiene movimientos ni saldo en el periodo.</td></tr>');
        end if;

    else
        w('<tr class="spx-th"><th>C&oacute;digo</th><th>Descripci&oacute;n</th><th class="num">Saldo inicial</th>'
          || '<th class="num">Debe</th><th class="num">Haber</th><th class="num">Saldo actual</th><th></th></tr>');
        for b in (with mov as (
                      select d.id_cuenta_ctb,
                             sum(case when a.fecha < v_desde then d.debe - d.haber else 0 end) ini,
                             sum(case when a.fecha >= v_desde then d.debe else 0 end) debe,
                             sum(case when a.fecha >= v_desde then d.haber else 0 end) haber
                        from ctb_asiento_det d join ctb_asientos a on a.id_asiento = d.id_asiento
                       where a.id_empresa = p_empresa and a.estado in ('CONFIRMADO', 'REVERSADO')
                         and a.fecha <= v_hasta
                       group by d.id_cuenta_ctb),
                  hoja as (
                      select c.codigo, m.ini, m.debe, m.haber
                        from ctb_cuentas c join mov m on m.id_cuenta_ctb = c.id_cuenta_ctb)
                  select c.codigo, c.nombre, c.nivel, c.acepta_movimiento,
                         sum(h.ini) ini, sum(h.debe) debe, sum(h.haber) haber
                    from ctb_cuentas c
                    join hoja h on (h.codigo = c.codigo
                                    or (c.acepta_movimiento = 'N' and substr(h.codigo, 1, length(c.codigo)) = c.codigo))
                   where c.id_empresa = p_empresa
                   group by c.codigo, c.nombre, c.nivel, c.acepta_movimiento
                  having sum(h.ini) <> 0 or sum(h.debe) <> 0 or sum(h.haber) <> 0
                   order by c.codigo) loop
            v_hay := true;
            w('<tr' || case when b.acepta_movimiento = 'N' then ' class="spx-grp"' end || '>'
              || t(b.codigo) || t(b.nombre, 'padding-left:' || ((b.nivel - 1) * 14 + 6) || 'px'
                                   || case when b.acepta_movimiento = 'N' then ';font-weight:bold' end)
              || n(b.ini, b.acepta_movimiento = 'N') || n(b.debe, b.acepta_movimiento = 'N')
              || n(b.haber, b.acepta_movimiento = 'N') || n(b.ini + b.debe - b.haber, b.acepta_movimiento = 'N')
              || '<td></td></tr>');
            if b.acepta_movimiento = 'S' then
                v_ts := v_ts + b.ini;
                v_td := v_td + b.debe;
                v_th := v_th + b.haber;
            end if;
        end loop;
        if not v_hay then
            w('<tr><td colspan="7">No hay movimientos hasta la fecha de corte.</td></tr>');
        end if;
        w('<tr class="spx-tot"><td colspan="2"><b>Total balance de comprobaci&oacute;n</b></td>'
          || n(v_ts, true) || n(v_td, true) || n(v_th, true) || n(v_ts + v_td - v_th, true)
          || '<td>' || case when v_td = v_th then 'Cuadra' else 'NO CUADRA' end || '</td></tr>');
    end if;

    w('</table>');
    if v_xls then
        w('<p>Saldos = debe - haber (los acreedores salen negativos). Moneda funcional de la empresa.</p></body></html>');
    end if;
    return v_html;
exception
    when no_data_found then
        return null;
end fn_ctb_libro;
/
