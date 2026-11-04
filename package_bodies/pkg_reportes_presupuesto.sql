create or replace PACKAGE BODY pkg_reportes_presupuesto AS

    FUNCTION fn_imprimir_presupuesto (p_id_presupuesto IN NUMBER) RETURN CLOB IS
        v_empresa       VARCHAR2(200);
        v_rif_empresa   VARCHAR2(50);
        v_folio         VARCHAR2(50);
        v_fecha         VARCHAR2(50);
        v_vencimiento   VARCHAR2(50);
        v_cliente       VARCHAR2(200);
        v_rif_cliente   VARCHAR2(50);
        v_tasa          NUMBER;
        v_estado        VARCHAR2(50);
        v_observaciones VARCHAR2(4000);
        v_creado_por    VARCHAR2(100);
        
        v_subtotal      NUMBER := 0;
        v_iva           NUMBER := 0;
        v_total         NUMBER := 0;
        
        v_html          CLOB;
    BEGIN
        -- 1. Obtener la cabecera del presupuesto y datos del cliente/empresa
        BEGIN
            SELECT e.nombre_empresa, e.rfc, p.folio,
                   TO_CHAR(p.fecha_emision, 'DD/MM/YYYY'), 
                   TO_CHAR(p.fecha_vencimiento, 'DD/MM/YYYY'), 
                   c.razon_social, c.rif, p.tipo_cambio,
                   p.estado, p.observaciones, p.creado_por,
                   fn_clean_num(p.subtotal), fn_clean_num(p.impuesto_iva), fn_clean_num(p.total)
              INTO v_empresa, v_rif_empresa, v_folio,
                   v_fecha, v_vencimiento, v_cliente, v_rif_cliente, v_tasa,
                   v_estado, v_observaciones, v_creado_por,
                   v_subtotal, v_iva, v_total
              FROM presupuestos p
              JOIN clientes c ON p.id_cliente = c.id_cliente AND p.id_empresa = c.id_empresa
              JOIN empresas e ON p.id_empresa = e.id_empresa
             WHERE p.id_presupuesto = p_id_presupuesto;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_empresa := 'Sypex Systems';
                v_estado  := 'PENDIENTE';
        END;

        -- 2. Construir el HTML corporativo para la vista de impresión / PDF
        v_html := '
        <style>
          @media print {
              .t-Header, .t-Footer, .t-Button, .u-no-print, #u-DevToolbar, .apex-developer-toolbar, header, footer, .apex-toolbar, .a-Toolbar, div[role="contentinfo"] {
                  display: none !important;
              }
              body {
                  background-color: #ffffff !important;
              }
          }
          .presupuesto-container {
            font-family: Arial, sans-serif;
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
            color: #333;
            border: 1px solid #ddd;
            background: #fff;
          }
          .header-table, .details-table, .totals-table {
            width: 100%;
            border-collapse: collapse;
            margin-bottom: 20px;
          }
          .header-table td {
            vertical-align: top;
          }
          .empresa-info h2 {
            margin: 0;
            color: #005b96;
          }
          .presupuesto-box {
            border: 2px solid #005b96;
            padding: 10px;
            text-align: center;
            border-radius: 5px;
          }
          .details-table th, .details-table td {
            border: 1px solid #ddd;
            padding: 8px;
            text-align: left;
            font-size: 12px;
          }
          .details-table th {
            background-color: #f4f4f4;
          }
          .text-right {
            text-align: right;
          }
          .totals-section {
            float: right;
            width: 400px;
          }
          .totals-table td {
            padding: 5px 10px;
            font-size: 13px;
          }
          .badge {
            padding: 4px 8px;
            border-radius: 4px;
            font-weight: bold;
            font-size: 11px;
          }
        </style>

        <div class="presupuesto-container">
          <table class="header-table">
            <tr>
              <td class="empresa-info" style="width: 60%;">
                <h2>' || NVL(v_empresa, 'Sypex Systems, C.A.') || '</h2>
                <p><strong>RIF / NIT:</strong> ' || v_rif_empresa || '<br>
                    Sistema de Facturación y Presupuestos B2B</p>
              </td>
              <td style="width: 40%;">
                <div class="presupuesto-box">
                  <h3 style="margin: 0; color: #005b96;">PRESUPUESTO</h3>
                  <p style="margin: 5px 0;"><strong>N°:</strong> ' || v_folio || '<br>
                     <strong>Emisión:</strong> ' || v_fecha || '<br>
                     <strong>Vencimiento:</strong> ' || v_vencimiento || '</p>
                </div>
              </td>
            </tr>
          </table>

          <table style="width: 100%; margin-bottom: 20px; font-size: 13px; background: #f9f9f9; padding: 10px; border-radius: 4px;">
            <tr>
              <td><strong>Cliente:</strong> ' || v_cliente || '</td>
              <td><strong>RIF / Cédula:</strong> ' || v_rif_cliente || '</td>
            </tr>
            <tr>
              <td><strong>Estado:</strong> ' || v_estado || '</td>
              <td><strong>Tasa BCV:</strong> ' || TO_CHAR(v_tasa, 'FM999,999,99990.0000') || ' VES</td>
            </tr>
          </table>

          <table class="details-table">
            <thead>
              <tr>
                <th>Item</th>
                <th>Descripción</th>
                <th class="text-right">Cant.</th>
                <th class="text-right">Precio USD</th>
                <th class="text-right">Total USD</th>
                <th class="text-right">Total Bs</th>
              </tr>
            </thead>
            <tbody>';

        -- 3. Iterar los detalles usando id_detalle y monto_total_linea
        FOR r IN (
            SELECT ROWNUM as num_linea, descripcion, 
                   fn_clean_num(TO_CHAR(cantidad)) as cantidad, 
                   fn_clean_num(TO_CHAR(precio_unitario)) as precio_unitario, 
                   fn_clean_num(TO_CHAR(monto_total_linea)) as monto_total_linea, 
                   fn_clean_num(TO_CHAR(monto_total_linea)) * v_tasa as total_bs
              FROM presupuestos_det
             WHERE id_presupuesto = p_id_presupuesto
             ORDER BY id_detalle
        ) LOOP
            v_html := v_html || '
              <tr>
                <td>' || r.num_linea || '</td>
                <td>' || r.descripcion || '</td>
                <td class="text-right">' || TO_CHAR(r.cantidad, 'FM999,999,990.00') || '</td>
                <td class="text-right">' || TO_CHAR(r.precio_unitario, 'FM999,999,990.00') || '</td>
                <td class="text-right">' || TO_CHAR(r.monto_total_linea, 'FM999,999,990.00') || '</td>
                <td class="text-right" style="color: #005b96; font-weight: bold;">' || TO_CHAR(r.total_bs, 'FM999,999,999,990.00') || '</td>
              </tr>';
        END LOOP;

        -- 4. Sección de Totales y Observaciones
        v_html := v_html || '
            </tbody>
          </table>';

        IF v_observaciones IS NOT NULL THEN
            v_html := v_html || '
              <div style="margin-bottom: 20px; font-size: 12px; background: #fff8e1; padding: 10px; border-radius: 4px; border: 1px solid #ffe082;">
                <strong>Observaciones:</strong> ' || v_observaciones || '
              </div>';
        END IF;

        v_html := v_html || '
          <div style="clear: both;">
            <div class="totals-section">
              <table class="totals-table">
                <tr>
                  <td><strong>Subtotal:</strong></td>
                  <td class="text-right">$' || TO_CHAR(v_subtotal, 'FM999,999,990.00') || '</td>
                </tr>
                <tr>
                  <td><strong>Impuestos / IVA:</strong></td>
                  <td class="text-right">$' || TO_CHAR(v_iva, 'FM999,999,990.00') || '</td>
                </tr>
                <tr style="border-top: 1px solid #ddd;">
                  <td><strong>TOTAL USD:</strong></td>
                  <td class="text-right"><strong>$' || TO_CHAR(v_total, 'FM999,999,990.00') || '</strong></td>
                </tr>
                <tr style="border-top: 2px solid #005b96; background: #eef6fc;">
                  <td><strong>TOTAL BS:</strong></td>
                  <td class="text-right" style="color: #005b96;"><strong>Bs. ' || TO_CHAR(v_total * v_tasa, 'FM999,999,999,990.00') || '</strong></td>
                </tr>
              </table>
            </div>
          </div>
        </div>';

        RETURN v_html;
    END fn_imprimir_presupuesto;

END pkg_reportes_presupuesto;
/