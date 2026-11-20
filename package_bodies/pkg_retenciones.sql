-- =============================================================================
-- package_bodies/pkg_retenciones.sql
--
-- OJO con el runner de importacion: descarta toda linea que empiece por "set ",
-- asi que los UPDATE llevan el SET en la misma linea que el UPDATE.
-- =============================================================================

create or replace package body pkg_retenciones as

    function fn_aplica(p_id_proveedor in number) return boolean is
        v_ret varchar2(1);
    begin
        select nvl(retener_iva, 'S') into v_ret
          from proveedores
         where id_proveedor = p_id_proveedor;
        return v_ret = 'S';
    exception
        when no_data_found then
            return false;
    end fn_aplica;

    function fn_porcentaje(p_id_proveedor in number) return number is
        v_pct number;
    begin
        select case
                 when nvl(p.retener_iva, 'S') <> 'S' then 0
                 when p.cod_pais is not null and e.cod_pais is not null
                      and p.cod_pais <> e.cod_pais then 100
                 else nvl(p.porcentaje_retencion, 75)
               end
          into v_pct
          from proveedores p
          join empresas e on e.id_empresa = p.id_empresa
         where p.id_proveedor = p_id_proveedor;
        return v_pct;
    exception
        when no_data_found then
            return 0;
    end fn_porcentaje;

    function fn_siguiente_numero(p_id_empresa in number, p_fecha in date) return varchar2 is
        v_periodo char(6);
        v_ultimo  number;
    begin
        v_periodo := to_char(nvl(p_fecha, sysdate), 'YYYYMM');
        select nvl(max(ultimo), 0) + 1 into v_ultimo
          from retencion_contador
         where id_empresa = p_id_empresa and periodo = v_periodo;
        return v_periodo || lpad(v_ultimo, 8, '0');
    end fn_siguiente_numero;

    function fn_base_imponible_bs(p_id_compra in number) return number is
        v_base number;
    begin
        select nvl(sum(d.subtotal_bs), 0) into v_base
          from compras_det d
         where d.id_compra = p_id_compra
           and nvl(d.porcentaje_impuesto, 0) > 0
           and not exists (select 1 from impuestos i
                            where i.id_impuesto = d.id_impuesto
                              and (i.cod_impuesto = 'IGTF' or nvl(i.es_retencion, 'N') = 'S'));
        return v_base;
    end fn_base_imponible_bs;

    function fn_iva_causado_bs(p_id_compra in number) return number is
        v_iva number;
    begin
        select nvl(sum(d.monto_impuesto * nvl(d.tasa_cambio_aplicada, 1)), 0) into v_iva
          from compras_det d
         where d.id_compra = p_id_compra
           and nvl(d.porcentaje_impuesto, 0) > 0
           and not exists (select 1 from impuestos i
                            where i.id_impuesto = d.id_impuesto
                              and (i.cod_impuesto = 'IGTF' or nvl(i.es_retencion, 'N') = 'S'));
        return v_iva;
    end fn_iva_causado_bs;

    -- Retencion de IVA del documento: el porcentaje sobre el IVA TOTAL de la factura.
    -- El IVA se agrupa por alicuota y cada grupo se redondea a bolivares (es lo que
    -- imprime el comprobante, linea a linea); los grupos redondeados se SUMAN, y sobre
    -- esa suma se aplica el porcentaje UNA vez, con un solo redondeo.
    --
    -- Es LA MISMA cuenta que hace la emision (prc_emitir) para la cabecera, y la que
    -- usa el resumen del BORRADOR: antes esta funcion sacaba el porcentaje de la suma
    -- SIN redondear los grupos, y en una factura en divisa con dos alicuotas se
    -- separaba un centimo del papel.
    function fn_retencion_bs(p_id_compra in number) return number is
        v_pct   number;
        v_iva   number;
    begin
        select nvl(porcentaje_retencion, 0) into v_pct
          from compras
         where id_compra = p_id_compra;
        if v_pct <= 0 then
            return 0;
        end if;

        select nvl(sum(g.iva_bs), 0) into v_iva
          from (select round(nvl(sum(d.monto_impuesto * nvl(d.tasa_cambio_aplicada, 1)), 0), 2) as iva_bs
                  from compras_det d
                 where d.id_compra = p_id_compra
                   and nvl(d.porcentaje_impuesto, 0) > 0
                   and not exists (select 1 from impuestos i
                                    where i.id_impuesto = d.id_impuesto
                                      and (i.cod_impuesto = 'IGTF'
                                           or nvl(i.es_retencion, 'N') = 'S'))
                 group by d.porcentaje_impuesto) g;

        return round(v_iva * v_pct / 100, 2);
    exception
        when no_data_found then
            return 0;
    end fn_retencion_bs;

    -- -------------------------------------------------------------------------
    -- ISLR (spec 2026-11-19-retenciones-iva-islr, seccion 7.2)
    --
    --   base_islr     = subtotal_documento x base_pct / 100 x tasa_documento
    --   sustraendo_bs = sustraendo_ut x UT
    --   retenido      = base_islr x tarifa / 100 - sustraendo_bs   (piso en 0)
    --
    -- El subtotal del documento es COMPRAS.SUBTOTAL, que mantiene el trigger de
    -- totales a partir del detalle: ya viene sin IVA y sin IGTF. La base es el
    -- documento COMPLETO; el prorrateo por linea no existe en esta fase (una
    -- compra mixta no se soporta: sin concepto no hay retencion).
    -- -------------------------------------------------------------------------

    function fn_valor_ut return number is
        v_ut number;
    begin
        select valor into v_ut
          from syn_parametros
         where clave = 'UT_ISLR';
        return nvl(v_ut, 43);
    exception
        -- Sin el parametro (o con un valor que no es numero) el ISLR no puede
        -- quedarse sin UT: se usa la ultima conocida, 43,00.
        when no_data_found then
            return 43;
        when value_error then
            return 43;
    end fn_valor_ut;

    function fn_islr_base_bs(p_id_compra in number, p_id_concepto in number) return number is
        v_base number;
    begin
        select round(nvl(c.subtotal, 0) * nvl(k.base_pct, 0) / 100 * nvl(c.tipo_cambio, 1), 2)
          into v_base
          from compras c
          join islr_conceptos k on k.id_concepto = p_id_concepto
         where c.id_compra = p_id_compra;
        return nvl(v_base, 0);
    exception
        -- La pantalla llama a esto con una compra que todavia no tiene concepto:
        -- 0 es la respuesta correcta, no un error.
        when no_data_found then
            return 0;
    end fn_islr_base_bs;

    function fn_islr_sustraendo_bs(p_id_concepto in number) return number is
        v_sus_ut number;
    begin
        select nvl(sustraendo_ut, 0)
          into v_sus_ut
          from islr_conceptos
         where id_concepto = p_id_concepto;
        return round(v_sus_ut * fn_valor_ut, 2);
    exception
        when no_data_found then
            return 0;
    end fn_islr_sustraendo_bs;

    function fn_islr_retencion_bs(p_id_compra in number, p_id_concepto in number) return number is
        v_tarifa number;
        v_base   number;
        v_ret    number;
    begin
        select nvl(tarifa, 0)
          into v_tarifa
          from islr_conceptos
         where id_concepto = p_id_concepto;

        v_base := fn_islr_base_bs(p_id_compra, p_id_concepto);
        -- El sustraendo sale de fn_islr_sustraendo_bs y no se recalcula aqui: la
        -- emision del comprobante guarda en la linea el mismo numero que se resto
        -- del importe, y asi no hay dos formulas que se puedan separar.
        v_ret  := round(v_base * v_tarifa / 100 - fn_islr_sustraendo_bs(p_id_concepto), 2);

        -- El sustraendo puede comerse la tarifa entera: por debajo del umbral la
        -- retencion es 0, nunca un importe negativo (seria un abono al proveedor).
        if v_ret < 0 then
            return 0;
        end if;
        return v_ret;
    exception
        when no_data_found then
            return 0;
    end fn_islr_retencion_bs;

    -- Numero del comprobante: una sola serie por empresa y mes de EMISION
    -- (RETENCION_CONTADOR), la misma para IVA y para ISLR. El UPDATE bloquea la fila
    -- hasta el COMMIT, asi que dos sesiones no se llevan el mismo numero; si la fila
    -- del mes todavia no existe se crea. Devuelve AAAAMM + 8 digitos.
    function fn_tomar_numero(p_id_empresa in number, p_fecha in date) return varchar2 is
        v_periodo char(6);
        v_ultimo  number;
    begin
        v_periodo := to_char(nvl(p_fecha, sysdate), 'YYYYMM');

        update retencion_contador set ultimo = ultimo + 1
         where id_empresa = p_id_empresa and periodo = v_periodo
        returning ultimo into v_ultimo;

        if sql%rowcount = 0 then
            begin
                insert into retencion_contador (id_empresa, periodo, ultimo)
                values (p_id_empresa, v_periodo, 1);
                v_ultimo := 1;
            exception
                when dup_val_on_index then
                    update retencion_contador set ultimo = ultimo + 1
                     where id_empresa = p_id_empresa and periodo = v_periodo
                    returning ultimo into v_ultimo;
            end;
        end if;

        return v_periodo || lpad(v_ultimo, 8, '0');
    end fn_tomar_numero;

    procedure prc_emitir(p_id_compra in number, p_id_retencion out number, p_usuario in varchar2) is
        type t_grupo is record (pct number, base_bs number, iva_bs number);
        type t_grupos is table of t_grupo index by pls_integer;
        v_grupos    t_grupos;
        v_g         pls_integer := 0;
        v_empresa   number;
        v_proveedor number;
        v_estado    varchar2(20);
        v_fecha     date;
        v_tasa      number;
        v_monto_total number;
        v_folio     varchar2(50);
        v_control   varchar2(30);
        v_tipo_doc  varchar2(10);
        v_pct       number;
        v_base      number := 0;
        v_iva       number := 0;
        v_retenido  number;
        v_retenido_linea number;
        v_suma      number := 0;
        v_residuo   number;
        v_idx       pls_integer;
        -- Retenido de cada linea, ya redondeado, antes de escribir: el residuo (si lo
        -- hay) se reparte despues, y para eso hay que tener todas las lineas a la vista.
        type t_importes is table of number index by pls_integer;
        v_linea_ret t_importes;
        v_numero    varchar2(14);
        v_ya_tiene  number;
    begin
        p_id_retencion := null;

        select id_empresa, id_proveedor, estado, nvl(fecha_emision, sysdate),
               nvl(tipo_cambio, 1), nvl(monto_total, 0), nvl(porcentaje_retencion, 0),
               folio_factura, nro_control, tipo_documento
          into v_empresa, v_proveedor, v_estado, v_fecha, v_tasa, v_monto_total, v_pct,
               v_folio, v_control, v_tipo_doc
          from compras
         where id_compra = p_id_compra;

        if v_estado <> 'REGISTRADA' then
            raise_application_error(-20083,
                'Solo se emite comprobante de una compra REGISTRADA; esta esta ' || v_estado || '.');
        end if;

        select count(*) into v_ya_tiene
          from retenciones where id_compra = p_id_compra and tipo = 'IVA';
        if v_ya_tiene > 0 then
            raise_application_error(-20086, 'La compra ya tiene comprobante de retencion de IVA.');
        end if;

        -- UNA FILA POR ALICUOTA. El exento y el IGTF quedan fuera (el IGTF es otro
        -- impuesto y no se retiene); es el mismo filtro de fn_base_imponible_bs.
        for r in (select d.porcentaje_impuesto as pct,
                         round(nvl(sum(d.subtotal_bs), 0), 2) as base_bs,
                         round(nvl(sum(d.monto_impuesto * nvl(d.tasa_cambio_aplicada, 1)), 0), 2) as iva_bs
                    from compras_det d
                   where d.id_compra = p_id_compra
                     and nvl(d.porcentaje_impuesto, 0) > 0
                     and not exists (select 1 from impuestos i
                                      where i.id_impuesto = d.id_impuesto
                                        and (i.cod_impuesto = 'IGTF'
                                             or nvl(i.es_retencion, 'N') = 'S'))
                   group by d.porcentaje_impuesto
                   order by d.porcentaje_impuesto) loop
            v_g := v_g + 1;
            v_grupos(v_g).pct     := r.pct;
            v_grupos(v_g).base_bs := r.base_bs;
            v_grupos(v_g).iva_bs  := r.iva_bs;
            v_base := v_base + r.base_bs;
            v_iva  := v_iva + r.iva_bs;
        end loop;

        -- La cabecera es el PORCENTAJE SOBRE EL IVA TOTAL del documento (los grupos ya
        -- redondeados y sumados, un solo redondeo al aplicar el porcentaje). Las lineas
        -- de abajo reparten ese importe entre las alicuotas.
        v_retenido := fn_retencion_bs(p_id_compra);

        -- 0 % (o un IVA que no da retencion) no consume numeracion.
        if v_pct <= 0 or v_retenido <= 0 then
            return;
        end if;

        v_numero := fn_tomar_numero(v_empresa, sysdate);

        -- La cabecera lleva la SUMA de las lineas y el total del documento: el papel
        -- imprime las lineas y su fila de totales tiene que cuadrar con ellas.
        insert into retenciones (id_empresa, id_proveedor, tipo, numero_comprobante, fecha_emision,
                                 periodo_anio, periodo_mes, id_compra, total_con_iva_bs,
                                 sin_derecho_credito_bs, base_imponible_bs, impuesto_bs, retenido_bs,
                                 estado, creado_por)
        values (v_empresa, v_proveedor, 'IVA', v_numero, sysdate,
                to_number(to_char(v_fecha, 'YYYY')), to_number(to_char(v_fecha, 'MM')),
                p_id_compra, round(v_monto_total * v_tasa, 2), 0,
                v_base, v_iva, v_retenido, 'EMITIDO', p_usuario)
        returning id_retencion into p_id_retencion;

        -- Primera pasada: la parte que le toca a cada alicuota (su IVA por el
        -- porcentaje, redondeado). La suma puede diferir en un centimo de la cabecera,
        -- que es el porcentaje del IVA TOTAL con un solo redondeo.
        for i in 1 .. v_g loop
            v_linea_ret(i) := round(v_grupos(i).iva_bs * v_pct / 100, 2);
            v_suma := v_suma + v_linea_ret(i);
        end loop;

        -- Ese centimo va a la linea de MAYOR IVA, no a la ultima: con alicuotas
        -- diminutas la ultima puede quedar en 0,00 teniendo base, y una linea con base
        -- y sin retencion no se sostiene en el papel. La suma de las lineas queda
        -- exactamente igual al retenido de la cabecera (la fila de totales del papel).
        v_residuo := round(v_retenido - v_suma, 2);
        if v_residuo <> 0 then
            v_idx := 1;
            for i in 2 .. v_g loop
                if v_grupos(i).iva_bs > v_grupos(v_idx).iva_bs then
                    v_idx := i;
                end if;
            end loop;
            v_linea_ret(v_idx) := v_linea_ret(v_idx) + v_residuo;
        end if;

        for i in 1 .. v_g loop
            v_retenido_linea := v_linea_ret(i);

            insert into retenciones_det (id_retencion, id_compra, fecha_factura, nro_factura,
                                         nro_control, tipo_documento, total_con_iva_bs,
                                         sin_derecho_credito_bs, base_imponible_bs, porcentaje,
                                         impuesto_bs, retenido_bs)
            values (p_id_retencion, p_id_compra, v_fecha, v_folio, v_control, v_tipo_doc,
                    v_grupos(i).base_bs + v_grupos(i).iva_bs, 0, v_grupos(i).base_bs,
                    v_grupos(i).pct, v_grupos(i).iva_bs, v_retenido_linea);
        end loop;

        update compras set retencion_iva_bs = v_retenido, porcentaje_retencion = v_pct
         where id_compra = p_id_compra;

    exception
        when no_data_found then
            raise_application_error(-20085, 'La compra ' || p_id_compra || ' no existe.');
    end prc_emitir;

    procedure prc_emitir_islr(p_id_compra in number, p_id_retencion out number, p_usuario in varchar2) is
        v_empresa   number;
        v_proveedor number;
        v_estado    varchar2(20);
        v_fecha     date;
        v_tasa      number;
        v_monto_total number;
        v_folio     varchar2(50);
        v_control   varchar2(30);
        v_tipo_doc  varchar2(10);
        v_concepto  number;
        v_codigo    varchar2(5);
        v_actividad varchar2(200);
        v_base_pct  number;
        v_tarifa    number;
        v_sus_ut    number;
        v_ut        number;
        v_base      number;
        v_ret       number;
        v_sus_bs    number;
        v_numero    varchar2(14);
        v_ya_tiene  number;
    begin
        p_id_retencion := null;

        select id_empresa, id_proveedor, estado, nvl(fecha_emision, sysdate),
               nvl(tipo_cambio, 1), nvl(monto_total, 0), folio_factura, nro_control,
               tipo_documento, id_concepto_islr
          into v_empresa, v_proveedor, v_estado, v_fecha, v_tasa, v_monto_total,
               v_folio, v_control, v_tipo_doc, v_concepto
          from compras
         where id_compra = p_id_compra;

        if v_estado <> 'REGISTRADA' then
            raise_application_error(-20083,
                'Solo se emite comprobante de una compra REGISTRADA; esta esta ' || v_estado || '.');
        end if;

        -- Sin concepto no hay retencion de ISLR: es el caso del proveedor que no la
        -- tiene marcada, y no puede consumir numeracion.
        if v_concepto is null then
            return;
        end if;

        v_base := fn_islr_base_bs(p_id_compra, v_concepto);
        v_ret  := fn_islr_retencion_bs(p_id_compra, v_concepto);

        -- Por debajo del umbral el retenido es 0 y no se emite comprobante.
        if v_ret <= 0 then
            return;
        end if;

        select count(*) into v_ya_tiene
          from retenciones where id_compra = p_id_compra and tipo = 'ISLR';
        if v_ya_tiene > 0 then
            raise_application_error(-20086, 'La compra ya tiene comprobante de retencion de ISLR.');
        end if;

        select codigo, actividad, nvl(base_pct, 0), nvl(tarifa, 0), nvl(sustraendo_ut, 0)
          into v_codigo, v_actividad, v_base_pct, v_tarifa, v_sus_ut
          from islr_conceptos
         where id_concepto = v_concepto;

        -- El sustraendo en bolivares sale de fn_islr_sustraendo_bs, que es el mismo
        -- numero que resto fn_islr_retencion_bs: no hay dos formulas que se puedan
        -- separar y la linea del papel guarda lo que de verdad se uso.
        v_ut     := fn_valor_ut;
        v_sus_bs := fn_islr_sustraendo_bs(v_concepto);

        v_numero := fn_tomar_numero(v_empresa, sysdate);

        insert into retenciones (id_empresa, id_proveedor, tipo, numero_comprobante, fecha_emision,
                                 periodo_anio, periodo_mes, id_compra, total_con_iva_bs,
                                 sin_derecho_credito_bs, base_imponible_bs, impuesto_bs, retenido_bs,
                                 id_concepto_islr, codigo_concepto, actividad, estado, creado_por)
        values (v_empresa, v_proveedor, 'ISLR', v_numero, sysdate,
                to_number(to_char(v_fecha, 'YYYY')), to_number(to_char(v_fecha, 'MM')),
                p_id_compra, round(v_monto_total * v_tasa, 2), 0,
                v_base, 0, v_ret,
                v_concepto, v_codigo, v_actividad, 'EMITIDO', p_usuario)
        returning id_retencion into p_id_retencion;

        -- Una sola linea: el ISLR se calcula sobre el documento completo (las compras
        -- mixtas no se soportan en esta fase) y la foto del calculo va aqui. El total
        -- de la linea es el de la factura, que es la columna Â«Total factura Bs.Â» del
        -- papel de ISLR.
        insert into retenciones_det (id_retencion, id_compra, fecha_factura, nro_factura,
                                     nro_control, tipo_documento, total_con_iva_bs,
                                     sin_derecho_credito_bs, base_imponible_bs, porcentaje,
                                     impuesto_bs, retenido_bs, base_pct, tarifa, sustraendo_ut,
                                     valor_ut, sustraendo_bs)
        values (p_id_retencion, p_id_compra, v_fecha, v_folio, v_control, v_tipo_doc,
                round(v_monto_total * v_tasa, 2), 0, v_base, v_tarifa,
                0, v_ret, v_base_pct, v_tarifa, v_sus_ut, v_ut, v_sus_bs);

    exception
        when no_data_found then
            raise_application_error(-20085, 'La compra ' || p_id_compra || ' no existe.');
    end prc_emitir_islr;

    procedure prc_anular(p_id_compra in number, p_usuario in varchar2) is
    begin
        update retenciones set estado = 'ANULADO'
         where id_compra = p_id_compra and estado = 'EMITIDO';
    end prc_anular;

end pkg_retenciones;
/
