-- =============================================================================
-- fn_compra_tiene_iva
--
-- ¿La compra tiene emitido su comprobante de retencion de IVA y sigue vigente?
--
-- Es la condicion del boton «Imprimir comprobante» de la pagina 28. El boton no
-- puede depender del estado ni del porcentaje: prc_emitir NO emite cuando el
-- porcentaje es 0 (proveedor que no retiene) o cuando la compra es toda exenta,
-- y entonces la pagina 31 imprimiria una region vacia.
--
-- Vive en una funcion y no en la condicion del boton porque una condicion PL/SQL
-- no admite subconsultas; asi el boton queda como el resto de la app
-- (`p_button_condition2=>'PLSQL'`).
--
-- El estado de un comprobante anulado es 'ANULADO' (no 'ANULADA'), igual que en
-- fn_compra_tiene_islr: anular la compra deja los dos papeles anulados y los dos
-- botones tienen que desaparecer.
-- =============================================================================

create or replace function fn_compra_tiene_iva (
    p_id_compra in number
) return boolean is
    v_n pls_integer;
begin
    if p_id_compra is null or p_id_compra = 0 then
        return false;
    end if;

    select count(*)
      into v_n
      from retenciones r
     where r.id_compra = p_id_compra
       and r.tipo = 'IVA'
       and nvl(r.estado, 'EMITIDO') <> 'ANULADO';

    return v_n > 0;
end fn_compra_tiene_iva;
/
