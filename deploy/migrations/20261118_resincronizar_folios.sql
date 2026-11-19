-- =============================================================================
-- 20261118_resincronizar_folios.sql
--
-- Los correlativos de FOLIO_CONTADOR iban POR DELANTE de los documentos: la purga
-- del demo y las pruebas (altas y bajas de documentos) consumieron numeros que ya
-- no existen. Medido el 2026-11-18:
--   empresa 1 FAC         contador 1064 · ultima factura F-1050
--   empresa 1 PRESUPUESTO contador 1057 · ultimo presupuesto 1055
--   empresa 1 CONTROL     contador 145  · ultimo control 00-000131
--
-- Esta migracion deja cada contador en el MAXIMO REAL de su tabla, para que el
-- siguiente documento continue desde el ultimo que existe (sin saltos hacia
-- adelante). NO renumera ningun documento: los folios ya emitidos no se tocan.
-- Tambien crea la fila del contador cuando hay documentos y no hay fila.
--
-- Es idempotente: correrla dos veces deja lo mismo.
-- Reversa: no aplica (los valores viejos no aportan nada; estan en la copia).
-- Verificacion: deploy/diagnostico/20261118_folios_verificacion.sql
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

-- Presupuestos: el folio es correlativo por empresa.
merge into folio_contador f
using (select id_empresa, 'PRESUPUESTO' tipo,
              nvl(max(to_number(regexp_substr(folio, '[0-9]+$'))), 0) ultimo
         from presupuestos
        group by id_empresa) d
on (f.id_empresa = d.id_empresa and f.tipo = d.tipo)
when matched then update set f.ultimo = d.ultimo
when not matched then insert (id_empresa, tipo, ultimo)
     values (d.id_empresa, d.tipo, d.ultimo)
/

-- Facturas: FAC, NC y ND, cada serie por empresa.
merge into folio_contador f
using (select id_empresa, tipo_documento tipo,
              nvl(max(to_number(regexp_substr(folio_factura, '[0-9]+$'))), 0) ultimo
         from facturas
        where tipo_documento in ('FAC', 'NC', 'ND')
        group by id_empresa, tipo_documento) d
on (f.id_empresa = d.id_empresa and f.tipo = d.tipo)
when matched then update set f.ultimo = d.ultimo
when not matched then insert (id_empresa, tipo, ultimo)
     values (d.id_empresa, d.tipo, d.ultimo)
/

-- Control de las facturas de venta: solo se cuentan los que tienen la forma de la
-- providencia (00-000131). Los valores tecleados a mano (876, 002) no empujan el
-- contador.
merge into folio_contador f
using (select id_empresa, 'CONTROL' tipo,
              nvl(max(to_number(regexp_substr(nro_control, '[0-9]+$'))), 0) ultimo
         from facturas
        where nro_control is not null
          and regexp_like(trim(nro_control), '^[0-9]{2}-[0-9]{6}$')
        group by id_empresa) d
on (f.id_empresa = d.id_empresa and f.tipo = d.tipo)
when matched then update set f.ultimo = d.ultimo
when not matched then insert (id_empresa, tipo, ultimo)
     values (d.id_empresa, d.tipo, d.ultimo)
/

-- Validacion: ningun contador puede quedar por debajo del maximo real.
declare
    v_mal number;
begin
    select count(*) into v_mal
      from folio_contador f
     where f.tipo = 'PRESUPUESTO'
       and f.ultimo < (select nvl(max(to_number(regexp_substr(p.folio, '[0-9]+$'))), 0)
                         from presupuestos p where p.id_empresa = f.id_empresa);
    if v_mal > 0 then
        raise_application_error(-20111, v_mal || ' contador(es) de presupuesto por debajo del maximo');
    end if;

    select count(*) into v_mal
      from folio_contador f
     where f.tipo in ('FAC', 'NC', 'ND')
       and f.ultimo < (select nvl(max(to_number(regexp_substr(x.folio_factura, '[0-9]+$'))), 0)
                         from facturas x
                        where x.id_empresa = f.id_empresa and x.tipo_documento = f.tipo);
    if v_mal > 0 then
        raise_application_error(-20111, v_mal || ' contador(es) de factura por debajo del maximo');
    end if;

    select count(*) into v_mal
      from folio_contador f
     where f.tipo = 'CONTROL'
       and f.ultimo < (select nvl(max(to_number(regexp_substr(x.nro_control, '[0-9]+$'))), 0)
                         from facturas x
                        where x.id_empresa = f.id_empresa
                          and x.nro_control is not null
                          and regexp_like(trim(x.nro_control), '^[0-9]{2}-[0-9]{6}$'));
    if v_mal > 0 then
        raise_application_error(-20111, v_mal || ' contador(es) de control por debajo del maximo');
    end if;
end;
/
