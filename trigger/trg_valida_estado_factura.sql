-- =============================================================================
-- trg_valida_estado_factura.sql
--
-- Impide los retrocesos de estado que no tienen sentido. La regla vive en
-- fn_transicion_estado_valida.
-- =============================================================================

create or replace trigger trg_valida_estado_factura
    before update of estado on facturas
    for each row
begin
    if not fn_transicion_estado_valida('FACTURA', :old.estado, :new.estado) then
        raise_application_error(-20070,
            'No se puede pasar una factura de ' || :old.estado
            || ' a ' || :new.estado
            || '. Una factura ANULADA ya no se mueve, y una PAGADA solo puede volver a'
            || ' TIMBRADA o PARCIAL (cuando se anula un cobro) o anularse.');
    end if;
end;
/
