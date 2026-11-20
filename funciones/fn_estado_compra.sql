-- =============================================================================
-- fn_estado_compra
--
-- La etiqueta que se LEE en pantalla para el estado de una factura de compra.
-- El valor guardado en COMPRAS.ESTADO no cambia: de el dependen las condiciones
-- de servidor de la pagina 28, la emision de los comprobantes y el libro.
--
--   select fn_estado_compra('BORRADOR')  from dual;  -> Borrador
--   select fn_estado_compra('REGISTRADA') from dual;  -> Procesada
--   select fn_estado_compra('ANULADA')   from dual;  -> Anulada
--
-- Cualquier otro valor se devuelve TAL CUAL (no se inventa una etiqueta para un
-- estado que no conoce: es preferible verlo crudo a leer algo falso).
--
-- "Procesada" es la palabra que usa el cliente para la compra ya registrada y
-- emitidos sus comprobantes de retencion: en Venezuela la factura de compra no se
-- "timbra", la procesa el receptor.
-- =============================================================================

create or replace function fn_estado_compra (
    p_estado in varchar2
) return varchar2 is
begin
    return case upper(nvl(p_estado, '#'))
               when 'BORRADOR'   then 'Borrador'
               when 'REGISTRADA' then 'Procesada'
               when 'ANULADA'    then 'Anulada'
               else p_estado
           end;
end fn_estado_compra;
/
