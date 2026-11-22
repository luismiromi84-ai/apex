-- =============================================================================
-- 20261121_pagos_modelo_verificacion.sql
--
-- Modelo de pagos a proveedores (2026-11-21). La estructura que el diseno aprobado
-- necesita antes de que exista una sola linea de logica:
--
--   M1  existen PAGOS y PAGOS_DETALLE con todas sus columnas
--   M2  los cuatro CHECK de la cabecera (estado, igtf, conciliado, monto > 0)
--   M3  PAGOS_DETALLE: unique (id_pago, id_compra) y monto_aplicado > 0
--   M4  COMPRAS gana IGTF_BS, RETENCION_ISLR_BS (NOT NULL con default 0) y
--       FECHA_VENCIMIENTO
--   M5  CHK_COMPRAS_ESTADO admite los cinco estados, PARCIAL y PAGADA incluidos
--   M6  los indices de consulta existen
--   M7  el relleno: las compras ya registradas con comprobante de ISLR tienen su
--       RETENCION_ISLR_BS igual a lo retenido en el comprobante
--   M8  toda compra con fecha de emision tiene vencimiento, y 0 objetos invalidos
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261121_pagos_modelo_verificacion.sql
-- El runner sale con codigo 1 aunque este bien: se lee el mensaje.
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000) := '';
    v_n      number;
    v_txt    varchar2(4000);

    procedure comprueba(p_caso varchar2, p_ok boolean, p_detalle varchar2) is
    begin
        if not p_ok then
            v_fallas := v_fallas + 1;
            v_lista  := v_lista || ' | ' || p_caso || ': ' || p_detalle;
        end if;
    end;
begin
    -- M1: las dos tablas y sus columnas ------------------------------------
    select count(*) into v_n
      from all_tables
     where owner = 'WKSP_SYPEXWS' and table_name in ('PAGOS', 'PAGOS_DETALLE');
    comprueba('M1', v_n = 2, 'tablas PAGOS/PAGOS_DETALLE: ' || v_n || ' de 2');

    select count(*) into v_n
      from all_tab_columns
     where owner = 'WKSP_SYPEXWS' and table_name = 'PAGOS'
       and column_name in ('ID_PAGO', 'ID_EMPRESA', 'ID_PROVEEDOR', 'FECHA_PAGO', 'COD_MONEDA',
                           'TIPO_CAMBIO', 'MONTO', 'MONTO_BS', 'ID_FORMA_PAGO', 'REFERENCIA',
                           'APLICA_IGTF', 'IGTF_MONTO', 'IGTF_BS', 'CONCILIADO',
                           'FECHA_CONCILIACION', 'ESTADO', 'OBSERVACIONES', 'CREADO_POR',
                           'FECHA_CREACION', 'MODIFICADO_POR', 'FECHA_MODIFICACION');
    comprueba('M1', v_n = 21, 'PAGOS: ' || v_n || ' de 21 columnas');

    select count(*) into v_n
      from all_tab_columns
     where owner = 'WKSP_SYPEXWS' and table_name = 'PAGOS_DETALLE'
       and column_name in ('ID_PAGO_DETALLE', 'ID_PAGO', 'ID_COMPRA', 'MONTO_APLICADO',
                           'FECHA_CREACION');
    comprueba('M1', v_n = 5, 'PAGOS_DETALLE: ' || v_n || ' de 5 columnas');

    -- M2: los cuatro CHECK de la cabecera ----------------------------------
    select count(*) into v_n
      from all_constraints
     where owner = 'WKSP_SYPEXWS' and table_name = 'PAGOS' and constraint_type = 'C'
       and constraint_name in ('CHK_PAGOS_ESTADO', 'CHK_PAGOS_IGTF', 'CHK_PAGOS_CONCILIADO',
                               'CHK_PAGOS_MONTO');
    comprueba('M2', v_n = 4, 'PAGOS: ' || v_n || ' de 4 checks');

    select nvl(max(search_condition_vc), '?') into v_txt
      from all_constraints
     where owner = 'WKSP_SYPEXWS' and constraint_name = 'CHK_PAGOS_ESTADO';
    comprueba('M2', instr(v_txt, 'ACTIVO') > 0 and instr(v_txt, 'ANULADO') > 0,
              'estado del pago: ' || v_txt);

    select nvl(max(search_condition_vc), '?') into v_txt
      from all_constraints
     where owner = 'WKSP_SYPEXWS' and constraint_name = 'CHK_PAGOS_MONTO';
    comprueba('M2', instr(v_txt, '0') > 0, 'monto > 0: ' || v_txt);

    -- M3: el detalle -------------------------------------------------------
    select count(*) into v_n
      from all_constraints
     where owner = 'WKSP_SYPEXWS' and table_name = 'PAGOS_DETALLE' and constraint_type = 'U'
       and constraint_name = 'UQ_PAGO_COMPRA';
    comprueba('M3', v_n = 1, 'falta UQ_PAGO_COMPRA (un pago no aplica dos veces a la misma compra)');

    select count(*) into v_n
      from all_cons_columns
     where owner = 'WKSP_SYPEXWS' and constraint_name = 'UQ_PAGO_COMPRA'
       and column_name in ('ID_PAGO', 'ID_COMPRA');
    comprueba('M3', v_n = 2, 'UQ_PAGO_COMPRA cubre ' || v_n || ' de 2 columnas');

    select nvl(max(search_condition_vc), '?') into v_txt
      from all_constraints
     where owner = 'WKSP_SYPEXWS' and constraint_name = 'CHK_PD_MONTO';
    comprueba('M3', instr(v_txt, '0') > 0, 'monto_aplicado > 0: ' || v_txt);

    -- M4: las columnas historicas en COMPRAS -------------------------------
    select count(*) into v_n
      from all_tab_columns
     where owner = 'WKSP_SYPEXWS' and table_name = 'COMPRAS'
       and column_name in ('IGTF_BS', 'RETENCION_ISLR_BS', 'FECHA_VENCIMIENTO');
    comprueba('M4', v_n = 3, 'COMPRAS: ' || v_n || ' de 3 columnas nuevas');

    select count(*) into v_n
      from all_tab_columns
     where owner = 'WKSP_SYPEXWS' and table_name = 'COMPRAS'
       and column_name in ('IGTF_BS', 'RETENCION_ISLR_BS')
       and nullable = 'N' and data_default is not null;
    comprueba('M4', v_n = 2, 'IGTF_BS/RETENCION_ISLR_BS NOT NULL con default: ' || v_n || ' de 2');

    -- M5: los cinco estados de la compra -----------------------------------
    select nvl(max(search_condition_vc), '?') into v_txt
      from all_constraints
     where owner = 'WKSP_SYPEXWS' and constraint_name = 'CHK_COMPRAS_ESTADO';
    comprueba('M5',
              instr(v_txt, 'PARCIAL') > 0 and instr(v_txt, 'PAGADA') > 0
              and instr(v_txt, 'BORRADOR') > 0 and instr(v_txt, 'REGISTRADA') > 0
              and instr(v_txt, 'ANULADA') > 0,
              'estados de compra: ' || v_txt);

    -- M6: indices -----------------------------------------------------------
    select count(*) into v_n
      from all_indexes
     where owner = 'WKSP_SYPEXWS'
       and index_name in ('IX_PAGOS_EMPRESA', 'IX_PAGOS_PROVEEDOR', 'IX_PD_COMPRA',
                          'IX_COMPRAS_VENCIMIENTO');
    comprueba('M6', v_n = 4, 'indices: ' || v_n || ' de 4');

    -- M7: el relleno del ISLR retenido -------------------------------------
    begin
        execute immediate q'~
            select count(*)
              from compras c
             where c.estado <> 'ANULADA'
               and exists (select 1 from retenciones r
                            where r.id_compra = c.id_compra and r.tipo = 'ISLR'
                              and r.estado = 'EMITIDO')
               and nvl(c.retencion_islr_bs, 0) <>
                   (select nvl(sum(r2.retenido_bs), 0) from retenciones r2
                     where r2.id_compra = c.id_compra and r2.tipo = 'ISLR'
                       and r2.estado = 'EMITIDO')~' into v_n;
        comprueba('M7', v_n = 0,
                  v_n || ' compras con comprobante ISLR y RETENCION_ISLR_BS distinto');
    exception
        when others then
            comprueba('M7', false, 'no se pudo medir: ' || substr(sqlerrm, 1, 90));
    end;

    -- M8: vencimiento y objetos invalidos -----------------------------------
    begin
        execute immediate 'select count(*) from compras '
                       || 'where fecha_emision is not null and fecha_vencimiento is null'
          into v_n;
        comprueba('M8', v_n = 0, v_n || ' compras sin fecha de vencimiento');
    exception
        when others then
            comprueba('M8', false, 'no se pudo medir: ' || substr(sqlerrm, 1, 90));
    end;

    select count(*) into v_n
      from all_objects
     where owner = 'WKSP_SYPEXWS' and status <> 'VALID'
       and object_type in ('FUNCTION', 'PROCEDURE', 'PACKAGE', 'PACKAGE BODY', 'TRIGGER', 'VIEW');
    comprueba('M8', v_n = 0, v_n || ' objetos invalidos');

    raise_application_error(-20100,
        substrb('RESULTADO: FALLAS=' || v_fallas || v_lista, 1, 3000));
end;
/
