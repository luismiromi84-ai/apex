-- =============================================================================
-- 20261125_estados_volver_cobrar_verificacion.sql
--
-- Cinco cosas que reporto el dueno el 2026-11-25:
--   1. el boton «Volver» de las impresiones tiene que ir a Presupuestos (5) y a
--      Facturacion (8), no a la Home
--   2. una NOTA en Venezuela no dice «TIMBRADA»: dice PROCESADA
--   3. el campo «Factura origen» del dialogo mostraba 2112 (el id) en vez del folio,
--      porque la factura ya estaba ANULADA por su nota y salia de la lista
--   4. en la lista de Facturacion se podia pulsar «Cobrar» en una nota
--
--   F1 fn_estado_factura: factura y nota VE PROCESADA · Mexico TIMBRADA
--   F2 la 9 tiene P9_ESTADO_TXT (visible) y P9_ESTADO oculto, y el proceso que lo llena
--   F3 la lista de la 8 cobra con fn_factura_cobrable (no con el estado a pelo)
--   F4 comportamiento: una nota y una PENDIENTE no son cobrables; una TIMBRADA con saldo si
--   F5 la lista de facturas origen incluye la que ya esta elegida aunque este ANULADA
--   F6 el «Volver» de la 12 va a la 5 y el de la 11 a la 8
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261125_estados_volver_cobrar_verificacion.sql
-- FALLAS=0 = EXITO. El runner sale con codigo 1 aunque sea verde: se lee el mensaje.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000) := '';
    v_n      number;
    v_txt    varchar2(32767);
    v_url    varchar2(2000);
    v_disp   varchar2(400);

    procedure falla(p_caso varchar2, p_detalle varchar2) is
    begin
        v_fallas := v_fallas + 1;
        v_lista  := v_lista || ' | ' || p_caso || ': ' || p_detalle;
    end;

    procedure espera_txt(p_caso varchar2, p_dado varchar2, p_esperado varchar2) is
    begin
        if nvl(p_dado, '#') <> p_esperado then
            falla(p_caso, 'se esperaba «' || p_esperado || '» y dio «' || nvl(p_dado, 'NULL') || '»');
        end if;
    end;
begin
    -- ------------------------------------------------------------------ F1
    espera_txt('F1', fn_estado_factura('TIMBRADA', 'VE', 'FAC'), 'PROCESADA');
    espera_txt('F1', fn_estado_factura('TIMBRADA', 'VE', 'NC'), 'PROCESADA');
    espera_txt('F1', fn_estado_factura('TIMBRADA', 'VE', 'ND'), 'PROCESADA');
    espera_txt('F1', fn_estado_factura('TIMBRADA', 'MX', 'NC'), 'TIMBRADA');
    espera_txt('F1', fn_estado_factura('TIMBRADA', 'MX', 'FAC'), 'TIMBRADA');

    -- ------------------------------------------------------------------ F2
    select count(*) into v_n
      from apex_260100.apex_application_page_items
     where application_id = 100 and page_id = 9 and item_name = 'P9_ESTADO_TXT'
       and display_as_code = 'NATIVE_DISPLAY_ONLY';
    if v_n <> 1 then
        falla('F2', 'no hay P9_ESTADO_TXT como Display Only en la 9');
    end if;

    select count(*) into v_n
      from apex_260100.apex_application_page_items
     where application_id = 100 and page_id = 9 and item_name = 'P9_ESTADO'
       and display_as_code = 'NATIVE_HIDDEN';
    if v_n <> 1 then
        falla('F2', 'P9_ESTADO no esta oculto (se seguiria viendo el codigo crudo)');
    end if;

    select count(*) into v_n
      from apex_260100.apex_application_page_proc
     where application_id = 100 and page_id = 9 and static_id = 'muestra-estado-documento'
       and upper(process_source) like '%FN_ESTADO_FACTURA%';
    if v_n <> 1 then
        falla('F2', 'no existe el proceso que llena P9_ESTADO_TXT');
    end if;

    -- ------------------------------------------------------------------ F3
    select region_source into v_txt
      from apex_260100.apex_application_page_regions
     where application_id = 100 and page_id = 8 and region_name like 'Lista%';
    if instr(v_txt, 'fn_factura_cobrable') = 0 then
        falla('F3', 'la lista de la 8 no usa fn_factura_cobrable para el enlace «Cobrar»');
    end if;
    if instr(v_txt, 'fn_estado_factura(f.estado') > 0
       and instr(v_txt, 'f.tipo_documento) as estado') = 0 then
        falla('F3', 'la lista de la 8 no le pasa el tipo a fn_estado_factura');
    end if;

    -- ------------------------------------------------------------------ F4
    for r in (select f.id_factura, f.folio_factura, f.tipo_documento, f.estado,
                     fn_saldo_factura(f.id_factura) as saldo,
                     case when fn_factura_cobrable(f.id_factura) then 1 else 0 end as cobrable
                from facturas f
               where f.id_empresa = 6) loop
        if r.tipo_documento <> 'FAC' and r.cobrable = 1 then
            falla('F4', 'la nota ' || r.folio_factura || ' sale cobrable');
        end if;
        if r.estado = 'PENDIENTE' and r.cobrable = 1 then
            falla('F4', 'la factura PENDIENTE ' || r.folio_factura || ' sale cobrable');
        end if;
        if r.tipo_documento = 'FAC' and r.estado = 'TIMBRADA' and r.saldo > 0.01 and r.cobrable = 0 then
            falla('F4', 'la factura ' || r.folio_factura || ' deberia ser cobrable');
        end if;
    end loop;

    select count(*) into v_n from facturas
     where id_empresa = 6 and tipo_documento in ('NC', 'ND');
    if v_n = 0 then
        falla('F4', 'la empresa 6 no tiene notas para probar');
    end if;

    -- ------------------------------------------------------------------ F5
    select lov_definition into v_txt
      from apex_260100.apex_application_page_items
     where application_id = 100 and page_id = 9 and item_name = 'P9_ID_FACTURA_ORIGEN';
    if instr(v_txt, ':P9_ID_FACTURA_ORIGEN') = 0 then
        falla('F5', 'la lista de facturas origen no conserva la que ya esta elegida');
    end if;

    -- comportamiento: con la factura ANULADA 2112 elegida tiene que salir su folio
    v_txt := replace(v_txt, ':F_EMPRESA_ACTIVA', '6');
    v_txt := replace(v_txt, ':P9_ID_EMPRESA', 'null');
    -- ojo con el orden: el nombre largo primero (si no, :P9_ID_FACTURA se come el prefijo)
    v_txt := replace(v_txt, ':P9_ID_FACTURA_ORIGEN', '2112');
    v_txt := replace(v_txt, ':P9_ID_FACTURA', 'null');
    begin
        execute immediate 'select max(display_value) from (' || v_txt || ') where return_value = 2112'
            into v_disp;
        if v_disp is null then
            falla('F5', 'la factura anulada 2112 no sale en su propia lista (el campo mostraria el id)');
        elsif instr(v_disp, 'F-5') = 0 then
            falla('F5', 'la lista devuelve «' || v_disp || '» en vez del folio F-5');
        end if;
    exception
        when others then
            falla('F5', 'la consulta de la lista revienta -> ' || sqlerrm);
    end;

    -- ------------------------------------------------------------------ F6
    select redirect_url into v_url
      from apex_260100.apex_application_page_buttons
     where application_id = 100 and page_id = 12 and button_name = 'BTN_VOLVER';
    if instr(v_url, ':5:') = 0 then
        falla('F6', 'el Volver de la 12 no va a Presupuestos: ' || v_url);
    end if;

    select redirect_url into v_url
      from apex_260100.apex_application_page_buttons
     where application_id = 100 and page_id = 11 and button_name = 'BTN_VOLVER';
    if instr(v_url, ':8:') = 0 then
        falla('F6', 'el Volver de la 11 no va a Facturacion: ' || v_url);
    end if;

    raise_application_error(-20100,
        substrb('RESULTADO: FALLAS=' || v_fallas || v_lista, 1, 3000));
end;
/
