-- =============================================================================
-- fn_factura_editable.sql
--
-- Indica si una factura se puede modificar (2026-11-19).
--
-- Regla fiscal: solo el BORRADOR se toca. En cuanto el documento se procesa
-- (TIMBRADA) ya tiene numero de control y folio y no se puede alterar; para
-- corregirlo se anula con nota de credito y se emite otro. Tambien estan
-- cerrados PARCIAL, PAGADA y ANULADA, y cualquier documento con comprobante de
-- retencion registrado.
--
-- Un id nulo, cero o inexistente devuelve TRUE: es el caso de alta.
--
-- Se usa en la base (PKG_FACTURACION.prc_actualizar, PKG_FACTURA_DETALLE) y en
-- las condiciones de los botones de la pagina 9.
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

    return nvl(upper(trim(v_estado)), 'PENDIENTE') = 'PENDIENTE';
exception
    when no_data_found then
        return true;
end;
/

-- =============================================================================
-- fn_factura_anulable: se puede anular mientras no este ya anulada.
--
-- Se separa de fn_factura_editable porque anular es justo lo que se hace con un
-- documento emitido: si la condicion del boton usara "editable", el boton
-- «Anular» desapareceria precisamente en las facturas TIMBRADA.
-- =============================================================================

create or replace function fn_factura_anulable (p_id_factura number)
    return boolean
is
    v_estado facturas.estado%type;
begin
    if p_id_factura is null or p_id_factura <= 0 then
        return false;
    end if;

    select upper(trim(estado))
      into v_estado
      from facturas
     where id_factura = p_id_factura;

    return nvl(v_estado, 'X') <> 'ANULADA';
exception
    when no_data_found then
        return false;
end;
/
