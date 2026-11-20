-- =============================================================================
-- 20261116_libro_compras_ventas_verificacion.sql
--
-- Libro unificado por pais (Task 8). Sustituye a 20261116_libro_ventas_verificacion.
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261116_libro_compras_ventas_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

begin
    begin execute immediate 'drop table tmp_lcv_fallas purge'; exception when others then null; end;
end;
/

create table tmp_lcv_fallas (caso varchar2(300))
/

-- L1: pagina 18 con el alias nuevo.
insert into tmp_lcv_fallas
select substrb('L1: no existe la pagina 18 con alias LIBRO-COMPRAS-VENTAS', 1, 300)
  from dual
 where not exists (select 1 from apex_application_pages
                    where application_id = 100 and page_id = 18
                      and upper(page_alias) = 'LIBRO-COMPRAS-VENTAS');
/

-- L2: la region de Venezuela une ventas y compras y trae la retencion.
insert into tmp_lcv_fallas
select substrb('L2: la region libro-ve no tiene la consulta esperada', 1, 300)
  from dual
 where not exists (select 1 from apex_application_page_regions r
                    where r.application_id = 100 and r.page_id = 18
                      and r.region_static_id = 'libro-ve'
                      and r.source_type_plugin_static_id = 'NATIVE_IR'
                      and instr(upper(r.region_source), 'COMPRAS') > 0
                      and instr(upper(r.region_source), 'PROVEEDORES') > 0
                      and instr(upper(r.region_source), 'RETENCION_IVA_BS') > 0
                      and instr(r.region_source, ':P18_LIBRO') > 0
                      and instr(upper(r.region_source), 'F_EMPRESA_ACTIVA') > 0);
/

-- L3: la region de Mexico trae el 8 % y NO la retencion.
insert into tmp_lcv_fallas
select substrb('L3: la region libro-mx no trae base8/iva8 o menciona retencion', 1, 300)
  from dual
 where not exists (select 1 from apex_application_page_regions r
                    where r.application_id = 100 and r.page_id = 18
                      and r.region_static_id = 'libro-mx'
                      and r.source_type_plugin_static_id = 'NATIVE_IR'
                      and instr(upper(r.region_source), 'BASE8') > 0
                      and instr(upper(r.region_source), 'IVA8') > 0
                      and instr(upper(r.region_source), 'RETENCION') = 0);
/

-- L4, L5 y L13: la consulta de Venezuela corre con los binds y cuadra.
-- Se crea una factura PENDIENTE con retencion del cliente (L13) dentro de un
-- SAVEPOINT: los fallos se insertan DESPUES del rollback o se perderian.
declare
    v_sql clob;
    v_n   number;
    v_mal number;
    v_cli number;
    v_fac number;
    v_f1  varchar2(300);
    v_f2  varchar2(300);
    v_f3  varchar2(300);
begin
    savepoint sp_l4;

    insert into clientes (id_empresa, rif, razon_social, es_agente_retencion, porcentaje_retencion)
    values (1, 'J-TESTLCV-1', 'Cliente agente del libro', 'S', 75)
    returning id_cliente into v_cli;

    pkg_facturacion.prc_guardar_factura(
        p_id_factura => v_fac, p_id_empresa => 1, p_folio_factura => 'LCV-1',
        p_id_cliente => v_cli, p_id_presupuesto => null,
        p_rfc_emisor => 'J-1', p_rfc_receptor => 'J-2', p_uuid_fiscal => null,
        p_uso_cfdi => null, p_forma_pago => null, p_metodo_pago => null,
        p_condicion_pago => null, p_fecha_emision => '16/11/2026',
        p_fecha_vencimiento => null, p_estado => 'PENDIENTE',
        p_subtotal => 100, p_monto_impuesto => 16, p_monto_total => 116,
        p_observaciones => null, p_cod_moneda => 'VES', p_tipo_cambio => 1,
        p_usuario => 'admin', p_tipo_documento => 'FAC',
        p_nro_comprobante_retencion => '20261100000003');

    insert into facturas_det (id_factura, num_linea, descripcion, cantidad, precio_unitario,
                              id_impuesto, porcentaje_impuesto, monto_impuesto, subtotal_linea,
                              monto_total_linea, tasa_cambio_aplicada, subtotal_bs, total_bs)
    values (v_fac, 1, 'Servicio', 1, 100, 1, 16, 16, 100, 116, 1, 100, 116);

    select region_source into v_sql
      from apex_application_page_regions
     where application_id = 100 and page_id = 18 and region_static_id = 'libro-ve';

    v_sql := replace(v_sql, ':F_EMPRESA_ACTIVA', '1');
    v_sql := replace(v_sql, ':P18_ID_EMPRESA', 'null');
    v_sql := replace(v_sql, ':P18_LIBRO', '''TODOS''');
    v_sql := replace(v_sql, ':P18_MES', '11');
    v_sql := replace(v_sql, ':P18_ANIO', '2026');
    -- el filtro de periodo (quincenas) se agrego el 2026-11-18
    v_sql := replace(v_sql, ':P18_PERIODO', '''MES''');
    v_sql := replace(v_sql, ':APP_USER', '''ADMIN''');

    execute immediate 'select count(*) from (' || v_sql || ')' into v_n;
    if v_n = 0 then
        v_f1 := 'L4: el libro de 11/2026 sale vacio';
    end if;

    execute immediate
        'select count(*) from (' || v_sql || ') where abs(nvl(total_bs,0) '
        || '- (nvl(base16,0)+nvl(iva16,0)+nvl(exento,0)+nvl(base_igtf,0)+nvl(igtf,0)'
        || '+nvl(otras_base,0)+nvl(otras_iva,0)+nvl(igtf_compra,0))) > 0.01'
        into v_mal;
    if v_mal > 0 then
        v_f2 := 'L5: ' || v_mal || ' fila(s) sin cuadre';
    end if;

    execute immediate
        'select count(*) from (' || v_sql || ') where estado = ''PENDIENTE'' and nvl(retencion_bs,0) > 0'
        into v_mal;
    if v_mal = 0 then
        v_f3 := 'L13: ninguna factura PENDIENTE muestra retencion';
    end if;

    rollback to sp_l4;

    if v_f1 is not null then insert into tmp_lcv_fallas values (substrb(v_f1, 1, 300)); end if;
    if v_f2 is not null then insert into tmp_lcv_fallas values (substrb(v_f2, 1, 300)); end if;
    if v_f3 is not null then insert into tmp_lcv_fallas values (substrb(v_f3, 1, 300)); end if;
exception
    when others then
        rollback to sp_l4;
        v_f1 := substrb('L4: la consulta de Venezuela falla: ' || sqlerrm, 1, 300);
        insert into tmp_lcv_fallas values (v_f1);
end;
/

-- L6 y L7: las notas de credito restan y las anuladas salen en 0.
declare
    v_sql clob;
    v_n   number;
begin
    select region_source into v_sql
      from apex_application_page_regions
     where application_id = 100 and page_id = 18 and region_static_id = 'libro-ve';
    v_sql := replace(v_sql, ':F_EMPRESA_ACTIVA', '1');
    v_sql := replace(v_sql, ':P18_ID_EMPRESA', 'null');
    v_sql := replace(v_sql, ':P18_LIBRO', '''TODOS''');
    v_sql := replace(v_sql, ':P18_MES', '11');
    v_sql := replace(v_sql, ':P18_ANIO', '2026');
    -- el filtro de periodo (quincenas) se agrego el 2026-11-18
    v_sql := replace(v_sql, ':P18_PERIODO', '''MES''');
    v_sql := replace(v_sql, ':APP_USER', '''ADMIN''');

    execute immediate 'select count(*) from (' || v_sql || ') where tipo like ''Nota de cr%'' and total_bs > 0'
      into v_n;
    if v_n > 0 then
        insert into tmp_lcv_fallas values (substrb('L6: hay notas de credito que no restan', 1, 300));
    end if;

    execute immediate 'select count(*) from (' || v_sql || ') where estado = ''ANULADA'' and nvl(total_bs,0) <> 0'
      into v_n;
    if v_n > 0 then
        insert into tmp_lcv_fallas values (substrb('L7: hay anuladas con importe', 1, 300));
    end if;
exception
    when others then
        insert into tmp_lcv_fallas values (substrb('L6: no se pudo medir', 1, 300));
end;
/

-- L8: el filtro Libro separa ventas de compras (cuatro referencias en la union).
insert into tmp_lcv_fallas
select substrb('L8: la consulta no filtra por P18_LIBRO en los dos lados', 1, 300)
  from dual
 where nvl((select max(regexp_count(upper(r.region_source), 'P18_LIBRO'))
              from apex_application_page_regions r
             where r.application_id = 100 and r.page_id = 18
               and r.region_static_id = 'libro-ve'), 0) < 4;
/

-- L9: la region de Venezuela no menciona el 8 % y la de Mexico no menciona IGTF.
insert into tmp_lcv_fallas
select substrb('L9: la region libro-ve menciona BASE8', 1, 300)
  from dual
 where exists (select 1 from apex_application_page_regions r
                where r.application_id = 100 and r.page_id = 18 and r.region_static_id = 'libro-ve'
                  and instr(upper(r.region_source), 'BASE8') > 0);
/

insert into tmp_lcv_fallas
select substrb('L9: la region libro-mx menciona IGTF', 1, 300)
  from dual
 where exists (select 1 from apex_application_page_regions r
                where r.application_id = 100 and r.page_id = 18 and r.region_static_id = 'libro-mx'
                  and instr(upper(r.region_source), 'IGTF') > 0);
/

-- L10: el total en Bs de una compra usa la tasa del documento.
insert into tmp_lcv_fallas
select substrb('L10: la consulta no convierte las compras con la tasa del documento', 1, 300)
  from dual
 where (select count(*) from apex_application_page_regions r
         where r.application_id = 100 and r.page_id = 18 and r.region_static_id = 'libro-ve'
           and instr(upper(r.region_source), 'TIPO_CAMBIO') > 0) = 0;
/

-- L11: la retencion de una nota se calcula prorrateada con el porcentaje del origen.
insert into tmp_lcv_fallas
select substrb('L11: la consulta no prorratea la retencion de las notas de compra', 1, 300)
  from dual
 where (select count(*) from apex_application_page_regions r
         where r.application_id = 100 and r.page_id = 18 and r.region_static_id = 'libro-ve'
           and instr(upper(r.region_source), 'ID_COMPRA_ORIGEN') > 0) = 0;
/

-- L12: la region de Mexico tambien trae las compras y su columna «Ver compra»
-- (hasta el 2026-11-19 solo traia ventas, y la columna no tenia a donde apuntar).
insert into tmp_lcv_fallas
select substrb('L12: la region libro-mx no incluye las compras', 1, 300)
  from dual
 where not exists (select 1 from apex_application_page_regions r
                    where r.application_id = 100 and r.page_id = 18 and r.region_static_id = 'libro-mx'
                      and instr(upper(r.region_source), 'COMPRAS') > 0
                      and instr(upper(r.region_source), 'VER_COMPRA') > 0);
/

-- L12b: la columna «Ver compra» del libro de Mexico apunta a la compra (28).
insert into tmp_lcv_fallas
select substrb('L12b: falta la columna Ver compra en el libro de Mexico', 1, 300)
  from dual
 where not exists (select 1 from apex_260100.apex_application_page_ir_col c
                    where c.application_id = 100 and c.page_id = 18
                      and c.region_name = 'Libro de Mexico'
                      and c.column_alias = 'VER_COMPRA'
                      and lower(c.column_link) like '%p28_id_compra%');
/

-- L14: totales de los dos paises y guarda de rol.
insert into tmp_lcv_fallas
select substrb('L14: falta la region de totales ' || x.t, 1, 300)
  from (select 'libro-ve-totales' t from dual union all select 'libro-mx-totales' from dual) x
 where not exists (select 1 from apex_application_page_regions r
                    where r.application_id = 100 and r.page_id = 18
                      and r.region_static_id = x.t);
/

insert into tmp_lcv_fallas
select substrb('L14: falta la guarda de rol del libro', 1, 300)
  from dual
 where not exists (select 1 from apex_application_page_proc p
                    where p.application_id = 100 and p.page_id = 18
                      and p.process_point_code = 'BEFORE_HEADER'
                      and upper(p.process_name) like 'VALIDA ROL%');
/

insert into tmp_lcv_fallas
select substrb('L14: el menu no dice Libro de compras y ventas', 1, 300)
  from dual
 where not exists (select 1 from apex_application_list_entries
                    where application_id = 100 and entry_target like '%:18:%'
                      and upper(entry_text) like '%LIBRO DE COMPRAS Y VENTAS%');
/

-- L9: el IGTF percibido del mes vive en su propio bloque de la pagina 18: se
-- declara por fecha de cobro (se percibe al pagar) y no es ingreso.
insert into tmp_lcv_fallas
select substrb('L9: la 18 no tiene el bloque de IGTF percibido', 1, 300)
  from dual
 where not exists (select 1 from apex_application_page_regions
                    where application_id = 100 and page_id = 18
                      and upper(region_name) like '%IGTF%');
/
insert into tmp_lcv_fallas
select substrb('L9: el bloque de IGTF no lee los recibos o no suma el IGTF en Bs', 1, 300)
  from dual
 where not exists (select 1 from apex_application_page_regions
                    where application_id = 100 and page_id = 18
                      and upper(region_name) like '%IGTF%'
                      and instr(lower(to_clob(region_source)), 'recibos') > 0
                      and instr(lower(to_clob(region_source)), 'igtf_bs') > 0);
/

declare
    v_fallas number;
    v_lista  varchar2(3000);
begin
    select count(*) into v_fallas from tmp_lcv_fallas;
    select substrb(listagg(caso, ' | ' on overflow truncate) within group (order by caso), 1, 3000)
      into v_lista from tmp_lcv_fallas;
    execute immediate 'drop table tmp_lcv_fallas purge';
    raise_application_error(-20100, substrb('RESULTADO: FALLAS=' || v_fallas || ' | ' || v_lista, 1, 3000));
end;
/
