-- =============================================================================
-- 20261116_reporte_documentos_verificacion.sql
--
-- Verificacion del «Centro de documentos» (pagina 17). Desde el 2026-11-20 el
-- informe es la union de VENTAS (FACTURAS + CLIENTES) y COMPRAS (COMPRAS +
-- PROVEEDORES), con un filtro de modulo, una columna de modulo con insignia y
-- los totales por modulo y moneda.
--
-- Se ejecuta de arriba a abajo, como las demas:
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261116_reporte_documentos_verificacion.sql
--
-- Patron de conteo igual que 20261110_multiempresa_verificacion.sql: cada caso
-- inserta su fallo en una tabla normal y el bloque final cuenta y lista.
-- FALLAS=0 = EXITO (el runner sale con codigo 1 igualmente: se lee el mensaje).
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

begin
    begin
        execute immediate 'drop table tmp_rep_fallas purge';
    exception
        when others then null;
    end;
end;
/

create table tmp_rep_fallas (caso varchar2(300))
/

-- R1: existe la pagina 17 con alias DOCUMENTOS.
insert into tmp_rep_fallas
select substrb('R1: no existe la pagina 17 con alias DOCUMENTOS', 1, 300)
  from dual
 where not exists (select 1 from apex_application_pages
                    where application_id = 100 and page_id = 17
                      and upper(page_alias) = 'DOCUMENTOS');
/

-- R2: la region del informe es un IR y su fuente es la union de los dos modulos
-- con los filtros de siempre mas el de modulo y el de proveedor.
insert into tmp_rep_fallas
select substrb('R2: la region rep-documentos no es la union de ventas y compras', 1, 300)
  from dual
 where not exists (select 1 from apex_application_page_regions r
                    where r.application_id = 100 and r.page_id = 17
                      and r.region_static_id = 'rep-documentos'
                      and r.source_type_plugin_static_id = 'NATIVE_IR'
                      and instr(upper(r.region_source), 'UNION ALL') > 0
                      and instr(upper(r.region_source), 'FROM COMPRAS') > 0
                      and instr(upper(r.region_source), 'PROVEEDORES') > 0
                      and instr(upper(r.region_source), 'FN_ESTADO_COMPRA') > 0
                      and instr(r.region_source, 'id_factura_origen') > 0
                      and instr(r.region_source, 'ANULADA') > 0
                      and instr(upper(r.region_source), 'F_EMPRESA_ACTIVA') > 0
                      and instr(r.region_source, ':P17_TIPO') > 0
                      and instr(r.region_source, ':P17_INCLUIR_ANULADAS') > 0
                      and instr(r.region_source, ':P17_MODULO') > 0
                      and instr(r.region_source, ':P17_PROVEEDOR') > 0);
/

-- R3 a R9: la consulta guardada se ejecuta con los binds sustituidos.
--   R3  devuelve filas
--   R4  el saldo de cada venta cuadra con fn_saldo_factura
--   R5  las compras no traen saldo ni notas de credito
--   R6  la union trae las dos insignias (Venta y Compra)
--   R7  con modulo VENTAS no queda ninguna compra
--   R8  con modulo COMPRAS no queda ninguna venta
--   R9  el filtro de proveedor recorta solo las compras
declare
    v_sql    clob;
    v_n      number;
    v_mal    number;
    v_emp    number;
    v_prov   number;
    v_error  varchar2(300);

    function arma(p_modulo varchar2, p_proveedor varchar2) return clob is
        s clob := v_sql;
    begin
        s := replace(s, ':F_EMPRESA_ACTIVA', to_char(v_emp));
        s := replace(s, ':P17_ID_EMPRESA', 'null');
        s := replace(s, ':P17_CLIENTE', 'null');
        s := replace(s, ':P17_PROVEEDOR', p_proveedor);
        s := replace(s, ':P17_TIPO', '''TODOS''');
        s := replace(s, ':P17_DESDE', 'null');
        s := replace(s, ':P17_HASTA', 'null');
        s := replace(s, ':P17_INCLUIR_ANULADAS', '''N''');
        s := replace(s, ':P17_MODULO', '''' || p_modulo || '''');
        s := replace(s, ':APP_USER', '''ADMIN''');
        return s;
    end;
begin
    begin
        select region_source into v_sql
          from apex_application_page_regions
         where application_id = 100 and page_id = 17
           and region_static_id = 'rep-documentos';
    exception
        when no_data_found then
            insert into tmp_rep_fallas
            values (substrb('R3: no existe la region rep-documentos', 1, 300));
            v_sql := null;
    end;

    if v_sql is not null then
        -- Una empresa que tenga de las dos cosas: si no, el caso R6 no mediria.
        begin
            select max(id_empresa) into v_emp
              from (select id_empresa from facturas
                    intersect
                    select id_empresa from compras);
        exception
            when others then v_emp := null;
        end;
        if v_emp is null then
            select min(id_empresa) into v_emp from empresas;
        end if;
        select min(id_proveedor) into v_prov from proveedores where id_empresa = v_emp;

        begin
            execute immediate 'select count(*) from (' || arma('TODOS', 'null') || ')'
              into v_n;
            if v_n = 0 then
                insert into tmp_rep_fallas
                values (substrb('R3: la consulta no devuelve filas para ADMIN', 1, 300));
            end if;
        exception
            when others then
                v_error := sqlerrm;
                insert into tmp_rep_fallas
                values (substrb('R3: la consulta falla: ' || v_error, 1, 300));
                v_n := 0;
        end;

        if v_n > 0 then
            begin
                execute immediate
                    'select count(*) from (' || arma('TODOS', 'null') || ') where saldo is not null '
                    || 'and abs(saldo - fn_saldo_factura(ver_venta)) > 0.01' into v_mal;
                if v_mal > 0 then
                    insert into tmp_rep_fallas
                    values (substrb('R4: ' || v_mal || ' fila(s) con saldo <> fn_saldo_factura', 1, 300));
                end if;
            exception
                when others then
                    v_error := substrb(sqlerrm, 1, 280);
                    insert into tmp_rep_fallas
                    values (substrb('R4: no se pudo comparar el saldo: ' || v_error, 1, 300));
            end;

            begin
                execute immediate
                    'select count(*) from (' || arma('TODOS', 'null') || ') '
                    || 'where modulo = ''Compra'' and (saldo is not null or notas_credito is not null)'
                  into v_mal;
                if v_mal > 0 then
                    insert into tmp_rep_fallas
                    values (substrb('R5: ' || v_mal || ' compra(s) con saldo o notas de credito', 1, 300));
                end if;
            exception
                when others then
                    v_error := substrb(sqlerrm, 1, 280);
                    insert into tmp_rep_fallas
                    values (substrb('R5: no se pudo mirar el saldo de las compras: ' || v_error, 1, 300));
            end;

            begin
                execute immediate
                    'select count(distinct modulo) from (' || arma('TODOS', 'null') || ')'
                  into v_mal;
                if v_mal < 2 then
                    insert into tmp_rep_fallas
                    values (substrb('R6: la union no trae las dos insignias (Venta y Compra)', 1, 300));
                end if;
            exception
                when others then
                    v_error := substrb(sqlerrm, 1, 280);
                    insert into tmp_rep_fallas
                    values (substrb('R6: no se pudo contar los modulos: ' || v_error, 1, 300));
            end;

            begin
                execute immediate
                    'select count(*) from (' || arma('VENTAS', 'null') || ') where modulo <> ''Venta'''
                  into v_mal;
                if v_mal > 0 then
                    insert into tmp_rep_fallas
                    values (substrb('R7: con modulo VENTAS quedan ' || v_mal || ' filas de compra', 1, 300));
                end if;
            exception
                when others then
                    v_error := substrb(sqlerrm, 1, 280);
                    insert into tmp_rep_fallas
                    values (substrb('R7: el filtro de modulo no se pudo probar: ' || v_error, 1, 300));
            end;

            begin
                execute immediate
                    'select count(*) from (' || arma('COMPRAS', 'null') || ') where modulo <> ''Compra'''
                  into v_mal;
                if v_mal > 0 then
                    insert into tmp_rep_fallas
                    values (substrb('R8: con modulo COMPRAS quedan ' || v_mal || ' filas de venta', 1, 300));
                end if;
            exception
                when others then
                    v_error := substrb(sqlerrm, 1, 280);
                    insert into tmp_rep_fallas
                    values (substrb('R8: el filtro de modulo no se pudo probar: ' || v_error, 1, 300));
            end;

            if v_prov is not null then
                begin
                    execute immediate
                        'select count(*) from (' || arma('COMPRAS', to_char(v_prov)) || ') '
                        || 'where ver_compra is null' into v_mal;
                    if v_mal > 0 then
                        insert into tmp_rep_fallas
                        values (substrb('R9: el filtro de proveedor no recorta las compras', 1, 300));
                    end if;
                exception
                    when others then
                        v_error := substrb(sqlerrm, 1, 280);
                        insert into tmp_rep_fallas
                        values (substrb('R9: el filtro de proveedor falla: ' || v_error, 1, 300));
                end;
            end if;
        end if;
    end if;
end;
/

-- R10: en los datos hay al menos una factura con notas (si no, R4 no mide nada).
insert into tmp_rep_fallas
select substrb('R10: ninguna factura con notas en los datos (no se puede probar el saldo)', 1, 300)
  from dual
 where not exists (select 1 from facturas f
                    where f.tipo_documento = 'FAC'
                      and exists (select 1 from facturas n
                                   where n.id_factura_origen = f.id_factura
                                     and n.id_empresa = f.id_empresa
                                     and n.tipo_documento = 'NC'
                                     and n.estado <> 'ANULADA'));
/

-- R11: el filtro de anuladas existe en las DOS ramas de la union.
insert into tmp_rep_fallas
select substrb('R11: falta el filtro de anuladas en alguna rama de la union', 1, 300)
  from dual
 where not exists (select 1 from apex_application_page_regions r
                    where r.application_id = 100 and r.page_id = 17
                      and r.region_static_id = 'rep-documentos'
                      and instr(r.region_source, 'P17_INCLUIR_ANULADAS') > 0
                      and instr(r.region_source, 'co.estado <> ''ANULADA''') > 0
                      and instr(r.region_source, 'f.estado <> ''ANULADA''') > 0);
/

-- R12: el item de modulo, sus tres opciones y su propia accion de cambio (una
-- accion por item: una DA no puede escuchar varios).
insert into tmp_rep_fallas
select substrb('R12: falta el item P17_MODULO con sus tres opciones', 1, 300)
  from dual
 where not exists (select 1 from apex_application_page_items
                    where application_id = 100 and page_id = 17
                      and item_name = 'P17_MODULO'
                      and display_as = 'Select List'
                      and instr(lov_definition, 'TODOS') > 0
                      and instr(lov_definition, 'VENTAS') > 0
                      and instr(lov_definition, 'COMPRAS') > 0);
/

insert into tmp_rep_fallas
select substrb('R12: el cambio de modulo no tiene su accion propia', 1, 300)
  from dual
 where not exists (select 1 from apex_application_page_da d
                    where d.application_id = 100 and d.page_id = 17
                      and d.when_element = 'P17_MODULO'
                      and upper(d.when_event_name) = 'CHANGE')
   or not exists (select 1 from apex_application_page_da d
                   where d.application_id = 100 and d.page_id = 17
                     and d.when_element = 'P17_PROVEEDOR'
                     and upper(d.when_event_name) = 'CHANGE');
/

-- R13: la LOV de proveedor filtra por la empresa activa.
insert into tmp_rep_fallas
select substrb('R13: la LOV de proveedor no filtra por la empresa activa', 1, 300)
  from dual
 where not exists (select 1 from apex_application_page_items
                    where application_id = 100 and page_id = 17
                      and item_name = 'P17_PROVEEDOR'
                      and instr(upper(lov_definition), 'PROVEEDORES') > 0
                      and instr(upper(lov_definition), 'F_EMPRESA_ACTIVA') > 0);
/

-- R14: la columna de modulo se pinta como insignia y el CSS de las dos clases
-- esta en la pagina (la pagina 0 no emite CSS).
insert into tmp_rep_fallas
select substrb('R14: la columna Modulo no se pinta como insignia', 1, 300)
  from dual
 where not exists (select 1 from apex_application_page_ir_col
                    where application_id = 100 and page_id = 17
                      and column_alias = 'MODULO'
                      and instr(upper(html_expression), 'STATUS-BADGE') > 0
                      and instr(html_expression, '#MODULO#') > 0);
/

insert into tmp_rep_fallas
select substrb('R14: falta el CSS de las insignias Venta/Compra', 1, 300)
  from dual
 where not exists (select 1 from apex_application_pages
                    where application_id = 100 and page_id = 17
                      and instr(inline_css, '.status-Venta') > 0
                      and instr(inline_css, '.status-Compra') > 0);
/

-- R15: los enlaces. Desde el 2026-11-25 hay UNA sola columna «Ver» (VER_VENTA) cuyo destino sale
-- de la fila (#VER_PAG#, #VER_ITEMS#, #VER_VALS#): la venta abre la 9 en modo consulta y la compra
-- la 28. Se comprueba el enlace sustituido y que la consulta arme esos destinos.
insert into tmp_rep_fallas
select substrb('R15: la columna Ver no toma la pagina de la fila (#VER_PAG#)', 1, 300)
  from dual
 where not exists (select 1 from apex_application_page_ir_col
                    where application_id = 100 and page_id = 17
                      and column_alias = 'VER_VENTA'
                      and instr(column_link, '#VER_PAG#') > 0
                      and instr(column_link, '#VER_ITEMS#') > 0);
/

insert into tmp_rep_fallas
select substrb('R15: la consulta no lleva la venta a la 9 en modo consulta y la compra a la 28', 1, 300)
  from dual
 where not exists (select 1 from apex_application_page_regions
                    where application_id = 100 and page_id = 17
                      and instr(region_source, 'P9_ID_FACTURA,P9_MODO_VER') > 0
                      and instr(region_source, 'P28_ID_COMPRA') > 0);
/

insert into tmp_rep_fallas
select substrb('R15: el «Imprimir» no abre la 11', 1, 300)
  from dual
 where not exists (select 1 from apex_application_page_ir_col
                    where application_id = 100 and page_id = 17
                      and column_alias = 'IMPRIMIR'
                      and instr(column_link, ':11:') > 0
                      and instr(column_link, 'P11_ID_FACTURA') > 0);
/

-- R16: guarda de rol.
insert into tmp_rep_fallas
select substrb('R16: falta la guarda de rol del reporte', 1, 300)
  from dual
 where not exists (select 1 from apex_application_page_proc p
                    where p.application_id = 100 and p.page_id = 17
                      and p.process_point_code = 'BEFORE_HEADER'
                      and upper(p.process_name) like 'VALIDA ROL%'
                      and instr(upper(p.process_source), 'ADMIN,GERENCIA,FACTURACION,CONSULTA,PRUEBA') > 0);
/

-- R17: la empresa del filtro se valida contra las del usuario.
insert into tmp_rep_fallas
select substrb('R17: el filtro de empresa no valida la empresa del usuario', 1, 300)
  from dual
 where not exists (select 1 from apex_application_page_proc p
                    where p.application_id = 100 and p.page_id = 17
                      and p.process_point_code = 'BEFORE_HEADER'
                      and instr(upper(p.process_source), 'FN_USUARIO_EMPRESA_VALIDA') > 0
                      and instr(upper(p.process_source), 'P17_ID_EMPRESA') > 0);
/

-- R18: el menu tiene el grupo «Reportes» y su hija «Reportes de Facturación» (17).
insert into tmp_rep_fallas
select substrb('R18: falta la entrada de menu del reporte', 1, 300)
  from dual
 where not exists (select 1
                     from apex_application_list_entries h
                     join apex_application_list_entries p
                       on p.list_entry_id = h.list_entry_parent_id
                      and p.application_id = h.application_id
                    where h.application_id = 100 and h.entry_target like '%:17:%'
                      and upper(h.entry_text) like 'REPORTES DE FACTURACI%'
                      and upper(p.entry_text) = 'REPORTES');
/

-- R19: «Ver» abre la factura en modo consulta y la pagina 9 lo respeta.
insert into tmp_rep_fallas
select substrb('R19: la pagina 9 no tiene P9_MODO_VER', 1, 300)
  from dual
 where not exists (select 1 from apex_application_page_items
                    where application_id = 100 and page_id = 9 and item_name = 'P9_MODO_VER');
/

insert into tmp_rep_fallas
select substrb('R19: el boton ' || button_name || ' no respeta el modo consulta', 1, 300)
  from apex_application_page_buttons
 where application_id = 100 and page_id = 9
   and button_name in ('BTN_GUARDAR', 'BTN_CANCELAR', 'BTN_TRAER')
   and instr(nvl(condition_expression1, '#'), 'P9_MODO_VER') = 0;
/

-- R20: la region de totales suma por modulo y por moneda, con los filtros del
-- informe (incluido el de modulo).
insert into tmp_rep_fallas
select substrb('R20: falta la region rep-totales o no suma por modulo y moneda', 1, 300)
  from dual
 where not exists (select 1 from apex_application_page_regions
                    where application_id = 100 and page_id = 17
                      and region_static_id = 'rep-totales'
                      and instr(upper(region_source), 'GROUP BY COD_MONEDA') > 0
                      and instr(upper(region_source), 'UNION ALL') > 0
                      and instr(upper(region_source), 'COMPRAS') > 0
                      and instr(region_source, ':P17_MODULO') > 0
                      and instr(region_source, ':P17_PROVEEDOR') > 0
                      and instr(region_source, ':P17_DESDE') > 0
                      and instr(region_source, ':P17_INCLUIR_ANULADAS') > 0);
/

declare
    v_fallas number;
    v_lista  varchar2(2000);
begin
    select count(*) into v_fallas from tmp_rep_fallas;
    select substrb(listagg(caso, ' | ' on overflow truncate) within group (order by caso), 1, 2000)
      into v_lista
      from tmp_rep_fallas;
    execute immediate 'drop table tmp_rep_fallas purge';
    raise_application_error(-20100, substrb('RESULTADO: FALLAS=' || v_fallas || ' | ' || v_lista, 1, 2000));
end;
/
