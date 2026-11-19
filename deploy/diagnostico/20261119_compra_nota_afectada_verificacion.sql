-- =============================================================================
-- 20261119_compra_nota_afectada_verificacion.sql
--
-- Nota de credito/debito de COMPRA: tiene que decir que factura afecta
-- (requisito de la providencia del SENIAT). pkg_compras lo exige con -20097 y
-- comprueba que sea una FAC de la misma empresa.
--
--   V1 una NC sin factura afectada se rechaza (-20097)
--   V2 una NC con una FAC de la misma empresa se guarda
--   V3 una NC que apunta a una compra de otra empresa se rechaza (-20097)
--   V4 una ND con factura afectada tambien se guarda
--
-- Todo va dentro de un SAVEPOINT y se revierte.
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261119_compra_nota_afectada_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000) := '';
    v_prov   number;
    v_fac    number;
    v_otra   number;
    v_id     number;
    v_msg    varchar2(300);

    procedure falla(p_caso varchar2, p_detalle varchar2) is
    begin
        v_fallas := v_fallas + 1;
        v_lista  := v_lista || ' | ' || p_caso || ': ' || substrb(p_detalle, 1, 140);
    end;

    function guarda(p_tipo varchar2, p_folio varchar2, p_origen number) return number is
        v_new number;
    begin
        pkg_compras.prc_guardar_compra(
            p_id_compra        => v_new,
            p_id_empresa       => 1,
            p_id_proveedor     => v_prov,
            p_tipo_documento   => p_tipo,
            p_folio_factura    => p_folio,
            p_nro_control      => '00-000991',
            p_fecha_emision    => trunc(sysdate),
            p_cod_moneda       => 'VES',
            p_tipo_cambio      => 1,
            p_porcentaje_retencion => 75,
            p_id_compra_origen => p_origen,
            p_usuario          => 'admin');
        return 0;
    exception
        when others then
            v_msg := sqlerrm;
            return sqlcode;
    end;
begin
    savepoint sp_nota;

    insert into proveedores (id_empresa, rif, razon_social, cod_pais)
    values (1, 'J-TESTNOTA-1', 'Proveedor de la nota', 'VE')
    returning id_proveedor into v_prov;

    -- una factura de compra de la misma empresa
    insert into compras (id_empresa, id_proveedor, tipo_documento, folio_factura,
                         nro_control, fecha_emision, cod_moneda, tipo_cambio,
                         porcentaje_retencion, estado)
    values (1, v_prov, 'FAC', 'NOTA-1', '00-000900', trunc(sysdate), 'VES', 1, 75, 'REGISTRADA')
    returning id_compra into v_fac;

    -- y otra de OTRA empresa (2), para el caso cruzado
    insert into compras (id_empresa, id_proveedor, tipo_documento, folio_factura,
                         nro_control, fecha_emision, cod_moneda, tipo_cambio,
                         porcentaje_retencion, estado)
    values (2, v_prov, 'FAC', 'NOTA-2', '00-000901', trunc(sysdate), 'VES', 1, 0, 'REGISTRADA')
    returning id_compra into v_otra;

    -- V1
    if guarda('NC', 'NC-SIN', null) <> -20097 then
        falla('V1', 'acepto una NC sin factura afectada (' || v_msg || ')');
    end if;

    -- V2
    if guarda('NC', 'NC-OK', v_fac) <> 0 then
        falla('V2', 'no dejo guardar la NC con su factura (' || v_msg || ')');
    end if;

    -- V3
    if guarda('NC', 'NC-CRUZ', v_otra) <> -20097 then
        falla('V3', 'acepto una NC apuntando a una compra de otra empresa (' || v_msg || ')');
    end if;

    -- V4
    if guarda('ND', 'ND-OK', v_fac) <> 0 then
        falla('V4', 'no dejo guardar la ND con su factura (' || v_msg || ')');
    end if;

    rollback to sp_nota;

    raise_application_error(-20100,
        substrb('RESULTADO: FALLAS=' || v_fallas || v_lista, 1, 3000));
end;
/
