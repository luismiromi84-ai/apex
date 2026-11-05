create or replace PACKAGE BODY pkg_reportes_factura AS

    -- -------------------------------------------------------------------------
    -- Utilidades internas (mismas reglas que pkg_reportes_presupuesto)
    -- -------------------------------------------------------------------------

    -- Importes con punto decimal fijo: no dependen de NLS_NUMERIC_CHARACTERS.
    FUNCTION fn_num (p_valor IN NUMBER, p_mascara IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(p_valor, p_mascara, 'NLS_NUMERIC_CHARACTERS=''.,''');
    END fn_num;

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

    FUNCTION fn_imprimir_factura (p_id_factura IN NUMBER) RETURN CLOB IS
        v_empresa         VARCHAR2(200);
        v_ident_empresa   VARCHAR2(50);
        v_ident_label     VARCHAR2(20);
        v_cliente_label   VARCHAR2(30);
        v_cod_pais        VARCHAR2(2);
        v_moneda_local    VARCHAR2(3);
        v_tasa_label      VARCHAR2(30) := 'Tipo de cambio';
        v_simbolo_local   VARCHAR2(10) := '';
        v_total_local_lbl VARCHAR2(30) := 'TOTAL';
        v_mostrar_local   BOOLEAN      := FALSE;

        v_folio           VARCHAR2(50);
        v_control         VARCHAR2(50);
        v_fecha           VARCHAR2(50);
        v_cliente         VARCHAR2(200);
        v_rif_cliente     VARCHAR2(50);
        v_condicion       VARCHAR2(100);
        v_tasa            NUMBER;

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
            SELECT e.nombre_empresa, e.rfc, f.folio_factura, f.uuid_fiscal,
                   TO_CHAR(f.fecha_emision, 'DD/MM/YYYY'),
                   c.razon_social, c.rif,
                   nvl(cp.descripcion, 'Contado'),
                   f.tipo_cambio,
                   nvl(f.subtotal, 0), nvl(f.monto_impuesto, 0), nvl(f.monto_total, 0),
                   nvl(e.tipo_ident_fiscal, 'RIF'), nvl(e.cod_pais, 'VE'),
                   nvl(pa.moneda_local, 'USD')
              INTO v_empresa, v_ident_empresa, v_folio, v_control,
                   v_fecha, v_cliente, v_rif_cliente,
                   v_condicion, v_tasa,
                   v_subtotal, v_iva, v_total,
                   v_ident_label, v_cod_pais, v_moneda_local
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

        -- 3. Cabecera del documento
        v_html := fn_css() || q'~
<div class="doc-container">
  <table class="header-table">
    <tr>
      <td class="empresa-info" style="width: 60%;">
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
                || '<tr><td>' || r.num_linea || '</td>'
                || '<td>' || sys.htf.escape_sc(r.descripcion) || '</td>'
                || '<td class="text-right">' || fn_num(r.cantidad, 'FM999,999,990.00') || '</td>'
                || '<td class="text-right">' || fn_num(r.precio_unitario, 'FM999,999,990.00') || '</td>'
                || '<td class="text-right">' || fn_num(r.monto_descuento, 'FM999,999,990.00') || '</td>'
                || '<td class="text-right">' || fn_num(r.monto_impuesto, 'FM999,999,990.00') || '</td>'
                || '<td class="text-right">' || fn_num(r.monto_total_linea, 'FM999,999,990.00') || '</td>';

            IF v_mostrar_local THEN
                v_html := v_html
                    || '<td class="text-right" style="color: #005b96; font-weight: bold;">'
                    || fn_num(r.monto_total_linea * nvl(v_tasa, 1), 'FM999,999,999,990.00')
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
          <td><strong>Subtotal (sin impuestos):</strong></td>
          <td class="text-right">$~' || fn_num(v_subtotal, 'FM999,999,990.00') || q'~</td>
        </tr>~';

        IF v_desc_total > 0 THEN
            v_html := v_html || q'~
        <tr>
          <td><strong style="color: #c5221f;">Descuentos:</strong></td>
          <td class="text-right" style="color: #c5221f;">-$~' || fn_num(v_desc_total, 'FM999,999,990.00') || q'~</td>
        </tr>~';
        END IF;

        v_html := v_html || q'~
        <tr>
          <td><strong>Impuestos / IVA:</strong></td>
          <td class="text-right">$~' || fn_num(v_iva, 'FM999,999,990.00') || q'~</td>
        </tr>
        <tr style="border-top: 1px solid #ddd;">
          <td><strong>TOTAL USD:</strong></td>
          <td class="text-right"><strong>$~' || fn_num(v_total, 'FM999,999,990.00') || q'~</strong></td>
        </tr>~';

        IF v_mostrar_local THEN
            v_html := v_html || q'~
        <tr style="border-top: 2px solid #005b96; background: #eef6fc;">
          <td><strong>~' || v_total_local_lbl || q'~:</strong></td>
          <td class="text-right" style="color: #005b96;"><strong>~' || v_simbolo_local || ' '
          || fn_num(v_total * nvl(v_tasa, 1), 'FM999,999,999,990.00') || q'~</strong></td>
        </tr>~';
        END IF;

        v_html := v_html || q'~
      </table>
    </div>
  </div>
</div>~';

        RETURN v_html;
    END fn_imprimir_factura;

END pkg_reportes_factura;
/
