-- =============================================================================
-- 20261120_nota_compra_tasa_origen.sql
--
-- LA NOTA DE COMPRA LLEVA LA TASA DE LA FACTURA QUE ACREDITA
--
-- Regla (decision del dueno para FACTURAS el 2026-11-09, aplicada a COMPRAS el
-- 2026-11-20): una nota de credito o debito se emite con la tasa de la factura
-- que acredita, no con la del dia en que se teclea. Es lo que exige la
-- correlacion fiscal y es lo que hace que el documento cuadre consigo mismo.
--
-- El defecto que cierra: la nota de compra 1462 (folio 3, BORRADOR) tenia la
-- cabecera a la tasa del dia (917,7751) y sus lineas copiadas de la compra 964 a
-- la tasa de la factura (916,6477). El libro de compras y ventas (18) suma las
-- FILAS por el detalle (compras_det.total_bs) y los TOTALES del mes por la
-- CABECERA (monto_total * tipo_cambio): 8.145.890,49 contra 8.144.595,78, una
-- diferencia de 1.294,71 Bs que no era de redondeo.
--
-- Que hace esta migracion:
--   1) Para cada compra NC/ND con factura de origen vigente cuya tasa de cabecera
--      difiere de la del origen, pone la tasa del origen en la cabecera.
--   2) Reprecia las lineas que se derivaron de la cabecera (las que tienen
--      id_detalle_origen y tasa_cambio_aplicada igual a la tasa vieja de la
--      cabecera), recalculando subtotal_bs y total_bs. Las lineas tecleadas a
--      mano (sin id_detalle_origen) no se tocan.
--   3) Solo actua sobre documentos cuyas lineas vienen TODAS del origen: una nota
--      con lineas a mano es otro caso y no se adivina.
--   4) No toca importes: monto_total y las lineas siguen igual; solo la tasa y sus
--      equivalentes en bolivares.
--
-- Idempotente: la segunda pasada no encuentra nada que corregir.
-- Sin DDL: no hace falta compilar el esquema.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_docs   number := 0;
    v_lineas number := 0;
    v_pend   number;
begin
    for r in (
        select co.id_compra,
               co.tipo_cambio   as tasa_vieja,
               o.tipo_cambio    as tasa_origen
          from compras co
          join compras o on o.id_compra = co.id_compra_origen
         where co.tipo_documento in ('NC', 'ND')
           and co.id_compra_origen is not null
           and o.tipo_documento = 'FAC'
           and o.estado <> 'ANULADA'
           and nvl(co.tipo_cambio, -1) <> nvl(o.tipo_cambio, -1)
           -- Solo documentos cuyas lineas vienen todas del origen.
           and not exists (select 1
                             from compras_det d
                            where d.id_compra = co.id_compra
                              and d.id_detalle_origen is null)
    ) loop
        -- Las lineas copiadas del origen traen la tasa del origen; las que se
        -- derivaron de la cabecera traen la tasa vieja. Solo se reprecia lo que
        -- apunta al origen (id_detalle_origen no nulo).
        update compras_det d set d.tasa_cambio_aplicada = r.tasa_origen,
               d.subtotal_bs = round(nvl(d.subtotal_linea, 0) * r.tasa_origen, 2),
               d.total_bs = round(nvl(d.total_linea, 0) * r.tasa_origen, 2)
         where d.id_compra = r.id_compra
           and d.id_detalle_origen is not null;

        v_lineas := v_lineas + sql%rowcount;

        update compras set tipo_cambio = r.tasa_origen,
               fecha_modificacion = systimestamp
         where id_compra = r.id_compra;

        v_docs := v_docs + 1;
    end loop;

    commit;

    -- Validacion: no puede quedar ninguna nota con factura de origen vigente y
    -- tasa distinta (ni cabecera distinta de sus lineas copiadas).
    select count(*) into v_pend
      from compras co
      join compras o on o.id_compra = co.id_compra_origen
     where co.tipo_documento in ('NC', 'ND')
       and o.tipo_documento = 'FAC'
       and o.estado <> 'ANULADA'
       and nvl(co.tipo_cambio, -1) <> nvl(o.tipo_cambio, -1);
    if v_pend > 0 then
        raise_application_error(-20130,
            'quedaron ' || v_pend || ' nota(s) de compra con la tasa del dia en vez de la del origen');
    end if;

    select count(*) into v_pend
      from compras co
      join compras_det d on d.id_compra = co.id_compra
     where co.tipo_documento in ('NC', 'ND')
       and d.id_detalle_origen is not null
       and nvl(d.tasa_cambio_aplicada, -1) <> nvl(co.tipo_cambio, -1);
    if v_pend > 0 then
        raise_application_error(-20130,
            'quedaron ' || v_pend || ' linea(s) de nota de compra con una tasa distinta de su cabecera');
    end if;

    -- dbms_output no se puede leer desde importar_export.py en este entorno: el
    -- numero de documentos corregidos se comprueba despues con una consulta
    -- (deploy/resultados/20261120_nota_compra_tasa_origen.txt).
end;
/
