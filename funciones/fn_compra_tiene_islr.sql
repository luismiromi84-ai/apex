-- =============================================================================
-- fn_compra_tiene_islr
--
-- ¿La compra tiene emitido su comprobante de retencion de ISLR y sigue vigente?
-- Es la condicion del boton «Comprobante ISLR» de la pagina 28: el boton no puede
-- depender del CONCEPTO (una compra por debajo del umbral tiene concepto y no
-- tiene papel: la impresion devolveria NULL) ni del estado de la compra.
--
-- Vive en una funcion y no en la condicion del boton porque una condicion PL/SQL
-- no admite subconsultas; asi el boton queda como los demas de la app
-- (`p_button_condition2=>'PLSQL'`) y no depende del SQL con BOOLEAN de 23ai+.
--
-- El estado de un comprobante anulado es 'ANULADO' (no 'ANULADA'): es la errata
-- que dejaba el boton visible en un comprobante anulado.
-- =============================================================================

create or replace function fn_compra_tiene_islr (
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
       and r.tipo = 'ISLR'
       and nvl(r.estado, 'EMITIDO') <> 'ANULADO';

    return v_n > 0;
end fn_compra_tiene_islr;
/
