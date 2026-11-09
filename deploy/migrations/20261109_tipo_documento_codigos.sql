-- =============================================================================
-- 20261109_tipo_documento_codigos.sql
--
-- Los codigos de TIPO_DOCUMENTO no coincidian con los que usa la app.
--
-- Por que: la combo "Tipo Documento" de la pagina 9 saca sus valores de
-- TIPO_DOCUMENTO, y esa tabla tenia 'NCR', 'NDB' y 'NDG'. Pero TODO el resto del
-- sistema usa 'FAC', 'NC' y 'ND':
--   * CHECK  FACTURAS.CHK_FACTURA_TIPO      -> tipo_documento IN ('FAC','NC','ND')
--   * CHECK  FOLIO_CONTADOR.CK_FOLIO_CONTADOR_TIPO -> ('PRESUPUESTO','FAC','NC','ND')
--   * fn_asignar_folio / fn_siguiente_folio -> 'NC' -> 'NC-1', 'ND' -> 'ND-1'
--   * fn_nota_traible, pkg_factura_detalle, impresos y los KPI del Panel
--     (todos comparan contra 'NC'/'ND')
-- Consecuencias medidas el 2026-11-09: al elegir "Nota de Credito" el item recibia
-- 'NCR', el JavaScript que intercambia Presupuesto <-> Factura origen comparaba
-- contra 'NC' y no cambiaba nada, y al guardar el INSERT habria fallado con
-- ORA-02290 (CHK_FACTURA_TIPO). No habia ninguna factura con NCR/NDB (imposible
-- por el CHECK), asi que no hay datos que migrar.
--
-- Que hace:
--   1. renombra 'NCR' -> 'NC' y 'NDB' -> 'ND' (la PK es CODIGO y nadie la referencia
--      con FK, comprobado en ALL_CONSTRAINTS el 2026-11-09).
--   2. desactiva 'NDG' (Nota de Entrega / Guia): la app no tiene ese tipo y el
--      CHECK no lo admite. Se deja la fila con ACTIVO='N', no se borra.
--   3. siembra los tres codigos canonicos por si la tabla esta vacia (una
--      instalacion limpia no los creaba: install.sql solo hace el DDL).
--
-- Idempotente: los UPDATE solo tocan las filas viejas y el MERGE va por CODIGO.
-- Acentos con unistr(): el runner corrompe los literales acentuados.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

update tipo_documento set codigo = 'NC' where codigo = 'NCR'
/

update tipo_documento set codigo = 'ND' where codigo = 'NDB'
/

update tipo_documento set activo = 'N' where codigo = 'NDG'
/

merge into tipo_documento d
using (
    select 'FAC' as codigo, 'Factura de Venta' as descripcion from dual
    union all
    select 'NC', to_char(unistr('Nota de Cr\00E9dito')) from dual
    union all
    select 'ND', to_char(unistr('Nota de D\00E9bito')) from dual
) s
on (d.codigo = s.codigo)
when not matched then insert (codigo, descripcion, activo)
                      values (s.codigo, s.descripcion, 'Y')
when matched then update set descripcion = s.descripcion, activo = 'Y'
/

commit
/

-- Validacion: tienen que salir exactamente FAC, NC y ND activos.
select codigo, descripcion, activo from tipo_documento order by codigo
/

-- Y ninguna factura con un codigo fuera del CHECK (debe dar 0 filas).
select tipo_documento, count(*) filas
  from facturas
 where tipo_documento not in ('FAC', 'NC', 'ND')
 group by tipo_documento
/
