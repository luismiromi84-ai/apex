-- =============================================================================
-- 20261110_usuario_empresa_principal.sql
--
-- Crea trg_usuario_empresa_principal: si USUARIO.ID_EMPRESA no es nula, esa
-- empresa se asocia en USUARIO_EMPRESA.
--
-- Motivo (medido el 2026-11-11 al cerrar multiempresa): la tarea 2 hizo que el
-- login exija al menos un par en USUARIO_EMPRESA, pero la pagina 4 todavia
-- escribe una sola empresa en USUARIO.ID_EMPRESA (la seleccion multiple es la
-- fase 3). Sin esto, todo usuario creado o activado desde la pantalla nacia
-- sin asociacion y no podia entrar. Lo detecto la suite de la tarea 7:
-- 20261104_auth_propia_verificacion.sql -> FALLAS=10.
--
-- Idempotente: create or replace. Al final recompila el esquema, porque tocar
-- USUARIO deja objetos INVALID sin nada en ALL_ERRORS (paso el 2026-11-05).
--
-- REVERSA:
--   drop trigger trg_usuario_empresa_principal;
--   (y volver a poblar USUARIO_EMPRESA a mano si se quitara el modelo)
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;
/

create or replace trigger trg_usuario_empresa_principal
    after insert or update of id_empresa on usuario
    for each row
    when (new.id_empresa is not null)
begin
    insert into usuario_empresa (usuario_id, id_empresa)
    values (:new.usuario_id, :new.id_empresa);
exception
    when dup_val_on_index then
        null;
end;
/

begin
    dbms_utility.compile_schema('WKSP_SYPEXWS', false);
end;
/

-- Validacion: el trigger existe, esta VALID y es ENABLED.
select 'FALLA: falta trg_usuario_empresa_principal' as caso from dual
 where not exists (select 1 from all_triggers
                    where owner = 'WKSP_SYPEXWS'
                      and trigger_name = 'TRG_USUARIO_EMPRESA_PRINCIPAL'
                      and status = 'ENABLED');
/

-- Validacion: los usuarios con empresa principal tienen su par.
select 'FALLA: ' || u.username || ' tiene id_empresa ' || u.id_empresa
       || ' sin par en usuario_empresa' as caso
  from usuario u
 where u.id_empresa is not null
   and not exists (select 1 from usuario_empresa ue
                    where ue.usuario_id = u.usuario_id
                      and ue.id_empresa  = u.id_empresa);
/

-- Validacion: sin objetos invalidos.
select 'FALLA: ' || object_name || ' quedo invalido' as caso
  from all_objects
 where owner = 'WKSP_SYPEXWS' and status <> 'VALID'
   and object_type in ('FUNCTION','PROCEDURE','PACKAGE','PACKAGE BODY','TRIGGER','VIEW');
/

commit;
/
