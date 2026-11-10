-- =============================================================================
-- tabla/usuario_empresa.sql
--
-- Tabla de asociacion usuario <-> empresa (modelo n:m).
--
-- POR QUE EXISTE: hasta el 2026-11-10 un usuario pertenecía a UNA sola empresa,
-- porque el vinculo estaba en la columna USUARIO.ID_EMPRESA. El dueño lo
-- clarified: un cliente puede tener varias empresas (y facturar a la que
-- corresponda) y puede tener varios empleados, cada uno trabajando con unas
-- empresas distintas. Con una sola columna habia que crear un login por
-- empresa, que no representa al cliente real.
--
-- QUE ES Y QUE NO ES:
--   - Una fila por par (usuario, empresa). La PK compuesta PK_USUARIO_EMPRESA
--     prohibe el duplicado.
--   - ESTA tabla es la que da permisos. USUARIO.ID_EMPRESA se conserva como
--     «empresa principal» (la usan la columna «Empresa» de la pagina 3,
--     prc_post_login, la pagina 4 y algunos defectos) y se recalcula como el
--     menor id_empresa de la seleccion, pero NO autoriza: un usuario sin par
--     aqui no puede entrar ni trabajar con esa empresa, aunque su
--     ID_EMPRESA la apunte.
--   - La vista V_EMPRESAS_USUARIO es la forma de leer las empresas de un
--     usuario; las pantallas filtran por ahi.
--
-- Nacio en deploy/migrations/20261110_multiempresa_usuario_empresa.sql.
-- =============================================================================

create table usuario_empresa (
    usuario_id     number       not null enable,
    id_empresa     number       not null enable,
    fecha_creacion timestamp    default systimestamp not null enable,
    constraint pk_usuario_empresa primary key (usuario_id, id_empresa)
        using index enable,
    constraint fk_ue_usuario foreign key (usuario_id)
        references usuario (usuario_id) enable,
    constraint fk_ue_empresa foreign key (id_empresa)
        references empresas (id_empresa) enable
);

create index ix_ue_empresa on usuario_empresa (id_empresa);
