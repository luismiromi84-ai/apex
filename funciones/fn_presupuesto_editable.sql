-- =============================================================================
-- fn_presupuesto_editable.sql
--
-- Indica si un presupuesto se puede modificar. CANCELADO y FACTURADO son
-- estados cerrados: el documento ya no se toca (si esta facturado, hay una
-- factura colgando; si esta cancelado, es terminal). Para rehacerlo se crea
-- otro. Un id nulo, cero o inexistente devuelve TRUE: es el caso de alta.
--
-- La usan la base (PKG_PRESUPUESTOS, PKG_PRESUPUESTO_DETALLE) y la condicion
-- del boton Guardar de la pagina 7.
--
-- Mismo criterio que fn_factura_editable (PAGADA y ANULADA), pedido por el
-- dueno el 2026-11-05 tras cerrar el lado de facturas.
-- =============================================================================

create or replace function fn_presupuesto_editable (p_id_presupuesto number)
    return boolean
is
    v_estado presupuestos.estado%type;
begin
    if p_id_presupuesto is null or p_id_presupuesto <= 0 then
        return true;
    end if;

    select estado
      into v_estado
      from presupuestos
     where id_presupuesto = p_id_presupuesto;

    return nvl(upper(trim(v_estado)), 'PENDIENTE') not in ('CANCELADO', 'FACTURADO');
exception
    when no_data_found then
        return true;
end;
/
