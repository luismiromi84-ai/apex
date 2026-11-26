-- =============================================================================
-- 20261125_anular_solo_facturas.sql
--
-- «Anular» solo en facturas (FAC): a una nota de credito/debito no se le ofrece
-- (antes fn_factura_anulable aceptaba cualquier documento no anulado y una nota
-- procesada mostraba el boton). Idempotente.
--
--   python deploy/conexion/importar_export.py deploy/migrations/20261125_anular_solo_facturas.sql
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

create or replace function fn_factura_anulable (p_id_factura number)
    return boolean
is
    v_estado facturas.estado%type;
    v_tipo   facturas.tipo_documento%type;
begin
    if p_id_factura is null or p_id_factura <= 0 then
        return false;
    end if;

    select upper(trim(estado)), upper(trim(nvl(tipo_documento, 'FAC')))
      into v_estado, v_tipo
      from facturas
     where id_factura = p_id_factura;

    return v_tipo = 'FAC' and nvl(v_estado, 'X') <> 'ANULADA';
exception
    when no_data_found then
        return false;
end;
/

declare
    v_n number;
    v_id number;
begin
    select count(*) into v_n from all_objects
     where owner = 'WKSP_SYPEXWS' and object_name = 'FN_FACTURA_ANULABLE' and status = 'VALID';
    if v_n <> 1 then
        raise_application_error(-20100, 'FN_FACTURA_ANULABLE no quedo VALID');
    end if;
    select max(id_factura) into v_id from facturas where tipo_documento in ('NC','ND') and estado <> 'ANULADA';
    if v_id is not null and fn_factura_anulable(v_id) then
        raise_application_error(-20100, 'una nota sigue siendo anulable');
    end if;
end;
/
