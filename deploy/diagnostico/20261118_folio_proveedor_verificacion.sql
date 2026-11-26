-- =============================================================================
-- 20261118_folio_proveedor_verificacion.sql
--
-- Series del PROVEEDOR en FOLIO_CONTADOR (2026-11-18). El dueño pidio que el
-- N° de factura y el N° de control de una compra vengan automaticos, sin tabla
-- nueva: dos series mas en la tabla que ya existe.
--
--   F1  el CHECK de FOLIO_CONTADOR admite FAC_PROV y CONTROL_PROV
--   F2  cada empresa obtiene sus dos series (la fila se crea en el primer uso)
--   F3  los formatos son '45' y '00-000001'
--   F4  al dar de alta una compra con la propuesta, la serie AVANZA y se guarda
--   F5  si el usuario teclea otro numero, se respeta y la serie NO se mueve
--   F6  la pagina 28 propone las dos series al abrir una compra nueva
--
-- Todo el DML va dentro de un SAVEPOINT y se revierte.
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261118_folio_proveedor_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_fallas  number := 0;
    v_lista   varchar2(3000) := '';
    v_n       number;
    v_sig1    varchar2(40);
    v_sig2    varchar2(40);
    v_antes1  number;
    v_antes2  number;
    v_desp1   number;
    v_desp2   number;
    v_id      number;
    v_folio   varchar2(50);
    v_control varchar2(50);
    v_prov    number;
    v_emp     number := 1;
    v_user    varchar2(30);

    procedure falla(p_caso varchar2, p_detalle varchar2) is
    begin
        v_fallas := v_fallas + 1;
        v_lista  := v_lista || ' | ' || p_caso || ': ' || substrb(p_detalle, 1, 160);
    end;
begin
    savepoint sp_fp;

    -- F1
    select count(*) into v_n
      from all_constraints
     where owner = 'WKSP_SYPEXWS' and table_name = 'FOLIO_CONTADOR'
       and constraint_name = 'CK_FOLIO_CONTADOR_TIPO'
       and instr(search_condition_vc, 'FAC_PROV') > 0
       and instr(search_condition_vc, 'CONTROL_PROV') > 0;
    if v_n = 0 then
        falla('F1', 'el CHECK de FOLIO_CONTADOR no admite las dos series nuevas');
    end if;

    -- F2 (revisada el 2026-11-26): toda empresa obtiene sus dos series de proveedor. No se exige la
    -- fila sembrada: fn_asignar_folio la crea en el primer uso, y una empresa nueva (la 7, «las
    -- minas») no la tiene hasta entonces; exigirla hacia fallar la prueba sin que hubiera error.
    select count(*) into v_n
      from empresas e
     where fn_siguiente_folio(e.id_empresa, 'FAC_PROV') is null
        or fn_siguiente_folio(e.id_empresa, 'CONTROL_PROV') is null;
    if v_n > 0 then
        falla('F2', v_n || ' empresa(s) sin folio de FAC_PROV o CONTROL_PROV');
    end if;

    -- F3
    v_sig1 := fn_siguiente_folio(v_emp, 'FAC_PROV');
    v_sig2 := fn_siguiente_folio(v_emp, 'CONTROL_PROV');
    if not regexp_like(v_sig1, '^[0-9]+$') then
        falla('F3', 'FAC_PROV no es un numero pelado: ' || v_sig1);
    end if;
    if not regexp_like(v_sig2, '^[0-9]{2}-[0-9]{6}$') then
        falla('F3', 'CONTROL_PROV no tiene la forma 00-000001: ' || v_sig2);
    end if;

    select ultimo into v_antes1 from folio_contador
     where id_empresa = v_emp and tipo = 'FAC_PROV';
    select ultimo into v_antes2 from folio_contador
     where id_empresa = v_emp and tipo = 'CONTROL_PROV';

    select min(id_proveedor) into v_prov from proveedores
     where id_empresa = v_emp and estado = 'ACTIVO';

    select username into v_user
      from (select u.username
              from usuario u join usuario_empresa ue on ue.usuario_id = u.usuario_id
             where ue.id_empresa = v_emp and u.estado = 'ACTIVO'
             order by u.username)
     where rownum = 1;

    -- F4: alta con la PROPUESTA -> consume las dos series
    v_id := null;
    pkg_compras.prc_guardar_compra(
        p_id_compra        => v_id,
        p_id_empresa       => v_emp,
        p_id_proveedor     => v_prov,
        p_tipo_documento   => 'FAC',
        p_folio_factura    => v_sig1,
        p_nro_control      => v_sig2,
        p_fecha_emision    => trunc(sysdate),
        p_cod_moneda       => 'VES',
        p_tipo_cambio      => 1,
        p_porcentaje_retencion => 75,
        p_observaciones    => 'prueba serie proveedor',
        p_usuario          => v_user);

    select folio_factura, nro_control into v_folio, v_control
      from compras where id_compra = v_id;
    select ultimo into v_desp1 from folio_contador
     where id_empresa = v_emp and tipo = 'FAC_PROV';
    select ultimo into v_desp2 from folio_contador
     where id_empresa = v_emp and tipo = 'CONTROL_PROV';

    if v_folio <> v_sig1 then
        falla('F4', 'la compra guardo el folio "' || v_folio || '" y se propuso "' || v_sig1 || '"');
    end if;
    if v_control <> v_sig2 then
        falla('F4', 'la compra guardo el control "' || v_control || '" y se propuso "' || v_sig2 || '"');
    end if;
    if v_desp1 <> v_antes1 + 1 then
        falla('F4', 'FAC_PROV no avanzo: ' || v_antes1 || ' -> ' || v_desp1);
    end if;
    if v_desp2 <> v_antes2 + 1 then
        falla('F4', 'CONTROL_PROV no avanzo: ' || v_antes2 || ' -> ' || v_desp2);
    end if;

    -- F5: numero TECLEADO distinto -> se respeta y la serie no se mueve
    v_id := null;
    pkg_compras.prc_guardar_compra(
        p_id_compra        => v_id,
        p_id_empresa       => v_emp,
        p_id_proveedor     => v_prov,
        p_tipo_documento   => 'FAC',
        p_folio_factura    => 'A-777',
        p_nro_control      => '00-999999',
        p_fecha_emision    => trunc(sysdate),
        p_cod_moneda       => 'VES',
        p_tipo_cambio      => 1,
        p_porcentaje_retencion => 75,
        p_observaciones    => 'prueba numero tecleado',
        p_usuario          => v_user);

    select folio_factura, nro_control into v_folio, v_control
      from compras where id_compra = v_id;
    select ultimo into v_desp1 from folio_contador
     where id_empresa = v_emp and tipo = 'FAC_PROV';
    select ultimo into v_desp2 from folio_contador
     where id_empresa = v_emp and tipo = 'CONTROL_PROV';

    if v_folio <> 'A-777' then
        falla('F5', 'se perdio el folio tecleado: ' || v_folio);
    end if;
    if v_control <> '00-999999' then
        falla('F5', 'se perdio el control tecleado: ' || v_control);
    end if;
    if v_desp1 <> v_antes1 + 1 then
        falla('F5', 'la serie FAC_PROV se movio sin tocar la propuesta: ' || v_desp1);
    end if;
    if v_desp2 <> v_antes2 + 1 then
        falla('F5', 'la serie CONTROL_PROV se movio sin tocar la propuesta: ' || v_desp2);
    end if;

    -- F6: la pagina 28 propone las dos series
    select count(*) into v_n
      from apex_260100.apex_application_page_proc
     where application_id = 100 and page_id = 28
       and static_id = 'sugiere-compra'
       and instr(upper(process_source), 'FAC_PROV') > 0
       and instr(upper(process_source), 'CONTROL_PROV') > 0;
    if v_n = 0 then
        falla('F6', 'el proceso sugiere-compra de la pagina 28 no propone las dos series');
    end if;

    rollback to sp_fp;

    raise_application_error(-20100,
        substrb('RESULTADO: FALLAS=' || v_fallas || v_lista, 1, 3000));
end;
/
