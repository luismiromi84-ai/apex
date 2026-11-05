-- =============================================================================
-- 20261105_purgar_logs_verificacion.sql
--
-- Verificacion de la purga de logs. Se ejecuta de arriba a abajo:
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261105_purgar_logs_verificacion.sql
--
-- Todo el trabajo va dentro de una transaccion con rollback: la purga no hace
-- COMMIT a proposito, asi que la prueba no borra nada de verdad.
--
-- Casos:
--   C1  PRC_PURGAR_LOGS existe y esta VALID.
--   C2  El job existe y esta habilitado.
--   C3  Borra lo mas viejo que la retencion y respeta lo reciente.
--   C4  Rechaza una retencion de 0 o nula.
--   C5  Funciona con la retencion por defecto (sin argumentos).
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;
/

select 'FALLA: falta PRC_PURGAR_LOGS' as caso from dual
 where not exists (select 1 from all_objects
                    where owner='WKSP_SYPEXWS' and object_name='PRC_PURGAR_LOGS'
                      and object_type='PROCEDURE' and status='VALID');
/

select 'FALLA: el job JOB_PURGA_LOGS no existe o esta parado' as caso from dual
 where not exists (select 1 from all_scheduler_jobs
                    where owner='WKSP_SYPEXWS' and job_name='JOB_PURGA_LOGS'
                      and enabled='TRUE');
/

declare
  v_fallas  number := 0;
  v_lista   varchar2(2000) := '';
  v_l       number;
  v_r       number;
  v_n       number;

  procedure falla (p_caso in varchar2, p_detalle in varchar2) is
  begin
    v_fallas := v_fallas + 1;
    v_lista  := v_lista || ' | ' || p_caso || ': ' || p_detalle;
  end falla;

begin
  -- C3: siembra de filas viejas y recientes
  insert into syn_login_log (usuario_intentado, ip, fecha, resultado)
  values ('prueba-purga-vieja', '127.0.0.1', sysdate - 100, 'OK');

  insert into syn_login_log (usuario_intentado, ip, fecha, resultado)
  values ('prueba-purga-reciente', '127.0.0.1', sysdate - 1, 'OK');

  insert into syn_reset_password_log (usuario_intentado, correo_intentado, ip, fecha, resultado)
  values ('prueba-purga-vieja', 'x@x', '127.0.0.1', sysdate - 100, 'OK');

  prc_purgar_logs(p_dias => 90, p_borrados_login => v_l, p_borrados_reset => v_r);

  if v_l < 1 then
    falla('C3', 'no conto el borrado de login');
  end if;
  if v_r <> 1 then
    falla('C3', 'no borro el reset viejo (v_r=' || v_r || ')');
  end if;

  select count(*) into v_n from syn_login_log where usuario_intentado = 'prueba-purga-vieja';
  if v_n <> 0 then
    falla('C3', 'la fila vieja de login sigue');
  end if;

  select count(*) into v_n from syn_login_log where usuario_intentado = 'prueba-purga-reciente';
  if v_n <> 1 then
    falla('C3', 'se llevo por delante la fila reciente');
  end if;

  -- C4: retencion invalida
  begin
    prc_purgar_logs(p_dias => 0, p_borrados_login => v_l, p_borrados_reset => v_r);
    falla('C4', 'acepto una retencion de 0 dias');
  exception
    when others then
      if sqlcode <> -20030 then
        falla('C4', 'fallo con otro error: ' || sqlcode);
      end if;
  end;

  -- C5: por defecto (90 dias)
  begin
    prc_purgar_logs(p_borrados_login => v_l, p_borrados_reset => v_r);
  exception
    when others then
      falla('C5', 'no funciona sin argumentos: ' || sqlerrm);
  end;

  rollback;

  raise_application_error(-20100, 'RESULTADO: FALLAS=' || v_fallas || v_lista);
end;
/
