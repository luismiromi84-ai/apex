-- ---------------------------------------------------------------------------
-- Nota de credito / debito: ligar la nota con la factura que acredita
-- ---------------------------------------------------------------------------
-- Fecha: 2026-11-09
-- Motivo: una NC/ND tiene que decir QUE factura acredita. Hasta hoy el tipo
--   de documento existia (FAC/NC/ND) pero no habia ninguna relacion con la
--   factura original, asi que el listado de "Presupuesto" de la pagina 9 no
--   servia para hacer una nota.
--   La nota puede ser PARCIAL (se agregan a mano solo las lineas que se
--   acreditan, en la pagina 10) o COMPLETA (boton "Traer lineas" de la pagina
--   9, que copia todas las lineas de la factura original).
-- Reversa:
--   drop index ix_facturas_origen;
--   alter table facturas drop constraint fk_factura_origen;
--   alter table facturas drop column id_factura_origen;
--   drop function fn_nota_traible;
--   (y volver a compilar pkg_facturacion y pkg_factura_detalle sin los cambios)
-- ---------------------------------------------------------------------------

alter table facturas add (id_factura_origen number);
/

alter table facturas add constraint fk_factura_origen
    foreign key (id_factura_origen) references facturas (id_factura);
/

create index ix_facturas_origen on facturas (id_factura_origen);
/

create or replace function fn_nota_traible (p_id_factura in number) return boolean is
    v_existe number;
    v_lineas number;
begin
    if p_id_factura is null then
        return false;
    end if;

    select count(*) into v_existe
      from facturas f
     where f.id_factura = p_id_factura
       and f.tipo_documento in ('NC', 'ND')
       and f.id_factura_origen is not null;

    if v_existe = 0 then
        return false;
    end if;

    select count(*) into v_lineas
      from facturas_det d
     where d.id_factura = p_id_factura;

    return v_lineas = 0;
end fn_nota_traible;
/

-- Los packages cambian tambien:
--   package/pkg_facturacion.sql          -> p_id_factura_origen en
--                                           prc_insertar / prc_actualizar /
--                                           prc_guardar_factura
--   package_bodies/pkg_facturacion.sql   -> lo escribe en FACTURAS
--   package/pkg_factura_detalle.sql      -> copiar_desde_factura
--   package_bodies/pkg_factura_detalle.sql
-- Compilar con deploy/conexion/compilar_objeto.py en este orden:
--   spec pkg_facturacion -> body pkg_facturacion
--   spec pkg_factura_detalle -> body pkg_factura_detalle
-- y terminar con dbms_utility.compile_schema('WKSP_SYPEXWS', false).

begin
    dbms_utility.compile_schema('WKSP_SYPEXWS', false);
end;
/

-- Validacion: 0 objetos invalidos
select object_name, object_type
  from all_objects
 where owner = 'WKSP_SYPEXWS' and status = 'INVALID';
