-- =============================================================================
-- 20261118_compra_tasa_retencion_verificacion.sql
--
-- Pagina 28 «Compra» (2026-11-18), a raiz de la revision del dueño:
--   C1  el N° de factura no puede ser un numero suelto de 1-2 digitos (-20088)
--   C2  el N° de control del proveedor tampoco (-20089)
--   C3  con formatos normales la compra se guarda
--   C4  la pagina 28 trae las acciones que proponen tasa y retencion, y el
--       proceso que las propone al abrir
--   C5  la tasa no lleva mascara de 2 decimales (se ve lo que se guarda)
--
-- Todo el DML va con rollback.
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261118_compra_tasa_retencion_verificacion.sql
-- FALLAS=0 = EXITO (el runner sale con codigo 1 igual: el detalle va en -20100).
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000) := '';
    v_n      number;
    v_prov   number;
    v_compra number;
    v_msg    varchar2(400);

    procedure falla(p_caso varchar2, p_detalle varchar2) is
    begin
        v_fallas := v_fallas + 1;
        v_lista  := v_lista || ' | ' || p_caso || ': ' || p_detalle;
    end;

    -- intenta guardar y devuelve el sqlcode (0 = guardo)
    function guarda(p_folio varchar2, p_control varchar2) return number is
        v_id number;
    begin
        pkg_compras.prc_guardar_compra(
            p_id_compra      => v_id,
            p_id_empresa     => 1,
            p_id_proveedor   => v_prov,
            p_tipo_documento => 'FAC',
            p_folio_factura  => p_folio,
            p_nro_control    => p_control,
            p_fecha_emision  => date '2026-11-18',
            p_cod_moneda     => 'VES',
            p_tipo_cambio    => 1,
            p_usuario        => 'test_compra');
        return 0;
    exception
        when others then
            v_msg := sqlerrm;
            return sqlcode;
    end;
begin
    savepoint sp_compra;

    -- usuario temporal: prc_guardar_compra comprueba la empresa del usuario
    insert into usuario (username, email, password_hash, estado, id_empresa, rol_id,
                         debe_cambiar_clave, reintentos_fallidos)
    values ('test_compra', 'test_compra@synpex.local', sypex_hash_password('x'), 'ACTIVO', 1,
            (select id_rol from syn_roles where codigo_rol = 'ADMIN'), 'N', 0);

    insert into proveedores (id_empresa, rif, razon_social, tipo_persona, cod_pais,
                             estado, retener_iva, porcentaje_retencion, es_spe, dias_credito)
    values (1, 'J-TESTCOMPRA-1', 'Proveedor de la verificacion', 'J', 'VE',
            'ACTIVO', 'S', 75, 'N', 30)
    returning id_proveedor into v_prov;

    -- C1: folio de 2 digitos
    if guarda('45', '00-000045') <> -20088 then
        falla('C1', 'acepto el folio «45» (' || sqlcode || ' ' || substrb(v_msg, 1, 120) || ')');
    end if;

    -- C2: control de 2 digitos
    if guarda('F-45', '45') <> -20089 then
        falla('C2', 'acepto el control «45» (' || sqlcode || ' ' || substrb(v_msg, 1, 120) || ')');
    end if;

    -- C3: formatos normales
    if guarda('F-45', '00-000045') <> 0 then
        falla('C3', 'no dejo guardar con formatos normales (' || sqlcode || ' ' || substrb(v_msg, 1, 120) || ')');
    end if;

    -- C4: la pagina 28 propone tasa y retencion
    select count(*) into v_n
      from apex_260100.apex_application_page_da
     where application_id = 100 and page_id = 28
       and when_element in ('P28_COD_MONEDA', 'P28_FECHA_EMISION', 'P28_ID_PROVEEDOR');
    if v_n < 3 then
        falla('C4', 'la 28 solo tiene ' || v_n || ' de 3 acciones (moneda, fecha, proveedor)');
    end if;

    select count(*) into v_n
      from apex_260100.apex_application_page_proc
     where application_id = 100 and page_id = 28
       and static_id = 'sugiere-compra'
       and process_point like 'On Load%';
    if v_n <> 1 then
        falla('C4', 'la 28 no tiene el proceso «Sugiere compra» al abrir');
    end if;

    -- C5: la tasa sin mascara
    select count(*) into v_n
      from apex_260100.apex_application_page_items
     where application_id = 100 and page_id = 28 and item_name = 'P28_TIPO_CAMBIO'
       and format_mask is null;
    if v_n <> 1 then
        falla('C5', 'P28_TIPO_CAMBIO lleva mascara (redondea la tasa al mostrarla)');
    end if;

    rollback to sp_compra;

    raise_application_error(-20100, substrb('RESULTADO: FALLAS=' || v_fallas || v_lista, 1, 3000));
end;
/
