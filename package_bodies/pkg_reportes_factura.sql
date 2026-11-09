create or replace PACKAGE BODY pkg_reportes_factura AS

    -- -------------------------------------------------------------------------
    -- Utilidades internas (mismas reglas que pkg_reportes_presupuesto)
    -- -------------------------------------------------------------------------

    -- Importes con punto decimal fijo: no dependen de NLS_NUMERIC_CHARACTERS.
    FUNCTION fn_num (p_valor IN NUMBER, p_mascara IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(p_valor, p_mascara, 'NLS_NUMERIC_CHARACTERS=''.,''');
    END fn_num;

    -- Igual que fn_num pero con el formato de Venezuela: punto de miles y coma decimal,
    -- que es como va la factura fiscal (el generico usa el formato de EE.UU.).
    FUNCTION fn_num_ve (p_valor IN NUMBER, p_mascara IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(p_valor, p_mascara, 'NLS_NUMERIC_CHARACTERS='',.''');
    END fn_num_ve;

    -- Antes, una factura inexistente devolvia un documento con "Sypex Systems"
    -- y totales en cero que parecia valido.
    FUNCTION fn_aviso (p_texto IN VARCHAR2) RETURN CLOB IS
    BEGIN
        RETURN q'~<div class="doc-aviso">
  <p><strong>No se puede imprimir la factura.</strong></p>
  <p>~' || sys.htf.escape_sc(p_texto) || q'~</p>
</div>~';
    END fn_aviso;

    FUNCTION fn_css RETURN VARCHAR2 IS
    BEGIN
        RETURN q'~
<style>
  @media print {
    .t-Header, .t-Footer, .t-Button, .u-no-print, #u-DevToolbar,
    .apex-developer-toolbar, .a-DevToolbar, header, footer,
    .apex-toolbar, .a-Toolbar, div[role="contentinfo"],
    .t-Body-nav, .t-Header-branding { display: none !important; }
    body, html { background: #ffffff !important; height: auto !important; overflow: visible !important; }
    .t-Body, .t-Body-content, .t-Body-mainContent {
      display: block !important; position: static !important;
      width: 100% !important; margin: 0 !important; padding: 0 !important;
    }
    .t-Body-main { margin-left: 0 !important; padding: 0 !important; }

    /* Lo unico visible al imprimir es el documento. No depende de los nombres
       de clase del tema: si APEX cambia el chrome (barra, menu, botones), esto
       sigue funcionando. Se probo con la lista de clases de arriba y el marco
       seguia saliendo. */
    body * { visibility: hidden !important; }
    .doc-container, .doc-container * { visibility: visible !important; }
    .doc-container {
      position: absolute !important; left: 0 !important; top: 0 !important;
      width: 100% !important; max-width: none !important;
      border: 0 !important; margin: 0 !important; padding: 0 !important;
    }
  }
  .doc-aviso {
    font-family: Arial, sans-serif; max-width: 800px; margin: 40px auto; padding: 18px 20px;
    border: 1px solid #fecaca; border-radius: 8px; background: #fef2f2; color: #991b1b; font-size: 14px;
  }
  .doc-container {
    font-family: Arial, sans-serif; max-width: 800px; margin: 0 auto; padding: 20px;
    color: #333; border: 1px solid #ddd; background: #fff;
  }
  .header-table, .details-table, .totals-table { width: 100%; border-collapse: collapse; margin-bottom: 20px; }
  .header-table td { vertical-align: top; }
  .empresa-info h2 { margin: 0; color: #005b96; }
  .doc-box { border: 2px solid #005b96; padding: 10px; text-align: center; border-radius: 5px; }
  .details-table th, .details-table td {
    border: 1px solid #ddd; padding: 8px; text-align: left; font-size: 12px;
  }
  .details-table th { background-color: #f4f4f4; }
  .text-right { text-align: right; }
  .totals-section { float: right; width: 420px; }
  .totals-table td { padding: 5px 10px; font-size: 13px; }
</style>~';
    END fn_css;

    -- -------------------------------------------------------------------------
    -- Reporte
    -- -------------------------------------------------------------------------

    FUNCTION fn_imprimir_factura_generica (p_id_factura IN NUMBER) RETURN CLOB IS
        v_empresa         VARCHAR2(200);
        v_id_empresa      NUMBER;
        v_logo            CLOB;
        v_ident_empresa   VARCHAR2(50);
        v_ident_label     VARCHAR2(20);
        v_cliente_label   VARCHAR2(30);
        v_cod_pais        VARCHAR2(2);
        v_moneda_local    VARCHAR2(3);
        v_tasa_label      VARCHAR2(30) := 'Tipo de cambio';
        v_simbolo_local   VARCHAR2(10) := '';
        v_simbolo_doc     VARCHAR2(10) := '';
        v_total_local_lbl VARCHAR2(30) := 'TOTAL';
        v_mostrar_local   BOOLEAN      := FALSE;

        v_folio           VARCHAR2(50);
        v_control         VARCHAR2(50);
        v_fecha           VARCHAR2(50);
        v_cliente         VARCHAR2(200);
        v_rif_cliente     VARCHAR2(50);
        v_condicion       VARCHAR2(100);
        v_tasa            NUMBER;
        v_moneda_doc      VARCHAR2(3);
        v_fecha_doc       DATE;
        v_tasa_usd        NUMBER := 1;
        v_factor_usd      NUMBER := 1;
        v_factor_local    NUMBER := 1;
        v_usd_subtotal    NUMBER := 0;
        v_usd_iva         NUMBER := 0;
        v_usd_desc        NUMBER := 0;
        v_usd_total       NUMBER := 0;
        v_local_total     NUMBER := 0;

        v_subtotal        NUMBER := 0;
        v_iva             NUMBER := 0;
        v_total           NUMBER := 0;
        v_desc_total      NUMBER := 0;

        v_html            CLOB;
    BEGIN
        IF p_id_factura IS NULL THEN
            RETURN fn_aviso('No se recibio el identificador de la factura.');
        END IF;

        -- 1. Cabecera
        BEGIN
            SELECT e.id_empresa, e.nombre_empresa, e.rfc, f.folio_factura, f.uuid_fiscal,
                   TO_CHAR(f.fecha_emision, 'DD/MM/YYYY'),
                   c.razon_social, c.rif,
                   nvl(cp.descripcion, 'Contado'),
                   f.tipo_cambio,
                   nvl(f.subtotal, 0), nvl(f.monto_impuesto, 0), nvl(f.monto_total, 0),
                   nvl(e.tipo_ident_fiscal, 'RIF'), nvl(e.cod_pais, 'VE'),
                   nvl(pa.moneda_local, 'USD'), f.cod_moneda, f.fecha_emision
              INTO v_id_empresa, v_empresa, v_ident_empresa, v_folio, v_control,
                   v_fecha, v_cliente, v_rif_cliente,
                   v_condicion, v_tasa,
                   v_subtotal, v_iva, v_total,
                   v_ident_label, v_cod_pais, v_moneda_local, v_moneda_doc, v_fecha_doc
              FROM facturas f
              JOIN empresas e
                ON e.id_empresa = f.id_empresa
              JOIN clientes c
                ON c.id_cliente = f.id_cliente
              LEFT JOIN condicion_pago cp
                ON cp.id_condicion_pago = f.condicion_pago
              LEFT JOIN paises pa
                ON pa.cod_pais = e.cod_pais
             WHERE f.id_factura = p_id_factura;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RETURN fn_aviso('No existe la factura ' || p_id_factura
                             || '. Revisa el enlace e intenta de nuevo.');
        END;

        -- 2. Etiquetas segun el pais de la empresa emisora
        IF v_cod_pais = 'MX' THEN
            v_cliente_label := 'RFC';
        ELSIF v_cod_pais = 'VE' THEN
            v_cliente_label := 'RIF / C&eacute;dula';
        ELSE
            v_cliente_label := nvl(sys.htf.escape_sc(v_ident_label),
                                   'Identificaci&oacute;n fiscal');
        END IF;

        IF v_moneda_local = 'VES' THEN
            v_tasa_label      := 'Tasa BCV';
            v_simbolo_local   := 'Bs.';
            v_total_local_lbl := 'TOTAL BS';
            v_mostrar_local   := TRUE;
        ELSIF v_moneda_local = 'USD' THEN
            v_tasa_label      := 'Tipo de cambio';
        ELSIF v_moneda_local = 'MXN' THEN
            v_tasa_label      := 'Tipo de cambio';
            v_simbolo_local   := 'MXN $';
            v_total_local_lbl := 'TOTAL MXN';
            v_mostrar_local   := TRUE;
        ELSE
            v_tasa_label      := 'Tipo de cambio';
            v_simbolo_local   := v_moneda_local;
            v_total_local_lbl := 'TOTAL ' || v_moneda_local;
            v_mostrar_local   := TRUE;
        END IF;

        -- 2 bis. Factores de conversion. `v_total` y las lineas estan en la moneda DEL DOCUMENTO
        -- (f.cod_moneda). Para pasar a USD o a la moneda local se usa la tasa del documento contra
        -- el bolivar, que es como se guarda TIPO_CAMBIO:
        --   importe_en_X = importe_doc * (tasa_doc_a_ves / tasa_X_a_ves)
        -- Asi un documento en VES tambien muestra su equivalente en dolares, y uno en USD su
        -- equivalente en bolivares; antes las dos lineas salian con el mismo numero.
        v_tasa_usd     := nvl(fn_tasa_ves(v_fecha_doc, 'USD'), 1);
        IF v_tasa_usd = 0 THEN
            v_tasa_usd := 1;
        END IF;
        v_factor_usd   := nvl(v_tasa, 1) / v_tasa_usd;
        v_factor_local := nvl(v_tasa, 1) / nvl(fn_tasa_ves(v_fecha_doc, v_moneda_local), 1);
        v_simbolo_doc  := CASE UPPER(v_moneda_doc)
                               WHEN 'USD' THEN '$'
                               WHEN 'VES' THEN 'Bs.'
                               WHEN 'MXN' THEN 'MXN $'
                               ELSE UPPER(v_moneda_doc)
                          END;

        v_usd_subtotal := ROUND(v_subtotal * v_factor_usd, 2);
        v_usd_iva      := ROUND(v_iva * v_factor_usd, 2);
        v_usd_desc     := ROUND(v_desc_total * v_factor_usd, 2);
        v_usd_total    := ROUND(v_total * v_factor_usd, 2);
        v_local_total  := ROUND(v_total * v_factor_local, 2);

        -- 3. Cabecera del documento
        v_logo := pkg_empresa_logo.fn_logo_img(
            v_id_empresa,
            'max-height:64px;max-width:220px;display:block;margin:0 0 8px 0;');

        v_html := fn_css() || q'~
<div class="doc-container">
  <table class="header-table">
    <tr>
      <td class="empresa-info" style="width: 60%;">~'
      || v_logo
      || q'~
        <h2>~' || sys.htf.escape_sc(v_empresa) || q'~</h2>
        <p><strong>~' || sys.htf.escape_sc(v_ident_label) || q'~:</strong> ~'
        || sys.htf.escape_sc(v_ident_empresa) || q'~<br>
            Sistema de Facturaci&oacute;n Multimoneda B2B</p>
      </td>
      <td style="width: 40%;">
        <div class="doc-box">
          <h3 style="margin: 0; color: #005b96;">FACTURA DE VENTA</h3>
          <p style="margin: 5px 0;"><strong>N&ordm;:</strong> ~' || sys.htf.escape_sc(v_folio) || q'~<br>~';

        -- El numero de control solo se imprime cuando la factura esta timbrada.
        IF v_control IS NOT NULL THEN
            v_html := v_html || q'~
             <strong>N&ordm; Control:</strong> ~' || sys.htf.escape_sc(v_control) || q'~<br>~';
        END IF;

        v_html := v_html || q'~
             <strong>Fecha:</strong> ~' || nvl(v_fecha, 'N/D') || q'~</p>
        </div>
      </td>
    </tr>
  </table>

  <table style="width: 100%; margin-bottom: 20px; font-size: 13px; background: #f9f9f9; padding: 10px; border-radius: 4px;">
    <tr>
      <td><strong>Cliente:</strong> ~' || sys.htf.escape_sc(v_cliente) || q'~</td>
      <td><strong>~' || v_cliente_label || q'~:</strong> ~' || sys.htf.escape_sc(v_rif_cliente) || q'~</td>
    </tr>
    <tr>
      <td><strong>Condici&oacute;n de Pago:</strong> ~' || sys.htf.escape_sc(v_condicion) || q'~</td>
      <td><strong>~' || v_tasa_label || q'~:</strong> ~' || fn_num(nvl(v_tasa, 1), 'FM999,999,99990.0000')
      || ' ' || CASE WHEN v_mostrar_local THEN v_moneda_local ELSE 'USD' END || q'~</td>
    </tr>
  </table>

  <table class="details-table">
    <thead>
      <tr>
        <th>Item</th>
        <th>Descripci&oacute;n</th>
        <th class="text-right">Cant.</th>
        <th class="text-right">Precio</th>
        <th class="text-right">Desc.</th>
        <th class="text-right">Impuesto</th>
        <th class="text-right">Total</th>~';

        IF v_mostrar_local THEN
            v_html := v_html || q'~
        <th class="text-right">Total ~' || v_simbolo_local || q'~</th>~';
        END IF;

        v_html := v_html || q'~
      </tr>
    </thead>
    <tbody>~';

        -- 4. Detalle
        FOR r IN (
            SELECT row_number() over (order by d.num_linea, d.id_detalle) AS num_linea,
                   d.descripcion,
                   nvl(d.cantidad, 0)          AS cantidad,
                   nvl(d.precio_unitario, 0)   AS precio_unitario,
                   nvl(d.monto_descuento, 0)   AS monto_descuento,
                   nvl(d.monto_impuesto, 0)    AS monto_impuesto,
                   nvl(d.monto_total_linea, 0) AS monto_total_linea
              FROM facturas_det d
             WHERE d.id_factura = p_id_factura
        ) LOOP
            v_desc_total := v_desc_total + r.monto_descuento;

            v_html := v_html
                || '<tr><td>' || to_char(r.num_linea) || '</td>'
                || '<td>' || sys.htf.escape_sc(r.descripcion) || '</td>'
                || '<td class="text-right">' || fn_num(r.cantidad, 'FM999,999,990.00') || '</td>'
                || '<td class="text-right">' || fn_num(r.precio_unitario, 'FM999,999,990.00') || '</td>'
                || '<td class="text-right">' || fn_num(r.monto_descuento, 'FM999,999,990.00') || '</td>'
                || '<td class="text-right">' || fn_num(r.monto_impuesto, 'FM999,999,990.00') || '</td>'
                || '<td class="text-right">' || fn_num(r.monto_total_linea, 'FM999,999,990.00') || '</td>';

            IF v_mostrar_local THEN
                v_html := v_html
                    || '<td class="text-right" style="color: #005b96; font-weight: bold;">'
                    || fn_num(r.monto_total_linea * v_factor_local, 'FM999,999,999,990.00')
                    || '</td>';
            END IF;

            v_html := v_html || '</tr>';
        END LOOP;

        -- 5. Totales
        --    Subtotal (sin impuestos) + descuentos + impuestos = TOTAL, que es
        --    justo la suma de la columna Total de las lineas.
        v_html := v_html || q'~
    </tbody>
  </table>

  <div style="clear: both;">
    <div class="totals-section">
      <table class="totals-table">
        <tr>
          <td><strong>Subtotal (sin impuestos, ~' || v_moneda_doc || q'~):</strong></td>
          <td class="text-right">~' || v_simbolo_doc || ' ' || fn_num(v_subtotal, 'FM999,999,990.00') || q'~</td>
        </tr>
        <tr>
          <td><strong style="color: #c5221f;">Descuentos (~' || v_moneda_doc || q'~):</strong></td>
          <td class="text-right" style="color: #c5221f;">-~' || v_simbolo_doc || ' ' || fn_num(v_desc_total, 'FM999,999,990.00') || q'~</td>
        </tr>
        <tr>
          <td><strong>Impuestos / IVA (~' || v_moneda_doc || q'~):</strong></td>
          <td class="text-right">~' || v_simbolo_doc || ' ' || fn_num(v_iva, 'FM999,999,990.00') || q'~</td>
        </tr>
        <tr style="border-top: 1px solid #ddd;">
          <td><strong>TOTAL ~' || v_moneda_doc || q'~:</strong></td>
          <td class="text-right"><strong>~' || v_simbolo_doc || ' ' || fn_num(v_total, 'FM999,999,990.00') || q'~</strong></td>
        </tr>~';

        IF UPPER(v_moneda_doc) <> 'USD' THEN
            v_html := v_html || q'~
        <tr style="border-top: 2px solid #005b96; background: #eef6fc;">
          <td><strong>TOTAL USD:</strong></td>
          <td class="text-right" style="color: #005b96;"><strong>~'
          || fn_num(v_usd_total, 'FM999,999,990.00') || q'~</strong></td>
        </tr>~';
        END IF;

        IF v_mostrar_local AND UPPER(v_moneda_local) <> UPPER(v_moneda_doc) THEN
            v_html := v_html || q'~
        <tr style="border-top: 2px solid #005b96; background: #eef6fc;">
          <td><strong>~' || v_total_local_lbl || q'~:</strong></td>
          <td class="text-right" style="color: #005b96;"><strong>~' || v_simbolo_local || ' '
          || fn_num(v_local_total, 'FM999,999,999,990.00') || q'~</strong></td>
        </tr>~';
        END IF;

        v_html := v_html || q'~
      </table>
    </div>
  </div>
</div>~';

        RETURN v_html;
    END fn_imprimir_factura_generica;

    -- -------------------------------------------------------------------------
    -- Factura fiscal venezolana «forma libre».
    -- Plantilla: libreria/factura-ejemplo-prefactura.pdf (ejemplo del cliente).
    --
    -- Diferencias con el impreso generico:
    --   * el emisor lleva direccion, telefono, email y RIF;
    --   * numero de control aparte del folio, y fecha de emision;
    --   * datos fiscales del cliente (RIF, direccion, telefono, email);
    --   * los importes se imprimen en BOLIVARES (si el documento esta en otra
    --     moneda se convierte con su tipo_cambio);
    --   * totales AGRUPADOS POR ALICUOTA: subtotal, descuento, base imponible e
    --     IVA por cada tipo, que es lo que exige la forma libre;
    --   * pie con la leyenda legal y los datos de la imprenta y la providencia.
    -- -------------------------------------------------------------------------
    FUNCTION fn_imprimir_factura_ve (p_id_factura IN NUMBER) RETURN CLOB IS
        v_html       CLOB;
        v_css        VARCHAR2(4000);

        v_empresa    VARCHAR2(200);
        v_rif_emp    VARCHAR2(60);
        v_dir_emp    VARCHAR2(300);
        v_tel_emp    VARCHAR2(60);
        v_mail_emp   VARCHAR2(120);
        v_id_empresa NUMBER;

        v_prov       VARCHAR2(60);
        v_prov_fec   VARCHAR2(20);
        v_desde      VARCHAR2(30);
        v_hasta      VARCHAR2(30);
        v_imp_nom    VARCHAR2(150);
        v_imp_rif    VARCHAR2(30);
        v_imp_dir    VARCHAR2(300);
        v_imp_tel    VARCHAR2(60);
        v_imp_mail   VARCHAR2(120);

        v_folio      VARCHAR2(60);
        v_control    VARCHAR2(60);
        v_fecha      VARCHAR2(20);
        v_obs        VARCHAR2(400);

        v_cliente    VARCHAR2(200);
        v_rif_cli    VARCHAR2(60);
        v_dir_cli    VARCHAR2(300);
        v_tel_cli    VARCHAR2(60);
        v_mail_cli   VARCHAR2(120);

        v_tasa       NUMBER := 1;
        v_total_bs   NUMBER := 0;
        v_logo       CLOB;
        v_pct_desc   NUMBER;
    -- Tipo de documento y referencia a la factura que se acredita (nota de
    -- credito/debito): por providencia la nota tiene que decir que documento modifica.
    v_tipo_doc   VARCHAR2(10);
    v_titulo     VARCHAR2(40);
    v_origen     NUMBER;
    v_ref        VARCHAR2(300);
    -- etiqueta del descuento: con el porcentaje solo si TODAS las lineas del
    -- grupo comparten el mismo (antes se mostraba el promedio y no cuadraba)
    v_lbl_desc   VARCHAR2(60);
    BEGIN
        IF p_id_factura IS NULL THEN
            RETURN fn_aviso('No se recibio el identificador de la factura.');
        END IF;

        BEGIN
            SELECT e.id_empresa, e.nombre_empresa,
                   CASE WHEN e.rfc IS NULL THEN NULL
                        ELSE nvl(e.tipo_ident_fiscal, 'RIF') || ': ' || e.rfc END,
                   ef.direccion_fiscal, ef.telefono, ef.email,
                   ef.nro_providencia, TO_CHAR(ef.prov_fecha, 'DD/MM/YYYY'),
                   ef.control_desde, ef.control_hasta,
                   ef.imprenta_nombre, ef.imprenta_rif, ef.imprenta_direccion,
                   ef.imprenta_telefono, ef.imprenta_email,
                   f.folio_factura, f.nro_control, TO_CHAR(f.fecha_emision, 'DD/MM/YYYY'),
                   nvl(f.observaciones, ' '),
                   c.razon_social, c.rif, c.direccion, c.telefono, c.email,
                   nvl(f.tipo_cambio, 1),
                   nvl(f.tipo_documento, 'FAC'), f.id_factura_origen
              INTO v_id_empresa, v_empresa, v_rif_emp, v_dir_emp, v_tel_emp, v_mail_emp,
                   v_prov, v_prov_fec, v_desde, v_hasta,
                   v_imp_nom, v_imp_rif, v_imp_dir, v_imp_tel, v_imp_mail,
                   v_folio, v_control, v_fecha, v_obs,
                   v_cliente, v_rif_cli, v_dir_cli, v_tel_cli, v_mail_cli,
                   v_tasa, v_tipo_doc, v_origen
              FROM facturas f
              JOIN empresas e ON e.id_empresa = f.id_empresa
              JOIN clientes c ON c.id_cliente = f.id_cliente
              LEFT JOIN empresa_fiscal ef ON ef.id_empresa = e.id_empresa
             WHERE f.id_factura = p_id_factura;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RETURN fn_aviso('La factura ' || p_id_factura ||
                                ' no existe o ya no se puede leer.');
        END;

        v_logo := pkg_empresa_logo.fn_logo_img(v_id_empresa,
                    'max-height:56px;max-width:200px;display:block;margin:0 auto 6px auto;');

        -- El documento se rotula por su tipo: una nota de credito no es una factura.
        v_titulo := CASE UPPER(NVL(v_tipo_doc, 'FAC'))
                        WHEN 'NC' THEN 'NOTA DE CR&Eacute;DITO'
                        WHEN 'ND' THEN 'NOTA DE D&Eacute;BITO'
                        ELSE 'FACTURA'
                    END;

        -- Referencia obligatoria a la factura que la nota modifica.
        IF v_origen IS NOT NULL THEN
            BEGIN
                SELECT 'Documento que acredita: Factura ' || o.folio_factura
                       || CASE WHEN o.nro_control IS NOT NULL
                               THEN ', N' || to_char(unistr('\00BA')) || ' de Control ' || o.nro_control ELSE '' END
                       || ', del ' || TO_CHAR(o.fecha_emision, 'DD/MM/YYYY')
                  INTO v_ref
                  FROM facturas o
                 WHERE o.id_factura = v_origen;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    v_ref := NULL;
            END;
        END IF;

        v_css := q'~
.fiscal { width: 100%; max-width: 780px; margin: 0 auto; font-family: "Segoe UI", Arial, sans-serif;
          font-size: 12px; color: #111; }
.fiscal .fe-emisor { text-align: center; border: 2px solid #7a7a7a; border-radius: 4px; padding: 8px; }
.fiscal .fe-emisor .fe-nombre { display: inline-block; background: #7a7a7a; color: #fff;
          font-size: 20px; font-weight: 700; padding: 4px 22px; border-radius: 4px; }
.fiscal .fe-emisor .fe-datos { margin-top: 6px; font-size: 12px; }
.fiscal .fe-emisor .fe-rif { margin-top: 4px; font-weight: 700; text-align: right; }
.fiscal .fe-cab { width: 100%; margin: 10px 0 4px 0; border-collapse: collapse; }
.fiscal .fe-cab td { vertical-align: bottom; }
.fiscal .fe-titulo { font-size: 20px; font-weight: 700; letter-spacing: 1px; }
.fiscal .fe-titulo span { color: #b00; }
.fiscal .fe-ref { margin: 2px 0 8px 0; font-size: 11px; font-weight: 600; color: #333; }
.fiscal .fe-derecha { text-align: right; }
.fiscal .fe-control { font-size: 15px; font-weight: 700; }
.fiscal .fe-cliente { border: 1px solid #111; border-radius: 8px; padding: 8px 12px; margin: 4px 0 10px 0; }
.fiscal .fe-cliente-tit { text-align: center; font-style: italic; font-weight: 600; margin-bottom: 4px; }
.fiscal table.fe-lineas { width: 100%; border-collapse: collapse; }
.fiscal table.fe-lineas th, .fiscal table.fe-lineas td { border: 1px solid #111; padding: 4px 6px; }
.fiscal table.fe-lineas th { background: #f2f2f2; font-size: 11px; text-align: center; }
.fiscal table.fe-lineas td.num { text-align: right; white-space: nowrap; }
.fiscal table.fe-lineas td.ctr { text-align: center; }
.fiscal .fe-alicuota { color: #666; font-size: 10px; }
.fiscal .fe-totales { width: 52%; margin: 10px 0 0 auto; border-collapse: collapse; }
.fiscal .fe-totales td { padding: 2px 6px; }
.fiscal .fe-totales td.num { text-align: right; white-space: nowrap; }
.fiscal .fe-totales tr.grupo td { font-weight: 600; border-bottom: 1px solid #ddd; padding-top: 6px; }
.fiscal .fe-totales tr.total td { font-size: 14px; font-weight: 700; border-top: 2px solid #111; }
.fiscal .fe-obs { border: 1px solid #111; padding: 6px 10px; margin-top: 12px; min-height: 28px; }
.fiscal .fe-leyenda { margin-top: 14px; font-size: 10px; text-align: center; font-weight: 600; }
.fiscal .fe-imprenta { margin-top: 4px; font-size: 9px; text-align: center; color: #333; line-height: 1.35; }
~';

        v_html := fn_css() || '<style>' || v_css || '</style>' || q'~
<div class="doc-container fiscal">

  <div class="fe-emisor">
    ~' || v_logo || q'~
    <div class="fe-nombre">~' || sys.htf.escape_sc(v_empresa) || q'~</div>
    <div class="fe-datos">~' || sys.htf.escape_sc(v_dir_emp) || q'~<br>
      Telefono: ~' || sys.htf.escape_sc(v_tel_emp) || q'~ / email: ~' || sys.htf.escape_sc(v_mail_emp) || q'~</div>
    <div class="fe-rif">~' || sys.htf.escape_sc(v_rif_emp) || q'~</div>
  </div>

  <table class="fe-cab">
    <tr>
      <td class="fe-titulo">~' || v_titulo || q'~ <span>N&ordm; ~' || sys.htf.escape_sc(v_folio) || q'~</span></td>
      <td class="fe-derecha">
        <div class="fe-control">N&ordm; CONTROL ~' || sys.htf.escape_sc(v_control) || q'~</div>
        <div>Fecha de emisi&oacute;n: ~' || sys.htf.escape_sc(v_fecha) || q'~</div>
      </td>
    </tr>
  </table>
~' || CASE WHEN v_ref IS NOT NULL
           THEN '<div class="fe-ref">' || sys.htf.escape_sc(v_ref) || '</div>'
           ELSE '' END || q'~
  <div class="fe-cliente">
    <div class="fe-cliente-tit">Datos del cliente</div>
    <div><strong>Raz&oacute;n social:</strong> ~' || sys.htf.escape_sc(v_cliente) || q'~
         &nbsp;&nbsp;<strong>R.I.F.:</strong> ~' || sys.htf.escape_sc(v_rif_cli) || q'~</div>
    <div><strong>Direcci&oacute;n fiscal:</strong> ~' || sys.htf.escape_sc(v_dir_cli) || q'~</div>
    <div><strong>Tel&eacute;fono:</strong> ~' || sys.htf.escape_sc(v_tel_cli) || q'~
         &nbsp;&#8901;&nbsp; <strong>E-mail:</strong> ~' || sys.htf.escape_sc(v_mail_cli) || q'~</div>
  </div>

  <table class="fe-lineas">
    <thead>
      <tr>
        <th style="width:8%">Cantidad</th>
        <th>Descripci&oacute;n</th>
        <th style="width:18%">Precio U. (Bs.)</th>
        <th style="width:18%">Precio T. (Bs.)</th>
      </tr>
    </thead>
    <tbody>~';

        FOR r IN (SELECT d.descripcion, d.cantidad, d.precio_unitario, d.monto_total_linea,
                         d.subtotal_linea, d.monto_impuesto, d.monto_descuento,
                         d.cantidad * d.precio_unitario AS bruto,
                         nvl(i.porcentage, 0) AS alicuota
                    FROM facturas_det d
                    LEFT JOIN impuestos i ON i.id_impuesto = d.id_impuesto
                   WHERE d.id_factura = p_id_factura
                   ORDER BY nvl(d.num_linea, 0), d.id_detalle) LOOP
            v_html := v_html || q'~
      <tr>
        <td class="ctr">~' || fn_num_ve(r.cantidad, 'FM999G999G990D00') || q'~</td>
        <td>~' || sys.htf.escape_sc(r.descripcion) || q'~
            <span class="fe-alicuota">(~' || fn_num_ve(r.alicuota, 'FM990D0') || q'~ %)</span></td>
        <td class="num">~' || fn_num_ve(r.precio_unitario * v_tasa, 'FM999G999G990D00') || q'~</td>
        <td class="num">~' || fn_num_ve(r.monto_total_linea * v_tasa, 'FM999G999G999G990D00') || q'~</td>
      </tr>~';
        END LOOP;

        v_html := v_html || q'~
    </tbody>
  </table>

  <table class="fe-totales">~';

        -- Totales por alicuota: subtotal, descuento, base imponible e IVA.
        FOR g IN (SELECT nvl(i.porcentage, 0) AS alicuota,
                         SUM(d.cantidad * d.precio_unitario) AS bruto,
                         SUM(d.monto_descuento)              AS descuento,
                         MIN(d.porcentaje_descuento)         AS pct_min,
                         MAX(d.porcentaje_descuento)         AS pct_max,
                         SUM(d.subtotal_linea)               AS base,
                         SUM(d.monto_impuesto)               AS iva
                    FROM facturas_det d
                    LEFT JOIN impuestos i ON i.id_impuesto = d.id_impuesto
                   WHERE d.id_factura = p_id_factura
                   GROUP BY nvl(i.porcentage, 0)
                   ORDER BY 1 DESC) LOOP
            IF NVL(g.pct_min, 0) = NVL(g.pct_max, 0) THEN
                v_lbl_desc := 'Descuento (' || fn_num_ve(NVL(g.pct_max, 0), 'FM990') || ' %)';
            ELSE
                v_lbl_desc := 'Descuento';
            END IF;

            v_html := v_html || q'~
    <tr class="grupo"><td colspan="2">Al&iacute;cuota ~' || fn_num_ve(g.alicuota, 'FM990D0') || q'~ %</td></tr>
    <tr>
      <td>Subtotal</td>
      <td class="num">Bs. ~' || fn_num_ve(g.bruto * v_tasa, 'FM999G999G999G990D00') || q'~</td>
    </tr>
    <tr>
      <td>~' || v_lbl_desc || q'~</td>
      <td class="num">Bs. ~' || fn_num_ve(g.descuento * v_tasa, 'FM999G999G999G990D00') || q'~</td>
    </tr>
    <tr>
      <td>Base imponible (~' || fn_num_ve(g.alicuota, 'FM990D0') || q'~ %)</td>
      <td class="num">Bs. ~' || fn_num_ve(g.base * v_tasa, 'FM999G999G999G990D00') || q'~</td>
    </tr>
    <tr>
      <td>IVA (~' || fn_num_ve(g.alicuota, 'FM990D0') || q'~ %)</td>
      <td class="num">Bs. ~' || fn_num_ve(g.iva * v_tasa, 'FM999G999G999G990D00') || q'~</td>
    </tr>~';
        END LOOP;

        SELECT nvl(SUM(monto_total_linea), 0) * v_tasa
          INTO v_total_bs
          FROM facturas_det
         WHERE id_factura = p_id_factura;

        v_html := v_html || q'~
    <tr class="total">
      <td>TOTAL</td>
      <td class="num">Bs. ~' || fn_num_ve(v_total_bs, 'FM999G999G999G990D00') || q'~</td>
    </tr>
  </table>

  <div class="fe-obs">~' || sys.htf.escape_sc(v_obs) || q'~</div>

  <div class="fe-leyenda">ESTA FORMA LIBRE VA SIN TACHADURA NI ENMIENDA
    &nbsp;&nbsp;&#8901;&nbsp;&nbsp; S&Oacute;LO EL ORIGINAL DA DERECHO A CR&Eacute;DITO FISCAL</div>
  <div class="fe-imprenta">~';

        IF v_imp_nom IS NOT NULL THEN
            v_html := v_html || 'Imprenta: ' || sys.htf.escape_sc(v_imp_nom) || '. '
                     || sys.htf.escape_sc(v_imp_dir) || ' RIF: ' || sys.htf.escape_sc(v_imp_rif)
                     || '. Tlf: ' || sys.htf.escape_sc(v_imp_tel)
                     || ' e-mail: ' || sys.htf.escape_sc(v_imp_mail) || '.';
        END IF;

        IF v_prov IS NOT NULL THEN
            v_html := v_html || ' No. Providencia SENIAT ' || sys.htf.escape_sc(v_prov)
                     || ' de fecha ' || sys.htf.escape_sc(v_prov_fec)
                     || ' - Control desde No. ' || sys.htf.escape_sc(v_desde)
                     || ' hasta No. ' || sys.htf.escape_sc(v_hasta) || '.';
        END IF;

        v_html := v_html || q'~</div>
</div>~';

        RETURN v_html;
    END fn_imprimir_factura_ve;

    -- Reparte: Venezuela imprime la forma libre; el resto, el documento generico.
    FUNCTION fn_imprimir_factura (p_id_factura IN NUMBER) RETURN CLOB IS
        v_pais VARCHAR2(2);
    BEGIN
        IF p_id_factura IS NULL THEN
            RETURN fn_aviso('No se recibio el identificador de la factura.');
        END IF;

        BEGIN
            SELECT nvl(e.cod_pais, 'VE')
              INTO v_pais
              FROM facturas f
              JOIN empresas e ON e.id_empresa = f.id_empresa
             WHERE f.id_factura = p_id_factura;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_pais := 'VE';
        END;

        IF UPPER(v_pais) = 'VE' THEN
            RETURN fn_imprimir_factura_ve(p_id_factura);
        END IF;

        RETURN fn_imprimir_factura_generica(p_id_factura);
    END fn_imprimir_factura;

END pkg_reportes_factura;
/
