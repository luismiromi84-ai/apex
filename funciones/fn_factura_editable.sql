-- =============================================================================
-- fn_factura_editable.sql
--
-- Indica si una factura se puede modificar. PAGADA y ANULADA son estados
-- cerrados: el documento ya no se toca, para corregirlo se anula y se emite
-- otro. Se usa en la base (PKG_FACTURACION.prc_actualizar,
-- PKG_FACTURA_DETALLE) y en la condicion del boton Guardar de la pagina 9.
--
-- Un id nulo, cero o inexistente devuelve TRUE: es el caso de alta.
--
-- Medido el 2026-11-05: con mx.demo se podia editar la factura PAGADA F-3
-- (1203) de la empresa 2. La cabecera no tenia ninguna comprobacion y el
-- detalle solo bloqueaba el estado FACTURADO, que no es el que se usa.
-- =============================================================================

create or replace function fn_factura_editable (p_id_factura number)
    return boolean
is
    v_estado facturas.estado%type;
    v_comprobante facturas.nro_comprobante_retencion%type;
begin
    if p_id_factura is null or p_id_factura <= 0 then
        return true;
    end if;

    select estado, nro_comprobante_retencion
      into v_estado, v_comprobante
      from facturas
     where id_factura = p_id_factura;

    -- Registrar el comprobante que entrego el cliente cierra la factura: si
    -- despues cambiaran las lineas, el papel y la factura dirian cosas distintas.
    if v_comprobante is not null then
        return false;
    end if;

    return nvl(upper(trim(v_estado)), 'PENDIENTE') not in ('PARCIAL', 'PAGADA', 'ANULADA');
exception
    when no_data_found then
        return true;
end;
/
