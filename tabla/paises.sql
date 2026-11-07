-- =============================================================================
-- tabla/paises.sql
--
-- Catalogo de paises. De el salen la moneda local (LOV de moneda de las paginas
-- 5, 8 y 13), el formato y el tipo de identificacion fiscal (RIF/RFC).
--
-- Nacio en deploy/migrations/20261103_pais_empresa.sql, que lo creaba junto con
-- EMPRESAS.COD_PAIS y CLIENTES.COD_PAIS. Se movio aqui el 2026-11-07 porque
-- install.sql no lo cargaba y una instalacion limpia quedaba sin catalogo: las
-- LOV de empresa/moneda devolvian vacio.
--
-- OJO con los acentos: el nombre de Mexico va con unistr() porque el runner de
-- importacion corrompe los literales acentuados. Medido: 'México' !=
-- unistr('M\00E9xico') despues de pasar por importar_export.py.
-- =============================================================================

create table paises (
    cod_pais        char(2)      constraint pk_paises primary key,
    nombre          varchar2(60) not null,
    moneda_local    varchar2(3)  not null,
    formato_moneda  varchar2(60),
    huso_horario    varchar2(40),
    activo          char(1) default 'S' not null,
    constraint ck_paises_activo check (activo in ('S','N'))
);

insert into paises (cod_pais, nombre, moneda_local, formato_moneda, huso_horario)
values ('VE', 'Venezuela', 'VES', 'Bs. 999.999.990,00', 'America/Caracas');

insert into paises (cod_pais, nombre, moneda_local, formato_moneda, huso_horario)
values ('MX', unistr('M\00E9xico'), 'MXN', '$ 999,999,990.00', 'America/Mexico_City');

commit;
