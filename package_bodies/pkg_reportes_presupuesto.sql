create or replace PACKAGE BODY pkg_reportes_presupuesto AS

    -- -------------------------------------------------------------------------
    -- Utilidades internas
    -- -------------------------------------------------------------------------

    -- Importes con punto decimal fijo. Si el esquema se instalara en una sesion
    -- con NLS_NUMERIC_CHARACTERS = ',.', los importes saldrian con coma y el
    -- documento impreso seria ilegible.
    FUNCTION fn_num (p_valor IN NUMBER, p_mascara IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(p_valor, p_mascara, 'NLS_NUMERIC_CHARACTERS=''.,''');
    END fn_num;

    -- El RIF venezolano se imprime con guiones (J-12345678-9) aunque en la base
    -- este sin ellos: los datos historicos se cargaron como 'J123456789' y el
    -- papel tiene que salir como lo pide el SENIAT. Lo que no encaja con la forma
    -- (un RFC mexicano, por ejemplo) se imprime tal cual.
    FUNCTION fn_rif (p_valor IN VARCHAR2) RETURN VARCHAR2 IS
        v_limpio VARCHAR2(50);
    BEGIN
        IF p_valor IS NULL THEN
            RETURN NULL;
        END IF;
        v_limpio := REPLACE(REPLACE(UPPER(TRIM(p_valor)), '-', ''), ' ', '');
        IF LENGTH(v_limpio) = 10
           AND SUBSTR(v_limpio, 1, 1) IN ('J', 'V', 'E', 'G', 'P', 'C')
           AND REGEXP_LIKE(SUBSTR(v_limpio, 2), '^[0-9]{9}$') THEN
            RETURN SUBSTR(v_limpio, 1, 1) || '-' || SUBSTR(v_limpio, 2, 8) || '-'
                   || SUBSTR(v_limpio, 10, 1);
        END IF;
        RETURN p_valor;
    END fn_rif;

    -- Sustituye al reporte cuando falta el documento. Antes se devolvia un
    -- reporte vacio con "Sypex Systems" como empresa, que parecia valido.
    FUNCTION fn_aviso (p_texto IN VARCHAR2) RETURN CLOB IS
    BEGIN
        RETURN q'~<div class="doc-aviso">
  <p><strong>No se puede imprimir el presupuesto.</strong></p>
  <p>~' || sys.htf.escape_sc(p_texto) || q'~</p>
</div>~';
    END fn_aviso;

    -- Reglas de impresion. Viven aqui para que el documento sea autonomo: la
    -- pagina ya no necesita su propia copia de @media print.
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

    FUNCTION fn_imprimir_presupuesto (p_id_presupuesto IN NUMBER) RETURN CLOB IS
        v_empresa         VARCHAR2(200);
        v_id_empresa      NUMBER;
        v_logo            CLOB;
        v_ident_empresa   VARCHAR2(50);
        v_ident_label     VARCHAR2(20);
        v_cliente_label   VARCHAR2(30);
        v_cod_pais        VARCHAR2(2);
        v_moneda_local    VARCHAR2(3);
        v_moneda_doc      VARCHAR2(3);
        v_fecha_doc       DATE;
        v_tasa_label      VARCHAR2(30) := 'Tipo de cambio';
        v_simbolo_local   VARCHAR2(10) := '';
        v_simbolo_doc     VARCHAR2(10) := '';
        v_total_local_lbl VARCHAR2(30) := 'TOTAL';
        v_total_doc_lbl   VARCHAR2(30) := 'TOTAL';
        v_mostrar_local   BOOLEAN      := FALSE;
        v_mostrar_usd     BOOLEAN      := FALSE;
        v_tasa_usd        NUMBER := 1;
        v_tasa_local      NUMBER := 1;
        v_factor_usd      NUMBER := 1;
        v_factor_local    NUMBER := 1;
        v_usd_total       NUMBER := 0;
        v_local_total     NUMBER := 0;

        v_folio           VARCHAR2(50);
        v_fecha           VARCHAR2(50);
        v_vencimiento     VARCHAR2(50);
        v_cliente         VARCHAR2(200);
        v_rif_cliente     VARCHAR2(50);
        v_tasa            NUMBER;
        v_estado          VARCHAR2(50);
        v_observaciones   VARCHAR2(4000);

        v_subtotal        NUMBER := 0;
        v_iva             NUMBER := 0;
        v_total           NUMBER := 0;
        v_desc_total      NUMBER := 0;

        v_html            CLOB;
    BEGIN
        IF p_id_presupuesto IS NULL THEN
            RETURN fn_aviso('No se recibio el identificador del presupuesto.');
        END IF;

        -- 1. Cabecera
        BEGIN
            SELECT e.id_empresa, e.nombre_empresa, e.rfc, p.folio,
                   TO_CHAR(p.fecha_emision, 'DD/MM/YYYY'),
                   TO_CHAR(p.fecha_vencimiento, 'DD/MM/YYYY'),
                   c.razon_social, c.rif, p.tipo_cambio,
                   p.estado, p.observaciones,
                   nvl(p.subtotal, 0), nvl(p.impuesto_iva, 0), nvl(p.total, 0),
                   nvl(e.tipo_ident_fiscal, 'RIF'), nvl(e.cod_pais, 'VE'),
                   nvl(pa.moneda_local, 'USD'), p.cod_moneda, p.fecha_emision
              INTO v_id_empresa, v_empresa, v_ident_empresa, v_folio,
                   v_fecha, v_vencimiento, v_cliente, v_rif_cliente, v_tasa,
                   v_estado, v_observaciones,
                   v_subtotal, v_iva, v_total,
                   v_ident_label, v_cod_pais, v_moneda_local, v_moneda_doc, v_fecha_doc
              FROM presupuestos p
              JOIN clientes c
                ON c.id_cliente = p.id_cliente
               AND c.id_empresa = p.id_empresa
              JOIN empresas e
                ON e.id_empresa = p.id_empresa
              LEFT JOIN paises pa
                ON pa.cod_pais = e.cod_pais
             WHERE p.id_presupuesto = p_id_presupuesto;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RETURN fn_aviso('No existe el presupuesto ' || p_id_presupuesto
                             || '. Revisa el enlace e intenta de nuevo.');
        END;

        -- 2. Etiquetas segun el pais de la empresa emisora.
        --    Las etiquetas propias llevan entidades HTML y NO se escapan; solo
        --    lo que viene de la base pasa por sys.htf.escape_sc.
        IF v_cod_pais = 'MX' THEN
            v_cliente_label := 'RFC';
        ELSIF v_cod_pais = 'VE' THEN
            v_cliente_label := 'RIF / C&eacute;dula';
        ELSE
            v_cliente_label := nvl(sys.htf.escape_sc(v_ident_label),
                                   'Identificaci&oacute;n fiscal');
        END IF;

        -- 2 bis. Etiquetas y factores de conversion.
        --   El total principal va en la MONEDA DEL DOCUMENTO (no siempre USD),
        --   el equivalente en USD se calcula con fn_tasa_ves y el total en la
        --   moneda local solo se muestra cuando no es la misma del documento.
        --   La tasa se guarda en BOLIVARES POR UNIDAD (USD->VES 896,12 ·
        --   MXN->VES 47,91 · VES = 1), asi que:
        --       factor_usd   = tasa_doc / tasa_usd
        --       factor_local = tasa_doc / tasa_local
        v_moneda_doc := upper(nvl(v_moneda_doc, 'USD'));

        v_simbolo_doc := CASE v_moneda_doc
                              WHEN 'VES' THEN 'Bs.'
                              WHEN 'MXN' THEN 'MXN $'
                              WHEN 'USD' THEN '$'
                              ELSE v_moneda_doc
                         END;
        v_total_doc_lbl := 'TOTAL ' || CASE WHEN v_moneda_doc = 'VES' THEN 'BS' ELSE v_moneda_doc END;

        v_tasa_local := nvl(fn_tasa_ves(v_fecha_doc, v_moneda_local), 1);
        v_tasa_usd   := nvl(fn_tasa_ves(v_fecha_doc, 'USD'), 1);

        v_factor_usd   := CASE WHEN v_moneda_doc = 'USD' THEN 1
                               ELSE nvl(v_tasa, 1) / v_tasa_usd END;
        v_factor_local := CASE WHEN v_moneda_doc = v_moneda_local THEN 1
                               ELSE nvl(v_tasa, 1) / v_tasa_local END;

        v_usd_total   := round(v_total * v_factor_usd, 2);
        v_local_total := round(v_total * v_factor_local, 2);

        v_mostrar_usd   := (v_moneda_doc <> 'USD');
        v_mostrar_local := (v_moneda_doc <> v_moneda_local);

        IF v_moneda_local = 'VES' THEN
            v_tasa_label      := 'Tasa BCV';
            v_simbolo_local   := 'Bs.';
            v_total_local_lbl := 'TOTAL BS';
        ELSIF v_moneda_local = 'MXN' THEN
            v_tasa_label      := 'Tipo de cambio';
            v_simbolo_local   := 'MXN $';
            v_total_local_lbl := 'TOTAL MXN';
        ELSE
            v_tasa_label      := 'Tipo de cambio';
            v_simbolo_local   := v_moneda_local;
            v_total_local_lbl := 'TOTAL ' || v_moneda_local;
        END IF;

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
        || sys.htf.escape_sc(fn_rif(v_ident_empresa)) || q'~<br>
            Sistema de Presupuestos B2B</p>
      </td>
      <td style="width: 40%;">
        <div class="doc-box">
          <h3 style="margin: 0; color: #005b96;">PRESUPUESTO</h3>
          <p style="margin: 5px 0;"><strong>N&ordm;:</strong> ~' || sys.htf.escape_sc(v_folio) || q'~<br>
             <strong>Emisi&oacute;n:</strong> ~' || nvl(v_fecha, 'N/D') || q'~<br>
             <strong>Vencimiento:</strong> ~' || nvl(v_vencimiento, 'N/D') || q'~</p>
        </div>
      </td>
    </tr>
  </table>

  <table style="width: 100%; margin-bottom: 20px; font-size: 13px; background: #f9f9f9; padding: 10px; border-radius: 4px;">
    <tr>
      <td><strong>Cliente:</strong> ~' || sys.htf.escape_sc(INITCAP(v_cliente)) || q'~</td>
      <td><strong>~' || v_cliente_label || q'~:</strong> ~'
      || sys.htf.escape_sc(fn_rif(v_rif_cliente)) || q'~</td>
    </tr>
    <tr>
      <td><strong>Estado:</strong> ~' || sys.htf.escape_sc(v_estado) || q'~</td>
      <td><strong>~' || v_tasa_label || q'~:</strong> ~' ||
      -- Se imprime en bolivares por unidad de la moneda del documento y se dice la
      -- unidad: «914,0218 Bs/USD» (antes decia «914.0218 USD», que parece una tasa
      -- en dolares). En un documento en bolivares la tasa es 1: «1,0000 Bs/VES».
      CASE WHEN v_moneda_doc IN ('VES', 'BS') THEN '1,0000'
           ELSE TO_CHAR(nvl(v_tasa, 1), 'FM999G999G990D0000',
                        'NLS_NUMERIC_CHARACTERS='',.''') END
      || ' Bs/' || v_moneda_doc || q'~</td>
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
        <th class="text-right">Total ~' || v_simbolo_doc || q'~</th>~';

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
            SELECT row_number() over (order by d.id_detalle) AS num_linea,
                   d.descripcion,
                   nvl(d.cantidad, 0)         AS cantidad,
                   nvl(d.precio_unitario, 0)  AS precio_unitario,
                   nvl(d.monto_descuento, 0)  AS monto_descuento,
                   nvl(d.monto_impuesto, 0)   AS monto_impuesto,
                   nvl(d.monto_total_linea, 0) AS monto_total_linea
              FROM presupuestos_det d
             WHERE d.id_presupuesto = p_id_presupuesto
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

        -- 5. Totales y observaciones
        v_html := v_html || q'~
    </tbody>
  </table>~';

        IF v_observaciones IS NOT NULL THEN
            v_html := v_html || q'~
  <div style="margin-bottom: 20px; font-size: 12px; background: #fff8e1; padding: 10px; border-radius: 4px; border: 1px solid #ffe082;">
    <strong>Observaciones:</strong> ~' || sys.htf.escape_sc(v_observaciones) || q'~
  </div>~';
        END IF;

        v_html := v_html || q'~
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
          <td><strong>~' || v_total_doc_lbl || q'~:</strong></td>
          <td class="text-right"><strong>~' || v_simbolo_doc || ' '
          || fn_num(v_total, 'FM999,999,990.00') || q'~</strong></td>
        </tr>~';

        IF v_mostrar_usd THEN
            v_html := v_html || q'~
        <tr>
          <td><strong>TOTAL USD:</strong></td>
          <td class="text-right"><strong>$~' || fn_num(v_usd_total, 'FM999,999,990.00') || q'~</strong></td>
        </tr>~';
        END IF;

        IF v_mostrar_local THEN
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
    END fn_imprimir_presupuesto;

END pkg_reportes_presupuesto;
/
