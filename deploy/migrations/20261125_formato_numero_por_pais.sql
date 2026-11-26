-- =============================================================================
-- 20261125_formato_numero_por_pais.sql
--
-- Formato de las cifras segun el pais de la empresa activa: Venezuela 1.234,56 y
-- Mexico 1,234.56. Crea el interruptor en SYN_PARAMETROS y prc_nls_sesion, que la
-- app llama en cada peticion (Initialization PL/SQL Code, viaja en f100.sql).
--
-- Idempotente. Para apagarlo sin reimportar:
--   update syn_parametros set valor = 0 where clave = 'FORMATO_NUMERO_POR_PAIS';
--
--   python deploy/conexion/importar_export.py deploy/migrations/20261125_formato_numero_por_pais.sql
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

merge into syn_parametros p
using (select 'FORMATO_NUMERO_POR_PAIS' clave from dual) s
   on (p.clave = s.clave)
 when not matched then insert (clave, valor, descripcion)
      values ('FORMATO_NUMERO_POR_PAIS', 1,
              'Formato de las cifras por pais de la empresa activa: 1 VE con 1.234,56; 0 todo como la app (1,234.56)')
/

commit
/

create or replace procedure prc_nls_sesion is
    v_on   number;
    v_emp  number;
    v_usr  varchar2(255) := v('APP_USER');
    v_pais varchar2(5);
begin
    select nvl(max(valor), 0) into v_on
      from syn_parametros
     where clave = 'FORMATO_NUMERO_POR_PAIS';
    if v_on <> 1 then
        return;
    end if;

    v_emp := nullif(fn_clean_num(v('F_EMPRESA_ACTIVA')), 0);
    if v_emp is null and v_usr is not null and upper(v_usr) <> 'NOBODY' then
        v_emp := fn_empresa_activa(v_usr, null);
    end if;
    if v_emp is null then
        return;
    end if;

    select max(cod_pais) into v_pais from empresas where id_empresa = v_emp;

    if v_pais = 'VE' then
        execute immediate q'[alter session set nls_numeric_characters = ',.']';
    end if;
exception
    when others then
        null;
end prc_nls_sesion;
/

declare
    v_n number;
begin
    select count(*) into v_n from all_objects
     where owner = 'WKSP_SYPEXWS' and object_name = 'PRC_NLS_SESION' and status = 'VALID';
    if v_n <> 1 then
        raise_application_error(-20100, 'PRC_NLS_SESION no quedo VALID');
    end if;
    select count(*) into v_n from syn_parametros where clave = 'FORMATO_NUMERO_POR_PAIS';
    if v_n <> 1 then
        raise_application_error(-20100, 'falta el parametro FORMATO_NUMERO_POR_PAIS');
    end if;
end;
/
