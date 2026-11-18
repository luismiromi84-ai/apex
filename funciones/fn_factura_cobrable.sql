-- =============================================================================
-- fn_factura_cobrable.sql
--
-- Indica si una factura se puede cobrar: estado TIMBRADA o PARCIAL y saldo
-- pendiente mayor que un centimo (2026-11-19).
--
-- Por que existe: el atajo «Cobrar» (columna de la lista de Facturacion y boton
-- del dialogo de la factura) tiene que desaparecer en cuanto la factura esta
-- PAGADA, ANULADA o ya no debe nada. La condicion de un boton es una expresion
-- PL/SQL y NO admite subconsultas, asi que la regla vive aqui, en un solo sitio.
--
-- Usa fn_saldo_factura: total - notas de credito timbradas + notas de debito
-- timbradas - cobros activos. Un id nulo o inexistente devuelve FALSE.
-- =============================================================================

create or replace function fn_factura_cobrable (p_id_factura number)
    return boolean
is
    v_estado facturas.estado%type;
    v_tipo   facturas.tipo_documento%type;
begin
    if p_id_factura is null or p_id_factura <= 0 then
        return false;
    end if;

    select upper(trim(estado)), tipo_documento
      into v_estado, v_tipo
      from facturas
     where id_factura = p_id_factura;

    -- Una nota de credito/debito no se cobra: lo que se cobra es la factura.
    if v_tipo <> 'FAC' then
        return false;
    end if;

    if v_estado not in ('TIMBRADA', 'PARCIAL') then
        return false;
    end if;

    return nvl(fn_saldo_factura(p_id_factura), 0) > 0.01;
exception
    when no_data_found then
        return false;
end;
/
