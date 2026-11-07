-- =============================================================================
-- 20261106_recalcular_tasa_cambio.sql
--
-- Recalcula `tipo_cambio` de presupuestos y facturas con la tasa que corresponde
-- a su fecha de emision, y rehace los montos en bolivares del detalle de factura.
--
-- Por que: la accion dinamica de la pagina 7 usaba fn_tasa_cambio(), escrita
-- como factor a USD, que devuelve 1 para USD. Los documentos en USD quedaron
-- guardados con tipo_cambio = 1 (medido: 29 presupuestos y 23 facturas), asi
-- que el impreso mostraba los mismos importes en USD y en Bs.
--
-- Regla (la misma de la accion dinamica de la pagina 9):
--   tipo_cambio = bolivares por unidad de la moneda del documento.
--   VES = 1; el resto = ultima MONEDA->VES de TIPO_CAMBIO con
--   fecha_vigencia <= fecha_emision.
--
-- No toca importes: solo la tasa y las columnas derivadas en Bs.
-- Idempotente: si ya esta bien, los UPDATE no cambian filas.
--
-- Reversa: no hay una automatica. Antes de correrlo se puede guardar el estado:
--   create table bk_tasa_20261106 as
--   select id_presupuesto, cod_moneda, tipo_cambio from presupuestos;
--   create table bk_tasa_fact_20261106 as
--   select id_factura, cod_moneda, tipo_cambio from facturas;
--
-- OJO para quien edite este archivo: el runner (importar_export.py) descarta
-- toda linea que empiece por SET (limpiando espacios), asi que el `set` de los
-- UPDATE va al final de la linea del `update`. Y cada sentencia se separa con
-- una linea que sea solo `/`.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

create or replace function fn_tasa_ves (
    p_fecha  in date,
    p_moneda in varchar2 default 'USD'
) return number is
    v_moneda varchar2(10) := upper(trim(p_moneda));
    v_tasa   number;
begin
    if v_moneda is null or v_moneda in ('VES', 'BS') then
        return 1;
    end if;

    select max(tasa_cambio) keep (dense_rank last order by fecha_vigencia)
      into v_tasa
      from tipo_cambio
     where moneda_origen = v_moneda
       and moneda_destino = 'VES'
       and tipo_tasa = 'REAL'
       and fecha_vigencia <= nvl(p_fecha, sysdate);

    return v_tasa;
end fn_tasa_ves;
/

update presupuestos p set
       p.tipo_cambio = case
                           when upper(p.cod_moneda) in ('VES', 'BS') then 1
                           else nvl(fn_tasa_ves(p.fecha_emision, p.cod_moneda), p.tipo_cambio)
                       end
 where nvl(p.tipo_cambio, -1) <> case
                                     when upper(p.cod_moneda) in ('VES', 'BS') then 1
                                     else nvl(fn_tasa_ves(p.fecha_emision, p.cod_moneda),
                                              nvl(p.tipo_cambio, -1))
                                 end
/

update facturas f set
       f.tipo_cambio = case
                           when upper(f.cod_moneda) in ('VES', 'BS') then 1
                           else nvl(fn_tasa_ves(f.fecha_emision, f.cod_moneda), f.tipo_cambio)
                       end
 where nvl(f.tipo_cambio, -1) <> case
                                     when upper(f.cod_moneda) in ('VES', 'BS') then 1
                                     else nvl(fn_tasa_ves(f.fecha_emision, f.cod_moneda),
                                              nvl(f.tipo_cambio, -1))
                                 end
/

update facturas_det d set
       (d.tasa_cambio_aplicada, d.subtotal_bs, d.total_bs) =
       (select f.tipo_cambio,
               round(nvl(d.subtotal_linea, 0) * f.tipo_cambio, 2),
               round(nvl(d.monto_total_linea, 0) * f.tipo_cambio, 2)
          from facturas f
         where f.id_factura = d.id_factura)
 where exists (select 1 from facturas f where f.id_factura = d.id_factura)
   and (nvl(d.tasa_cambio_aplicada, -1) <> nvl((select f.tipo_cambio from facturas f
                                                  where f.id_factura = d.id_factura), -2)
        or d.subtotal_bs is null
        or d.total_bs is null)
/

begin
    dbms_utility.compile_schema('WKSP_SYPEXWS', false);
end;
/

-- Validacion rapida (las dos deben devolver 0):
--   select count(*) from presupuestos
--    where upper(cod_moneda) not in ('VES','BS') and nvl(tipo_cambio,1) = 1;
--   select count(*) from facturas
--    where upper(cod_moneda) not in ('VES','BS') and nvl(tipo_cambio,1) = 1;
