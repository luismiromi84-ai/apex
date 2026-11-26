-- =============================================================================
-- fn_estado_factura
--
-- El estado INTERNO de un documento no cambia (TIMBRADA, PARCIAL, PAGADA…): es lo
-- que comparan el saldo, los cobros, el libro y los reportes. Lo que cambia es
-- lo que se LEE:
--
--   * en Venezuela no se timbra (eso es el CFDI de Mexico): una FACTURA y una NOTA
--     de credito o de debito en TIMBRADA se leen PROCESADA (2026-11-25, el dueno:
--     «el estado es PROCESADA tanto en nota como en factura»; antes la factura
--     decia EMITIDA);
--   * en Mexico se queda TIMBRADA (ahi si hay timbrado).
--
--   select fn_estado_factura('TIMBRADA', 'VE')        from dual;  -> PROCESADA
--   select fn_estado_factura('TIMBRADA', 'VE', 'NC')  from dual;  -> PROCESADA
--   select fn_estado_factura('TIMBRADA', 'MX', 'NC')  from dual;  -> TIMBRADA
--
-- El tercer parametro (tipo) se conserva por compatibilidad con las llamadas.
-- Se usa en las pantallas (listas, reporte, libro, ficha del cliente y dialogo
-- de la factura).
-- =============================================================================

create or replace function fn_estado_factura (
    p_estado    in varchar2,
    p_cod_pais  in varchar2,
    p_tipo      in varchar2 default null
) return varchar2 is
    v_estado varchar2(30) := upper(trim(nvl(p_estado, '#')));
    v_pais   varchar2(10) := upper(trim(nvl(p_cod_pais, '#')));
    v_tipo   varchar2(10) := upper(trim(nvl(p_tipo, '#')));
begin
    if v_estado = 'TIMBRADA' and v_pais = 'VE' then
        -- 2026-11-25 (dueno): en Venezuela no se timbra; factura y nota procesadas
        -- se leen igual, PROCESADA. p_tipo se conserva por compatibilidad.
        return 'PROCESADA';
    end if;
    return p_estado;
end fn_estado_factura;
/
