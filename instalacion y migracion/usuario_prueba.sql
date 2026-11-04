-- =============================================================================
-- usuario_prueba.sql
-- Crea un usuario de prueba para poder entrar a la app antes de cargar los
-- 8 usuarios reales del origen.
--
--   Usuario:     PRUEBA
--   Contraseña:  Prueba#2026
--   Rol:         PRUEBA (id 9001)
--   Empresa:     1 - Empresa Principal
--
-- Por qué ids 9001: la carga real del origen trae ids bajos (roles 1-4,
-- usuarios 1-8). Con ids altos no hay colisión de PK y `validar_carga.sql`
-- los excluye de los conteos (`id >= 9000` cuenta como fila de prueba).
--
-- El hash se calculó con la propia función del esquema:
--   SYPEX_HASH_PASSWORD('Prueba#2026')
--   = LOWER(RAWTOHEX(STANDARD_HASH('Prueba#2026' || 'SYPEX_SALT_2026','SHA256')))
--
-- Ejecutar en SQLcl sobre el DESTINO:
--   sql -name SYPEX_SQL_MCP @usuario_prueba.sql
-- =============================================================================

set define off
set feedback on
set verify off

alter session set current_schema = WKSP_SYPEXWS;

insert into syn_roles (id_rol, codigo_rol, nombre_rol, descripcion)
values (9001, 'PRUEBA', 'Rol de prueba',
        'Rol temporal para validar la app en Sypex_SQL');

insert into usuario (usuario_id, username, email, password_hash, estado,
                     fecha_creacion, id_empresa, rol_id)
values (9001, 'PRUEBA', 'prueba@sypex.local',
        '79bf79f838f4e215a561b2fc82201df0b09789543b7bb8ee1002016fce0ea805',
        'ACTIVO', sysdate, 1, 9001);

commit;

prompt
prompt Usuario de prueba creado: PRUEBA / Prueba#2026 (empresa 1, rol 9001)
prompt

-- -----------------------------------------------------------------------------
-- Limpieza, cuando ya estén cargados y probados los usuarios reales:
--
--   alter session set current_schema = WKSP_SYPEXWS;
--   delete from usuario   where usuario_id = 9001;
--   delete from syn_roles where id_rol      = 9001;
--   commit;
-- -----------------------------------------------------------------------------
