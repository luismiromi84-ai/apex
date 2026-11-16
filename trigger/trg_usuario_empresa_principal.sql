-- =============================================================================
-- trg_usuario_empresa_principal.sql
--
-- Mantiene la invariante de la que depende el login desde el 2026-11-10:
-- si USUARIO.ID_EMPRESA no es nula, esa empresa tiene que estar entre las
-- asociaciones de USUARIO_EMPRESA.
--
-- Por que hace falta: desde la tarea 2 de multiempresa, fn_autenticar_usuario y
-- prc_post_login exigen **al menos un par** en USUARIO_EMPRESA. La pagina 4
-- sigue asignando una sola empresa escribiendo USUARIO.ID_EMPRESA (la seleccion
-- multiple es la fase 3 del spec), asi que sin este trigger un usuario creado o
-- activado desde la pantalla nacia sin asociacion y **no podia entrar**. Medido
-- el 2026-11-11: 20261104_auth_propia_verificacion.sql daba FALLAS=10 y
-- 20261110_menu_alfabetico.py no encontraba el menu (el usuario temporal no
-- autenticaba).
--
-- No sustituye a la fase 3: la sincronizacion de la pagina 4 con seleccion
-- multiple sigue pendiente. Esto solo garantiza que la empresa "principal"
-- nunca quede fuera del conjunto de asociaciones (que es lo que el spec exige:
-- ID_EMPRESA se recalcula como el menor de la seleccion).
--
-- Se escribe con INSERT + DUP_VAL_ON_INDEX en vez de SELECT + INSERT para que
-- dos sesiones que guarden el mismo par a la vez no se peleen.
-- =============================================================================

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
