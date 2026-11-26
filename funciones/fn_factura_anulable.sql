-- =============================================================================
-- fn_factura_anulable
--
-- ¿Se puede pulsar «Anular» en este documento? (pagina 9)
--
-- Solo una FACTURA (FAC) que no este ya ANULADA. Anular emite una nota de credito
-- por el total (prc_anular_factura_nc); sobre una nota de credito o de debito eso
-- no tiene sentido fiscal (para revertir una NC se emite una ND), asi que a las
-- notas no se les ofrece el boton (2026-11-25; antes la funcion aceptaba cualquier
-- documento no anulado). Una factura con cobros vivos la rechaza el package (-20091).
-- =============================================================================

create or replace function fn_factura_anulable (p_id_factura number)
    return boolean
is
    v_estado facturas.estado%type;
    v_tipo   facturas.tipo_documento%type;
begin
    if p_id_factura is null or p_id_factura <= 0 then
        return false;
    end if;

    select upper(trim(estado)), upper(trim(nvl(tipo_documento, 'FAC')))
      into v_estado, v_tipo
      from facturas
     where id_factura = p_id_factura;

    return v_tipo = 'FAC' and nvl(v_estado, 'X') <> 'ANULADA';
exception
    when no_data_found then
        return false;
end;
/
