-- =============================================================================
-- 20261119_compra_igtf_libro.sql
--
-- El IGTF de las COMPRAS en el libro (pagina 18). Desde el 2026-11-19 el IGTF de
-- una compra es de CABECERA (empresa SPE + FORMA_PAGO.GENERA_IGTF + documento en
-- divisas), asi que el libro no lo veia: solo miraba las lineas con impuesto IGTF.
--
-- La pantalla viaja en pagina_apex/f100.sql (columna «IGTF compra» del informe de
-- Venezuela y fila «IGTF de compras Bs» en los totales del mes). Aquí va lo que
-- vive en la base:
--   1. fn_libro_excel: rotula la columna IGTF_COMPRA y deja fuera del Excel
--      TODAS las columnas VER_* (antes solo VER_ID: con «Ver compra» el archivo
--      sacaba una columna de mas y descuadraba la fila de TOTALES).
--
-- Reversa: volver a la version anterior de la funcion (git) y recompilar.
-- Verificacion: deploy/diagnostico/20261119_compra_igtf_libro_verificacion.sql
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

-- =============================================================================
-- fn_libro_excel.sql
--
-- Devuelve el «Excel fiscal» del Libro de compras y ventas (página 18) como un
-- documento HTML que Excel abre con formato: membrete (empresa, RIF y período),
-- cabecera, una fila por documento y una fila de TOTALES.
--
-- Por qué HTML y no XLSX: el botón nativo del informe (XLSX) exporta las columnas
-- del informe con sus máscaras, pero sin membrete ni totales. Este documento es
-- autónomo, trae los importes como NÚMEROS y deja el RIF y el N° de Control como
-- TEXTO (así Excel no se come los ceros a la izquierda).
--
-- La consulta NO se copia: se ejecuta la que tiene guardada el informe, con sus
-- binds sustituidos. Una sola fuente de verdad con la pantalla.
-- =============================================================================

create or replace function fn_libro_excel (
    p_libro      in varchar2,     -- 'VENTAS' | 'COMPRAS' | 'TODOS'
    p_mes        in number,
    p_anio       in number,
    p_id_empresa in number,
    p_periodo    in varchar2 default 'MES',   -- 'MES' | 'Q1' | 'Q2'
    p_imprimir   in varchar2 default 'N'      -- 'S' = versión para imprimir/PDF
) return clob is
    type t_suma is table of number index by binary_integer;

    v_region  number;
    v_sql     clob;
    v_html    clob;
    v_c       integer;
    v_ncols   number;
    v_dummy   number;
    v_desc    dbms_sql.desc_tab;
    v_vc      varchar2(4000);
    v_txt     varchar2(4000);
    v_num     number;
    v_empresa varchar2(200);
    v_rif     varchar2(40);
    v_pais    varchar2(2);
    v_filas   number := 0;
    v_hay     number;
    v_mes_tx  varchar2(20);
    v_sumas   t_suma;
    v_primera boolean := true;
begin
    -- 1. La consulta guardada del informe. El libro que se imprime depende del
    -- PAIS de la empresa (Venezuela o Mexico), no del filtro de tipo: son dos
    -- regiones distintas, con columnas fiscales distintas.
    select e.nombre_empresa, fn_formato_rif(e.rfc), nvl(e.cod_pais, 'VE')
      into v_empresa, v_rif, v_pais
      from empresas e
     where e.id_empresa = p_id_empresa;

    if v_pais = 'MX' then
        v_region := 43000000000000740;   -- Libro de Mexico
    else
        v_region := 43000000000000710;   -- Libro de Venezuela
    end if;

    select region_source into v_sql
      from apex_application_page_regions
     where application_id = 100 and region_id = v_region;

    v_sql := replace(v_sql, ':F_EMPRESA_ACTIVA', to_char(p_id_empresa));
    v_sql := replace(v_sql, ':P18_ID_EMPRESA', to_char(p_id_empresa));
    v_sql := replace(v_sql, ':P18_LIBRO', '''' || upper(nvl(p_libro, 'TODOS')) || '''');
    v_sql := replace(v_sql, ':P18_MES', to_char(p_mes));
    v_sql := replace(v_sql, ':P18_ANIO', to_char(p_anio));
    v_sql := replace(v_sql, ':P18_PERIODO', '''' || upper(nvl(p_periodo, 'MES')) || '''');
    v_sql := replace(v_sql, ':APP_USER', '''');

    -- 2. Membrete (la empresa ya se leyo arriba, para elegir el libro)
    v_mes_tx := lpad(to_char(p_mes), 2, '0') || '/' || to_char(p_anio);

    v_html := '<html><head><meta http-equiv="Content-Type" content="text/html; charset=utf-8">'
           || '<style>'
           || 'table { border-collapse: collapse; font-family: Arial, sans-serif; font-size: 11px; }'
           || 'td, th { border: 1px solid #b8c4cc; padding: 3px 6px; }'
           || 'th { background: #0076ce; color: #fff; font-weight: bold; }'
           || '.titulo { font-size: 16px; font-weight: bold; }'
           || '.sub { font-size: 12px; color: #334155; margin: 4px 0 8px 0; }'
           || '.num { mso-number-format:"#\,##0\.00"; text-align: right; }'
           || '.txt { mso-number-format:"\@"; }'
           || '.fec { mso-number-format:"dd\/mm\/yyyy"; }'
           || '.tot { background: #eaf3f6; font-weight: bold; }'
           || case when upper(nvl(p_imprimir, 'N')) = 'S' then
                  -- version para imprimir / PDF: A4 horizontal, la cabecera se repite
                  -- en cada pagina y el navegador abre el dialogo de impresion solo.
                  '@page { size: A4 landscape; margin: 8mm; }'
                  || 'body { margin: 0; }'
                  || 'thead { display: table-header-group; }'
                  || 'tr { page-break-inside: avoid; }'
                  || 'th { -webkit-print-color-adjust: exact; print-color-adjust: exact; }'
              else '' end
           || '</style>'
           || case when upper(nvl(p_imprimir, 'N')) = 'S' then
                  '<title>Libro de compras y ventas</title>'
                  || '<script>window.addEventListener("load", function () {'
                  || '  window.addEventListener("afterprint", function () { window.history.back(); });'
                  || '  window.print();});</script>'
              else '' end
           || '</head><body>'
           || '<div class="titulo">' || sys.htf.escape_sc(v_empresa) || '</div>'
           || '<div class="sub">'
           || case when v_pais = 'MX' then 'RFC: ' else 'RIF: ' end
           || sys.htf.escape_sc(v_rif)
           || ' &nbsp;&nbsp; Libro de compras y ventas - ' || v_mes_tx
           || case upper(nvl(p_periodo, 'MES'))
                  when 'Q1' then ' (1ra quincena: 1 al 15)'
                  when 'Q2' then ' (2da quincena: 16 al final)'
                  else ' (mes completo)'
              end
           || ' &nbsp;&nbsp; Documentos: '
           || case upper(nvl(p_libro, 'TODOS'))
                  when 'VENTAS'  then 'ventas'
                  when 'COMPRAS' then 'compras'
                  else 'compras y ventas'
              end
           || '</div>';

    -- 3. La consulta, en un cursor dinámico
    v_c := dbms_sql.open_cursor;
    dbms_sql.parse(v_c, v_sql, dbms_sql.native);
    dbms_sql.describe_columns(v_c, v_ncols, v_desc);
    for i in 1 .. v_ncols loop
        if v_desc(i).col_type = dbms_sql.number_type then
            dbms_sql.define_column(v_c, i, v_num);
            v_sumas(i) := 0;
        else
            dbms_sql.define_column(v_c, i, v_vc, 4000);
        end if;
    end loop;
    v_dummy := dbms_sql.execute(v_c);

    -- 4. Cabecera
    v_html := v_html || '<table><thead><tr>';
    for i in 1 .. v_ncols loop
        -- Las columnas de enlace del informe («Ver» de la factura y «Ver compra»)
        -- no van en el Excel fiscal: se reconocen por su alias (VER_...), no por
        -- la posicion, para que un cambio en el informe no descuadre el archivo.
        if substr(upper(v_desc(i).col_name), 1, 4) <> 'VER_' then
            v_html := v_html || '<th>' || sys.htf.escape_sc(
                case upper(v_desc(i).col_name)
                    when 'LIBRO' then 'Libro'
                    when 'FECHA_EMISION' then 'Fecha'
                    when 'RIF' then case when v_pais = 'MX' then 'RFC' else 'RIF' end
                    when 'RAZON_SOCIAL' then 'Raz' || unistr('\00F3') || 'n social'
                    when 'TIPO' then 'Tipo'
                    when 'FOLIO' then 'N' || unistr('\00BA') || ' factura'
                    when 'NRO_CONTROL' then case when v_pais = 'MX' then 'UUID (CFDI)'
                                                 else 'N' || unistr('\00BA') || ' control' end
                    when 'MONEDA' then 'Moneda'
                    when 'TASA' then 'Tasa BCV'
                    when 'TOTAL_DIVISA' then 'Total en divisa'
                    when 'BASE16' then 'Base 16%'
                    when 'IVA16' then 'IVA 16%'
                    when 'BASE8' then 'Base 8%'
                    when 'IVA8' then 'IVA 8%'
                    when 'EXENTO' then 'Exento'
                    when 'BASE_IGTF' then 'Base IGTF'
                    when 'IGTF' then 'IGTF 3%'
                    when 'IGTF_COMPRA' then 'IGTF compra'
                    when 'OTRAS_BASE' then 'Otras base'
                    when 'OTRAS_IVA' then 'Otras IVA'
                    when 'TOTAL_BS' then 'Total Bs'
                    when 'COMPROBANTE' then 'N' || unistr('\00BA') || ' comp. retenci' || unistr('\00F3') || 'n'
                    when 'RETENCION_BS' then 'IVA retenido Bs'
                    when 'NETO' then 'Neto Bs'
                    when 'ESTADO' then 'Estado'
                    when 'AFECTADA' then 'Documento afectado'
                    else upper(v_desc(i).col_name)
                end) || '</th>';
        end if;
    end loop;
    v_html := v_html || '</tr></thead><tbody>';

    -- 5. Filas
    -- OJO: aqui no se usa "exit": importar_export.py descarta las lineas que empiezan
    -- por "exit" y el bucle quedaria SIN SALIDA (cuelgue medido el 2026-11-18). Se
    -- recorre con un while.
    v_hay := dbms_sql.fetch_rows(v_c);
    while v_hay > 0 loop
        v_filas := v_filas + 1;
        v_html := v_html || '<tr>';
        for i in 1 .. v_ncols loop
            continue when substr(upper(v_desc(i).col_name), 1, 4) = 'VER_';
            if v_desc(i).col_type = dbms_sql.number_type then
                dbms_sql.column_value(v_c, i, v_num);
                if v_num is not null then
                    v_sumas(i) := v_sumas(i) + v_num;
                end if;
                v_html := v_html || '<td class="num">'
                    || case when v_num is null then ''
                            else to_char(v_num, 'FM999999999999999990.00',
                                         'NLS_NUMERIC_CHARACTERS=''.,''') end
                    || '</td>';
            else
                dbms_sql.column_value(v_c, i, v_vc);
                if upper(v_desc(i).col_name) like '%FECHA%' then
                    -- La consulta del informe devuelve la fecha ya formateada por
                    -- TO_CHAR (p. ej. 07-NOV-26). Se normaliza a dd/mm/aaaa para
                    -- que Excel la reconozca como fecha y no dependa del idioma de
                    -- los nombres de mes de la sesion.
                    v_txt := v_vc;
                    if v_txt is not null then
                        begin
                            v_txt := to_char(to_date(v_txt, 'DD-MON-RR',
                                                     'NLS_DATE_LANGUAGE=SPANISH'), 'DD/MM/YYYY');
                        exception
                            when others then
                                begin
                                    v_txt := to_char(to_date(v_txt, 'DD-MON-RR',
                                                             'NLS_DATE_LANGUAGE=ENGLISH'), 'DD/MM/YYYY');
                                exception
                                    when others then null;   -- se deja tal cual
                                end;
                        end;
                    end if;
                    v_html := v_html || '<td class="fec">' || sys.htf.escape_sc(nvl(v_txt, ' ')) || '</td>';
                else
                    v_html := v_html || '<td class="txt">' || sys.htf.escape_sc(nvl(v_vc, ' ')) || '</td>';
                end if;
            end if;
        end loop;
        v_html := v_html || '</tr>';
        v_hay := dbms_sql.fetch_rows(v_c);
    end loop;

    dbms_sql.close_cursor(v_c);

    -- 6. Totales: la suma de cada columna de dinero, calculada al recorrer las
    -- filas. La etiqueta TOTALES va en la primera celda que se pinta.
    v_html := v_html || '</tbody><tfoot><tr class="tot">';
    v_primera := true;
    for i in 1 .. v_ncols loop
        if substr(upper(v_desc(i).col_name), 1, 4) = 'VER_' then
            continue;
        end if;
        if v_primera then
            v_html := v_html || '<td class="txt">TOTALES</td>';
            v_primera := false;
        elsif v_desc(i).col_type = dbms_sql.number_type
              and upper(v_desc(i).col_name) <> 'TASA' then
            v_html := v_html || '<td class="num">'
                || to_char(v_sumas(i), 'FM999999999999999990.00',
                           'NLS_NUMERIC_CHARACTERS=''.,''') || '</td>';
        else
            v_html := v_html || '<td class="txt"></td>';   -- una tasa o un texto no se suman
        end if;
    end loop;
    v_html := v_html || '</tr></tfoot></table>'
           || '<p class="sub">Documentos: ' || v_filas || ' - generado el '
           || to_char(sysdate, 'DD/MM/YYYY HH24:MI') || '</p>'
           || '</body></html>';

    return v_html;
exception
    when others then
        if dbms_sql.is_open(v_c) then
            dbms_sql.close_cursor(v_c);
        end if;
        raise;
end fn_libro_excel;
/

begin
    dbms_utility.compile_schema('WKSP_SYPEXWS', false);
end;
/

declare
    v_n    number;
    v_html clob;
begin
    select count(*) into v_n from all_objects
     where owner = 'WKSP_SYPEXWS' and object_name = 'FN_LIBRO_EXCEL' and status = 'VALID';
    if v_n < 1 then
        raise_application_error(-20112, 'FN_LIBRO_EXCEL quedo invalida');
    end if;

    -- la region de Venezuela tiene que traer el IGTF de cabecera de las compras
    select count(*) into v_n
      from apex_application_page_regions
     where application_id = 100 and page_id = 18 and region_static_id = 'libro-ve'
       and instr(upper(region_source), 'IGTF_COMPRA') > 0
       and instr(upper(region_source), 'GENERA_IGTF') > 0;
    if v_n <> 1 then
        raise_application_error(-20112, 'la region libro-ve no trae el IGTF de las compras');
    end if;

    -- y el Excel fiscal lo rotula y no arrastra las columnas de enlace
    v_html := fn_libro_excel('COMPRAS', extract(month from sysdate),
                             extract(year from sysdate), 1);
    if instr(upper(v_html), 'VER_COMPRA') > 0 then
        raise_application_error(-20112, 'el Excel fiscal saca la columna del enlace Ver compra');
    end if;
    if instr(upper(v_html), 'IGTF COMPRA') = 0 then
        raise_application_error(-20112, 'el Excel fiscal no rotula el IGTF de compras');
    end if;
end;
/
