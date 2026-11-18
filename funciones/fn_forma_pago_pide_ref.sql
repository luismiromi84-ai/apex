-- =============================================================================
-- fn_forma_pago_pide_ref.sql
--
-- Dice si una forma de pago exige referencia bancaria (2026-11-19).
--
-- Por que existe: en el cobro, si la forma de pago es «Efectivo» (o cualquier
-- otra que no deje rastro bancario) el campo «Referencia bancaria» no tiene
-- sentido y se deja de solo lectura. La condicion de solo lectura de un item es
-- una expresion PL/SQL y NO admite subconsultas, asi que la regla vive aqui.
--
-- Devuelve 'S' o 'N' (para poder usarla tal cual en la condicion). Un id nulo o
-- inexistente devuelve 'N'.
-- =============================================================================

create or replace function fn_forma_pago_pide_ref (p_id_forma_pago number)
    return varchar2
is
    v_ref forma_pago.requiere_ref%type;
begin
    if p_id_forma_pago is null or p_id_forma_pago <= 0 then
        return 'N';
    end if;

    select nvl(requiere_ref, 'N')
      into v_ref
      from forma_pago
     where id_forma_pago = p_id_forma_pago;

    return case when upper(trim(v_ref)) in ('S', 'Y') then 'S' else 'N' end;
exception
    when no_data_found then
        return 'N';
end;
/
