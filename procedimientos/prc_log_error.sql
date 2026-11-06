-- =============================================================================
-- prc_log_error.sql
--
-- Deja constancia de un error de la aplicacion en SYN_ERROR_LOG. El 2026-11-06
-- no habia forma de enterarse de un fallo en produccion salvo que el usuario lo
-- contara; esto es el registro minimo.
--
-- Lo llama fn_error_handler (el manejador de errores de la app), pero los
-- parametros son planos a proposito: asi se puede probar desde SQL sin montar
-- un apex_error.t_error.
--
-- Va en TRANSACCION AUTONOMA y no propaga excepciones: el log no puede tumbar
-- la pagina que esta mostrando el error. Si la escritura falla, se descarta.
--
-- Los textos se recortan al tamano de la columna para no cambiar un error de
-- negocio por un ORA-12899.
-- =============================================================================

create or replace procedure prc_log_error (
    p_usuario       in varchar2,
    p_codigo        in varchar2,
    p_mensaje       in varchar2,
    p_detalle       in varchar2 default null,
    p_sentencia     in varchar2 default null,
    p_componente    in varchar2 default null,
    p_peticion      in varchar2 default null,
    p_id_aplicacion in number   default null,
    p_id_pagina     in number   default null,
    p_sesion        in varchar2 default null,
    p_es_interno    in varchar2 default null
) is
    pragma autonomous_transaction;
begin
    insert into syn_error_log (
        usuario, sesion, id_aplicacion, id_pagina, peticion, componente,
        codigo, mensaje, detalle, sentencia, es_interno
    ) values (
        substr(p_usuario, 1, 100),
        substr(p_sesion, 1, 50),
        p_id_aplicacion,
        p_id_pagina,
        substr(p_peticion, 1, 400),
        substr(p_componente, 1, 300),
        substr(p_codigo, 1, 30),
        substr(p_mensaje, 1, 4000),
        substr(p_detalle, 1, 4000),
        substr(p_sentencia, 1, 4000),
        substr(p_es_interno, 1, 1)
    );
    commit;
exception
    when others then
        -- Nunca reventar la pagina por no poder registrar el error.
        rollback;
end prc_log_error;
/
