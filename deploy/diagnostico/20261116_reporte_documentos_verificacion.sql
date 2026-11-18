-- =============================================================================
-- 20261116_reporte_documentos_verificacion.sql
--
-- Verificacion del reporte «Facturas y notas» (pagina 17). Se ejecuta de arriba
-- a abajo, como las demas:
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

-- R2: la region del informe es un IR y su fuente trae el saldo y los filtros.
insert into tmp_rep_fallas
select substrb('R2: la region rep-documentos no es un IR con la consulta esperada', 1, 300)
  from dual
 where not exists (select 1 from apex_application_page_regions r
                    where r.application_id = 100 and r.page_id = 17
                      and r.region_static_id = 'rep-documentos'
                      and r.source_type_plugin_static_id = 'NATIVE_IR'
                      and instr(r.region_source, 'id_factura_origen') > 0
                      and instr(r.region_source, 'ANULADA') > 0
                      and instr(upper(r.region_source), 'F_EMPRESA_ACTIVA') > 0
                      and instr(r.region_source, ':P17_TIPO') > 0
                      and instr(r.region_source, ':P17_INCLUIR_ANULADAS') > 0);
/

-- R3 y R4: la consulta guardada se ejecuta con los binds sustituidos y el saldo
-- de TODAS las filas cuadra con fn_saldo_factura (total - notas timbradas - cobros).
declare
    v_sql    clob;
    v_n      number;
    v_mal    number;
    v_emp    number;
    v_error  varchar2(300);
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
        -- La empresa activa manda (plan empresa-activa, tarea 3): la consulta ya no
        -- filtra por «todas mis empresas» sino por el ítem de aplicación.
        select min(id_empresa) into v_emp from facturas;
        v_sql := replace(v_sql, ':F_EMPRESA_ACTIVA', to_char(nvl(v_emp, 0)));
        v_sql := replace(v_sql, ':P17_ID_EMPRESA', 'null');
        v_sql := replace(v_sql, ':P17_CLIENTE', 'null');
        v_sql := replace(v_sql, ':P17_TIPO', '''TODOS''');
        v_sql := replace(v_sql, ':P17_DESDE', 'null');
        v_sql := replace(v_sql, ':P17_HASTA', 'null');
        v_sql := replace(v_sql, ':P17_INCLUIR_ANULADAS', '''N''');
        v_sql := replace(v_sql, ':APP_USER', '''ADMIN''');

        begin
            execute immediate 'select count(*) from (' || v_sql || ')' into v_n;
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
                    'select count(*) from (' || v_sql || ') where saldo is not null '
                    || 'and abs(saldo - fn_saldo_factura(detalle_link)) > 0.01' into v_mal;
                if v_mal > 0 then
                    insert into tmp_rep_fallas
                    values (substrb('R4: ' || v_mal || ' fila(s) con saldo <> fn_saldo_factura', 1, 300));
                end if;
            exception
                when others then
                    v_error := sqlerrm;
                    insert into tmp_rep_fallas
                    values (substrb('R4: no se pudo comparar el saldo: ' || v_error, 1, 300));
            end;
        end if;
    end if;
end;
/

-- R5: en el resultado hay al menos una factura con notas y su saldo cuadra.
insert into tmp_rep_fallas
select substrb('R5: ninguna factura con notas en los datos (no se puede probar el saldo)', 1, 300)
  from dual
 where not exists (select 1 from facturas f
                    where f.tipo_documento = 'FAC'
                      and exists (select 1 from facturas n
                                   where n.id_factura_origen = f.id_factura
                                     and n.id_empresa = f.id_empresa
                                     and n.tipo_documento = 'NC'
                                     and n.estado <> 'ANULADA'));
/

-- R6: el filtro de anuladas existe y su expresion es la esperada.
insert into tmp_rep_fallas
select substrb('R6: falta el filtro de anuladas en la consulta', 1, 300)
  from dual
 where not exists (select 1 from apex_application_page_regions r
                    where r.application_id = 100 and r.page_id = 17
                      and r.region_static_id = 'rep-documentos'
                      and instr(r.region_source, 'P17_INCLUIR_ANULADAS') > 0
                      and instr(r.region_source, '''S''') > 0);
/

-- R7: guarda de rol.
insert into tmp_rep_fallas
select substrb('R7: falta la guarda de rol del reporte', 1, 300)
  from dual
 where not exists (select 1 from apex_application_page_proc p
                    where p.application_id = 100 and p.page_id = 17
                      and p.process_point_code = 'BEFORE_HEADER'
                      and upper(p.process_name) like 'VALIDA ROL%'
                      and instr(upper(p.process_source), 'ADMIN,GERENCIA,FACTURACION,CONSULTA,PRUEBA') > 0);
/

-- R8: la empresa del filtro se valida contra las del usuario.
insert into tmp_rep_fallas
select substrb('R8: el filtro de empresa no valida la empresa del usuario', 1, 300)
  from dual
 where not exists (select 1 from apex_application_page_proc p
                    where p.application_id = 100 and p.page_id = 17
                      and p.process_point_code = 'BEFORE_HEADER'
                      and instr(upper(p.process_source), 'FN_USUARIO_EMPRESA_VALIDA') > 0
                      and instr(upper(p.process_source), 'P17_ID_EMPRESA') > 0);
/

-- R9: entrada de menu «Reportes Factura y Notas C/D» (antes «Facturas y notas»).
insert into tmp_rep_fallas
select substrb('R9: falta la entrada de menu del reporte', 1, 300)
  from dual
 where not exists (select 1 from apex_application_list_entries
                    where application_id = 100 and entry_target like '%:17:%'
                      and upper(entry_text) like '%REPORTES FACTURA Y NOTAS C/D%');
/

-- R10: «Ver» abre la factura en modo consulta y la pagina 9 lo respeta.
insert into tmp_rep_fallas
select substrb('R10: la pagina 9 no tiene P9_MODO_VER', 1, 300)
  from dual
 where not exists (select 1 from apex_application_page_items
                    where application_id = 100 and page_id = 9 and item_name = 'P9_MODO_VER');
/

insert into tmp_rep_fallas
select substrb('R10: el boton ' || button_name || ' no respeta el modo consulta', 1, 300)
  from apex_application_page_buttons
 where application_id = 100 and page_id = 9
   and button_name in ('BTN_GUARDAR', 'BTN_CANCELAR', 'BTN_TRAER')
   and instr(nvl(condition_expression1, '#'), 'P9_MODO_VER') = 0;
/

insert into tmp_rep_fallas
select substrb('R10: el proceso ' || process_name || ' no respeta el modo consulta', 1, 300)
  from apex_application_page_proc
 where application_id = 100 and page_id = 9
   and process_name in ('Insert/update Facturacion', 'Elimiar factura', 'Traer todas las lineas')
   and instr(nvl(process_source, '#'), 'P9_MODO_VER') = 0;
/

-- R11: la pagina 9 muestra el detalle de la factura y el boton de imprimir.
insert into tmp_rep_fallas
select substrb('R11: falta la region detalle-factura en la 9', 1, 300)
  from dual
 where not exists (select 1 from apex_application_page_regions
                    where application_id = 100 and page_id = 9
                      and region_static_id = 'detalle-factura'
                      and instr(upper(region_source), 'FACTURAS_DET') > 0);
/

insert into tmp_rep_fallas
select substrb('R11: falta el boton Imprimir en la 9', 1, 300)
  from dual
 where not exists (select 1 from apex_application_page_buttons
                    where application_id = 100 and page_id = 9
                      and button_name = 'BTN_IMPRIMIR_FACTURA'
                      and instr(nvl(redirect_url, '#'), 'P11_ID_FACTURA') > 0);
/

-- R12: la region de totales del periodo existe y trae los filtros y las sumas.
insert into tmp_rep_fallas
select substrb('R12: falta la region rep-totales', 1, 300)
  from dual
 where not exists (select 1 from apex_application_page_regions
                    where application_id = 100 and page_id = 17
                      and region_static_id = 'rep-totales'
                      and instr(upper(region_source), 'GROUP BY F.COD_MONEDA') > 0
                      and instr(upper(region_source), '''NC''  THEN -F.MONTO_TOTAL') > 0
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
