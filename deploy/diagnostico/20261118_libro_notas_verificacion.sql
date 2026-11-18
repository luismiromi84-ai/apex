-- =============================================================================
-- 20261118_libro_notas_verificacion.sql
--
-- Libro de compras y ventas (18) y notas de crédito (revisión del 2026-11-18):
--   V1  los «Totales del mes» suman exactamente lo que suman las filas del libro
--       (mismos filtros: empresa activa, libro y mes/año)
--   V2  una nota de crédito que cubre el total deja la factura en PAGADA
--   V3  al anular esa nota, la factura vuelve a TIMBRADA
--   V4  guardar una factura con un N de Control fuera del rango da -20063
--   V5  las notas no llevan N de Control propio y las facturas sí cumplen el formato
--   V6  la página 17 se llama «Reportes Factura y Notas C/D»
--   V7  la LOV del filtro de cliente de la 17 devuelve primero el nombre (display_value)
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261118_libro_notas_verificacion.sql
-- FALLAS=0 = EXITO (el runner sale con 1 a propósito: -20100).
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

begin
    begin execute immediate 'drop table tmp_libnot_fallas purge'; exception when others then null; end;
end;
/

create table tmp_libnot_fallas (caso varchar2(300))
/

-- V1: los totales del mes suman lo mismo que las filas del libro
declare
    v_libro clob;
    v_mes   varchar2(2);
    v_anio  varchar2(4);
    v_emp   number;
    v_suma  number;
    v_totbs number;
    v_err   varchar2(200);
begin
    begin
        select min(id_empresa) into v_emp from facturas;
    exception when others then v_emp := null;
    end;
    if v_emp is null then
        insert into tmp_libnot_fallas values ('V1: no hay facturas para medir');
        return;
    end if;

    select to_char(min(fecha_emision), 'MM'), to_char(min(fecha_emision), 'YYYY')
      into v_mes, v_anio from facturas where id_empresa = v_emp;

    select region_source into v_libro
      from apex_application_page_regions
     where application_id = 100 and page_id = 18 and region_id = 43000000000000710;

    begin
        -- suma de la columna TOTAL_BS de las filas que pinta el libro
        v_libro := replace(v_libro, ':F_EMPRESA_ACTIVA', to_char(v_emp));
        v_libro := replace(v_libro, ':P18_ID_EMPRESA', 'null');
        v_libro := replace(v_libro, ':P18_LIBRO', '''TODOS''');
        v_libro := replace(v_libro, ':P18_MES', v_mes);
        v_libro := replace(v_libro, ':P18_ANIO', v_anio);
        v_libro := replace(v_libro, ':APP_USER', '''ADMIN''');
        execute immediate 'select round(sum(total_bs), 2) from (' || to_char(v_libro) || ')' into v_suma;

        -- lo que suma el bloque de «Totales del mes» (cabecera x tasa, mismo filtro)
        execute immediate '
            select round(sum(sg * tot), 2) from (
              select case when f.estado = ''ANULADA'' then 0 else 1 end
                       * case when f.tipo_documento = ''NC'' then -1 else 1 end as sg,
                     nvl(f.monto_total,0) * nvl(f.tipo_cambio,1) as tot
                from facturas f
               where f.id_empresa = ' || v_emp || '
                 and f.fecha_emision >= to_date(''01/' || v_mes || '/' || v_anio || ''',''DD/MM/YYYY'')
                 and f.fecha_emision <  add_months(to_date(''01/' || v_mes || '/' || v_anio || ''',''DD/MM/YYYY''), 1)
            )' into v_totbs;

        if abs(nvl(v_suma, 0) - nvl(v_totbs, 0)) > 0.05 then
            insert into tmp_libnot_fallas
            values ('V1: las filas del libro suman ' || v_suma || ' y los totales ' || v_totbs);
        end if;
    exception
        when others then
            v_err := substr(sqlerrm, 1, 150);
            insert into tmp_libnot_fallas values ('V1: ' || v_err);
    end;
end;
/

-- V2 y V3: la nota de crédito mueve el estado de la factura
declare
    v_fac number;
    v_nc  number;
    v_est varchar2(20);
    v_cli number;
    v_err varchar2(200);
begin
    select min(id_cliente) into v_cli from clientes where id_empresa = 1;
    if v_cli is null then
        insert into tmp_libnot_fallas values ('V2: la empresa 1 no tiene clientes');
        return;
    end if;

    pkg_facturacion.prc_guardar_factura(
        p_id_factura => v_fac, p_id_empresa => 1, p_folio_factura => 'T-NC-1',
        p_id_cliente => v_cli, p_id_presupuesto => null,
        p_rfc_emisor => 'J-1', p_rfc_receptor => 'J-2', p_uuid_fiscal => null,
        p_uso_cfdi => null, p_forma_pago => null, p_metodo_pago => null,
        p_condicion_pago => null, p_fecha_emision => to_char(sysdate, 'DD/MM/YYYY'),
        p_fecha_vencimiento => null, p_estado => 'TIMBRADA',
        p_subtotal => 100, p_monto_impuesto => 0, p_monto_total => 100,
        p_observaciones => null, p_cod_moneda => 'VES', p_tipo_cambio => 1,
        p_usuario => 'admin', p_tipo_documento => 'FAC');

    pkg_facturacion.prc_guardar_factura(
        p_id_factura => v_nc, p_id_empresa => 1, p_folio_factura => 'T-NC-2',
        p_id_cliente => v_cli, p_id_presupuesto => null,
        p_rfc_emisor => 'J-1', p_rfc_receptor => 'J-2', p_uuid_fiscal => null,
        p_uso_cfdi => null, p_forma_pago => null, p_metodo_pago => null,
        p_condicion_pago => null, p_fecha_emision => to_char(sysdate, 'DD/MM/YYYY'),
        p_fecha_vencimiento => null, p_estado => 'PENDIENTE',
        p_subtotal => -100, p_monto_impuesto => 0, p_monto_total => -100,
        p_observaciones => null, p_cod_moneda => 'VES', p_tipo_cambio => 1,
        p_usuario => 'admin', p_tipo_documento => 'NC', p_id_factura_origen => v_fac);

    pkg_facturacion.prc_procesar_factura(v_nc, 'admin');

    select estado into v_est from facturas where id_factura = v_fac;
    if v_est <> 'PAGADA' then
        insert into tmp_libnot_fallas
        values ('V2: la factura quedo ' || v_est || ' con una NC que cubre su total (se esperaba PAGADA)');
    end if;

    -- V3: al anular la nota, la factura recupera su saldo
    pkg_facturacion.prc_anular_factura(v_nc, null, 'admin');
    select estado into v_est from facturas where id_factura = v_fac;
    if v_est <> 'TIMBRADA' then
        insert into tmp_libnot_fallas
        values ('V3: al anular la NC la factura quedo ' || v_est || ' (se esperaba TIMBRADA)');
    end if;

    rollback;
exception
    when others then
        rollback;
        v_err := substr(sqlerrm, 1, 150);
        insert into tmp_libnot_fallas values ('V2/V3: ' || v_err);
end;
/

-- V4: el control se valida al guardar
declare
    v_fac number;
    v_cli number;
    v_cod number := 0;
begin
    select min(id_cliente) into v_cli from clientes where id_empresa = 1;
    begin
        pkg_facturacion.prc_guardar_factura(
            p_id_factura => v_fac, p_id_empresa => 1, p_folio_factura => 'T-CTRL-1',
            p_id_cliente => v_cli, p_id_presupuesto => null,
            p_rfc_emisor => 'J-1', p_rfc_receptor => 'J-2', p_uuid_fiscal => null,
            p_uso_cfdi => null, p_forma_pago => null, p_metodo_pago => null,
            p_condicion_pago => null, p_fecha_emision => to_char(sysdate, 'DD/MM/YYYY'),
            p_fecha_vencimiento => null, p_estado => 'PENDIENTE',
            p_subtotal => 1, p_monto_impuesto => 0, p_monto_total => 1,
            p_observaciones => null, p_cod_moneda => 'VES', p_tipo_cambio => 1,
            p_usuario => 'admin', p_tipo_documento => 'FAC',
            p_nro_control => '876');
    exception
        when others then v_cod := sqlcode;
    end;
    rollback;
    if v_cod <> -20063 then
        insert into tmp_libnot_fallas values ('V4: un control fuera de rango devolvio ' || v_cod || ' (se esperaba -20063)');
    end if;
end;
/

-- V5: datos limpios (notas sin control; facturas con el formato del rango)
declare
    v_n number;
begin
    select count(*) into v_n from facturas
     where tipo_documento in ('NC', 'ND') and nro_control is not null;
    if v_n > 0 then
        insert into tmp_libnot_fallas values ('V5: ' || v_n || ' nota(s) con N de Control propio');
    end if;

    select count(*) into v_n
      from facturas f
      join empresa_fiscal ef on ef.id_empresa = f.id_empresa
     where f.tipo_documento = 'FAC'
       and ef.control_desde is not null
       and (f.nro_control is null
            or not regexp_like(f.nro_control,
                   '^' || substr(ef.control_desde, 1,
                                 length(ef.control_desde) - length(regexp_substr(ef.control_desde, '[0-9]+$')))
                   || '[0-9]{' || length(regexp_substr(ef.control_desde, '[0-9]+$')) || '}$'));
    if v_n > 0 then
        insert into tmp_libnot_fallas values ('V5: ' || v_n || ' factura(s) con el N de Control fuera de formato');
    end if;
end;
/

-- V6 y V7: el nombre de la página 17 y el orden de columnas de su LOV de cliente
insert into tmp_libnot_fallas
select 'V6: la pagina 17 no se llama «Reportes Factura y Notas C/D»' from dual
 where not exists (select 1 from apex_application_pages
                    where application_id = 100 and page_id = 17
                      and upper(page_title) = upper('Reportes Factura y Notas C/D'))
/

insert into tmp_libnot_fallas
select 'V7: la LOV del cliente de la 17 no devuelve primero el nombre' from dual
 where not exists (select 1 from apex_application_page_items
                    where application_id = 100 and item_name = 'P17_CLIENTE'
                      and regexp_like(lower(lov_definition),
                          'select\s+.*razon_social.*as\s+display_value'))
/

declare
    v_fallas number;
    v_lista  varchar2(3000);
begin
    select count(*) into v_fallas from tmp_libnot_fallas;
    select substrb(listagg(caso, ' | ' on overflow truncate) within group (order by caso), 1, 3000)
      into v_lista from tmp_libnot_fallas;
    execute immediate 'drop table tmp_libnot_fallas purge';
    raise_application_error(-20100, substrb('RESULTADO: FALLAS=' || v_fallas || ' | ' || v_lista, 1, 3000));
end;
/
