-- =============================================================================
-- fn_importe_compra.sql
--
-- Lo que se debe de una compra ANTES de pagar, en la moneda de la compra
-- (2026-11-21). Es la base de fn_saldo_compra y la unica formula del sistema:
--
--   importe = total + IGTF_BS/tc - RETENCION_IVA_BS/tc - RETENCION_ISLR_BS/tc
--             + notas de debito - notas de credito
--
-- Las tres cantidades en bolivares (IGTF y las dos retenciones) son FOTOGRAFIAS
-- guardadas en la compra: aqui NO se recalculan ni se consulta la configuracion
-- de la empresa (SPE) ni la forma de pago. Asi una compra cerrada no cambia su
-- deuda porque manana se apague ES_SPE.
--
-- Las notas de credito restan y las de debito suman, igual que en ventas
-- (fn_saldo_factura), y cada una se convierte con SU propia tasa porque pueden
-- haberse emitido otro dia.
--
-- Solo cuentan las notas REGISTRADAS: una nota en BORRADOR no esta emitida y no
-- puede bajar (ni subir) la deuda real. Medido el 2026-11-21: el borrador de NC
-- de la compra 964 dejaba su saldo en negativo y hacia desaparecer la factura de
-- la pantalla de pagos.
--
-- Devuelve 0 si la compra no existe o esta ANULADA.
-- =============================================================================

create or replace function fn_importe_compra (
    p_id_compra in number
) return number is
    v_total   number;
    v_estado  varchar2(20);
    v_tc      number;
    v_igtf    number;
    v_riva    number;
    v_rislr   number;
    v_notas   number;
begin
    if p_id_compra is null then
        return 0;
    end if;

    begin
        select c.monto_total, c.estado, nvl(nullif(c.tipo_cambio, 0), 1),
               nvl(c.igtf_bs, 0), nvl(c.retencion_iva_bs, 0), nvl(c.retencion_islr_bs, 0)
          into v_total, v_estado, v_tc, v_igtf, v_riva, v_rislr
          from compras c
         where c.id_compra = p_id_compra;
    exception
        when no_data_found then
            return 0;
    end;

    if v_estado = 'ANULADA' then
        return 0;
    end if;

    select nvl(sum(case n.tipo_documento when 'NC' then -1 else 1 end
                   * nvl(n.monto_total, 0) * nvl(nullif(n.tipo_cambio, 0), 1) / v_tc), 0)
      into v_notas
      from compras n
     where n.id_compra_origen = p_id_compra
       and n.tipo_documento in ('NC', 'ND')
       and n.estado = 'REGISTRADA';

    return round(v_total + v_notas
                 + v_igtf / v_tc - v_riva / v_tc - v_rislr / v_tc, 2);
end fn_importe_compra;
/
