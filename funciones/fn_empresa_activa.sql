-- =============================================================================
-- fn_empresa_activa.sql
--
-- Empresa activa de la sesion (2026-11-17).
--
-- Devuelve la empresa con la que el usuario esta trabajando:
--   * si llega una empresa elegida y es suya, esa;
--   * si llega una que no es suya, NULL (nunca se confia en el navegador);
--   * si no llega ninguna y el usuario tiene UNA sola empresa, esa;
--   * si tiene varias, NULL: las listas salen vacias hasta que elija.
--
-- La usan el proceso de aplicacion que fija F_EMPRESA_ACTIVA, las listas y los
-- formularios de documento. La seguridad no depende de esto: los procesos de
-- escritura siguen comprobando la propiedad con fn_*_propio.
-- =============================================================================

create or replace function fn_empresa_activa (
    p_usuario in varchar2,
    p_elegida in number default null
) return number is
    v_n   number;
    v_emp number;
begin
    if p_usuario is null then
        return null;
    end if;

    if p_elegida is not null and p_elegida <> 0 then
        if fn_usuario_empresa_valida(p_usuario, p_elegida) then
            return p_elegida;
        end if;
        return null;
    end if;

    select count(*), min(id_empresa)
      into v_n, v_emp
      from v_empresas_usuario
     where upper(username) = upper(p_usuario);

    if v_n = 1 then
        return v_emp;
    end if;

    -- Varias empresas y ninguna elegida: no se escoge por su cuenta.
    return null;
end fn_empresa_activa;
/
