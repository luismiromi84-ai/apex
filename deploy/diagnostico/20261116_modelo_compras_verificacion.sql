-- =============================================================================
-- 20261116_modelo_compras_verificacion.sql
--
-- Verificacion del modelo de compras (Task 1 del plan libro-compras-ventas).
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261116_modelo_compras_verificacion.sql
-- FALLAS=0 = EXITO.
--
-- M8 (que install.sql cargue las tablas nuevas) no se puede medir desde SQL:
-- se comprueba con Select-String sobre deploy/install.sql en el mismo paso.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

begin
    begin execute immediate 'drop table tmp_modelo_fallas purge'; exception when others then null; end;
end;
/

create table tmp_modelo_fallas (caso varchar2(300))
/

-- M1: existen las cinco tablas.
insert into tmp_modelo_fallas
select substrb('M1: falta la tabla ' || x.t, 1, 300)
  from (select 'PROVEEDORES' t from dual union all
        select 'COMPRAS' from dual union all
        select 'COMPRAS_DET' from dual union all
        select 'RETENCIONES_IVA' from dual union all
        select 'RETENCION_CONTADOR' from dual) x
 where not exists (select 1 from all_tables
                    where owner = 'WKSP_SYPEXWS' and table_name = x.t)
/

-- M1b: cada una tiene PK.
insert into tmp_modelo_fallas
select substrb('M1b: la tabla ' || x.t || ' no tiene PK', 1, 300)
  from (select 'PROVEEDORES' t from dual union all
        select 'COMPRAS' from dual union all
        select 'COMPRAS_DET' from dual union all
        select 'RETENCIONES_IVA' from dual union all
        select 'RETENCION_CONTADOR' from dual) x
 where not exists (select 1 from all_constraints c
                    where c.owner = 'WKSP_SYPEXWS' and c.table_name = x.t
                      and c.constraint_type = 'P')
/

-- M2: COMPRAS tiene el unico (empresa, proveedor, tipo, folio).
insert into tmp_modelo_fallas
select substrb('M2: COMPRAS no tiene el unico (empresa, proveedor, tipo, folio)', 1, 300)
  from dual
 where not exists (
   select 1 from all_constraints c
    where c.owner = 'WKSP_SYPEXWS' and c.table_name = 'COMPRAS' and c.constraint_type = 'U'
      and (select count(*) from all_cons_columns k
            where k.owner = c.owner and k.constraint_name = c.constraint_name
              and k.table_name = c.table_name) = 4
      and exists (select 1 from all_cons_columns k where k.owner = c.owner
                   and k.constraint_name = c.constraint_name and k.column_name = 'ID_EMPRESA')
      and exists (select 1 from all_cons_columns k where k.owner = c.owner
                   and k.constraint_name = c.constraint_name and k.column_name = 'ID_PROVEEDOR')
      and exists (select 1 from all_cons_columns k where k.owner = c.owner
                   and k.constraint_name = c.constraint_name and k.column_name = 'TIPO_DOCUMENTO')
      and exists (select 1 from all_cons_columns k where k.owner = c.owner
                   and k.constraint_name = c.constraint_name and k.column_name = 'FOLIO_FACTURA'))
/

-- M2b: el CHECK de estado admite BORRADOR, REGISTRADA y ANULADA.
insert into tmp_modelo_fallas
select substrb('M2b: COMPRAS no tiene el CHECK de estado BORRADOR/REGISTRADA/ANULADA', 1, 300)
  from dual
 where not exists (select 1 from all_constraints c
                    where c.owner = 'WKSP_SYPEXWS' and c.table_name = 'COMPRAS'
                      and c.constraint_type = 'C'
                      and c.search_condition_vc like '%BORRADOR%'
                      and c.search_condition_vc like '%REGISTRADA%'
                      and c.search_condition_vc like '%ANULADA%')
/

-- M3: COMPRAS_DET tiene las columnas en Bs y FK a COMPRAS sin cascada.
insert into tmp_modelo_fallas
select substrb('M3: a COMPRAS_DET le falta la columna ' || x.c, 1, 300)
  from (select 'SUBTOTAL_BS' c from dual union all
        select 'TOTAL_BS' from dual union all
        select 'ID_DETALLE_ORIGEN' from dual) x
 where not exists (select 1 from all_tab_columns t
                    where t.owner = 'WKSP_SYPEXWS' and t.table_name = 'COMPRAS_DET'
                      and t.column_name = x.c)
/

insert into tmp_modelo_fallas
select substrb('M3b: COMPRAS_DET no tiene FK a COMPRAS sin cascada', 1, 300)
  from dual
 where not exists (select 1 from all_constraints c
                    where c.owner = 'WKSP_SYPEXWS' and c.table_name = 'COMPRAS_DET'
                      and c.constraint_type = 'R' and c.delete_rule = 'NO ACTION'
                      and c.r_constraint_name in (select p.constraint_name from all_constraints p
                                                   where p.owner = 'WKSP_SYPEXWS'
                                                     and p.table_name = 'COMPRAS'
                                                     and p.constraint_type = 'P'))
/

-- M4: RETENCIONES_IVA es unico por compra y por (empresa, numero).
insert into tmp_modelo_fallas
select substrb('M4: RETENCIONES_IVA no es unico por ID_COMPRA', 1, 300)
  from dual
 where not exists (select 1 from all_constraints c
                    where c.owner = 'WKSP_SYPEXWS' and c.table_name = 'RETENCIONES_IVA'
                      and c.constraint_type = 'U'
                      and (select count(*) from all_cons_columns k
                            where k.owner = c.owner and k.constraint_name = c.constraint_name) = 1
                      and exists (select 1 from all_cons_columns k where k.owner = c.owner
                                   and k.constraint_name = c.constraint_name
                                   and k.column_name = 'ID_COMPRA'))
/

insert into tmp_modelo_fallas
select substrb('M4b: RETENCIONES_IVA no es unico por (ID_EMPRESA, NUMERO_COMPROBANTE)', 1, 300)
  from dual
 where not exists (select 1 from all_constraints c
                    where c.owner = 'WKSP_SYPEXWS' and c.table_name = 'RETENCIONES_IVA'
                      and c.constraint_type = 'U'
                      and (select count(*) from all_cons_columns k
                            where k.owner = c.owner and k.constraint_name = c.constraint_name) = 2
                      and exists (select 1 from all_cons_columns k where k.owner = c.owner
                                   and k.constraint_name = c.constraint_name
                                   and k.column_name = 'NUMERO_COMPROBANTE'))
/

-- M5: CLIENTES gana las dos columnas de retencion con sus defectos.
insert into tmp_modelo_fallas
select substrb('M5: CLIENTES no tiene ' || x.c, 1, 300)
  from (select 'ES_AGENTE_RETENCION' c from dual union all select 'PORCENTAJE_RETENCION' from dual) x
 where not exists (select 1 from all_tab_columns t
                    where t.owner = 'WKSP_SYPEXWS' and t.table_name = 'CLIENTES'
                      and t.column_name = x.c)
/

-- M5b y M7: los defectos se prueban por comportamiento (data_default es LONG y no
-- se puede comparar): se inserta una fila sin esas columnas y se lee lo que puso.
-- OJO: se usa SAVEPOINT, no ROLLBACK: un rollback se llevaria por delante los
-- fallos ya insertados en tmp_modelo_fallas (estaban sin confirmar).
declare
    v_es   varchar2(1);
    v_pct  number;
    v_ret  varchar2(1);
    v_pct2 number;
    v_cli  varchar2(300);
    v_pro  varchar2(300);
begin
    begin
        savepoint sp_defecto;
        execute immediate q'~insert into clientes (id_empresa, rif, razon_social)
                               values (1, 'V-TESTDEF-1', 'Prueba defecto')~';
        execute immediate q'~select es_agente_retencion, porcentaje_retencion from clientes
                              where id_empresa = 1 and rif = 'V-TESTDEF-1'~' into v_es, v_pct;
        rollback to sp_defecto;
        if v_es <> 'N' or v_pct <> 75 then
            v_cli := substrb('M5b: CLIENTES no nace con N/75 sino ' || v_es || '/' || v_pct, 1, 300);
        end if;
    exception
        when others then
            rollback to sp_defecto;
            v_cli := substrb('M5b: no se pudo probar el defecto de CLIENTES: ' || sqlerrm, 1, 300);
    end;

    begin
        savepoint sp_defecto;
        execute immediate q'~insert into proveedores (id_empresa, rif, razon_social)
                               values (1, 'V-TESTDEF-2', 'Prueba defecto')~';
        execute immediate q'~select retener_iva, porcentaje_retencion from proveedores
                              where id_empresa = 1 and rif = 'V-TESTDEF-2'~' into v_ret, v_pct2;
        rollback to sp_defecto;
        if v_ret <> 'S' or v_pct2 <> 75 then
            v_pro := substrb('M7: PROVEEDORES no nace con S/75 sino ' || v_ret || '/' || v_pct2, 1, 300);
        end if;
    exception
        when others then
            rollback to sp_defecto;
            v_pro := substrb('M7: no se pudo probar el defecto de PROVEEDORES: ' || sqlerrm, 1, 300);
    end;

    if v_cli is not null then insert into tmp_modelo_fallas values (v_cli); end if;
    if v_pro is not null then insert into tmp_modelo_fallas values (v_pro); end if;
end;
/

-- M6: FACTURAS gana las tres columnas de retencion.
insert into tmp_modelo_fallas
select substrb('M6: FACTURAS no tiene ' || x.c, 1, 300)
  from (select 'PORCENTAJE_RETENCION' c from dual union all
        select 'RETENCION_IVA_BS' from dual union all
        select 'NRO_COMPROBANTE_RETENCION' from dual) x
 where not exists (select 1 from all_tab_columns t
                    where t.owner = 'WKSP_SYPEXWS' and t.table_name = 'FACTURAS'
                      and t.column_name = x.c)
/

-- M7b: PROVEEDORES unico (empresa, rif).
insert into tmp_modelo_fallas
select substrb('M7b: PROVEEDORES no es unico por (ID_EMPRESA, RIF)', 1, 300)
  from dual
 where not exists (select 1 from all_constraints c
                    where c.owner = 'WKSP_SYPEXWS' and c.table_name = 'PROVEEDORES'
                      and c.constraint_type = 'U'
                      and (select count(*) from all_cons_columns k
                            where k.owner = c.owner and k.constraint_name = c.constraint_name) = 2
                      and exists (select 1 from all_cons_columns k where k.owner = c.owner
                                   and k.constraint_name = c.constraint_name and k.column_name = 'RIF'))
/

-- M9: ningun objeto invalido en el esquema.
insert into tmp_modelo_fallas
select substrb('M9: ' || count(*) || ' objeto(s) invalido(s) en WKSP_SYPEXWS', 1, 300)
  from all_objects
 where owner = 'WKSP_SYPEXWS' and status = 'INVALID'
having count(*) > 0
/

declare
    v_fallas number;
    v_lista  varchar2(3000);
begin
    select count(*) into v_fallas from tmp_modelo_fallas;
    select substrb(listagg(caso, ' | ' on overflow truncate) within group (order by caso), 1, 3000)
      into v_lista from tmp_modelo_fallas;
    execute immediate 'drop table tmp_modelo_fallas purge';
    raise_application_error(-20100, substrb('RESULTADO: FALLAS=' || v_fallas || ' | ' || v_lista, 1, 3000));
end;
/
