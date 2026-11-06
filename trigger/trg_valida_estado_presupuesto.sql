-- =============================================================================
-- trg_valida_estado_presupuesto.sql
--
-- Impide los retrocesos de estado que no tienen sentido. La regla vive en
-- fn_transicion_estado_valida.
-- =============================================================================

create or replace trigger trg_valida_estado_presupuesto
    before update of estado on presupuestos
    for each row
begin
    if not fn_transicion_estado_valida('PRESUPUESTO', :old.estado, :new.estado) then
        raise_application_error(-20070,
            'No se puede pasar un presupuesto de ' || :old.estado
            || ' a ' || :new.estado
            || '. Un presupuesto CANCELADO ya no se mueve, y uno FACTURADO solo vuelve a APROBADO (anulando la factura).');
    end if;
end;
/
