-- =============================================================================
-- fn_usuario_administrable.sql
--
-- ¿Puede el administrador p_admin tocar la cuenta p_usuario_id?
--
-- Desde multiempresa (2026-11-11, fase 3) la respuesta no es "es de mi empresa"
-- sino "comparte al menos una empresa conmigo". Se admite tambien al usuario
-- SIN ninguna empresa: es el PENDIENTE que llega del registro (pagina 2) y el
-- administrador tiene que poder activarlo.
--
-- Lo usan los cuatro procesos de escritura de la pagina 4 y el procedimiento
-- prc_empresas_usuario (defensa en profundidad).
-- =============================================================================

create or replace function fn_usuario_administrable (
    p_admin      in varchar2,
    p_usuario_id in number
) return boolean is
    v_existe   number;
    v_pares    number;
    v_comparte number;
begin
    if p_admin is null or p_usuario_id is null then
        return false;
    end if;

    select count(*) into v_existe from usuario where usuario_id = p_usuario_id;
    if v_existe = 0 then
        return false;
    end if;

    select count(*) into v_pares from usuario_empresa where usuario_id = p_usuario_id;
    if v_pares = 0 then
        -- Alta pendiente: el administrador puede activarla y asignarle empresas.
        return true;
    end if;

    select count(*) into v_comparte
      from usuario_empresa objetivo
      join usuario_empresa mia      on mia.id_empresa = objetivo.id_empresa
      join usuario         admin    on admin.usuario_id = mia.usuario_id
     where objetivo.usuario_id = p_usuario_id
       and upper(admin.username) = upper(p_admin)
       and nvl(upper(admin.estado), '#') in ('ACTIVO', 'A', '1');

    return v_comparte > 0;
end fn_usuario_administrable;
/
