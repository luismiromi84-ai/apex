-- =============================================================================
-- 20261125_estado_nota_procesada.sql
--
-- En Venezuela una NOTA de credito o de debito no se «timbra» ni se «emite»: se
-- PROCESA. Hasta hoy el dialogo de la factura mostraba «TIMBRADA» (el codigo
-- interno) y las listas la pintaban «EMITIDA», igual que una factura.
--
-- fn_estado_factura gana un tercer parametro (el tipo de documento, opcional):
--   TIMBRADA + VE + FAC  -> EMITIDA    (como estaba)
--   TIMBRADA + VE + NC/ND-> PROCESADA  (nuevo)
--   TIMBRADA + MX        -> TIMBRADA   (sin cambios)
--
-- Idempotente. FALLAS=0 = EXITO.
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
        -- Una nota no se «emite» ni se «timbra»: se procesa.
        if v_tipo in ('NC', 'ND') then
            return 'PROCESADA';
        end if;
        return 'EMITIDA';
    end if;
    return p_estado;
end fn_estado_factura;
/

declare
    v_fallas number := 0;
    v_lista  varchar2(2000) := '';
    v_n      number;

    procedure espera(p_caso varchar2, p_dado varchar2, p_esperado varchar2) is
    begin
        if nvl(p_dado, '#') <> p_esperado then
            v_fallas := v_fallas + 1;
            v_lista := v_lista || ' | ' || p_caso || ': ' || nvl(p_dado, 'NULL') || ' <> ' || p_esperado;
        end if;
    end;
begin
    espera('factura VE',   fn_estado_factura('TIMBRADA', 'VE', 'FAC'), 'EMITIDA');
    espera('nota VE',      fn_estado_factura('TIMBRADA', 'VE', 'NC'),  'PROCESADA');
    espera('nota debito',  fn_estado_factura('TIMBRADA', 'VE', 'ND'),  'PROCESADA');
    espera('Mexico',       fn_estado_factura('TIMBRADA', 'MX', 'FAC'), 'TIMBRADA');
    espera('nota Mexico',  fn_estado_factura('TIMBRADA', 'MX', 'NC'),  'TIMBRADA');
    espera('sin tipo',     fn_estado_factura('TIMBRADA', 'VE'),        'EMITIDA');
    espera('pendiente',    fn_estado_factura('PENDIENTE', 'VE', 'FAC'), 'PENDIENTE');
    espera('anulada',      fn_estado_factura('ANULADA', 'VE', 'FAC'),  'ANULADA');

    select count(*) into v_n from all_objects
     where owner = 'WKSP_SYPEXWS' and object_name = 'FN_ESTADO_FACTURA' and status = 'INVALID';
    if v_n > 0 then
        v_fallas := v_fallas + 1;
        v_lista := v_lista || ' | FN_ESTADO_FACTURA invalida';
    end if;

    raise_application_error(-20100, substrb('RESULTADO: FALLAS=' || v_fallas || v_lista, 1, 2000));
end;
/
