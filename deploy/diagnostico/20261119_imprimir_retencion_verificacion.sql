-- =============================================================================
-- 20261119_imprimir_retencion_verificacion.sql
--
-- El comprobante de retencion en papel (2026-11-19):
--   V1 fn_imprimir_retencion esta VALID
--   V2 arma el documento de IVA con el numero, la base, el IVA retenido y la
--      providencia del formato
--   V3 devuelve NULL si la compra no tiene comprobante (no inventa un papel)
--   V4 la pagina 31 lo sirve y tiene su guarda de rol
--   V5 la compra (28) tiene el boton para imprimirlo
--
-- DESDE EL 2026-11-19 (comprobantes de IVA e ISLR) este papel se lee de
-- RETENCIONES/RETENCIONES_DET, no de la tabla plana RETENCIONES_IVA: la vieja
-- solo guardaba el historico y ya no tiene escritores. El formato detallado de
-- los dos papeles (Providencia SNAT/2025/000054 y Decreto 1.808) lo mide R11 en
-- 20261119_retenciones_verificacion.sql; aqui queda la prueba de que la funcion
-- sigue sirviendo el documento y de que la pantalla no se rompio.
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261119_imprimir_retencion_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000) := '';
    v_n      number;
    v_id     number;
    v_num    varchar2(14);
    v_base   number;
    v_ret    number;
    v_txt    clob;

    procedure falla(p_caso varchar2, p_detalle varchar2) is
    begin
        v_fallas := v_fallas + 1;
        v_lista  := v_lista || ' | ' || p_caso || ': ' || substrb(p_detalle, 1, 140);
    end;
begin
    -- V1
    select count(*) into v_n from all_objects
     where owner = 'WKSP_SYPEXWS' and object_name = 'FN_IMPRIMIR_RETENCION'
       and status = 'VALID';
    if v_n < 1 then
        falla('V1', 'fn_imprimir_retencion no esta VALID');
    end if;

    -- V2: con un comprobante real. Se lee RETENCIONES (el modelo nuevo) y se
    -- comprueba que el papel trae las cifras GUARDADAS, con el formato
    -- venezolano de los importes y las etiquetas del formato de la Providencia.
    -- Si la base no tiene ningun comprobante de IVA el caso tiene que ANOTARLO, no
    -- reventar con ORA-01403 (un select into sin filas se lleva por delante el
    -- RESULTADO entero).
    begin
        select id_compra, numero_comprobante, base_imponible_bs, retenido_bs
          into v_id, v_num, v_base, v_ret
          from retenciones
         where tipo = 'IVA' and id_compra is not null and rownum = 1;
    exception
        when no_data_found then
            v_id := null;
    end;

    if v_id is null then
        falla('V2', 'no hay ningun comprobante de IVA que imprimir');
    else
        v_txt := fn_imprimir_retencion(v_id);
        if v_txt is null then
            falla('V2', 'no armo el documento');
        else
            if instr(v_txt, v_num) = 0 then
                falla('V2', 'el documento no trae el numero ' || v_num);
            end if;
            -- Las etiquetas se comprueban TAL COMO las emite la funcion, con su
            -- salto de linea dentro de la celda: 'I.V.A.' a secas lo cumple
            -- cualquier mencion del titulo, y eso no mide la columna.
            if instr(v_txt, 'I.V.A.<br>Retenido') = 0 then
                falla('V2', 'el documento no trae la columna del IVA retenido');
            end if;
            if instr(v_txt, 'Base<br>Imponible') = 0 then
                falla('V2', 'el documento no trae la columna de la base imponible');
            end if;
            if instr(v_txt, 'Compras sin derecho a Cr&eacute;dito') = 0 then
                falla('V2', 'el documento no trae la columna de las compras sin derecho a credito');
            end if;
            if instr(v_txt, to_char(v_base, 'FM999G999G999G990D00',
                                    'NLS_NUMERIC_CHARACTERS='',.''')) = 0 then
                falla('V2', 'el documento no trae la base con el formato venezolano');
            end if;
            if instr(v_txt, to_char(v_ret, 'FM999G999G999G990D00',
                                    'NLS_NUMERIC_CHARACTERS='',.''')) = 0 then
                falla('V2', 'el documento no trae el retenido con el formato venezolano');
            end if;
            if instr(v_txt, 'SNAT/2025/000054') = 0 then
                falla('V2', 'el documento no cita la providencia del formato');
            end if;
        end if;
    end if;

    -- V3: una compra sin comprobante devuelve NULL
    begin
        select min(id_compra) into v_n from compras
         where id_compra not in (select id_compra from retenciones
                                  where tipo = 'IVA' and id_compra is not null);
        if v_n is not null then
            v_txt := fn_imprimir_retencion(v_n);
            if v_txt is not null then
                falla('V3', 'invento un comprobante para una compra sin retencion');
            end if;
        end if;
    exception
        when no_data_found then null;
    end;

    -- V4: la pagina 31
    select count(*) into v_n
      from apex_260100.apex_application_page_regions
     where application_id = 100 and page_id = 31
       and source_type_plugin_static_id = 'NATIVE_DYNAMIC_CONTENT'
       and lower(region_source) like '%fn_imprimir_retencion%';
    if v_n <> 1 then
        falla('V4', 'la pagina 31 no sirve el comprobante');
    end if;

    select count(*) into v_n
      from apex_260100.apex_application_page_proc
     where application_id = 100 and page_id = 31
       and static_id = 'valida-rol-retencion-print';
    if v_n <> 1 then
        falla('V4', 'la pagina 31 no tiene su guarda de rol');
    end if;

    -- V5: el boton en la compra
    select count(*) into v_n
      from apex_260100.apex_application_page_buttons
     where application_id = 100 and page_id = 28
       and button_name = 'BTN_IMPRIMIR_RETENCION';
    if v_n <> 1 then
        falla('V5', 'la compra (28) no tiene el boton de imprimir');
    end if;

    raise_application_error(-20100,
        substrb('RESULTADO: FALLAS=' || v_fallas || v_lista, 1, 3000));
end;
/
