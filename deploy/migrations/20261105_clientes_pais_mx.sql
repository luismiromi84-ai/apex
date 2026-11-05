-- =============================================================================
-- 20261105_clientes_pais_mx.sql
--
-- Objetivo: rellenar CLIENTES.COD_PAIS, que esta nulo en los tres clientes de
--           la empresa 2 (Mexico). Medido el 2026-11-05: empresa 1 tiene 15
--           clientes con 'VE'; empresa 2 tiene 3 con NULL.
--
-- Por que importa: la LOV de cliente y la cascada empresa -> cliente usan el
--           pais, y el impreso decide la etiqueta fiscal (RIF / RFC) por el
--           pais de la empresa. Un cliente sin pais se queda fuera de esos
--           filtros.
--
-- Afecta a: CLIENTES (solo la columna COD_PAIS). No toca importes ni estados.
--
-- Idempotente: solo escribe donde COD_PAIS es nulo y existe la empresa.
--
-- Ejecutar:
--   python deploy/conexion/importar_export.py deploy/migrations/20261105_clientes_pais_mx.sql
--
-- REVERSA:
--   update clientes set cod_pais = null where id_empresa = 2;
--   (solo si de verdad se quiere volver al estado anterior)
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;
/

select 'antes: clientes sin pais' as control, count(*) as filas
  from clientes where cod_pais is null;
/

update clientes set
       cod_pais = (select e.cod_pais from empresas e where e.id_empresa = clientes.id_empresa)
 where cod_pais is null
   and exists (select 1 from empresas e where e.id_empresa = clientes.id_empresa);
/

select 'despues: clientes sin pais' as control, count(*) as filas
  from clientes where cod_pais is null;
/

select 'despues: pais que no coincide con el de su empresa' as control, count(*) as filas
  from clientes c
  join empresas e on e.id_empresa = c.id_empresa
 where c.cod_pais is not null and c.cod_pais <> e.cod_pais;
/
