-- =============================================================================
-- 20261119_impuesto_porcentaje_verificacion.sql
--
-- El % del impuesto lo manda el impuesto elegido (2026-11-19).
--
-- Sintoma que reporto el dueno: en la linea de compra puso «VE - Exento / No
-- Sujeto (0 %)» y el «% del impuesto» seguia en 16, asi que la linea exenta
-- habria guardado IVA.
--
--   V1 la linea de compra (29) tiene la accion sobre P29_ID_IMPUESTO
--   V2 esa accion devuelve P29_PORCENTAJE_IMPUESTO y lleva suppress_change_event='Y'
--   V3 la linea de factura (10) conserva la suya (PORCENTAJE_IMP), que ya existia
--   V4 el catalogo tiene el impuesto de VE al 0 % que se usa como exento
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261119_impuesto_porcentaje_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000) := '';
    v_n      number;

    procedure falla(p_caso varchar2, p_detalle varchar2) is
    begin
        v_fallas := v_fallas + 1;
        v_lista  := v_lista || ' | ' || p_caso || ': ' || p_detalle;
    end;
begin
    -- V1: la accion nueva de la linea de compra
    select count(*) into v_n
      from apex_260100.apex_application_page_da
     where application_id = 100 and page_id = 29
       and when_element = 'P29_ID_IMPUESTO'
       and static_id = 'impuesto-linea-pct';
    if v_n <> 1 then
        falla('V1', 'la 29 no tiene la accion «impuesto-linea-pct» sobre P29_ID_IMPUESTO');
    end if;

    -- V2: devuelve el porcentaje y no rebota eventos (si no, vuelve la avalancha de AJAX)
    select count(*) into v_n
      from apex_260100.apex_application_page_da_acts
     where application_id = 100 and page_id = 29
       and instr(json_value(attributes, '$.items_to_return'), 'P29_PORCENTAJE_IMPUESTO') > 0
       and json_value(attributes, '$.suppress_change_event') = 'Y';
    if v_n <> 1 then
        falla('V2', 'la accion de la 29 no devuelve el % o no lleva suppress_change_event=Y');
    end if;

    -- V3: la 10 ya tenia la suya desde antes; no se duplico
    select count(*) into v_n
      from apex_260100.apex_application_page_da
     where application_id = 100 and page_id = 10
       and when_element = 'P10_ID_IMPUESTO';
    if v_n <> 1 then
        falla('V3', 'la 10 tiene ' || v_n || ' acciones sobre P10_ID_IMPUESTO (se esperaba 1)');
    end if;

    -- 2026-11-26: la accion del impuesto es la que debe devolver el %. Desde el 2026-11-23 tambien lo
    -- devuelve la que carga el producto escaneado (CARGAR_DATOS_PRODUCTO), y eso es correcto.
    select count(*) into v_n
      from apex_260100.apex_application_page_da_acts a
      join apex_260100.apex_application_page_da d on d.dynamic_action_id = a.dynamic_action_id
     where a.application_id = 100 and a.page_id = 10 and d.when_element = 'P10_ID_IMPUESTO'
       and instr(json_value(a.attributes, '$.items_to_return'), 'P10_PORCENTAJE_IMPUESTO') > 0;
    if v_n <> 1 then
        falla('V3', 'la accion de la 10 no devuelve P10_PORCENTAJE_IMPUESTO');
    end if;

    -- V4: el catalogo trae el exento de Venezuela
    select count(*) into v_n
      from impuestos
     where cod_pais = 'VE' and porcentage = 0 and estado = 'ACTIVO'
       and nvl(aplica_en, 'LINEA') = 'LINEA';
    if v_n = 0 then
        falla('V4', 'no hay impuesto de VE al 0 % que aplicar en las lineas');
    end if;

    raise_application_error(-20100,
        substrb('RESULTADO: FALLAS=' || v_fallas || v_lista, 1, 3000));
end;
/
