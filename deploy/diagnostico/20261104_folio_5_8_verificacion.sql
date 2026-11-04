-- Verificacion: folio por empresa y acciones dinamicas muertas (paginas 5 y 8)
-- Uso: SQL puro, solo lectura. Cada fila devuelta es una falla.
-- Esperado DESPUES del cambio: 0 filas.
-- Autor: agente, 2026-11-04. App 100, esquema WKSP_SYPEXWS.
-- Cubre: DA muertas, cableado de la DA de la pagina 7 (disparo, destino, guarda,
--        ejecucion al cargar) y forma del calculo de folio de la pagina 9.

select 'A) DA muerta en pagina ' || d.page_id || ': ' || d.dynamic_action_name
       || ' <- ' || d.when_element as falla
  from apex_application_page_da d
 where d.application_id = 100
   and d.when_selection_type = 'Item'
   and d.page_id in (5, 8)
   and not exists (select 1
                     from apex_application_page_items i
                    where i.application_id = d.application_id
                      and i.page_id = d.page_id
                      and i.item_name = d.when_element)
union all
-- B) pagina 7: disparo con la empresa, escribe P7_FOLIO, no recalcula al editar,
--    no corre al cargar la pagina
select 'B) la DA NUEVO_FOLIO de la pagina 7 no esta cableada como corresponde'
  from dual
 where not exists (select 1
                     from apex_application_page_da d
                     join apex_application_page_da_acts a
                       on a.dynamic_action_id = d.dynamic_action_id
                    where d.application_id = 100
                      and d.page_id = 7
                      and d.dynamic_action_name = 'NUEVO_FOLIO'
                      and instr(d.when_element, 'P7_ID_EMPRESA') > 0
                      and d.when_event_internal_name = 'change'
                      and instr(a.affected_elements, 'P7_FOLIO') > 0
                      and a.client_condition_type_code = 'NULL'
                      and a.client_condition_element = 'P7_ID_PRESUPUESTO'
                      and a.execute_on_page_init = 'No')
union all
-- C) la computacion de P7_FOLIO debe filtrar por empresa
select 'C) la computacion de P7_FOLIO no filtra por empresa'
  from apex_application_page_comp c
 where c.application_id = 100
   and c.page_id = 7
   and c.item_name = 'P7_FOLIO'
   and instr(upper(c.computation), 'ID_EMPRESA') = 0
union all
-- D) pagina 9: prefijo F-, filtro por empresa, sin corte por tipo de documento
select 'D) el folio de factura no conserva el prefijo F- o no filtra por empresa'
  from dual
 where not exists (select 1
                     from apex_application_page_da_acts a
                    where a.application_id = 100
                      and a.page_id = 9
                      and instr(a.affected_elements, 'P9_FOLIO_FACTURA') > 0
                      and instr(upper(a.attributes), 'ID_EMPRESA') > 0
                      and instr(a.attributes, '''F-''') > 0
                      and instr(upper(a.attributes), 'TIPO_DOCUMENTO') = 0)
union all
-- E) el calculo del folio de factura debe dispararse al cambiar la empresa (evento
--    'change', no 'focusout': la empresa tambien llega por retorno del presupuesto)
select 'E) el calculo del folio de factura no se dispara al cambiar la empresa'
  from dual
 where not exists (select 1
                     from apex_application_page_da d
                     join apex_application_page_da_acts a
                       on a.dynamic_action_id = d.dynamic_action_id
                    where d.application_id = 100
                      and d.page_id = 9
                      and instr(a.affected_elements, 'P9_FOLIO_FACTURA') > 0
                      and instr(d.when_element, 'P9_ID_EMPRESA') > 0
                      and d.when_event_internal_name = 'change')
union all
-- F) editar una factura existente no debe tocar el folio
select 'F) el calculo del folio de factura no esta guardado con "P9_ID_FACTURA is null"'
  from dual
 where not exists (select 1
                     from apex_application_page_da_acts a
                    where a.application_id = 100
                      and a.page_id = 9
                      and instr(a.affected_elements, 'P9_FOLIO_FACTURA') > 0
                      and a.client_condition_type_code = 'NULL'
                      and a.client_condition_element = 'P9_ID_FACTURA')
