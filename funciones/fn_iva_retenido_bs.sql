-- =============================================================================
-- fn_iva_retenido_bs.sql
--
-- IVA retenido por el cliente, en bolivares, de una factura (2026-11-17).
--
-- La retencion de IVA se calcula sobre el **IVA**, no sobre el total de
-- impuestos: el IGTF 3 % no se retiene. Antes se usaba MONTO_IMPUESTO completo,
-- asi que un documento que mezclara IVA e IGTF retenia tambien el 3 % del IGTF.
--
-- Se calcula por linea, con la tasa aplicada a la linea (la misma que usan el
-- libro de ventas y el impreso) y sin mirar el porcentaje guardado en la
-- cabecera: el porcentaje se pasa como parametro para poder recalcular cuando
-- cambia. La tasa de respaldo tambien llega como parametro (ver nota abajo).
--
-- Se usa desde:
--   * trg_actualiza_totales_factura, cada vez que cambia el detalle;
--   * pkg_facturacion.prc_guardar_factura, al guardar la cabecera.
--
-- Devuelve 0 si no hay factura o el porcentaje es 0 o nulo.
-- =============================================================================

create or replace function fn_iva_retenido_bs (
    p_id_factura  in number,
    p_porcentaje  in number default null,
    p_tasa_defecto in number default 1
) return number is
    v_pct    number := nvl(p_porcentaje, 0);
    v_iva_bs number := 0;
begin
    if p_id_factura is null or v_pct <= 0 then
        return 0;
    end if;

    -- Ojo: aqui NO se puede leer FACTURAS. La funcion se llama desde el trigger
    -- de totales mientras esa misma cabecera se esta actualizando, y leerla da
    -- ORA-04091 (tabla mutante). La tasa de respaldo llega como parametro.
    select nvl(sum(case
                    when nvl(i.cod_impuesto, 'X') <> 'IGTF'
                     and nvl(d.porcentaje_impuesto, 0) > 0
                    then nvl(d.monto_impuesto, 0)
                         * nvl(d.tasa_cambio_aplicada, nvl(p_tasa_defecto, 1))
                    else 0
                   end), 0)
      into v_iva_bs
      from facturas_det d
      left join impuestos i on i.id_impuesto = d.id_impuesto
     where d.id_factura = p_id_factura;

    return round(v_iva_bs * v_pct / 100, 2);
end fn_iva_retenido_bs;
/
