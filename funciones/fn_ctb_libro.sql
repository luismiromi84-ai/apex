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
    v_lib   varchar2(10) := upper(nvl(p_libro, 'BALANCE'));
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
        w('<tr class="spx-tot"><td colspan="2"><b>' || case when v_ts - v_td - v_th >= 0 then 'UTILIDAD' else 'P&Eacute;RDIDA' end
          || ' DEL PER&Iacute;ODO</b> (ingresos - costos - gastos)</td>' || n(v_ts - v_td - v_th, true) || '</tr>');

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
           and substr(c.codigo, 1, 1) in ('4', '5', '6');
        w('<tr><td></td><td>Resultado del ejercicio a&uacute;n no cerrado</td>' || n(v_saldo, true) || '</tr>');
        w('<tr class="spx-tot"><td colspan="2"><b>Total pasivo + patrimonio + resultado</b></td>'
          || n(v_td + v_th + v_saldo, true) || '</tr>');
        w('<tr><td colspan="3">' || case when abs(v_ts - (v_td + v_th + v_saldo)) < 0.005 then 'Cuadra: activo = pasivo + patrimonio + resultado'
          else 'NO CUADRA: diferencia ' || to_char(v_ts - (v_td + v_th + v_saldo), 'FM999G999G999G990D00') end || '</td></tr>');

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
