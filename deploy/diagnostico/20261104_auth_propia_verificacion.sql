-- =============================================================================
-- 20261104_auth_propia_verificacion.sql
--
-- Verificacion de la autenticacion propia. Se ejecuta de arriba a abajo:
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261104_auth_propia_verificacion.sql
--
-- Los SELECT devuelven filas solo cuando algo FALLA. El bloque PL/SQL del final
-- no puede imprimir, asi que informa levantando -20100 con el resumen
-- ('RESULTADO tarea N: FALLAS=0'); se lee el mensaje, no el codigo.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;
/

-- -----------------------------------------------------------------------------
-- 1. Esquema: tabla de log, columnas de bloqueo e indice unico
-- -----------------------------------------------------------------------------
select 'FALLA: falta SYN_LOGIN_LOG' as caso from dual
 where not exists (select 1 from all_tables
                    where owner = 'WKSP_SYPEXWS' and table_name = 'SYN_LOGIN_LOG');
/

select 'FALLA: falta columna ' || c as caso
  from (select 'REINTENTOS_FALLIDOS' c from dual union all
        select 'BLOQUEADO_HASTA'          from dual union all
        select 'ULTIMO_INTENTO_LOGIN'     from dual)
 where not exists (select 1 from all_tab_columns
                    where owner = 'WKSP_SYPEXWS' and table_name = 'USUARIO'
                      and column_name = c);
/

select 'FALLA: falta UQ_USUARIO_USERNAME_UPPER' as caso from dual
 where not exists (select 1 from all_indexes
                    where owner = 'WKSP_SYPEXWS'
                      and index_name = 'UQ_USUARIO_USERNAME_UPPER');
/

select 'FALLA: prc_auth_registrar no compila' as caso from dual
 where not exists (select 1 from all_objects
                    where owner = 'WKSP_SYPEXWS' and object_name = 'PRC_AUTH_REGISTRAR'
                      and status = 'VALID');
/

-- -----------------------------------------------------------------------------
-- 2. Comportamiento de prc_auth_registrar
--    5 fallos bloquean, un OK resetea, y cada llamada deja su fila en el log.
-- -----------------------------------------------------------------------------
declare
  v_id      number;
  v_fallas  number := 0;
  v_detalle varchar2(2000);
  v_reint   number;
  v_bloq    date;
  v_log     number;
begin
  delete from syn_login_log where usuario_intentado = 'ZZ_TEST_AUTH';
  delete from usuario where upper(username) = 'ZZ_TEST_AUTH';

  insert into usuario (username, email, password_hash, estado, fecha_creacion, id_empresa, rol_id)
  values ('ZZ_TEST_AUTH', 'zz@test.local', 'x', 'ACTIVO', sysdate, 1, 1001)
  returning usuario_id into v_id;

  -- commit: en produccion el usuario ya existe y la transaccion autonoma no
  -- puede esperar un lock de esta misma sesion
  commit;

  for i in 1..5 loop
    prc_auth_registrar(p_usuario_id        => v_id,
                       p_resultado         => 'CLAVE_MALA',
                       p_usuario_intentado => 'ZZ_TEST_AUTH');
  end loop;

  select reintentos_fallidos, bloqueado_hasta into v_reint, v_bloq
    from usuario where usuario_id = v_id;
  if v_reint <> 5 then v_fallas := v_fallas + 1; v_detalle := v_detalle || ' [contador=' || v_reint || ' tras 5 fallos]'; end if;
  if v_bloq is null then v_fallas := v_fallas + 1; v_detalle := v_detalle || ' [sin bloqueo tras 5 fallos]'; end if;

  prc_auth_registrar(p_usuario_id        => v_id,
                     p_resultado         => 'OK',
                     p_usuario_intentado => 'ZZ_TEST_AUTH');

  select reintentos_fallidos, bloqueado_hasta into v_reint, v_bloq
    from usuario where usuario_id = v_id;
  if v_reint <> 0 then v_fallas := v_fallas + 1; v_detalle := v_detalle || ' [contador=' || v_reint || ' tras exito]'; end if;
  if v_bloq is not null then v_fallas := v_fallas + 1; v_detalle := v_detalle || ' [sigue bloqueado tras exito]'; end if;

  select count(*) into v_log from syn_login_log where usuario_intentado = 'ZZ_TEST_AUTH';
  if v_log <> 6 then v_fallas := v_fallas + 1; v_detalle := v_detalle || ' [log=' || v_log || ' filas, esperado 6]'; end if;

  delete from syn_login_log where usuario_intentado = 'ZZ_TEST_AUTH';
  delete from usuario where usuario_id = v_id;
  commit;

  raise_application_error(-20100, 'RESULTADO tarea 1: FALLAS=' || v_fallas || v_detalle);
exception
  when others then
    begin
      delete from syn_login_log where usuario_intentado = 'ZZ_TEST_AUTH';
      delete from usuario where upper(username) = 'ZZ_TEST_AUTH';
      commit;
    exception when others then null;
    end;
    raise;
end;
/
