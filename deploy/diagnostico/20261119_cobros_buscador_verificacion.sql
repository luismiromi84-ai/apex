-- =============================================================================
-- 20261119_cobros_buscador_verificacion.sql
--
-- Página 24 «Cobros» convertida en buscador (2026-11-19):
--   B1  la región «Cobros» es un Interactive Report y ya no lleva
--       «fetch first 200 rows only»
--   B2  la columna «Abrir» enlaza a la 25 con #ID_RECIBO#
--   B3  los filtros existen y el de conciliado es una lista Todos/Si/No
--   B4  la consulta guardada filtra por conciliado y por texto
--       (referencia, factura, RIF y cliente)
--   B5  hay una acción de cambio por filtro (una DA no escucha varios ítems)
--   B6  se retiraron el selector de cobro y el botón «Abrir cobro»
--   B7  la guarda de rol de la página sigue puesta
--
-- Todo el DML va dentro de un SAVEPOINT y se revierte.
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261119_cobros_buscador_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

begin
    begin execute immediate 'drop table tmp_buscob_fallas purge'; exception when others then null; end;
end;
/

create table tmp_buscob_fallas (caso varchar2(300))
/

declare
    type t_lista is table of varchar2(300);
    v_fallas t_lista := t_lista();
    v_msg    varchar2(300);
    v_n      number;
    v_sql    clob;
    v_fac    number;
    v_folio  varchar2(60);
    v_rif    varchar2(60);
    v_cli    varchar2(200);
    v_txt    varchar2(200);
    v_base_t number;
    v_base_s number;
    v_base_n number;

    procedure falla(p_texto varchar2) is
    begin
        v_fallas.extend;
        v_fallas(v_fallas.count) := substrb(p_texto, 1, 300);
    end;

    function cuenta(p_valor varchar2, p_conciliado varchar2) return number is
        v_q   clob;
        v_res number;
    begin
        v_q := v_sql;
        v_q := replace(v_q, ':F_EMPRESA_ACTIVA', '1');
        v_q := replace(v_q, ':P24_ID_EMPRESA', 'null');
        v_q := replace(v_q, ':P24_DESDE', '''01/11/2026''');
        v_q := replace(v_q, ':P24_HASTA', '''30/11/2026''');
        v_q := replace(v_q, ':P24_ESTADO', '''TODOS''');
        v_q := replace(v_q, ':P24_CONCILIADO', '''' || p_conciliado || '''');
        if p_valor is null then
            v_q := replace(v_q, ':P24_BUSCAR', 'null');
        else
            v_q := replace(v_q, ':P24_BUSCAR', '''' || replace(upper(p_valor), '''', '''''') || '''');
        end if;
        execute immediate 'select count(*) from (' || v_q || ')' into v_res;
        return v_res;
    end;
begin
    savepoint sp_buscob;

    -- B1 / B2: es un IR, con la columna de enlace, y sin el tope de 200.
    select count(*) into v_n
      from apex_260100.apex_application_page_regions
     where application_id = 100 and page_id = 24 and region_static_id = 'lista-cobros'
       and source_type_plugin_static_id = 'NATIVE_IR'
       and instr(lower(region_source), 'fetch first') = 0;
    if v_n = 0 then
        falla('B1: la lista de cobros no es un IR o conserva el fetch first');
    end if;

    select count(*) into v_n
      from apex_260100.apex_application_page_ir_col
     where application_id = 100 and page_id = 24 and column_alias = 'ID_RECIBO'
       and instr(nvl(column_link, '#'), 'P25_ID_RECIBO:#ID_RECIBO#') > 0;
    if v_n = 0 then
        falla('B2: la columna Abrir no enlaza a la pagina 25');
    end if;

    -- B3: los filtros, con el de conciliado como lista estatica1.
    select count(*) into v_n
      from apex_260100.apex_application_page_items
     where application_id = 100 and page_id = 24
       and item_name in ('P24_BUSCAR', 'P24_DESDE', 'P24_HASTA', 'P24_ESTADO', 'P24_CONCILIADO');
    if v_n <> 5 then
        falla('B3: faltan filtros en la pagina 24 (hay ' || v_n || ' de 5)');
    end if;

    select count(*) into v_n
      from apex_260100.apex_application_page_items
     where application_id = 100 and page_id = 24 and item_name = 'P24_CONCILIADO'
       and lov_definition like 'STATIC2:%'
       and instr(upper(lov_definition), 'TODOS') > 0
       -- El valor de retorno sigue siendo SI; lo que lleva tilde es el rotulo
       -- («Sí»), que es lo que lee la persona. Se comprueban las dos cosas.
       and instr(upper(lov_definition), ';SI') > 0
       and instr(lov_definition, 'Sí') > 0
       and instr(upper(lov_definition), 'NO') > 0;
    if v_n = 0 then
        falla('B3: el filtro Conciliado no es la lista Todos/Si/No');
    end if;

    select region_source into v_sql
      from apex_260100.apex_application_page_regions
     where application_id = 100 and page_id = 24 and region_static_id = 'lista-cobros';

    -- B4: con dos cobros de prueba, la consulta filtra. Los conteos se miden
    -- contra la BASE (los recibos reales de la empresa 1 en el periodo): desde
    -- que el dueno cobra de verdad, esperar "2" a secas fallaba por sus cobros.
    v_base_t := cuenta(null, 'TODOS');
    v_base_s := cuenta(null, 'SI');
    v_base_n := cuenta(null, 'NO');

    select f.id_factura, f.folio_factura, c.rif, c.razon_social
      into v_fac, v_folio, v_rif, v_cli
      from facturas f join clientes c on c.id_cliente = f.id_cliente
     where f.id_empresa = 1 and f.estado <> 'ANULADA' and rownum = 1;

    insert into recibos (id_empresa, id_factura, fecha_cobro, cod_moneda, monto_cobrado,
                         monto_bs, monto_factura, monto_neto, referencia, conciliado,
                         estado, creado_por)
    values (1, v_fac, to_date('15/11/2026', 'DD/MM/YYYY'), 'USD', 100, 91574.76, 100, 100,
            'TRF-VERIF-1', 'S', 'ACTIVO', 'VERIF')
    returning referencia into v_txt;

    insert into recibos (id_empresa, id_factura, fecha_cobro, cod_moneda, monto_cobrado,
                         monto_bs, monto_factura, monto_neto, referencia, conciliado,
                         estado, creado_por)
    values (1, v_fac, to_date('16/11/2026', 'DD/MM/YYYY'), 'USD', 50, 45787.38, 50, 50,
            'CHQ-VERIF-2', 'N', 'ACTIVO', 'VERIF');

    if cuenta(null, 'TODOS') <> v_base_t + 2 then
        falla('B4: sin filtro de conciliado no salen los 2 cobros (hay '
              || cuenta(null, 'TODOS') || ' y la base era ' || v_base_t || ')');
    end if;
    if cuenta(null, 'SI') <> v_base_s + 1 then
        falla('B4: el filtro conciliado=Si no deja 1 mas (hay '
              || cuenta(null, 'SI') || ' y la base era ' || v_base_s || ')');
    end if;
    if cuenta(null, 'NO') <> v_base_n + 1 then
        falla('B4: el filtro conciliado=No no deja 1 mas (hay '
              || cuenta(null, 'NO') || ' y la base era ' || v_base_n || ')');
    end if;
    if cuenta('TRF-VERIF', 'TODOS') <> 1 then
        falla('B4: la busqueda por referencia no filtra');
    end if;
    if cuenta(v_folio, 'TODOS') < 1 then
        falla('B4: la busqueda por numero de factura no filtra');
    end if;
    if cuenta(v_rif, 'TODOS') < 1 then
        falla('B4: la busqueda por RIF no filtra');
    end if;
    if cuenta(v_cli, 'TODOS') < 1 then
        falla('B4: la busqueda por cliente no filtra');
    end if;
    if cuenta('NO-EXISTE-XYZ', 'TODOS') <> 0 then
        falla('B4: una busqueda sin resultados devuelve filas');
    end if;

    rollback to sp_buscob;

    -- B5: una accion de cambio por filtro.
    select count(*) into v_n
      from apex_260100.apex_application_page_da
     where application_id = 100 and page_id = 24
       and when_element in ('P24_BUSCAR', 'P24_DESDE', 'P24_HASTA',
                            'P24_ESTADO', 'P24_CONCILIADO');
    if v_n <> 5 then
        falla('B5: hay ' || v_n || ' acciones de cambio (deberian ser 5)');
    end if;

    -- B6: se retiraron el selector y el boton viejos.
    select count(*) into v_n
      from apex_260100.apex_application_page_items
     where application_id = 100 and page_id = 24 and item_name = 'P24_ID_RECIBO';
    if v_n > 0 then
        falla('B6: sigue el selector P24_ID_RECIBO');
    end if;

    select count(*) into v_n
      from apex_260100.apex_application_page_buttons
     where application_id = 100 and page_id = 24 and button_name = 'BTN_ABRIR_COBRO';
    if v_n > 0 then
        falla('B6: sigue el boton BTN_ABRIR_COBRO');
    end if;

    -- B7: la guarda de rol.
    select count(*) into v_n
      from apex_260100.apex_application_page_proc
     where application_id = 100 and page_id = 24
       and static_id = 'valida-rol-cobros';
    if v_n = 0 then
        falla('B7: falta la guarda de rol de la pagina 24');
    end if;

    -- B8 (2026-11-20): los cinco filtros tienen que quedar en el estado de sesion.
    -- Estaban declarados p_is_persistent=>'N' y su accion hace apex.submit: APEX
    -- descartaba el valor antes de renderizar, asi que el informe salia SIN filtrar
    -- y el combo volvia a «Todos». La pagina 17 no los marca y sus filtros si filtran.
    select count(*) into v_n
      from apex_260100.apex_application_page_items
     where application_id = 100 and page_id = 24
       and item_name in ('P24_BUSCAR', 'P24_DESDE', 'P24_HASTA', 'P24_ESTADO', 'P24_CONCILIADO')
       and maintain_session_state = 'Per Session';
    if v_n <> 5 then
        falla('B8: ' || v_n || ' de 5 filtros se guardan en sesion; sin eso no filtran');
    end if;

    -- B9: el filtro de estado dice «Emitidos» y su valor sigue siendo ACTIVO.
    select count(*) into v_n
      from apex_260100.apex_application_page_items
     where application_id = 100 and page_id = 24 and item_name = 'P24_ESTADO'
       and instr(lov_definition, 'Emitidos;ACTIVO') > 0
       and instr(lov_definition, 'Activos;') = 0;
    if v_n = 0 then
        falla('B9: el filtro de Estado no dice Emitidos con el valor ACTIVO');
    end if;

    for i in 1 .. v_fallas.count loop
        insert into tmp_buscob_fallas values (v_fallas(i));
    end loop;
exception
    when others then
        rollback to sp_buscob;
        v_msg := substrb('B?: el caso revento: ' || sqlerrm, 1, 300);
        insert into tmp_buscob_fallas values (v_msg);
end;
/

declare
    v_fallas number;
    v_lista  varchar2(3000);
begin
    select count(*) into v_fallas from tmp_buscob_fallas;
    select substrb(listagg(caso, ' | ' on overflow truncate) within group (order by caso), 1, 3000)
      into v_lista from tmp_buscob_fallas;
    execute immediate 'drop table tmp_buscob_fallas purge';
    raise_application_error(-20100, substrb('RESULTADO: FALLAS=' || v_fallas || ' | ' || v_lista, 1, 3000));
end;
/
