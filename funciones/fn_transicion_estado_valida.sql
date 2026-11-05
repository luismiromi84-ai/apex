-- =============================================================================
-- fn_transicion_estado_valida.sql
--
-- Decide si un cambio de estado esta permitido. La usan los triggers
-- TRG_VALIDA_ESTADO_PRESUPUESTO y TRG_VALIDA_ESTADO_FACTURA.
--
-- No se prohibe todo lo que no este en una lista: eso bloquearia corregir un
-- estado mal puesto. Se prohiben solo los retrocesos que destruyen informacion
-- o falsean el documento:
--
--   PRESUPUESTO
--     CANCELADO  -> nada. Es terminal.
--     FACTURADO  -> solo APROBADO (cuando se anula la factura) o quedarse igual.
--     el resto  -> libre, incluido pasar a CANCELADO.
--
--   FACTURA
--     ANULADA    -> nada. Es terminal.
--     PAGADA     -> solo ANULADA.
--     el resto  -> libre.
--
-- Escotilla: si la sesion tiene CLIENT_INFO = 'SYPEX_FORZAR_ESTADO' se permite
-- cualquier cambio. Sirve para corregir a mano desde SQL:
--   begin dbms_application_info.set_client_info('SYPEX_FORZAR_ESTADO'); end;
--   update ... ; commit;
--   begin dbms_application_info.set_client_info(null); end;
-- =============================================================================

create or replace function fn_transicion_estado_valida (
    p_tabla   in varchar2,
    p_antes   in varchar2,
    p_despues in varchar2
) return boolean is
    v_antes   varchar2(30) := upper(trim(p_antes));
    v_despues varchar2(30) := upper(trim(p_despues));
    v_tabla   varchar2(30) := upper(trim(p_tabla));
begin
    if nvl(sys_context('userenv', 'client_info'), '#') = 'SYPEX_FORZAR_ESTADO' then
        return true;
    end if;

    -- Sin estado anterior, sin estado nuevo o sin cambio: nada que validar.
    if v_antes is null or v_despues is null or v_antes = v_despues then
        return true;
    end if;

    if v_tabla = 'PRESUPUESTO' then
        if v_antes = 'CANCELADO' then
            return false;
        end if;
        if v_antes = 'FACTURADO' and v_despues <> 'APROBADO' then
            return false;
        end if;
    elsif v_tabla = 'FACTURA' then
        if v_antes = 'ANULADA' then
            return false;
        end if;
        if v_antes = 'PAGADA' and v_despues <> 'ANULADA' then
            return false;
        end if;
    end if;

    return true;
end fn_transicion_estado_valida;
/
