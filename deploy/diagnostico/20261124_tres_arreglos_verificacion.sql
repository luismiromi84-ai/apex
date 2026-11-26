-- =============================================================================
-- 20261124_tres_arreglos_verificacion.sql
--
-- Tres cosas que reporto el dueno el 2026-11-24:
--   1. la impresion de presupuesto (12) no tiene boton para volver a la Home
--   2. la tarjeta de la 5 sumaba el gasto real en USD y lo restaba de un total
--      en bolivares (30 USD aparecian como «30,00» y la desviacion como 974,00)
--   3. el reporte de documentos (17) no ofrece «Presupuestos» en Modulo
--
--   A1 la funcion nueva devuelve el gasto en bolivares; el USD no cambia y, con
--      gastos en divisa, los bolivares son mayores que los dolares
--   A2 la tarjeta de la 5 usa esa funcion y lleva el gasto a la moneda del documento
--   A3 la tarjeta muestra el detalle en USD
--   B1 las paginas 12 y 11 tienen el boton «Volver al inicio» (pagina 1, u-no-print)
--   C1 el combo Modulo de la 17 ofrece Presupuestos
--   C2 el informe tiene la rama de presupuestos y la columna VER_PRESUPUESTO (a la 7)
--   C3 ejecutando la consulta GUARDADA con Modulo=Presupuestos salen presupuestos
--   C4 con Modulo=Ventas no sale ninguno
--   C5 los totales del periodo incluyen la fila de presupuestos
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261124_tres_arreglos_verificacion.sql
-- FALLAS=0 = EXITO. El runner sale con codigo 1 aunque sea verde: se lee el mensaje.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000) := '';
    v_n      number;
    v_txt    varchar2(32767);
    v_sql    varchar2(32767);
    v_bs     number;
    v_usd    number;
    v_bs_exp number;
    v_usd_exp number;
    v_idp    number;
    v_emp    number;

    procedure falla(p_caso varchar2, p_detalle varchar2) is
    begin
        v_fallas := v_fallas + 1;
        v_lista  := v_lista || ' | ' || p_caso || ': ' || p_detalle;
    end;

    -- Ejecuta la consulta de un informe sustituyendo los binds de los filtros.
    function cuenta(p_modulo varchar2, p_tipo varchar2, p_emp number, p_como varchar2) return number is
        s varchar2(32767) := v_sql;
        r number;
    begin
        s := replace(s, ':F_EMPRESA_ACTIVA', to_char(p_emp));
        s := replace(s, ':P17_ID_EMPRESA', 'null');
        s := replace(s, ':P17_CLIENTE', 'null');
        s := replace(s, ':P17_PROVEEDOR', 'null');
        s := replace(s, ':P17_TIPO', '''' || p_tipo || '''');
        s := replace(s, ':P17_DESDE', '''01/01/2020''');
        s := replace(s, ':P17_HASTA', '''31/12/2030''');
        s := replace(s, ':P17_INCLUIR_ANULADAS', '''S''');
        s := replace(s, ':P17_MODULO', '''' || p_modulo || '''');
        execute immediate 'select count(*) from (' || s || ') where modulo = ''' || p_como || ''''
            into r;
        return r;
    end;
begin
    -- ------------------------------------------------------------------ A1
    select count(*) into v_n from all_procedures
     where owner = 'WKSP_SYPEXWS' and object_name = 'PKG_GASTO_REAL'
       and procedure_name = 'FN_TOTAL_GASTO_BS';
    if v_n = 0 then
        falla('A1', 'no existe pkg_gasto_real.fn_total_gasto_bs');
    else
        select max(id_presupuesto) into v_idp from gasto_real;
        if v_idp is not null then
            select nvl(sum(monto_origen * tasa_real), 0), nvl(sum(monto_base_usd), 0)
              into v_bs_exp, v_usd_exp
              from gasto_real where id_presupuesto = v_idp;

            v_bs  := pkg_gasto_real.fn_total_gasto_bs(v_idp);
            v_usd := pkg_gasto_real.fn_total_gasto_usd(v_idp);

            if abs(v_bs - v_bs_exp) > 0.05 then
                falla('A1', 'fn_total_gasto_bs(' || v_idp || ') = ' || v_bs || ' y la suma es ' || v_bs_exp);
            end if;
            if abs(v_usd - v_usd_exp) > 0.05 then
                falla('A1', 'fn_total_gasto_usd(' || v_idp || ') = ' || v_usd || ' y la suma es ' || v_usd_exp);
            end if;
            -- el bug: se mostraban los USD (30) donde van bolivares (27.594,68)
            if v_usd_exp > 0 and v_bs_exp > v_usd_exp * 2 and v_bs <= v_usd_exp then
                falla('A1', 'el gasto en Bs (' || v_bs || ') no es mayor que el de USD (' || v_usd || ')');
            end if;
        end if;
    end if;

    -- ------------------------------------------------------------------ A2 y A3
    select region_source into v_txt
      from apex_260100.apex_application_page_regions
     where application_id = 100 and page_id = 5 and region_name = 'Resumen Financiero';

    if instr(v_txt, 'fn_total_gasto_bs') = 0 then
        falla('A2', 'la tarjeta de la 5 no usa fn_total_gasto_bs');
    end if;
    if instr(v_txt, 'v_gasto_bs / NVL(v_tasa, 1)') = 0 then
        falla('A2', 'la tarjeta de la 5 no lleva el gasto a la moneda del documento');
    end if;
    if instr(v_txt, 'v_total - v_gasto_real') = 0 then
        falla('A2', 'la desviacion ya no se calcula contra el total del documento');
    end if;
    if instr(v_txt, 'Gasto real (') = 0 then
        falla('A3', 'la etiqueta del gasto no dice la moneda');
    end if;
    if instr(v_txt, 'fn_total_gasto_usd') = 0 then
        falla('A3', 'la tarjeta no muestra el detalle en USD');
    end if;

    -- ------------------------------------------------------------------ B1
    select count(*) into v_n
      from apex_260100.apex_application_page_buttons
     where application_id = 100 and page_id in (11, 12) and button_name = 'BTN_VOLVER';
    if v_n <> 2 then
        falla('B1', 'hay ' || v_n || ' botones Volver en las impresiones (se esperaban 2: 11 y 12)');
    end if;

    for r in (select page_id, redirect_url, button_css_classes
                from apex_260100.apex_application_page_buttons
               where application_id = 100 and page_id in (11, 12) and button_name = 'BTN_VOLVER') loop
        if instr(nvl(r.redirect_url, 'x'), ':1:') = 0 then
            falla('B1', 'la pagina ' || r.page_id || ' vuelve a ' || r.redirect_url || ' (no a la 1)');
        end if;
        if instr(nvl(r.button_css_classes, 'x'), 'u-no-print') = 0 then
            falla('B1', 'el boton de la ' || r.page_id || ' se imprimiria (le falta u-no-print)');
        end if;
    end loop;

    -- ------------------------------------------------------------------ C1
    select lov_definition into v_txt
      from apex_260100.apex_application_page_items
     where application_id = 100 and page_id = 17 and item_name = 'P17_MODULO';
    if instr(upper(v_txt), 'PRESUPUESTOS') = 0 then
        falla('C1', 'el combo Modulo no ofrece Presupuestos: ' || v_txt);
    end if;

    -- ------------------------------------------------------------------ C2
    select region_source into v_sql
      from apex_260100.apex_application_page_regions
     where application_id = 100 and page_id = 17 and region_name = 'Reportes Factura y Notas C/D';
    v_txt := v_sql;

    if instr(v_txt, 'ver_presupuesto') = 0 or instr(v_txt, 'from presupuestos p') = 0 then
        falla('C2', 'el informe no trae la rama de presupuestos con su columna');
    end if;

    select count(*) into v_n
      from apex_260100.apex_application_page_ir_col
     where application_id = 100 and page_id = 17 and column_alias = 'VER_PRESUPUESTO';
    if v_n <> 1 then
        falla('C2', 'no existe la columna VER_PRESUPUESTO del informe');
    end if;

    select column_link into v_txt
      from apex_260100.apex_application_page_ir_col
     where application_id = 100 and page_id = 17 and column_alias = 'VER_PRESUPUESTO';
    if instr(v_txt, ':7:') = 0 or instr(v_txt, 'P7_ID_PRESUPUESTO') = 0 then
        falla('C2', 'el enlace de Ver presup. no abre la pagina 7: ' || v_txt);
    end if;

    -- ------------------------------------------------------------------ C3 y C4
    begin
        select id_empresa into v_emp from presupuestos
         where id_presupuesto = (select max(id_presupuesto) from presupuestos);
    exception
        when others then v_emp := 1;
    end;

    v_n := cuenta('PRESUPUESTOS', 'TODOS', v_emp, 'Presupuesto');
    if v_n = 0 then
        falla('C3', 'con Modulo=Presupuestos no sale ningun presupuesto de la empresa ' || v_emp);
    end if;

    if cuenta('PRESUPUESTOS', 'TODOS', v_emp, 'Venta') > 0 then
        falla('C3', 'con Modulo=Presupuestos siguen saliendo ventas');
    end if;
    if cuenta('PRESUPUESTOS', 'TODOS', v_emp, 'Compra') > 0 then
        falla('C3', 'con Modulo=Presupuestos siguen saliendo compras');
    end if;

    v_n := cuenta('VENTAS', 'TODOS', v_emp, 'Presupuesto');
    if v_n > 0 then
        falla('C4', 'con Modulo=Ventas salen ' || v_n || ' presupuestos (no deberia)');
    end if;

    v_n := cuenta('COMPRAS', 'TODOS', v_emp, 'Presupuesto');
    if v_n > 0 then
        falla('C4', 'con Modulo=Compras salen ' || v_n || ' presupuestos (no deberia)');
    end if;

    v_n := cuenta('TODOS', 'TODOS', v_emp, 'Presupuesto');
    if v_n = 0 then
        falla('C4', 'con Modulo=Todos no aparecen los presupuestos');
    end if;

    -- ------------------------------------------------------------------ C5
    select region_source into v_txt
      from apex_260100.apex_application_page_regions
     where application_id = 100 and page_id = 17 and region_name = 'Totales del período';
    if instr(v_txt, '''Presupuesto'' as modulo') = 0 then
        falla('C5', 'los totales del periodo no traen la fila de presupuestos');
    end if;

    raise_application_error(-20100,
        substrb('RESULTADO: FALLAS=' || v_fallas || v_lista, 1, 3000));
end;
/
