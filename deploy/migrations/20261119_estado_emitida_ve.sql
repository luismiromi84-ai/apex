-- =============================================================================
-- 20261119_estado_emitida_ve.sql
--
-- En Venezuela la factura NO se timbra (el timbrado es el CFDI de Mexico). El
-- estado interno sigue siendo TIMBRADA —lo comparan el saldo, los cobros, el
-- libro y los reportes— pero para una empresa venezolana se MUESTRA «EMITIDA».
--
-- Solo se crea la funcion; las pantallas (lista de Facturacion, reporte de
-- facturas y libro) ya la llaman desde el export.
--
-- Reversa: drop function fn_estado_factura.
-- Verificacion: deploy/diagnostico/20261119_estado_emitida_ve_verificacion.sql
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

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

begin
    dbms_utility.compile_schema('WKSP_SYPEXWS', false);
end;
/

declare
    v_n   number;
    v_txt varchar2(30);
begin
    select count(*) into v_n
      from all_objects
     where owner = 'WKSP_SYPEXWS' and object_name = 'FN_ESTADO_FACTURA'
       and status = 'VALID';
    if v_n < 1 then
        raise_application_error(-20112, 'FN_ESTADO_FACTURA quedo invalida');
    end if;

    select fn_estado_factura('TIMBRADA', 'VE') into v_txt from dual;
    if v_txt <> 'EMITIDA' then
        raise_application_error(-20112, 'VE no muestra EMITIDA: ' || v_txt);
    end if;

    select fn_estado_factura('TIMBRADA', 'MX') into v_txt from dual;
    if v_txt <> 'TIMBRADA' then
        raise_application_error(-20112, 'MX deberia seguir TIMBRADA: ' || v_txt);
    end if;
end;
/
