-- =============================================================================
-- fn_estado_compra
--
-- La etiqueta que se LEE en pantalla para el estado de una factura de compra.
-- El valor guardado en COMPRAS.ESTADO no cambia: de el dependen las condiciones
-- de servidor de la pagina 28, la emision de los comprobantes y el libro.
--
--   select fn_estado_compra('BORRADOR')  from dual;  -> Pendiente
--   select fn_estado_compra('REGISTRADA') from dual;  -> Procesada
--   select fn_estado_compra('PARCIAL')    from dual;  -> Abonada
--   select fn_estado_compra('PAGADA')     from dual;  -> Pagada
--   select fn_estado_compra('ANULADA')   from dual;  -> Anulada
--
-- Cualquier otro valor se devuelve TAL CUAL (no se inventa una etiqueta para un
-- estado que no conoce: es preferible verlo crudo a leer algo falso).
--
-- "Procesada" es la palabra que usa el cliente para la compra ya registrada y
-- emitidos sus comprobantes de retencion: en Venezuela la factura de compra no se
-- "timbra", la procesa el receptor.
--
-- "Pendiente" (2026-11-22, pedido del dueno): el documento capturado que todavia
-- no se ha procesado. El valor guardado SIGUE SIENDO BORRADOR; solo cambia lo que
-- se lee, igual que "Procesada".
-- =============================================================================

create or replace function fn_estado_compra (
    p_estado in varchar2
) return varchar2 is
begin
    return case upper(nvl(p_estado, '#'))
               when 'BORRADOR'   then 'Pendiente'
               when 'REGISTRADA' then 'Procesada'
               when 'PARCIAL'    then 'Abonada'
               when 'PAGADA'     then 'Pagada'
               when 'ANULADA'    then 'Anulada'
               else p_estado
           end;
end fn_estado_compra;
/
