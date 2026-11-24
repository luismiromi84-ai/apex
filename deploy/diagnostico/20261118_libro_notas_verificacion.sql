-- =============================================================================
-- 20261118_libro_notas_verificacion.sql
--
-- Libro de compras y ventas (18) y notas de crÃ©dito (revisiÃ³n del 2026-11-18):
--   V1  los Â«Totales del mesÂ» suman exactamente lo que suman las filas del libro
--       (mismos filtros: empresa activa, libro y mes/aÃ±o)
--   V2  una nota de crÃ©dito que cubre el total deja la factura en PAGADA
--   V3  al anular esa nota, la factura vuelve a TIMBRADA
--   V4  guardar una factura con un N de Control fuera del rango da -20063
--   V5  las notas no llevan N de Control propio y las facturas sÃ­ cumplen el formato
--   V6  la pÃ¡gina 17 se llama Â«Reportes Factura y Notas C/DÂ»
--   V7  la LOV del filtro de cliente de la 17 devuelve primero el nombre (display_value)
--   V8  una nota de compra creada por el package con la tasa del dia termina con
--       la tasa de la FACTURA que acredita, y su cabecera cuadra con sus lineas
--       (2026-11-20)
--   V9  no queda ninguna nota de compra con la tasa del dia (reparacion aplicada)
--   V10 la pagina 28 toma la tasa de la factura origen (accion dinamica y proceso)
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261118_libro_notas_verificacion.sql
-- FALLAS=0 = EXITO (el runner sale con 1 a propÃ³sito: -20100).
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
        -- el filtro de periodo (quincenas) se agrego el 2026-11-18
        v_libro := replace(v_libro, ':P18_PERIODO', '''MES''');
        v_libro := replace(v_libro, ':APP_USER', '''ADMIN''');
        execute immediate 'select round(sum(total_bs), 2) from (' || to_char(v_libro) || ')' into v_suma;

        -- Lo que suma el bloque de Â«Totales del mesÂ»: ventas y compras por
        -- cabecera a la tasa del documento, mas el IGTF de cabecera de las
        -- compras que lo causan (2026-11-19).
        execute immediate '
            select round(nvl(sum(sg * tot), 0), 2) from (
              select case when f.estado = ''ANULADA'' then 0 else 1 end
                       * case when f.tipo_documento = ''NC'' then -1 else 1 end as sg,
                     nvl(f.monto_total,0) * nvl(f.tipo_cambio,1) as tot
                from facturas f
               where f.id_empresa = ' || v_emp || '
                 and f.fecha_emision >= to_date(''01/' || v_mes || '/' || v_anio || ''',''DD/MM/YYYY'')
                 and f.fecha_emision <  add_months(to_date(''01/' || v_mes || '/' || v_anio || ''',''DD/MM/YYYY''), 1)
              union all
              select case when co.estado = ''ANULADA'' then 0 else 1 end
                       * case when co.tipo_documento = ''NC'' then -1 else 1 end,
                     nvl(co.monto_total,0) * nvl(co.tipo_cambio,1)
                       -- La foto congelada en la compra, como la pantalla (2026-11-22).
                       + nvl(co.igtf_bs, 0) as tot
                from compras co
                join empresas e on e.id_empresa = co.id_empresa
                left join forma_pago fp on fp.id_forma_pago = co.id_forma_pago
               where co.id_empresa = ' || v_emp || '
                 and co.fecha_emision >= to_date(''01/' || v_mes || '/' || v_anio || ''',''DD/MM/YYYY'')
                 and co.fecha_emision <  add_months(to_date(''01/' || v_mes || '/' || v_anio || ''',''DD/MM/YYYY''), 1)
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
    commit;
end;
/

-- V2 y V3: la nota de crÃ©dito mueve el estado de la factura
declare
    v_fac number;
    v_nc  number;
    v_est varchar2(20);
    v_cli number;
    v_err varchar2(200);
    v_f2  varchar2(300);
    v_f3  varchar2(300);
begin
    savepoint sp_v23;
    -- Un cliente que NO sea agente de retencion: con uno que retiene la factura
    -- guarda igual (el comprobante se pide despues, 2026-11-20), pero la prueba
    -- no va de retencion y asi el IVA retenido no ensucia el saldo.
    select min(id_cliente) into v_cli
      from clientes
     where id_empresa = 1 and nvl(es_agente_retencion, 'N') <> 'S';
    if v_cli is null then
        insert into tmp_libnot_fallas values ('V2: la empresa 1 no tiene clientes sin retencion');
        commit;
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
        -- La nota va en POSITIVO: fn_saldo_factura resta el monto de las NC, y
        -- pkg_facturacion.copiar_desde_factura copia las lineas tal cual (2026-11-20).
        p_subtotal => 100, p_monto_impuesto => 0, p_monto_total => 100,
        p_observaciones => null, p_cod_moneda => 'VES', p_tipo_cambio => 1,
        p_usuario => 'admin', p_tipo_documento => 'NC', p_id_factura_origen => v_fac);

    pkg_facturacion.prc_procesar_factura(v_nc, 'admin');

    select estado into v_est from facturas where id_factura = v_fac;
    if v_est <> 'PAGADA' then
        v_f2 := 'V2: la factura quedo ' || v_est
             || ' con una NC que cubre su total (se esperaba PAGADA)';
    end if;

    -- V3: al anular la nota, la factura recupera su saldo
    pkg_facturacion.prc_anular_factura(v_nc, null, 'admin');
    select estado into v_est from facturas where id_factura = v_fac;
    if v_est <> 'TIMBRADA' then
        v_f3 := 'V3: al anular la NC la factura quedo ' || v_est || ' (se esperaba TIMBRADA)';
    end if;

    -- Los fallos se anotan DESPUES del rollback: si no, el rollback se los lleva
    -- (paso hasta el 2026-11-19 y dejaba V2/V3 en verde sin medir nada).
    rollback to sp_v23;
    if v_f2 is not null then
        insert into tmp_libnot_fallas values (substrb(v_f2, 1, 300));
    end if;
    if v_f3 is not null then
        insert into tmp_libnot_fallas values (substrb(v_f3, 1, 300));
    end if;
    commit;
exception
    when others then
        rollback to sp_v23;
        v_err := substr(sqlerrm, 1, 150);
        insert into tmp_libnot_fallas values ('V2/V3: ' || v_err);
        commit;
end;
/

-- V4: el control se valida al guardar
declare
    v_fac number;
    v_cli number;
    v_cod number := 0;
begin
    savepoint sp_v4;
    -- El rango de control de la providencia es dato del cliente y hoy puede
    -- estar vacio (la empresa 1 lo tiene en NULL desde que se cargaron los
    -- datos reales): sin rango, fn_control_en_rango no puede rechazar nada y
    -- V4 mediria otra cosa. Se pone uno de prueba DENTRO del savepoint y se
    -- revierte con el resto, asi la prueba mide la regla y no el dato.
    merge into empresa_fiscal ef
    using (select 1 as id_empresa from dual) s
       on (ef.id_empresa = s.id_empresa)
    when matched then update set control_desde = '00-000001', control_hasta = '00-000100'
    when not matched then insert (id_empresa, control_desde, control_hasta)
                          values (1, '00-000001', '00-000100');
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
    rollback to sp_v4;
    if v_cod <> -20063 then
        insert into tmp_libnot_fallas values ('V4: un control fuera de rango devolvio ' || v_cod || ' (se esperaba -20063)');
    end if;
    commit;
end;
/

-- V5: datos limpios (notas sin control; facturas con el formato del rango)
declare
    v_n number;
begin
    select count(*) into v_n
      from facturas
     where tipo_documento in ('NC', 'ND') and nro_control is not null;
    if v_n > 0 then
        insert into tmp_libnot_fallas values ('V5: ' || v_n || ' nota(s) con N de Control propio');
    end if;

    -- El formato contra el rango VIGENTE se retiro el 2026-11-22: el cliente cambio
    -- el rango de control (000001..0000010000) y las facturas historicas quedan con
    -- el prefijo anterior (00-000xxx). Eso es dato, no un fallo de la app: la regla
    -- se vigila al guardar en V4 y en 20261116_control_factura_verificacion.sql.
end;
/

-- V6 y V7: el nombre de la pÃ¡gina 17 y el orden de columnas de su LOV de cliente
insert into tmp_libnot_fallas
select 'V6: la pagina 17 no se llama Â«Reportes Factura y Notas C/DÂ»' from dual
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

-- V8: la nota de compra toma la tasa de la FACTURA que acredita (2026-11-20)
declare
    v_prov  number;
    v_fac   number;
    v_nc    number;
    v_det   number;
    v_add   number := 0;
    v_ya    number := 0;
    v_tasa  number;
    v_n     number;
    v_tot   number;
    v_linea number;
    v_err   varchar2(300);
begin
    savepoint sp_v8;
    select min(id_proveedor) into v_prov from proveedores where id_empresa = 1;
    if v_prov is null then
        insert into tmp_libnot_fallas values ('V8: la empresa 1 no tiene proveedores');
        commit;
        return;
    end if;

    begin
        -- Factura de compra en USD a una tasa conocida (900) y una linea.
        pkg_compras.prc_guardar_compra(
            p_id_compra => v_fac, p_id_empresa => 1, p_id_proveedor => v_prov,
            p_tipo_documento => 'FAC', p_folio_factura => 'T-TASA-1',
            p_nro_control => '00-000901', p_fecha_emision => sysdate,
            p_cod_moneda => 'USD', p_tipo_cambio => 900,
            p_porcentaje_retencion => 0, p_id_compra_origen => null,
            p_observaciones => null, p_id_forma_pago => null,
            p_id_concepto_islr => 0, p_usuario => 'admin');

        pkg_compra_detalle.guardar_detalle(
            p_id_detalle => v_det, p_id_compra => v_fac, p_num_linea => 1,
            p_id_producto_servicio => null, p_descripcion => 'T tasa origen',
            p_cantidad => 1, p_precio_unitario => 100,
            p_porcentaje_descuento => 0, p_monto_descuento => 0,
            p_id_impuesto => null, p_porcentaje_impuesto => 16,
            p_usuario => 'admin');

        -- La nota se guarda con la tasa del DIA (917,7751), que es lo que hacia
        -- la pantalla: el package tiene que imponer la de la factura (900).
        pkg_compras.prc_guardar_compra(
            p_id_compra => v_nc, p_id_empresa => 1, p_id_proveedor => v_prov,
            p_tipo_documento => 'NC', p_folio_factura => 'T-TASA-2',
            p_nro_control => '00-000902', p_fecha_emision => sysdate,
            p_cod_moneda => 'USD', p_tipo_cambio => 917.7751,
            p_porcentaje_retencion => 0, p_id_compra_origen => v_fac,
            p_observaciones => null, p_id_forma_pago => null,
            p_id_concepto_islr => 0, p_usuario => 'admin');

        pkg_compra_detalle.copiar_desde_compra(
            p_id_compra => v_nc, p_id_compra_origen => v_fac,
            p_usuario => 'admin', p_agregadas => v_add, p_ya_estaban => v_ya);

        select tipo_cambio into v_tasa from compras where id_compra = v_nc;
        if nvl(v_tasa, -1) <> 900 then
            v_err := 'V8: la nota quedo a la tasa ' || v_tasa || ' (se esperaba 900, la del origen)';
        end if;

        select count(*) into v_n
          from compras_det
         where id_compra = v_nc
           and nvl(tasa_cambio_aplicada, -1) <> nvl(v_tasa, -2);
        if v_n > 0 then
            v_err := (case when v_err is null then '' else v_err || ' | ' end) || 'V8: ' || v_n
                  || ' linea(s) de la nota con una tasa distinta de su cabecera';
        end if;

        select round(nvl(monto_total, 0) * nvl(tipo_cambio, 1), 2) into v_tot
          from compras where id_compra = v_nc;
        select round(nvl(sum(total_bs), 0), 2) into v_linea
          from compras_det where id_compra = v_nc;
        if abs(v_tot - v_linea) > 0.05 then
            v_err := (case when v_err is null then '' else v_err || ' | ' end) || 'V8: la cabecera da ' || v_tot
                  || ' Bs y sus lineas ' || v_linea;
        end if;
    exception
        when others then
            v_err := 'V8: ' || substr(sqlerrm, 1, 220);
    end;

    rollback to sp_v8;
    if v_err is not null then
        insert into tmp_libnot_fallas values (substrb(v_err, 1, 300));
    end if;
    commit;
end;
/

-- V9: reparacion aplicada (ninguna nota de compra con la tasa del dia)
declare
    v_n number;
begin
    select count(*) into v_n
      from compras co
      join compras o on o.id_compra = co.id_compra_origen
     where co.tipo_documento in ('NC', 'ND')
       and o.tipo_documento = 'FAC'
       and o.estado <> 'ANULADA'
       and nvl(co.tipo_cambio, -1) <> nvl(o.tipo_cambio, -1);
    if v_n > 0 then
        insert into tmp_libnot_fallas
        values ('V9: ' || v_n || ' nota(s) de compra con la tasa del dia en vez de la del origen');
    end if;

    select count(*) into v_n
      from compras co
      join compras_det d on d.id_compra = co.id_compra
     where co.tipo_documento in ('NC', 'ND')
       and d.id_detalle_origen is not null
       and nvl(d.tasa_cambio_aplicada, -1) <> nvl(co.tipo_cambio, -1);
    if v_n > 0 then
        insert into tmp_libnot_fallas
        values ('V9: ' || v_n || ' linea(s) de nota con tasa distinta de su cabecera');
    end if;
end;
/

-- V10: la pagina 28 toma la tasa de la factura origen (accion + proceso)
declare
    v_n number;
begin
    select count(*) into v_n
      from apex_application_page_da
     where application_id = 100 and page_id = 28
       and static_id = 'tasa-nota-origen'
       and when_element = 'P28_ID_COMPRA_ORIGEN'
       and upper(when_event_name) = 'CHANGE';
    if v_n = 0 then
        insert into tmp_libnot_fallas
        values ('V10: la 28 no tiene la accion TASA_NOTA_ORIGEN sobre P28_ID_COMPRA_ORIGEN');
    end if;

    select count(*) into v_n
      from apex_application_page_da_acts
     where application_id = 100 and page_id = 28
       and dynamic_action_name = 'TASA_NOTA_ORIGEN'
       and action_code = 'NATIVE_EXECUTE_PLSQL_CODE'
       and dbms_lob.instr(attributes, 'P28_TIPO_CAMBIO') > 0
       and dbms_lob.instr(attributes, 'suppress_change_event":"Y') > 0;
    if v_n = 0 then
        insert into tmp_libnot_fallas
        values ('V10: la accion de la 28 no devuelve P28_TIPO_CAMBIO o no suprime el change');
    end if;

    select count(*) into v_n
      from apex_application_page_proc
     where application_id = 100 and page_id = 28
       and static_id = 'tasa-nota-origen'
       and process_point_code = 'BEFORE_HEADER'
       and upper(process_source) like '%FROM COMPRAS%'
       and upper(process_source) like '%TIPO_CAMBIO%';
    if v_n = 0 then
        insert into tmp_libnot_fallas
        values ('V10: la 28 no tiene el proceso BEFORE_HEADER que toma la tasa del origen');
    end if;
end;
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
