-- =============================================================================
-- 20261122_rif_mayusculas.sql
--
-- Los RIF/RFC se guardan en MAYUSCULAS (2026-11-22). El de clientes y proveedores
-- ya se normalizaba al guardar; el que quedo en minusculas fue el RIF de la
-- imprenta en los datos fiscales ('j-85462139-7') y el de la empresa se guardaba
-- tal cual se tecleaba. Aqui se corrige lo ya guardado y se valida.
--
-- Los procesos de las paginas 19 (empresa y datos fiscales), 21 y 23 ya pasan el
-- valor por upper(trim(...)): esto es solo el barrido del historico.
--
-- Idempotente.
--
-- Uso:
--   python deploy/conexion/importar_export.py deploy/migrations/20261122_rif_mayusculas.sql
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

update clientes set rif = upper(trim(rif)) where rif <> upper(trim(rif));
/

update proveedores set rif = upper(trim(rif)) where rif <> upper(trim(rif));
/

update empresas set rfc = upper(trim(rfc)) where rfc <> upper(trim(rfc));
/

update empresa_fiscal set imprenta_rif = upper(trim(imprenta_rif))
 where imprenta_rif <> upper(trim(imprenta_rif));
/

declare
    v_lista varchar2(500) := '';
    v_n     number;
begin
    -- OJO: la validacion lanza al final (para que el runner lo vea) y eso revierte
    -- la transaccion: el barrido se confirma ANTES de validar (medido el 2026-11-22,
    -- sin este commit los UPDATE no quedaban guardados).
    commit;

    select count(*) into v_n from clientes where rif <> upper(rif);
    if v_n <> 0 then
        v_lista := v_lista || ' | ' || v_n || ' clientes';
    end if;
    select count(*) into v_n from proveedores where rif <> upper(rif);
    if v_n <> 0 then
        v_lista := v_lista || ' | ' || v_n || ' proveedores';
    end if;
    select count(*) into v_n from empresas where rfc <> upper(rfc);
    if v_n <> 0 then
        v_lista := v_lista || ' | ' || v_n || ' empresas';
    end if;
    select count(*) into v_n from empresa_fiscal where imprenta_rif <> upper(imprenta_rif);
    if v_n <> 0 then
        v_lista := v_lista || ' | ' || v_n || ' datos fiscales';
    end if;

    if v_lista is null then
        raise_application_error(-20100, 'RESULTADO: FALLAS=0');
    else
        raise_application_error(-20100, substrb('RESULTADO: FALLAS=1' || v_lista, 1, 500));
    end if;
end;
/
