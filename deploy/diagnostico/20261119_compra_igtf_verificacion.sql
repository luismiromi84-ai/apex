-- =============================================================================
-- 20261119_compra_igtf_verificacion.sql
--
-- IGTF en las compras (2026-11-19): la forma de pago decide, la alicuota sale de
-- IMPUESTOS y solo aplica si la empresa es SPE y el documento va en divisas.
--
--   V1 FORMA_PAGO tiene VISIBLE_COMPRAS y la lista la usa
--   V2 COMPRAS tiene ID_FORMA_PAGO y el package la guarda
--   V3 en divisas, con una forma que genera IGTF y empresa SPE -> 3 % del total
--   V4 en bolivares no hay IGTF aunque la forma lo genere
--   V5 una forma que NO genera IGTF deja 0
--   V6 el resumen de la compra (region) lo calcula y lo muestra
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261119_compra_igtf_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000) := '';
    v_n      number;
    v_prov   number;
    v_forma  number;
    v_forma_sin number;
    v_id     number;
    v_igtf   number;
    v_tot    number;
    v_alic   number;

    procedure falla(p_caso varchar2, p_detalle varchar2) is
    begin
        v_fallas := v_fallas + 1;
        v_lista  := v_lista || ' | ' || p_caso || ': ' || substrb(p_detalle, 1, 140);
    end;

    -- la misma cuenta que hace la region del resumen
    function igtf_de(p_id_compra number) return number is
        v_t number;
        v_aplic varchar2(1);
        v_al number;
        v_emp number;
        v_m varchar2(5);
    begin
        select c.monto_total, c.cod_moneda
          into v_t, v_m
          from compras c where c.id_compra = p_id_compra;
        if nvl(v_m, 'VES') in ('VES', 'BS') then
            return 0;
        end if;
        select case when nvl(e.es_spe, 'N') = 'S' and nvl(f.genera_igtf, 'N') = 'S'
                    then 'S' else 'N' end
          into v_aplic
          from compras c
          join empresas e on e.id_empresa = c.id_empresa
          left join forma_pago f on f.id_forma_pago = c.id_forma_pago
         where c.id_compra = p_id_compra;
        if v_aplic <> 'S' then
            return 0;
        end if;
        select c.id_empresa into v_emp from compras c where c.id_compra = p_id_compra;
        v_al := nvl(fn_alicuota_igtf(v_emp), 0);
        return round(v_t * v_al / 100, 2);
    exception
        when others then return -1;
    end;
begin
    -- V1
    select count(*) into v_n from all_tab_columns
     where owner = 'WKSP_SYPEXWS' and table_name = 'FORMA_PAGO'
       and column_name = 'VISIBLE_COMPRAS';
    if v_n <> 1 then
        falla('V1', 'FORMA_PAGO no tiene VISIBLE_COMPRAS');
    end if;

    select count(*) into v_n
      from apex_260100.apex_application_page_items
     where application_id = 100 and page_id = 28 and item_name = 'P28_ID_FORMA_PAGO'
       and lower(lov_definition) like '%visible_compras%';
    if v_n <> 1 then
        falla('V1', 'la lista de formas de pago de la 28 no filtra por VISIBLE_COMPRAS');
    end if;

    -- V2: el package guarda la forma de pago
    savepoint sp_igtf;

    select count(*) into v_n from all_tab_columns
     where owner = 'WKSP_SYPEXWS' and table_name = 'COMPRAS' and column_name = 'ID_FORMA_PAGO';
    if v_n <> 1 then
        falla('V2', 'COMPRAS no tiene ID_FORMA_PAGO');
    end if;

    select min(id_proveedor) into v_prov from proveedores where id_empresa = 1;
    select min(id_forma_pago) into v_forma from forma_pago where genera_igtf = 'S' and activo = 'Y';
    select min(id_forma_pago) into v_forma_sin from forma_pago where genera_igtf = 'N' and activo = 'Y';

    v_id := null;
    pkg_compras.prc_guardar_compra(
        p_id_compra => v_id, p_id_empresa => 1, p_id_proveedor => v_prov,
        p_tipo_documento => 'FAC', p_folio_factura => 'IGTF-1', p_nro_control => '00-000800',
        p_fecha_emision => trunc(sysdate), p_cod_moneda => 'VES', p_tipo_cambio => 1,
        p_porcentaje_retencion => 75, p_id_forma_pago => v_forma, p_usuario => 'admin');

    select id_forma_pago into v_n from compras where id_compra = v_id;
    if v_n <> v_forma then
        falla('V2', 'el package no guardo la forma de pago');
    end if;

    insert into compras_det (id_compra, num_linea, descripcion, cantidad, precio_unitario,
                             subtotal_linea, porcentaje_impuesto, monto_impuesto, total_linea,
                             tasa_cambio_aplicada)
    values (v_id, 1, 'Linea gravada', 1, 100, 100, 16, 16, 116, 1);

    -- V4: en bolivares no hay IGTF
    if igtf_de(v_id) <> 0 then
        falla('V4', 'calculo IGTF en un documento en bolivares: ' || igtf_de(v_id));
    end if;

    -- V3: el mismo documento en divisas
    update compras set cod_moneda = 'USD', tipo_cambio = 900 where id_compra = v_id;
    select monto_total into v_tot from compras where id_compra = v_id;
    select nvl(fn_alicuota_igtf(1), 0) into v_alic from dual;
    v_igtf := igtf_de(v_id);
    if v_igtf <> round(v_tot * v_alic / 100, 2) then
        falla('V3', 'IGTF ' || v_igtf || ' en vez de ' || round(v_tot * v_alic / 100, 2));
    end if;

    -- V5: una forma que no genera IGTF deja 0
    update compras set id_forma_pago = v_forma_sin where id_compra = v_id;
    if igtf_de(v_id) <> 0 then
        falla('V5', 'calculo IGTF con una forma de pago que no lo genera');
    end if;

    rollback to sp_igtf;

    -- V6: el resumen lo calcula
    select count(*) into v_n
      from apex_260100.apex_application_page_regions
     where application_id = 100 and page_id = 28 and region_static_id = 'compra-resumen'
       and lower(region_source) like '%alicuota_igtf%'
       and lower(region_source) like '%genera_igtf%';
    if v_n <> 1 then
        falla('V6', 'el resumen de la compra no calcula el IGTF');
    end if;

    raise_application_error(-20100,
        substrb('RESULTADO: FALLAS=' || v_fallas || v_lista, 1, 3000));
end;
/
