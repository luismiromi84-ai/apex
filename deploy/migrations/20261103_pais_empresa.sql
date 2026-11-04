-- =============================================================================
-- 20261103_pais_empresa.sql
-- Objetivo: dar país explícito a la empresa para distinguir Venezuela y México.
--   1. Catálogo PAISES.
--   2. EMPRESAS.COD_PAIS + TIPO_IDENT_FISCAL.
--   3. CLIENTES.COD_PAIS (para validar RIF vs RFC).
--
-- Reversa al final (comentada).
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;

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
values ('MX', 'México',    'MXN', '$ 999,999,990.00',  'America/Mexico_City');

alter table empresas add (cod_pais char(2) default 'VE');
alter table empresas add (tipo_ident_fiscal varchar2(10) default 'RIF');

update empresas set cod_pais = 'VE', tipo_ident_fiscal = 'RIF' where cod_pais is null;

alter table empresas modify (cod_pais not null);
alter table empresas add constraint fk_empresas_pais foreign key (cod_pais) references paises(cod_pais);
alter table empresas add constraint ck_empresas_ident check (tipo_ident_fiscal in ('RIF','RFC'));

alter table clientes add (cod_pais char(2));

update clientes c
   set cod_pais = (select e.cod_pais from empresas e where e.id_empresa = c.id_empresa);

alter table clientes add constraint fk_clientes_pais foreign key (cod_pais) references paises(cod_pais);

commit;

select 'paises' as control, count(*) as filas from paises
union all
select 'empresas con pais', count(*) from empresas where cod_pais is not null
union all
select 'clientes con pais', count(*) from clientes where cod_pais is not null;

-- -----------------------------------------------------------------------------
-- Reversa
--   alter table clientes drop constraint fk_clientes_pais;
--   alter table clientes drop column cod_pais;
--   alter table empresas drop constraint ck_empresas_ident;
--   alter table empresas drop constraint fk_empresas_pais;
--   alter table empresas drop column tipo_ident_fiscal;
--   alter table empresas drop column cod_pais;
--   drop table paises;
-- -----------------------------------------------------------------------------
