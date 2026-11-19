-- =============================================================================
-- fn_estado_factura
--
-- El estado INTERNO de una factura no cambia (TIMBRADA, PARCIAL, PAGADA…): es lo
-- que comparan el saldo, los cobros, el libro y los reportes. Lo que cambia es
-- lo que se LEE: en Venezuela la factura no se timbra (eso es el CFDI de Mexico),
-- asi que para una empresa venezolana «TIMBRADA» se muestra como «EMITIDA».
--
--   select fn_estado_factura('TIMBRADA', 'VE') from dual;  -> EMITIDA
--   select fn_estado_factura('TIMBRADA', 'MX') from dual;  -> TIMBRADA
--
-- Se usa en las pantallas (listas, reporte, libro y el dialogo de la factura).
-- =============================================================================

create or replace function fn_estado_factura (
    p_estado    in varchar2,
    p_cod_pais  in varchar2
) return varchar2 is
begin
    if upper(nvl(p_estado, '#')) = 'TIMBRADA' and upper(nvl(p_cod_pais, '#')) = 'VE' then
        return 'EMITIDA';
    end if;
    return p_estado;
end fn_estado_factura;
/
