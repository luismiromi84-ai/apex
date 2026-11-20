-- =============================================================================
-- 20261119_compra_igtf_libro_verificacion.sql
--
-- El IGTF de las COMPRAS en el Libro de compras y ventas (pagina 18).
--
-- Desde el 2026-11-19 el IGTF de una compra es de CABECERA: se causa con el pago
-- en divisas si la empresa es SPE (Sujeto Pasivo Especial) y la forma de pago lo
-- genera. Hasta hoy el libro solo miraba las lineas con impuesto IGTF, asi que
-- ese 3 % no aparecia por ningun lado. Estas comprobaciones son las que tienen que
-- pasar:
--
--   L1  la region libro-ve calcula el IGTF de cabecera (SPE + forma de pago + divisas)
--   L2  el informe tiene la columna IGTF_COMPRA con su rotulo y su mascara
--   L3  compra en divisas de una empresa SPE con forma de pago que lo genera:
--       3 % del total del documento, en bolivares, y sumado al Total Bs
--   L4  la misma compra en bolivares no causa IGTF
--   L5  la misma compra con la empresa NO SPE no causa IGTF
--   L6  la misma compra con una forma de pago que no lo genera no causa IGTF
--   L7  el Total Bs del periodo (region de totales) lo incluye
--   L8  el Excel fiscal (fn_libro_excel) rotula el IGTF y no arrastra las columnas "Ver"
--   L9  el resumen de la compra (pagina 28) y el libro dicen lo mismo
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261119_compra_igtf_libro_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000) := '';
    v_n      number;
    v_src    clob;
    v_sql    clob;
    v_prov   number;
    v_forma  number;
    v_forma_sin number;
    v_id     number;
    v_igtf   number;
    v_tot    number;
    v_cuadre number;
    v_val    number;
    v_html   clob;
    v_alic   number;

    procedure falla(p_caso varchar2, p_detalle varchar2) is
    begin
        v_fallas := v_fallas + 1;
        v_lista  := v_lista || ' | ' || p_caso || ': ' || substrb(p_detalle, 1, 150);
    end;

    function consulta_libro return clob is
        v clob;
    begin
        select region_source into v
          from apex_260100.apex_application_page_regions
         where application_id = 100 and page_id = 18 and region_static_id = 'libro-ve';
        v := replace(v, ':F_EMPRESA_ACTIVA', '1');
        v := replace(v, ':P18_ID_EMPRESA', 'null');
        v := replace(v, ':P18_LIBRO', '''TODOS''');
        v := replace(v, ':P18_MES', to_char(extract(month from sysdate)));
        v := replace(v, ':P18_ANIO', to_char(extract(year from sysdate)));
        v := replace(v, ':P18_PERIODO', '''MES''');
        return v;
    end;

    -- el IGTF de cabecera que muestra el libro para una compra
    function igtf_del_libro(p_folio varchar2) return number is
        v number;
    begin
        execute immediate 'select nvl(igtf_compra, 0) from (' || consulta_libro()
            || ') where folio = ''' || p_folio || '''' into v;
        return v;
    exception
        when others then return -999;
    end;

    function total_del_libro(p_folio varchar2) return number is
        v number;
    begin
        execute immediate 'select nvl(total_bs, 0) from (' || consulta_libro()
            || ') where folio = ''' || p_folio || '''' into v;
        return v;
    exception
        when others then return -999;
    end;
begin
    -- L1: la region calcula el IGTF de cabecera
    select region_source into v_src
      from apex_260100.apex_application_page_regions
     where application_id = 100 and page_id = 18 and region_static_id = 'libro-ve';
    if instr(upper(v_src), 'IGTF_COMPRA') = 0
       or instr(upper(v_src), 'ES_SPE') = 0
       or instr(upper(v_src), 'GENERA_IGTF') = 0
       or instr(upper(v_src), 'ALICUOTA_IGTF') = 0 then
        falla('L1', 'libro-ve no calcula el IGTF de cabecera de las compras');
    end if;

    -- L2: la columna del informe
    select count(*) into v_n
      from apex_260100.apex_application_page_ir_col
     where application_id = 100 and page_id = 18
       and region_name = 'Libro de Venezuela'
       and column_alias = 'IGTF_COMPRA'
       and lower(report_label) like '%igtf%compra%'
       and format_mask is not null;
    if v_n <> 1 then
        falla('L2', 'el informe no tiene la columna IGTF_COMPRA con rotulo y mascara');
    end if;

    -- De aqui en adelante se crea una compra de prueba y se revierte
    savepoint sp_ligtf;

    select min(id_proveedor) into v_prov from proveedores where id_empresa = 1;
    select min(id_forma_pago) into v_forma from forma_pago where genera_igtf = 'S' and activo = 'Y';
    select min(id_forma_pago) into v_forma_sin from forma_pago where genera_igtf = 'N' and activo = 'Y';
    if v_prov is null or v_forma is null or v_forma_sin is null then
        falla('L3', 'faltan datos base (proveedor o formas de pago)');
        raise_application_error(-20100, 'RESULTADO: FALLAS=' || v_fallas || v_lista);
    end if;

    v_id := null;
    pkg_compras.prc_guardar_compra(
        p_id_compra => v_id, p_id_empresa => 1, p_id_proveedor => v_prov,
        p_tipo_documento => 'FAC', p_folio_factura => 'LIBROIGTF-1', p_nro_control => '00-000900',
        p_fecha_emision => trunc(sysdate), p_cod_moneda => 'USD', p_tipo_cambio => 900,
        p_porcentaje_retencion => 0, p_id_forma_pago => v_forma, p_usuario => 'admin');

    insert into compras_det (id_compra, num_linea, descripcion, cantidad, precio_unitario,
                             subtotal_linea, porcentaje_impuesto, monto_impuesto, total_linea,
                             tasa_cambio_aplicada, subtotal_bs, total_bs)
    values (v_id, 1, 'Linea gravada', 1, 100, 100, 16, 16, 116, 900, 90000, 104400);

    -- L4: en bolivares no hay IGTF
    update compras set cod_moneda = 'VES', tipo_cambio = 1 where id_compra = v_id;
    if igtf_del_libro('LIBROIGTF-1') <> 0 then
        falla('L4', 'el libro calcula IGTF en una compra en bolivares: ' || igtf_del_libro('LIBROIGTF-1'));
    end if;

    -- L3: en divisas, empresa SPE y forma de pago que lo genera
    update compras set cod_moneda = 'USD', tipo_cambio = 900 where id_compra = v_id;
    select nvl(fn_alicuota_igtf(1), 0) into v_alic from dual;
    v_igtf := igtf_del_libro('LIBROIGTF-1');
    v_tot  := total_del_libro('LIBROIGTF-1');
    if v_alic <= 0 then
        falla('L3', 'la empresa 1 no tiene alicuota de IGTF configurada');
    elsif abs(v_igtf - round(round(116 * v_alic / 100, 2) * 900, 2)) > 0.01 then
        falla('L3', 'IGTF de la compra en el libro = ' || v_igtf || ' en vez de '
            || round(round(116 * v_alic / 100, 2) * 900, 2));
    end if;
    -- y el Total Bs del documento lo incluye
    begin
        execute immediate 'select abs(total_bs - (nvl(base16,0)+nvl(iva16,0)+nvl(exento,0)'
            || '+nvl(base_igtf,0)+nvl(igtf,0)+nvl(otras_base,0)+nvl(otras_iva,0)'
            || '+nvl(igtf_compra,0))) from (' || consulta_libro()
            || ') where folio = ''LIBROIGTF-1''' into v_cuadre;
        if v_cuadre > 0.01 then
            falla('L3', 'el Total Bs no cuadra con sus componentes (dif ' || v_cuadre || ')');
        end if;
    exception
        when others then
            falla('L3', 'no se pudo comprobar el cuadre del Total Bs: ' || substrb(sqlerrm, 1, 100));
    end;
    if abs(v_tot - (104400 + round(round(116 * v_alic / 100, 2) * 900, 2))) > 0.01 then
        falla('L3', 'Total Bs del documento = ' || v_tot || ' sin el IGTF');
    end if;

    -- L5: la empresa no es SPE
    update empresas set es_spe = 'N' where id_empresa = 1;
    if igtf_del_libro('LIBROIGTF-1') <> 0 then
        falla('L5', 'el libro calcula IGTF con una empresa que no es SPE');
    end if;
    update empresas set es_spe = 'S' where id_empresa = 1;

    -- L6: la forma de pago no lo genera
    update compras set id_forma_pago = v_forma_sin where id_compra = v_id;
    if igtf_del_libro('LIBROIGTF-1') <> 0 then
        falla('L6', 'el libro calcula IGTF con una forma de pago que no lo genera');
    end if;
    update compras set id_forma_pago = v_forma where id_compra = v_id;

    -- L7: los totales del mes lo incluyen
    begin
        select region_source into v_sql
          from apex_260100.apex_application_page_regions
         where application_id = 100 and page_id = 18 and region_static_id = 'libro-ve-totales';
        v_sql := replace(v_sql, ':F_EMPRESA_ACTIVA', '1');
        v_sql := replace(v_sql, ':P18_ID_EMPRESA', 'null');
        v_sql := replace(v_sql, ':P18_LIBRO', '''TODOS''');
        v_sql := replace(v_sql, ':P18_MES', to_char(extract(month from sysdate)));
        v_sql := replace(v_sql, ':P18_ANIO', to_char(extract(year from sysdate)));
        v_sql := replace(v_sql, ':P18_PERIODO', '''MES''');
        v_sql := replace(v_sql, 'return ', ':v_out := ');
        execute immediate to_clob(v_sql) using out v_html;
        if instr(upper(v_html), 'IGTF') = 0 then
            falla('L7', 'los totales del mes no muestran el IGTF de compras');
        elsif instr(v_html, to_char(round(round(116 * v_alic / 100, 2) * 900, 2),
                                    'FM999G999G999G990D00')) = 0 then
            falla('L7', 'los totales del mes no suman el IGTF de compras');
        end if;
    exception
        when others then
            falla('L7', 'no se pudo ejecutar la region de totales: ' || substrb(sqlerrm, 1, 120));
    end;

    -- L8: el Excel fiscal
    begin
        v_html := fn_libro_excel(p_libro => 'COMPRAS',
                                 p_mes => extract(month from sysdate),
                                 p_anio => extract(year from sysdate),
                                 p_id_empresa => 1);
        if instr(upper(v_html), 'VER_COMPRA') > 0 then
            falla('L8', 'el Excel fiscal saca la columna del enlace Ver compra');
        end if;
        if instr(upper(v_html), 'IGTF COMPRA') = 0 then
            falla('L8', 'el Excel fiscal no rotula la columna del IGTF de compras');
        end if;
        if instr(v_html, to_char(round(round(116 * v_alic / 100, 2) * 900, 2),
                                 'FM999999999999999990.00',
                                 'NLS_NUMERIC_CHARACTERS=''.,''')) = 0 then
            falla('L8', 'el Excel fiscal no suma el IGTF de compras');
        end if;
    exception
        when others then
            falla('L8', 'no se pudo generar el Excel: ' || substrb(sqlerrm, 1, 120));
    end;

    -- L9: el resumen de la compra (pagina 28) y el libro dicen lo mismo
    begin
        select region_source into v_sql
          from apex_260100.apex_application_page_regions
         where application_id = 100 and page_id = 28 and region_static_id = 'compra-resumen';
        v_sql := replace(v_sql, ':P28_ID_COMPRA', to_char(v_id));
        v_sql := replace(v_sql, 'return ', ':v_out := ');
        execute immediate to_clob(v_sql) using out v_html;
        -- El resumen pinta los bolivares con NLS_NUMERIC_CHARACTERS=',.' (miles con
        -- punto y decimales con coma), como el impreso; el esperado se formatea igual
        -- o el instr no encuentra nada aunque el numero sea el correcto.
        if instr(v_html, to_char(round(116 * v_alic / 100, 2), 'FM999G999G999G990D00',
                                 'NLS_NUMERIC_CHARACTERS='',.''')) = 0 then
            falla('L9', 'el resumen de la compra no muestra el IGTF en Bs');
        end if;
        if instr(v_html, to_char(104400 + round(round(116 * v_alic / 100, 2) * 900, 2),
                                 'FM999G999G999G990D00', 'NLS_NUMERIC_CHARACTERS='',.''')) = 0 then
            falla('L9', 'el neto del resumen no cuadra con el libro (107.532,00 esperado)');
        end if;
    exception
        when others then
            falla('L9', 'no se pudo ejecutar el resumen de la compra: ' || substrb(sqlerrm, 1, 110));
    end;

    rollback to sp_ligtf;

    raise_application_error(-20100,
        substrb('RESULTADO: FALLAS=' || v_fallas || v_lista, 1, 3000));
end;
/
