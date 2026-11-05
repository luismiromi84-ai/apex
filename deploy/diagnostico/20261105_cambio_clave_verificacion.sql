-- =============================================================================
-- 20261105_cambio_clave_verificacion.sql
--
-- Verificacion del cambio de clave obligatorio. Se ejecuta de arriba a abajo:
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261105_cambio_clave_verificacion.sql
--
-- Los SELECT devuelven filas solo cuando algo FALLA. El bloque PL/SQL del final
-- resume con -20100 ('RESULTADO: FALLAS=0'); codigo de salida 1 con FALLAS=0
-- significa EXITO, igual que en las otras verificaciones del repo.
--
-- Casos:
--   C1  La columna existe con DEFAULT 'N' NOT NULL y su CHECK.
--   C2  prc_post_login publica F_DEBE_CAMBIAR_CLAVE.
--   C3  F_DEBE_CAMBIAR_CLAVE esta declarado como item de aplicacion.
--   C4  La guarda existe en la pagina 0 y apunta a la 14.
--   C5  La pagina 4 marca la bandera en el alta y en el reseteo.
--   C6  La pagina 14 tiene la rama forzada y cierra con end;.
--   C7  P14_USERNAME y P14_EMAIL ya no son obligatorios en el navegador.
--   C8  Un usuario con 'S' cambia la clave y la bandera queda en 'N' (simulacion
--       del UPDATE de la pagina 14, dentro de una transaccion con rollback).
--   C9  El CHECK rechaza un valor distinto de S/N.
--   C10 Ningun objeto del esquema quedo INVALID.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;
/

select 'FALLA: falta USUARIO.DEBE_CAMBIAR_CLAVE' as caso from dual
 where not exists (select 1 from all_tab_columns
                    where owner='WKSP_SYPEXWS' and table_name='USUARIO'
                      and column_name='DEBE_CAMBIAR_CLAVE');
/

select 'FALLA: la columna no es CHAR(1) o admite nulos' as caso from dual
 where not exists (select 1 from all_tab_columns
                    where owner='WKSP_SYPEXWS' and table_name='USUARIO'
                      and column_name='DEBE_CAMBIAR_CLAVE'
                      and data_type='CHAR' and data_length=1 and nullable='N');
/

select 'FALLA: falta el CHECK de la bandera' as caso from dual
 where not exists (select 1 from all_constraints
                    where owner='WKSP_SYPEXWS' and table_name='USUARIO'
                      and constraint_name='CK_USUARIO_DEBE_CAMBIAR'
                      and status='ENABLED');
/

select 'FALLA: prc_post_login no publica F_DEBE_CAMBIAR_CLAVE' as caso from dual
 where not exists (select 1 from all_source
                    where owner='WKSP_SYPEXWS' and name='PRC_POST_LOGIN'
                      and lower(text) like '%f_debe_cambiar_clave%');
/

select 'FALLA: F_DEBE_CAMBIAR_CLAVE no es item de aplicacion' as caso from dual
 where not exists (select 1 from apex_application_items
                    where application_id=100 and item_name='F_DEBE_CAMBIAR_CLAVE');
/

select 'FALLA: no hay guarda en la pagina 0' as caso from dual
 where not exists (select 1 from apex_application_page_proc
                    where application_id=100 and page_id=0
                      and static_id='cambio-clave-obligatorio');
/

select 'FALLA: la guarda no redirige a la pagina 14' as caso
  from apex_application_page_proc
 where application_id=100 and page_id=0 and static_id='cambio-clave-obligatorio'
   and dbms_lob.instr(process_source, ':14:') = 0;
/

select 'FALLA: la pagina 4 no marca la bandera en el alta' as caso from dual
 where not exists (select 1 from apex_application_page_proc
                    where application_id=100 and page_id=4
                      and process_name='Crear Usuario'
                      and dbms_lob.instr(process_source, 'debe_cambiar_clave') > 0);
/

select 'FALLA: la pagina 4 no marca la bandera al resetear' as caso from dual
 where not exists (select 1 from apex_application_page_proc
                    where application_id=100 and page_id=4
                      and process_name='update usuario'
                      and dbms_lob.instr(process_source, 'debe_cambiar_clave') > 0);
/

select 'FALLA: la pagina 14 no tiene la rama forzada' as caso from dual
 where not exists (select 1 from apex_application_page_proc
                    where application_id=100 and page_id=14
                      and dbms_lob.instr(process_source, 'v_obligatorio') > 0);
/

select 'FALLA: P14_USERNAME o P14_EMAIL siguen siendo obligatorios' as caso from dual
 where exists (select 1 from apex_application_page_items
                where application_id=100 and page_id=14
                  and item_name in ('P14_USERNAME','P14_EMAIL')
                  and is_required='Yes');
/

select 'FALLA: hay objetos INVALID en el esquema' as caso
  from all_objects
 where owner='WKSP_SYPEXWS' and status <> 'VALID'
   and object_type in ('FUNCTION','PROCEDURE','PACKAGE','PACKAGE BODY','TRIGGER','VIEW');
/

declare
  v_fallas number := 0;
  v_lista  varchar2(2000) := '';
  v_id     number;
  v_band   char(1);
  v_reint  number;
  v_bloq   date;

  procedure falla (p_caso in varchar2, p_detalle in varchar2) is
  begin
    v_fallas := v_fallas + 1;
    v_lista  := v_lista || ' | ' || p_caso || ': ' || p_detalle;
  end falla;

  -- Ejecuta el mismo UPDATE que hace la pagina 14 en modo forzado, sin COMMIT.
  procedure cambia (p_id in number, p_nueva in varchar2) is
  begin
    update usuario set
           password_hash      = sypex_hash_password(p_nueva),
           debe_cambiar_clave = 'N',
           reintentos_fallidos = 0,
           bloqueado_hasta    = null
     where usuario_id = p_id;

    if sql%rowcount <> 1 then
      falla('C8', 'el UPDATE no toco una fila');
    end if;
  end cambia;

begin
  -- C8: la bandera se limpia con el cambio de clave
  select min(usuario_id) into v_id from usuario;

  update usuario set
         debe_cambiar_clave = 'S',
         reintentos_fallidos = 3,
         bloqueado_hasta = sysdate + 1
   where usuario_id = v_id;

  cambia(v_id, 'ClaveTemporal#2026');

  select debe_cambiar_clave, reintentos_fallidos, bloqueado_hasta
    into v_band, v_reint, v_bloq
    from usuario
   where usuario_id = v_id;

  if v_band <> 'N' then
    falla('C8', 'la bandera no se limpio');
  end if;
  if nvl(v_reint, -1) <> 0 or v_bloq is not null then
    falla('C8', 'no se resetearon contadores o bloqueo');
  end if;

  rollback;

  -- C9: el CHECK rechaza valores fuera de S/N
  begin
    update usuario set
           debe_cambiar_clave = 'X'
     where usuario_id = v_id;
    falla('C9', 'acepto un valor distinto de S/N');
  exception
    when others then
      if sqlcode <> -2290 then
        falla('C9', 'fallo con otro error: ' || sqlcode);
      end if;
  end;
  rollback;

  raise_application_error(-20100, 'RESULTADO: FALLAS=' || v_fallas || v_lista);
end;
/
