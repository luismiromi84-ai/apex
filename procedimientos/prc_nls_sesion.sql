-- =============================================================================
-- prc_nls_sesion.sql
--
-- Formato de los numeros segun el pais de la empresa activa (2026-11-25).
--
-- La app corre en es-mx, asi que por defecto las cifras salen 1,234.56. Para una
-- empresa venezolana el formato es 1.234,56. Este procedimiento lo fija en cada
-- peticion de APEX (lo llama el «Initialization PL/SQL Code» de la app, p_vpd),
-- tambien en las peticiones AJAX (refrescos de informes, acciones dinamicas), asi
-- que pantalla, tablas, tarjetas y la validacion de los campos numericos usan el
-- mismo separador.
--
--   VE  -> nls_numeric_characters = ',.'   (1.234,56)
--   MX  -> se deja el de la app            (1,234.56)
--
-- Interruptor: SYN_PARAMETROS.FORMATO_NUMERO_POR_PAIS = 1 lo activa, 0 lo apaga
-- (vuelve al formato de la app sin reimportar nada).
--
-- Nunca lanza: si algo falla, la peticion sigue con el formato de la app.
-- =============================================================================

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
