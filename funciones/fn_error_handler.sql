-- =============================================================================
-- fn_error_handler.sql
--
-- Manejador de errores de la aplicacion (aplicacion 100 -> atributo
-- «Error Handling Function»). Hace dos cosas:
--   1. registra el error en SYN_ERROR_LOG (via prc_log_error);
--   2. devuelve el mensaje de siempre, para que el usuario vea lo mismo que
--      antes de existir este manejador.
--
-- Firma obligatoria de APEX: recibe un apex_error.t_error y devuelve un
-- apex_error.t_error_result.
--
-- OJO CON LOS CAMPOS: en APEX 26.1 el registro apex_error.t_error NO tiene
-- `component_name`, `type`, `error_code`, `internal_error_code`, `region_id`,
-- `is_constraint_violation` ni `error_type`. Medido el 2026-11-06 compilando
-- una funcion sonda que los tocaba todos; los que si existen y se usan aqui
-- son: message, additional_info, ora_sqlcode, ora_sqlerrm, error_statement,
-- page_item_name, is_internal_error y display_location.
--
-- Se copia `display_location` al resultado para no cambiar donde se ve cada
-- error: las validaciones de campo siguen saliendo junto al campo y no en la
-- pagina de error.
-- =============================================================================

create or replace function fn_error_handler (
    p_error in apex_error.t_error
) return apex_error.t_error_result
is
    l_result  apex_error.t_error_result;
    l_mensaje varchar2(4000);
    l_codigo  varchar2(30);
begin
    l_mensaje := apex_error.get_first_ora_error_text(p_error => p_error);
    if l_mensaje is null then
        l_mensaje := p_error.message;
    end if;

    l_result := apex_error.t_error_result();
    l_result.message          := l_mensaje;
    l_result.additional_info  := p_error.additional_info;
    l_result.display_location := p_error.display_location;

    if p_error.ora_sqlcode is not null then
        l_codigo := 'ORA-' || lpad(to_char(abs(p_error.ora_sqlcode)), 5, '0');
    end if;

    begin
        prc_log_error(
            p_usuario       => apex_application.g_user,
            p_codigo        => l_codigo,
            p_mensaje       => nvl(l_mensaje, p_error.message),
            p_detalle       => p_error.ora_sqlerrm,
            p_sentencia     => p_error.error_statement,
            p_componente    => p_error.page_item_name,
            p_peticion      => apex_application.g_request,
            p_id_aplicacion => apex_application.g_flow_id,
            p_id_pagina     => apex_application.g_flow_step_id,
            p_sesion        => apex_application.g_instance,
            p_es_interno    => case when p_error.is_internal_error then 'S' else 'N' end
        );
    exception
        when others then
            null;   -- el log nunca puede tapar el error que se esta mostrando
    end;

    return l_result;
end fn_error_handler;
/
