-- =============================================================================
-- vistas/v_presupuesto_real.sql
--
-- Presupuestado, gastado, desviacion y % ejecutado por presupuesto. La usa la
-- region «Resumen Financiero» de la pagina 5.
--
-- Nacio en deploy/migrations/20261105_gasto_real.sql. Se movio aqui el
-- 2026-11-07 porque install.sql no la cargaba y una instalacion limpia se
-- quedaba sin la vista.
-- =============================================================================

create or replace view v_presupuesto_real as
select p.id_presupuesto,
       p.id_empresa,
       p.folio,
       p.estado,
       p.cod_moneda,
       nvl(p.total, 0)                                   as presupuestado_usd,
       nvl(g.gasto_usd, 0)                               as gasto_real_usd,
       nvl(p.total, 0) - nvl(g.gasto_usd, 0)             as desviacion_usd,
       case when nvl(p.total, 0) > 0
            then round(nvl(g.gasto_usd, 0) / p.total * 100, 2)
       end                                               as pct_ejecutado
  from presupuestos p
  left join (select id_presupuesto, sum(monto_base_usd) as gasto_usd
               from gasto_real
              group by id_presupuesto) g
    on g.id_presupuesto = p.id_presupuesto;
