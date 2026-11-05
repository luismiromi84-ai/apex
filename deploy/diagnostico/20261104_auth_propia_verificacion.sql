-- =============================================================================
-- 20261104_auth_propia_verificacion.sql
--
-- Verificacion de la autenticacion propia. Se ejecuta de arriba a abajo:
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261104_auth_propia_verificacion.sql
--
-- Los SELECT devuelven filas solo cuando algo FALLA. El bloque PL/SQL del final
-- no puede imprimir, asi que informa levantando -20100 con el resumen
-- ('RESULTADO: FALLAS=0'). Codigo de salida 1 con FALLAS=0 significa EXITO:
-- el raise es solo el mecanismo para leer la salida.
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

select 'FALLA: ' || o || ' no compila' as caso
  from (select 'PRC_AUTH_REGISTRAR' o from dual union all
        select 'SYPEX_HASH_PASSWORD'  from dual union all
        select 'FN_VERIFICAR_PASSWORD' from dual union all
        select 'FN_PASSWORD_ES_LEGADO' from dual)
 where not exists (select 1 from all_objects
                    where owner = 'WKSP_SYPEXWS' and object_name = o and status = 'VALID');
/

-- -----------------------------------------------------------------------------
-- 2. Comportamiento
--    2.1 prc_auth_registrar: 5 fallos bloquean, un OK resetea, todo deja log.
--    2.2 hash: formato, ida y vuelta, sal aleatoria, legado y nulos.
-- -----------------------------------------------------------------------------
declare
  v_id      number;
  v_fallas  number := 0;
  v_detalle varchar2(2000);
  v_reint   number;
  v_bloq    date;
  v_log     number;
  v_h       varchar2(512);
  v_h2      varchar2(512);
  v_leg     varchar2(64);
  v_t0      number;
  v_id2     number;
  v_ph      varchar2(512);
  v_ok      boolean;
begin
  -- 2.1 registro de intentos ---------------------------------------------------
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

  -- 2.2 hash -------------------------------------------------------------------
  v_t0 := dbms_utility.get_time;
  v_h  := sypex_hash_password('abc');
  if (dbms_utility.get_time - v_t0) / 100 > 2 then
    v_fallas := v_fallas + 1;
    v_detalle := v_detalle || ' [hash lento: ' || round((dbms_utility.get_time - v_t0)/100,2) || ' s]';
  end if;

  if v_h not like 'PBKDF2-SHA256$100000$%' then
    v_fallas := v_fallas + 1; v_detalle := v_detalle || ' [formato del hash]';
  end if;

  if not fn_verificar_password('abc', v_h) then
    v_fallas := v_fallas + 1; v_detalle := v_detalle || ' [ida y vuelta]';
  end if;

  if fn_verificar_password('abd', v_h) then
    v_fallas := v_fallas + 1; v_detalle := v_detalle || ' [acepta clave incorrecta]';
  end if;

  v_h2 := sypex_hash_password('abc');
  if v_h2 = v_h then
    v_fallas := v_fallas + 1; v_detalle := v_detalle || ' [sal no aleatoria]';
  end if;

  execute immediate 'select lower(rawtohex(standard_hash(:1,''SHA256''))) from dual'
    into v_leg using '123' || 'SYPEX_SALT_2026';

  if not fn_verificar_password('123', v_leg) then
    v_fallas := v_fallas + 1; v_detalle := v_detalle || ' [hash legado no verifica]';
  end if;

  if not fn_password_es_legado(v_leg) then
    v_fallas := v_fallas + 1; v_detalle := v_detalle || ' [legado no detectado]';
  end if;

  if fn_password_es_legado(v_h) then
    v_fallas := v_fallas + 1; v_detalle := v_detalle || ' [hash nuevo marcado como legado]';
  end if;

  if sypex_hash_password(null) is not null then
    v_fallas := v_fallas + 1; v_detalle := v_detalle || ' [hash de null no es null]';
  end if;

  if fn_verificar_password(null, null) then
    v_fallas := v_fallas + 1; v_detalle := v_detalle || ' [null verifica]';
  end if;

  -- 2.3 fn_autenticar_usuario -------------------------------------------------
  delete from usuario where upper(username) = 'ZZ_AUTH_TEST';
  commit;

  insert into usuario (username, email, password_hash, estado, fecha_creacion, id_empresa, rol_id)
  values ('ZZ_AUTH_TEST', 'zz2@test.local', sypex_hash_password('Clave#2026'), 'ACTIVO', sysdate, 1, 1001)
  returning usuario_id into v_id2;
  commit;

  -- caso 1: clave correcta
  if not fn_autenticar_usuario('ZZ_AUTH_TEST', 'Clave#2026') then
    v_fallas := v_fallas + 1; v_detalle := v_detalle || ' [caso1: no autentica con la clave correcta]';
  end if;

  -- caso 2: clave mala deja el contador en 1
  v_ok := fn_autenticar_usuario('ZZ_AUTH_TEST', 'mala');
  if v_ok then
    v_fallas := v_fallas + 1; v_detalle := v_detalle || ' [caso2: acepta clave mala]';
  end if;
  select reintentos_fallidos into v_reint from usuario where usuario_id = v_id2;
  if v_reint <> 1 then
    v_fallas := v_fallas + 1; v_detalle := v_detalle || ' [caso2: contador=' || v_reint || ']';
  end if;

  -- caso 3: cinco fallos bloquean
  for i in 1..4 loop
    v_ok := fn_autenticar_usuario('ZZ_AUTH_TEST', 'mala');
  end loop;
  select bloqueado_hasta into v_bloq from usuario where usuario_id = v_id2;
  if v_bloq is null then
    v_fallas := v_fallas + 1; v_detalle := v_detalle || ' [caso3: sin bloqueo tras 5 fallos]';
  end if;

  -- caso 4: clave correcta estando bloqueado no entra y no mueve el contador
  v_ok := fn_autenticar_usuario('ZZ_AUTH_TEST', 'Clave#2026');
  if v_ok then
    v_fallas := v_fallas + 1; v_detalle := v_detalle || ' [caso4: entra estando bloqueado]';
  end if;
  select reintentos_fallidos into v_reint from usuario where usuario_id = v_id2;
  if v_reint <> 5 then
    v_fallas := v_fallas + 1; v_detalle := v_detalle || ' [caso4: contador=' || v_reint || ']';
  end if;

  -- caso 5: sin bloqueo vuelve a entrar
  update usuario set bloqueado_hasta = null, reintentos_fallidos = 0 where usuario_id = v_id2;
  commit;
  if not fn_autenticar_usuario('ZZ_AUTH_TEST', 'Clave#2026') then
    v_fallas := v_fallas + 1; v_detalle := v_detalle || ' [caso5: no entra tras desbloquear]';
  end if;

  -- caso 6: inactivo
  update usuario set estado = 'INACTIVO' where usuario_id = v_id2;
  commit;
  if fn_autenticar_usuario('ZZ_AUTH_TEST', 'Clave#2026') then
    v_fallas := v_fallas + 1; v_detalle := v_detalle || ' [caso6: entra estando inactivo]';
  end if;

  -- caso 7: sin empresa no entra y queda registrado
  update usuario set estado = 'ACTIVO', id_empresa = null where usuario_id = v_id2;
  commit;
  if fn_autenticar_usuario('ZZ_AUTH_TEST', 'Clave#2026') then
    v_fallas := v_fallas + 1; v_detalle := v_detalle || ' [caso7: entra sin empresa]';
  end if;
  select count(*) into v_log from syn_login_log
   where usuario_intentado = 'ZZ_AUTH_TEST' and resultado = 'SIN_EMPRESA';
  if v_log = 0 then
    v_fallas := v_fallas + 1; v_detalle := v_detalle || ' [caso7: no registro SIN_EMPRESA]';
  end if;

  -- caso 8: hash legado entra y queda convertido
  execute immediate 'select lower(rawtohex(standard_hash(:1,''SHA256''))) from dual'
    into v_leg using '123' || 'SYPEX_SALT_2026';
  update usuario set id_empresa = 1, password_hash = v_leg where usuario_id = v_id2;
  commit;
  if not fn_autenticar_usuario('ZZ_AUTH_TEST', '123') then
    v_fallas := v_fallas + 1; v_detalle := v_detalle || ' [caso8: no entra con hash legado]';
  end if;
  select password_hash into v_ph from usuario where usuario_id = v_id2;
  if v_ph not like 'PBKDF2-SHA256$%' then
    v_fallas := v_fallas + 1; v_detalle := v_detalle || ' [caso8: hash legado sin convertir]';
  end if;

  -- caso 9: clave nula
  v_ok := fn_autenticar_usuario('ZZ_AUTH_TEST', null);
  if v_ok then
    v_fallas := v_fallas + 1; v_detalle := v_detalle || ' [caso9: autentica con clave nula]';
  end if;

  -- caso 10: mayusculas y espacios
  if not fn_autenticar_usuario('zz_auth_test', '123') then
    v_fallas := v_fallas + 1; v_detalle := v_detalle || ' [caso10: no entra en minusculas]';
  end if;
  if not fn_autenticar_usuario('  ZZ_AUTH_TEST  ', '123') then
    v_fallas := v_fallas + 1; v_detalle := v_detalle || ' [caso10: no entra con espacios]';
  end if;

  delete from syn_login_log where usuario_intentado = 'ZZ_AUTH_TEST';
  delete from usuario where usuario_id = v_id2;
  commit;

  raise_application_error(-20100, 'RESULTADO: FALLAS=' || v_fallas || v_detalle);
end;
/
