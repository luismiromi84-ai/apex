-- =============================================================================
-- 20261106_factura_fiscal_ve.sql
--
-- Datos que la factura fiscal venezolana (forma libre) necesita y que el modelo
-- no tenia. Sale del ejemplo del cliente: `libreria/factura-ejemplo-prefactura.pdf`.
--
-- Que imprime una forma libre y no tenemos:
--   * Emisor: direccion fiscal, telefono, email (EMPRESAS solo tiene nombre y RFC).
--   * Nro de control y numeracion autorizada (rango «desde / hasta»).
--   * Providencia SENIAT y su fecha.
--   * Datos de la imprenta (nombre, RIF, direccion, telefono, email).
--   * El numero de control de cada factura.
--
-- Se resuelve con una tabla 1:1 `EMPRESA_FISCAL` (para no llenar EMPRESAS de
-- columnas que solo usa el impreso) y una columna `FACTURAS.NRO_CONTROL`.
--
-- Los datos de relleno son DEL EJEMPLO, para poder comparar el impreso contra el
-- PDF. Hay que reemplazarlos por los reales.
--
-- Reversa:
--   alter table facturas drop column nro_control;
--   drop table empresa_fiscal;
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

create table empresa_fiscal (
    id_empresa          number        not null enable,
    direccion_fiscal    varchar2(300),
    telefono            varchar2(60),
    email               varchar2(120),
    nro_providencia     varchar2(60),
    prov_fecha          date,
    control_desde       varchar2(30),
    control_hasta       varchar2(30),
    imprenta_nombre     varchar2(150),
    imprenta_rif        varchar2(30),
    imprenta_direccion  varchar2(300),
    imprenta_telefono   varchar2(60),
    imprenta_email      varchar2(120),
    constraint pk_empresa_fiscal primary key (id_empresa) enable,
    constraint fk_empresa_fiscal foreign key (id_empresa)
        references empresas (id_empresa) enable
)
/

comment on table empresa_fiscal is 'Datos fiscales del emisor y de la imprenta, para la factura de forma libre (VE)'
/

comment on column empresa_fiscal.control_desde is 'Primer numero de control autorizado por la providencia'
/

comment on column empresa_fiscal.control_hasta is 'Ultimo numero de control autorizado por la providencia'
/

alter table facturas add (nro_control varchar2(30))
/

comment on column facturas.nro_control is 'Numero de control de la forma libre; distinto de folio_factura y de uuid_fiscal (CFDI de Mexico)'
/

insert into empresa_fiscal (
    id_empresa, direccion_fiscal, telefono, email,
    nro_providencia, prov_fecha, control_desde, control_hasta,
    imprenta_nombre, imprenta_rif, imprenta_direccion, imprenta_telefono, imprenta_email)
values (
    1,
    'Av. Garcilaso de la Vega, Qta. San Roman, Santa Monica, Caracas, Venezuela.',
    '+58 (123) 456.78.90',
    'lazaro@sanroman.com',
    '01/01060', date '2008-11-12', '00-000001', '00-010000',
    'IMPRESOS DE LA VEGA', 'R-87.654.321-0',
    'Av. Garcilaso de la Vega, Qta. San Roman, Santa Monica, Caracas, Venezuela.',
    '(0123) 456.78.90', 'imprenta@sanroman.com')
/

insert into empresa_fiscal (
    id_empresa, direccion_fiscal, telefono, email,
    nro_providencia, prov_fecha, control_desde, control_hasta,
    imprenta_nombre, imprenta_rif, imprenta_direccion, imprenta_telefono, imprenta_email)
values (
    2, 'Av. Reforma 123, Ciudad de Mexico, Mexico.', '+52 55 1234 5678', 'contacto@empresamx.demo',
    null, null, null, null, null, null, null, null, null)
/

-- Numero de control demo: correlativo por empresa en orden de emision.
update facturas f set
       f.nro_control = (select '00-' || to_char(count(*), 'FM000000')
                          from facturas f2
                         where f2.id_empresa = f.id_empresa
                           and (f2.fecha_emision < f.fecha_emision
                                or (f2.fecha_emision = f.fecha_emision
                                    and f2.id_factura <= f.id_factura)))
 where f.nro_control is null
/

begin
    dbms_utility.compile_schema('WKSP_SYPEXWS', false);
end;
/

-- Validacion: no debe quedar ninguna factura sin numero de control
--   select count(*) from facturas where nro_control is null;
-- Y los objetos deben quedar validos:
--   select count(*) from all_objects where owner = 'WKSP_SYPEXWS' and status <> 'VALID'
--    and object_type in ('FUNCTION','PROCEDURE','PACKAGE','PACKAGE BODY','TRIGGER','VIEW');
