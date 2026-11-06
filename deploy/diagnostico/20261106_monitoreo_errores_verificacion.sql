-- =============================================================================
-- 20261106_monitoreo_errores_verificacion.sql
--
-- Verifica el monitoreo de errores: que el manejador este conectado a la app,
-- que registre de verdad, que recorte los textos largos y que la purga respete
-- lo reciente.
--
-- Se ejecuta de arriba a abajo:
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261106_monitoreo_errores_verificacion.sql
--
-- Todo vive en un solo bloque PL/SQL (el runner de python no imprime los
-- SELECT) y termina con -20100 ('RESULTADO: FALLAS=0'). Codigo de salida 1 con
-- FALLAS=0 significa EXITO, igual que en las otras verificaciones.
--
-- Limpieza: las filas de prueba se borran y se confirman dentro del bloque,
-- porque prc_log_error escribe en transaccion autonoma y el rollback de la
-- conexion no las alcanza.
--
-- Casos:
--   C1  SYN_ERROR_LOG existe con sus columnas.
--   C2  PRC_LOG_ERROR y FN_ERROR_HANDLER existen y estan VALID.
--   C3  PUBLIC tiene EXECUTE sobre los dos.
--   C4  La aplicacion 100 usa fn_error_handler (atributo de APEX).
--   C5  La region «Ultimos errores» de la pagina 3 resuelve (no es una region
--       huerfana como la que tumbo la pagina 15).
--   C6  prc_log_error registra la fila y recorta un mensaje de 5000 caracteres.
--   C7  prc_purgar_logs borra lo que tiene 100 dias y respeta lo de hoy.
--   C8  Las filas reales que ya habia siguen ahi.
--   C9  No queda ningun objeto INVALID.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;
/

declare
    v_fallas  number := 0;
    v_lista   varchar2(3000) := '';
    v_cnt     number;
    v_id      number;
    v_largo   number;
    v_usuario constant varchar2(100) := 'zz_verifica_monitoreo';
    v_antes   number;

    procedure falla (p_caso in varchar2, p_detalle in varchar2) is
    begin
        v_fallas := v_fallas + 1;
        v_lista  := v_lista || ' | ' || p_caso || ': ' || p_detalle;
    end falla;

    procedure cierra is
    begin
        raise_application_error(-20100, substr('RESULTADO: FALLAS=' || v_fallas
            || v_lista, 1, 1900));
    end cierra;
begin
    -- C1
    select count(*) into v_cnt
      from all_tab_columns
     where owner = 'WKSP_SYPEXWS' and table_name = 'SYN_ERROR_LOG'
       and column_name in ('ID_ERROR', 'FECHA', 'USUARIO', 'SESION',
                           'ID_APLICACION', 'ID_PAGINA', 'PETICION',
                           'COMPONENTE', 'CODIGO', 'MENSAJE', 'DETALLE',
                           'SENTENCIA', 'ES_INTERNO');
    if v_cnt <> 13 then
        falla('C1', 'SYN_ERROR_LOG tiene ' || v_cnt || ' de 13 columnas esperadas');
    end if;

    -- C2
    select count(*) into v_cnt
      from all_objects
     where owner = 'WKSP_SYPEXWS' and status = 'VALID'
       and object_type in ('PROCEDURE', 'FUNCTION')
       and object_name in ('PRC_LOG_ERROR', 'FN_ERROR_HANDLER');
    if v_cnt <> 2 then
        falla('C2', 'falta PRC_LOG_ERROR o FN_ERROR_HANDLER, o no estan VALID');
    end if;

    -- C3
    select count(*) into v_cnt
      from all_tab_privs
     where table_schema = 'WKSP_SYPEXWS'
       and table_name in ('PRC_LOG_ERROR', 'FN_ERROR_HANDLER')
       and grantee = 'PUBLIC' and privilege = 'EXECUTE';
    if v_cnt <> 2 then
        falla('C3', 'PUBLIC no tiene EXECUTE en los dos objetos (' || v_cnt || '/2)');
    end if;

    -- C4
    declare
        v_funcion varchar2(200);
    begin
        select error_handling_function into v_funcion
          from apex_260100.apex_applications
         where application_id = 100;
        if upper(nvl(v_funcion, '#')) <> 'FN_ERROR_HANDLER' then
            falla('C4', 'la app no usa fn_error_handler (usa "' || nvl(v_funcion, 'nada') || '")');
        end if;
    exception when others then
        falla('C4', 'no se pudo leer el atributo de la app: ' || sqlerrm);
    end;

    -- C5
    select count(*) into v_cnt
      from apex_260100.apex_application_page_regions
     where application_id = 100 and page_id = 3
       and region_name = 'Ultimos errores'
       and source_type is not null
       and source_type_plugin_name = 'NATIVE_SQL_REPORT';
    if v_cnt <> 1 then
        falla('C5', 'la region «Ultimos errores» no resuelve en la pagina 3');
    end if;

    -- C6: registra y recorta.
    prc_log_error(
        p_usuario   => v_usuario,
        p_codigo    => 'ORA-20999',
        p_mensaje   => rpad('x', 5000, 'y'),
        p_detalle   => 'detalle de prueba',
        p_componente=> 'P0_PRUEBA',
        p_peticion  => 'VERIFICACION',
        p_id_pagina => 3,
        p_sesion    => '0',
        p_es_interno=> 'N');

    select max(id_error), max(length(mensaje)) into v_id, v_largo
      from syn_error_log
     where usuario = v_usuario;
    if v_id is null then
        falla('C6', 'prc_log_error no registro la fila');
    elsif v_largo <> 4000 then
        falla('C6', 'el mensaje se guardo con ' || v_largo || ' caracteres, se esperaban 4000');
    end if;

    -- C7 y C8: la purga borra lo viejo y respeta lo nuevo.
    select count(*) into v_antes from syn_error_log;

    insert into syn_error_log (fecha, usuario, mensaje)
    values (sysdate - 100, v_usuario, 'viejo de prueba');
    insert into syn_error_log (fecha, usuario, mensaje)
    values (sysdate, v_usuario, 'nuevo de prueba');

    declare
        v_login number;
        v_reset number;
    begin
        prc_purgar_logs(p_dias => 90, p_borrados_login => v_login,
                        p_borrados_reset => v_reset);
    end;

    select count(*) into v_cnt
      from syn_error_log
     where usuario = v_usuario and mensaje = 'viejo de prueba';
    if v_cnt <> 0 then
        falla('C7', 'la purga no borro la fila de 100 dias');
    end if;
    select count(*) into v_cnt
      from syn_error_log
     where usuario = v_usuario and mensaje = 'nuevo de prueba';
    if v_cnt <> 1 then
        falla('C7', 'la purga se llevo una fila reciente');
    end if;

    -- C8: las filas reales (de usuarios de verdad) siguen ahi.
    select count(*) into v_cnt from syn_error_log where usuario <> v_usuario;
    if v_cnt < 1 then
        falla('C8', 'la purga borro las filas reales del log');
    end if;

    -- Limpieza de las filas de prueba (la de prc_log_error es autonoma).
    delete from syn_error_log where usuario = v_usuario;
    commit;

    -- C9
    select count(*) into v_cnt
      from all_objects
     where owner = 'WKSP_SYPEXWS' and status <> 'VALID'
       and object_type in ('FUNCTION', 'PROCEDURE', 'PACKAGE', 'PACKAGE BODY',
                           'TRIGGER', 'VIEW');
    if v_cnt > 0 then
        falla('C9', v_cnt || ' objetos INVALID en el esquema');
    end if;

    cierra;
end;
/
