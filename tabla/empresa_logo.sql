-- =============================================================================
-- empresa_logo.sql
--
-- Logo por empresa cliente. EMPRESAS.LOGO_FILENAME solo guardaba el nombre y
-- nadie lo leia; la imagen vive aqui para poder incrustarla en el impreso como
-- data URI (asi el PDF y el papel no dependen de una URL que puede no ser
-- accesible cuando se imprime).
--
-- Una fila por empresa como maximo: la PK es ID_EMPRESA.
-- =============================================================================

create table empresa_logo (
    id_empresa      number        not null enable,
    nombre_archivo  varchar2(255),
    mime_type       varchar2(100) not null enable,
    tamano          number        not null enable,
    imagen          blob          not null enable,
    fecha_carga     date          default sysdate,
    subido_por      varchar2(100),
    constraint pk_empresa_logo primary key (id_empresa)
        using index enable,
    constraint fk_empresa_logo foreign key (id_empresa)
        references empresas (id_empresa) enable,
    constraint ck_empresa_logo_mime check (mime_type in ('image/png', 'image/jpeg')) enable
);
