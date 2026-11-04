create or replace PACKAGE BODY pkg_reportes_factura AS

    FUNCTION fn_imprimir_factura (p_id_factura IN NUMBER) RETURN CLOB IS
        v_empresa       VARCHAR2(200);
        v_rif_empresa   VARCHAR2(50);
        v_folio         VARCHAR2(50);
        v_control       VARCHAR2(50);
        v_fecha         VARCHAR2(50);
        v_cliente       VARCHAR2(200);
        v_rif_cliente   VARCHAR2(50);
        v_condicion     VARCHAR2(100);
        v_moneda        VARCHAR2(20);
        v_tasa          NUMBER;
        
        v_sub_bruto     NUMBER := 0;
        v_tot_desc      NUMBER := 0;
        v_sub_neto      NUMBER := 0;
        v_iva_usd       NUMBER := 0;
        v_total_usd     NUMBER := 0;
        
        v_html          CLOB;
    BEGIN
        -- 1. Obtener cabecera haciendo JOIN con CONDICION_PAGO
        BEGIN
            SELECT e.nombre_empresa, e.rfc, f.folio_factura, NVL(f.uuid_fiscal, f.folio_factura),
                   TO_CHAR(f.fecha_emision, 'DD/MM/YYYY'), c.razon_social, c.rif,
                   NVL(cp.descripcion, 'Contado / Contado Riguroso'),
                   f.cod_moneda, f.tipo_cambio,
                   fn_clean_num(f.subtotal), fn_clean_num(f.monto_impuesto), fn_clean_num(f.monto_total)
              INTO v_empresa, v_rif_empresa, v_folio, v_control,
                   v_fecha, v_cliente, v_rif_cliente,
                   v_condicion, v_moneda, v_tasa,
                   v_sub_neto, v_iva_usd, v_total_usd
              FROM facturas f
              JOIN empresas e ON f.id_empresa = e.id_empresa
              JOIN clientes c ON f.id_cliente = c.id_cliente
              LEFT JOIN condicion_pago cp ON f.condicion_pago = cp.id_condicion_pago
             WHERE f.id_factura = p_id_factura;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_empresa := 'Sypex Systems';
                v_condicion := 'Contado / Contado Riguroso';
        END;

        -- 2. Calcular Subtotal Bruto y Descuentos del detalle
        SELECT NVL(SUM(fn_clean_num(TO_CHAR(cantidad)) * fn_clean_num(TO_CHAR(precio_unitario))), 0),
               NVL(SUM(fn_clean_num(TO_CHAR(monto_descuento))), 0)
          INTO v_sub_bruto, v_tot_desc
          FROM facturas_det
         WHERE id_factura = p_id_factura;

        IF v_sub_bruto = 0 THEN
            v_sub_bruto := v_sub_neto;
        END IF;

        -- 3. Construir Estilos CSS y Estructura HTML en la variable CLOB
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
          .factura-container {
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
          .factura-box {
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
        </style>

        <div class="factura-container">
          <table class="header-table">
            <tr>
              <td class="empresa-info" style="width: 60%;">
                <h2>' || NVL(v_empresa, 'Sypex Systems, C.A.') || '</h2>
                <p><strong>RIF / NIT:</strong> ' || v_rif_empresa || '<br>
                    Sistema de Facturación Multimoneda B2B</p>
              </td>
              <td style="width: 40%;">
                <div class="factura-box">
                  <h3 style="margin: 0; color: #005b96;">FACTURA DE VENTA</h3>
                  <p style="margin: 5px 0;"><strong>N°:</strong> ' || v_folio || '<br>
                     <strong>N° Control:</strong> ' || v_control || '<br>
                     <strong>Fecha:</strong> ' || v_fecha || '</p>
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
              <td><strong>Condición de Pago:</strong> ' || v_condicion || '</td>
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

        -- 4. Iterar los detalles de la factura y concatenar al CLOB
        FOR r IN (
            SELECT num_linea, descripcion, 
                   fn_clean_num(TO_CHAR(cantidad)) as cantidad, 
                   fn_clean_num(TO_CHAR(precio_unitario)) as precio_unitario, 
                   fn_clean_num(TO_CHAR(monto_total_linea)) as monto_total_linea, 
                   fn_clean_num(TO_CHAR(total_bs)) as total_bs
              FROM facturas_det
             WHERE id_factura = p_id_factura
             ORDER BY num_linea
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

        -- 5. Totales y cierre de la estructura HTML
        v_html := v_html || '
            </tbody>
          </table>

          <div style="clear: both;">
            <div class="totals-section">
              <table class="totals-table">
                <tr>
                  <td><strong>Subtotal Bruto:</strong></td>
                  <td class="text-right">$' || TO_CHAR(v_sub_bruto, 'FM999,999,990.00') || '</td>
                </tr>';

        IF v_tot_desc > 0 THEN
            v_html := v_html || '
                <tr>
                  <td><strong style="color: #c5221f;">Descuento Total:</strong></td>
                  <td class="text-right" style="color: #c5221f;">-$' || TO_CHAR(v_tot_desc, 'FM999,999,990.00') || '</td>
                </tr>';
        END IF;

        v_html := v_html || '
                <tr>
                  <td><strong>Subtotal Neto:</strong></td>
                  <td class="text-right">$' || TO_CHAR(v_sub_neto, 'FM999,999,990.00') || '</td>
                </tr>
                <tr>
                  <td><strong>Impuestos / IVA:</strong></td>
                  <td class="text-right">$' || TO_CHAR(v_iva_usd, 'FM999,999,990.00') || '</td>
                </tr>
                <tr style="border-top: 1px solid #ddd;">
                  <td><strong>TOTAL USD:</strong></td>
                  <td class="text-right"><strong>$' || TO_CHAR(v_total_usd, 'FM999,999,990.00') || '</strong></td>
                </tr>
                <tr style="border-top: 2px solid #005b96; background: #eef6fc;">
                  <td><strong>TOTAL BS:</strong></td>
                  <td class="text-right" style="color: #005b96;"><strong>Bs. ' || TO_CHAR(v_total_usd * v_tasa, 'FM999,999,999,990.00') || '</strong></td>
                </tr>
              </table>
            </div>
          </div>
        </div>';

        RETURN v_html;
    END fn_imprimir_factura;

END pkg_reportes_factura;
/