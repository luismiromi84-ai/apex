-- =============================================================================
-- 20261111_clientes_tipo_persona.sql
--
-- Modulo de Clientes (2026-11-11):
--   1. CLIENTES.TIPO_PERSONA ('J' juridica, 'N' natural). Los clientes que ya
--      existen quedan como juridicas (default).
--   2. fn_rif_cliente_valido: la forma del RIF/RFC por pais y tipo de persona,
--      SIN comprobar el digito verificador (decision del dueno).
--
-- Idempotente. Recompila el esquema al final.
--
-- REVERSA:
--   drop function fn_rif_cliente_valido;
--   alter table clientes drop constraint chk_clientes_tipo_persona;
--   alter table clientes drop column tipo_persona;
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;
/

declare
    v_n number;
begin
    select count(*) into v_n
      from all_tab_columns
     where owner = 'WKSP_SYPEXWS' and table_name = 'CLIENTES'
       and column_name = 'TIPO_PERSONA';

    if v_n = 0 then
        execute immediate q'[alter table clientes add (tipo_persona char(1) default 'J' not null)]';
    end if;
end;
/

declare
    v_n number;
begin
    select count(*) into v_n
      from all_constraints
     where owner = 'WKSP_SYPEXWS' and table_name = 'CLIENTES'
       and constraint_name = 'CHK_CLIENTES_TIPO_PERSONA';

    if v_n = 0 then
        execute immediate q'[alter table clientes add constraint chk_clientes_tipo_persona
                              check (tipo_persona in ('J','N')) enable]';
    end if;
end;
/

create or replace function fn_rif_cliente_valido (
    p_rif          in varchar2,
    p_cod_pais     in varchar2,
    p_tipo_persona in varchar2
) return boolean is
    v_rif   varchar2(40);
    v_letra varchar2(1);
    v_resto varchar2(30);
    v_pais  varchar2(2) := upper(trim(p_cod_pais));
    v_tipo  varchar2(1) := upper(trim(p_tipo_persona));
begin
    -- Los separadores no cuentan: se quitan antes de mirar la forma.
    v_rif := replace(replace(upper(trim(p_rif)), '-', ''), ' ', '');

    if v_rif is null or v_tipo is null then
        return false;
    end if;

    if v_pais = 'VE' then
        v_letra := substr(v_rif, 1, 1);
        v_resto := substr(v_rif, 2);
        if v_tipo = 'J' then
            return v_letra = 'J' and regexp_like(v_resto, '^[0-9]{6,12}$');
        elsif v_tipo = 'N' then
            return v_letra in ('V', 'E') and regexp_like(v_resto, '^[0-9]{6,12}$');
        end if;
        return false;
    end if;

    if v_pais = 'MX' then
        if v_tipo = 'J' then
            return regexp_like(v_rif, '^[A-Z&]{3}[0-9]{6}[A-Z0-9]{3}$');
        elsif v_tipo = 'N' then
            return regexp_like(v_rif, '^[A-Z&]{4}[0-9]{6}[A-Z0-9]{3}$');
        end if;
        return false;
    end if;

    return length(v_rif) between 5 and 30;
end fn_rif_cliente_valido;
/

begin
    dbms_utility.compile_schema('WKSP_SYPEXWS', false);
end;
/

select 'FALLA: falta la columna TIPO_PERSONA' as caso from dual
 where not exists (select 1 from all_tab_columns
                    where owner = 'WKSP_SYPEXWS' and table_name = 'CLIENTES'
                      and column_name = 'TIPO_PERSONA');
/

select 'FALLA: ' || object_name || ' quedo invalido' as caso
  from all_objects
 where owner = 'WKSP_SYPEXWS' and status <> 'VALID'
   and object_type in ('FUNCTION','PROCEDURE','PACKAGE','PACKAGE BODY','TRIGGER','VIEW');
/

commit;
/
