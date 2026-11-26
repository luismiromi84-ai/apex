-- =============================================================================
-- 20261125_estado_procesada_ve.sql
--
-- En Venezuela una factura procesada (TIMBRADA) se lee PROCESADA, igual que una
-- nota (antes EMITIDA). El dato guardado no cambia. Idempotente.
--
--   python deploy/conexion/importar_export.py deploy/migrations/20261125_estado_procesada_ve.sql
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

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

declare
    v_n number;
begin
    if fn_estado_factura('TIMBRADA', 'VE') <> 'PROCESADA'
       or fn_estado_factura('TIMBRADA', 'VE', 'NC') <> 'PROCESADA'
       or fn_estado_factura('TIMBRADA', 'MX') <> 'TIMBRADA'
       or fn_estado_factura('PAGADA', 'VE') <> 'PAGADA' then
        raise_application_error(-20100, 'fn_estado_factura no devuelve lo esperado');
    end if;
end;
/
