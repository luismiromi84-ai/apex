-- =============================================================================
-- 20261119_factura_precio_dos_decimales.sql
--
-- La linea de factura se calcula con el precio redondeado a 2 decimales
-- (2026-11-19). Idempotente.
--
-- Que arregla: en la factura F-1050 (id 1048, PENDIENTE) la linea guardaba
-- SUBTOTAL_LINEA = 3.388,39 con PRECIO_UNITARIO = 38,0717 (4 decimales). El
-- papel imprime 38,07, y 38,07 x 89 = 3.388,23: la linea no cuadraba con el
-- precio impreso y el recuadro de totales mostraba un centimo de diferencia
-- entre "Subtotal Bruto" y "Subtotal Neto".
--
-- Regla que se aplica (la que usa ya el proceso de la pagina 10 para las lineas
-- nuevas): precio unitario a 2 decimales; subtotal de linea = cantidad x precio
-- redondeado, menos el descuento; el IVA y el total salen de ahi.
--
-- Solo toca lineas que NO cuadran con esa regla y solo en documentos que no
-- estan cerrados fiscalmente (PENDIENTE/TIMBRADA/PARCIAL). Hoy en la base hay
-- una sola: la de la F-1050.
--
-- Reversa: los importes anteriores estan en el cuerpo del ticket; para volver
-- atras hay que reescribir a mano precio_unitario = 38,0717, subtotal_linea =
-- 3388.39, monto_impuesto = 542.14, monto_total_linea = 3930.53 (y sus Bs).
-- No se guarda copia porque el documento es un pendiente de prueba.
--
-- Verificacion: deploy/diagnostico/20261119_redondeo_retencion_verificacion.sql
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

update facturas_det d set precio_unitario = round(d.precio_unitario, 2),
       subtotal_linea    = round(d.cantidad * round(d.precio_unitario, 2), 2)
                           - nvl(d.monto_descuento, 0),
       monto_impuesto    = round((round(d.cantidad * round(d.precio_unitario, 2), 2)
                           - nvl(d.monto_descuento, 0)) * nvl(d.porcentaje_impuesto, 0) / 100, 2),
       monto_total_linea = (round(d.cantidad * round(d.precio_unitario, 2), 2)
                           - nvl(d.monto_descuento, 0))
                           + round((round(d.cantidad * round(d.precio_unitario, 2), 2)
                           - nvl(d.monto_descuento, 0)) * nvl(d.porcentaje_impuesto, 0) / 100, 2),
       subtotal_bs       = round((round(d.cantidad * round(d.precio_unitario, 2), 2)
                           - nvl(d.monto_descuento, 0))
                           * (select nvl(f.tipo_cambio, 1) from facturas f where f.id_factura = d.id_factura), 2),
       total_bs          = round(((round(d.cantidad * round(d.precio_unitario, 2), 2)
                           - nvl(d.monto_descuento, 0))
                           + round((round(d.cantidad * round(d.precio_unitario, 2), 2)
                           - nvl(d.monto_descuento, 0)) * nvl(d.porcentaje_impuesto, 0) / 100, 2))
                           * (select nvl(f.tipo_cambio, 1) from facturas f where f.id_factura = d.id_factura), 2)
 where exists (select 1
                 from facturas f
                where f.id_factura = d.id_factura
                  and nvl(f.estado, 'PENDIENTE') in ('PENDIENTE', 'TIMBRADA', 'PARCIAL'))
   and d.subtotal_linea + nvl(d.monto_descuento, 0)
       <> round(d.cantidad * round(d.precio_unitario, 2), 2)
/
