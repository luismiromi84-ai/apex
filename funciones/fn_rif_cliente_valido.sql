-- =============================================================================
-- fn_rif_cliente_valido.sql
--
-- ¿El RIF/RFC de un cliente tiene la forma que le toca? (2026-11-11)
--
-- Decisiones del dueño (2026-11-11, tras probar el alta con V76554445677):
--   * Venezuela: la letra y **9 digitos** (2026-11-17; antes se aceptaban de 6 a 12
--     y colaba «J-6454545»). Sin la letra. Juridica -> J; natural -> V (venezolano)
--     o E (extranjero). El resto, digitos. Los guiones y espacios dan igual:
--     'V-12345678-9' y 'V123456789' valen lo mismo.
--   * Mexico: RFC de 12 (moral) o 13 (fisica), alfanumerico.
--   * El digito verificador NO se comprueba.
--   * Cualquier otro pais: no vacio y de 5 a 30 caracteres.
--
-- Devuelve boolean para usarla tambien en una validacion PL/SQL de APEX.
-- =============================================================================

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
            return v_letra = 'J' and regexp_like(v_resto, '^[0-9]{9}$');
        elsif v_tipo = 'N' then
            return v_letra in ('V', 'E') and regexp_like(v_resto, '^[0-9]{9}$');
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
