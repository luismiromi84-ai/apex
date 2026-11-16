-- =============================================================================
-- vistas/v_empresas_usuario.sql
--
-- Vista UNICA de las empresas asociadas a un usuario. Reemplaza al
-- 'join usuario + select id_empresa from usuario u where ...' que estaba
-- repetido en unas 30 pantallas y en la LOV EMPRESA, para que el cambio a
-- multiempresa sea un solo sitio y no una copia del filtro por todas partes.
--
-- El patron de filtro de toda la app queda en una linea:
--   id_empresa in (select id_empresa from v_empresas_usuario
--                   where upper(username) = upper(:APP_USER))
--
-- COLUMNAS, en este orden (lo consumen la LOV EMPRESA, la pagina 19 y los
-- filtros): USERNAME, USUARIO_ID, ID_EMPRESA, NOMBRE_EMPRESA, COD_PAIS,
-- TIPO_IDENT_FISCAL, RFC, ESTADO, MONEDA_LOCAL.
--
-- FILTROS:
--   - El ESTADO que se filtra es el del USUARIO ('ACTIVO', 'A' o '1'): un
--     usuario inactivo no aporta empresas a ninguna parte.
--   - El estado de la EMPRESA NO se filtra aqui, y es a proposito: si la vista
--     filtrara por empresas.estado = 'ACTIVO', una empresa puesta INACTIVA
--     desapareceria tambien de la pagina 19, que es el unico sitio donde se
--     puede volver a ACTIVA, y quedaria irrecuperable desde la interfaz.
--     Las pantallas que OFRECEN empresa (LOV EMPRESA y los combos de documento)
--     exigen estado = 'ACTIVO' por su cuenta.
--
-- MONEDA_LOCAL viene de PAISES (izquierda) para no perder la fila cuando la
-- empresa no tiene pais valido: es la moneda que ofrecen las LOV de moneda.
--
-- Nacio en deploy/migrations/20261110_multiempresa_usuario_empresa.sql.
-- =============================================================================

create or replace view v_empresas_usuario as
select u.username,
       u.usuario_id,
       e.id_empresa,
       e.nombre_empresa,
       e.cod_pais,
       e.tipo_ident_fiscal,
       e.rfc,
       e.estado,
       p.moneda_local
  from usuario u
  join usuario_empresa ue on ue.usuario_id = u.usuario_id
  join empresas e        on e.id_empresa   = ue.id_empresa
  left join paises p     on p.cod_pais     = e.cod_pais
 where upper(u.estado) in ('ACTIVO', 'A', '1');
