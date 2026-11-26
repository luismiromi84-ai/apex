-- =============================================================================
-- ctb_plantilla_mx.sql
--
-- BORRADOR del plan de cuentas de Mexico (2026-11-26), con el codigo agrupador del SAT de
-- cada cuenta tomado del Anexo 24 de la RMF 2024 (catalogo de cuentas para contabilidad
-- electronica). Todas las cuentas van con ORIGEN='SYNPEX' («Revisar»): las valida el contador
-- de Mexico antes de usarlas. Clase 7 = resultado integral de financiamiento (701 gastos
-- financieros, 702 productos financieros), como en el codigo agrupador.
-- Pendiente con el contador: el traspaso del IVA trasladado no cobrado -> cobrado al cobrar,
-- y si la diferencia cambiaria se separa en utilidad (702.01) y perdida (701.01).
-- Idempotente (merge).
-- =============================================================================

declare
    procedure c(p_cod varchar2, p_nom varchar2, p_sat varchar2, p_nat varchar2) is
    begin
        merge into ctb_plantilla_cuentas t
        using (select 'MX' cod_pais, p_cod codigo from dual) s
           on (t.cod_pais = s.cod_pais and t.codigo = s.codigo)
         when matched then update set t.nombre = p_nom, t.origen = 'SYNPEX', t.naturaleza = p_nat,
                                      t.codigo_agrupador_sat = p_sat
         when not matched then insert (cod_pais, codigo, nombre, origen, naturaleza, codigo_agrupador_sat)
              values ('MX', p_cod, p_nom, 'SYNPEX', p_nat, p_sat);
    end c;
    procedure m(p_con varchar2, p_cod varchar2, p_des varchar2) is
    begin
        merge into ctb_plantilla_mapeo t
        using (select 'MX' cod_pais, p_con concepto from dual) s
           on (t.cod_pais = s.cod_pais and t.concepto = s.concepto)
         when matched then update set t.codigo = p_cod, t.descripcion = p_des
         when not matched then insert (cod_pais, concepto, codigo, descripcion)
              values ('MX', p_con, p_cod, p_des);
    end m;
begin
    c('1.', 'ACTIVO', '100', null);
    c('1.1.', 'ACTIVO A CORTO PLAZO', '100.01', null);
    c('1.1.01.', 'CAJA', '101.01', null);
    c('1.1.01.001', 'CAJA Y EFECTIVO', '101.01', null);
    c('1.1.02.', 'BANCOS NACIONALES', '102.01', null);
    c('1.1.05.', 'CLIENTES', '105', null);
    c('1.1.05.001', 'CLIENTES NACIONALES', '105.01', null);
    c('1.1.05.002', 'CLIENTES EXTRANJEROS', '105.02', null);
    c('1.1.07.', 'DEUDORES DIVERSOS', '107', null);
    c('1.1.07.005', 'OTROS DEUDORES DIVERSOS', '107.05', null);
    c('1.1.13.', 'IMPUESTOS A FAVOR', '113', null);
    c('1.1.13.001', 'IVA A FAVOR', '113.01', null);
    c('1.1.13.002', 'ISR A FAVOR', '113.02', null);
    c('1.1.15.', 'INVENTARIO', '115', null);
    c('1.1.15.001', 'INVENTARIO', '115.01', null);
    c('1.1.18.', 'IMPUESTOS ACREDITABLES PAGADOS', '118', null);
    c('1.1.18.001', 'IVA ACREDITABLE PAGADO', '118.01', null);
    c('1.1.19.', 'IMPUESTOS ACREDITABLES POR PAGAR', '119', null);
    c('1.1.19.001', 'IVA PENDIENTE DE PAGO', '119.01', null);
    c('1.1.20.', 'ANTICIPO A PROVEEDORES', '120', null);
    c('1.1.20.001', 'ANTICIPO A PROVEEDORES NACIONAL', '120.01', null);
    c('2.', 'PASIVO', '200', null);
    c('2.1.', 'PASIVO A CORTO PLAZO', '200.01', null);
    c('2.1.01.', 'PROVEEDORES', '201', null);
    c('2.1.01.001', 'PROVEEDORES NACIONALES', '201.01', null);
    c('2.1.01.002', 'PROVEEDORES EXTRANJEROS', '201.02', null);
    c('2.1.05.', 'ACREEDORES DIVERSOS A CORTO PLAZO', '205', null);
    c('2.1.05.006', 'OTROS ACREEDORES DIVERSOS A CORTO PLAZO', '205.06', null);
    c('2.1.06.', 'ANTICIPO DE CLIENTE', '206', null);
    c('2.1.06.001', 'ANTICIPO DE CLIENTE NACIONAL', '206.01', null);
    c('2.1.08.', 'IMPUESTOS TRASLADADOS COBRADOS', '208', null);
    c('2.1.08.001', 'IVA TRASLADADO COBRADO', '208.01', null);
    c('2.1.09.', 'IMPUESTOS TRASLADADOS NO COBRADOS', '209', null);
    c('2.1.09.001', 'IVA TRASLADADO NO COBRADO', '209.01', null);
    c('2.1.13.', 'IMPUESTOS Y DERECHOS POR PAGAR', '213', null);
    c('2.1.13.001', 'IVA POR PAGAR', '213.01', null);
    c('2.1.13.003', 'ISR POR PAGAR', '213.03', null);
    c('2.1.16.', 'IMPUESTOS RETENIDOS', '216', null);
    c('2.1.16.003', 'IMPUESTOS RETENIDOS DE ISR POR ARRENDAMIENTO', '216.03', null);
    c('2.1.16.004', 'IMPUESTOS RETENIDOS DE ISR POR SERVICIOS PROFESIONALES', '216.04', null);
    c('2.1.16.010', 'IMPUESTOS RETENIDOS DE IVA', '216.10', null);
    c('3.', 'CAPITAL CONTABLE', '300', null);
    c('3.01.', 'CAPITAL SOCIAL', '301', null);
    c('3.01.001', 'CAPITAL FIJO', '301.01', null);
    c('3.04.', 'RESULTADO DE EJERCICIOS ANTERIORES', '304', null);
    c('3.04.001', 'UTILIDAD DE EJERCICIOS ANTERIORES', '304.01', null);
    c('3.04.002', to_char(unistr('P\00C9RDIDA DE EJERCICIOS ANTERIORES')), '304.02', 'D');
    c('3.05.', 'RESULTADO DEL EJERCICIO', '305', null);
    c('3.05.001', 'UTILIDAD DEL EJERCICIO', '305.01', null);
    c('3.05.002', to_char(unistr('P\00C9RDIDA DEL EJERCICIO')), '305.02', 'D');
    c('4.', 'INGRESOS', '400', null);
    c('4.01.', 'INGRESOS', '401', null);
    c('4.01.001', 'VENTAS Y/O SERVICIOS GRAVADOS A LA TASA GENERAL', '401.01', null);
    c('4.01.004', 'VENTAS Y/O SERVICIOS GRAVADOS AL 0%', '401.04', null);
    c('4.01.007', 'VENTAS Y/O SERVICIOS EXENTOS', '401.07', null);
    c('4.02.', 'DEVOLUCIONES, DESCUENTOS O BONIFICACIONES SOBRE INGRESOS', '402', 'D');
    c('4.02.001', 'DEVOLUCIONES, DESCUENTOS O BONIFICACIONES SOBRE VENTAS A LA TASA GENERAL', '402.01', 'D');
    c('4.03.', 'OTROS INGRESOS', '403', null);
    c('4.03.001', 'OTROS INGRESOS', '403.01', null);
    c('5.', 'COSTOS', '500', null);
    c('5.01.', 'COSTO DE VENTA Y/O SERVICIO', '501', null);
    c('5.01.001', 'COSTO DE VENTA', '501.01', null);
    c('5.01.002', 'COSTO DE SERVICIOS (MANO DE OBRA)', '501.02', null);
    c('5.01.090', 'FALTANTES DE INVENTARIO', '501.01', null);
    c('6.', 'GASTOS', '600', null);
    c('6.01.', 'GASTOS GENERALES', '601', null);
    c('6.01.001', 'SUELDOS Y SALARIOS', '601.01', null);
    c('6.01.046', 'ARRENDAMIENTO A PERSONAS MORALES RESIDENTES NACIONALES', '601.46', null);
    c('6.01.050', to_char(unistr('TEL\00C9FONO, INTERNET')), '601.50', null);
    c('6.01.052', to_char(unistr('ENERG\00CDA EL\00C9CTRICA')), '601.52', null);
    c('6.01.055', to_char(unistr('PAPELER\00CDA Y ART\00CDCULOS DE OFICINA')), '601.55', null);
    c('6.01.056', to_char(unistr('MANTENIMIENTO Y CONSERVACI\00D3N')), '601.56', null);
    c('6.01.084', 'OTROS GASTOS GENERALES', '601.84', null);
    c('7.', 'RESULTADO INTEGRAL DE FINANCIAMIENTO', '700', 'D');
    c('7.01.', 'GASTOS FINANCIEROS', '701', 'D');
    c('7.01.001', to_char(unistr('P\00C9RDIDA CAMBIARIA')), '701.01', 'D');
    c('7.01.010', 'COMISIONES BANCARIAS', '701.10', 'D');
    c('7.01.011', 'OTROS GASTOS FINANCIEROS', '701.11', 'D');
    c('7.02.', 'PRODUCTOS FINANCIEROS', '702', 'H');
    c('7.02.001', 'UTILIDAD CAMBIARIA', '702.01', 'H');

    m('CXC', '1.1.05.001', 'Clientes (ventas y cobros)');
    m('VENTAS', '4.01.001', 'Ventas gravadas a la tasa general');
    m('VENTAS_SERVICIOS', '4.01.001', 'Servicios gravados a la tasa general');
    m('DEVOLUCIONES_VENTAS', '4.02.001', 'Notas de credito de venta');
    m('IVA_DEBITO', '2.1.09.001', 'IVA trasladado no cobrado (al facturar)');
    m('IVA_CREDITO', '1.1.19.001', 'IVA pendiente de pago (al comprar)');
    m('IVA_POR_PAGAR', '2.1.13.001', 'IVA por pagar (liquidacion)');
    m('IVA_EXCEDENTE', '1.1.13.001', 'IVA a favor (liquidacion)');
    m('RET_IVA_CLIENTES', '1.1.13.001', 'IVA retenido por clientes (a favor)');
    m('RET_ISLR_CLIENTES', '1.1.13.002', 'ISR retenido por clientes (a favor)');
    m('ANTICIPO_CLIENTES', '2.1.06.001', 'Anticipo de clientes');
    m('CXP', '2.1.01.001', 'Proveedores nacionales');
    m('RET_IVA_PROVEEDORES', '2.1.16.010', 'IVA retenido a proveedores');
    m('RET_ISLR_PROVEEDORES', '2.1.16.004', 'ISR retenido por servicios profesionales');
    m('IGTF_GASTO', '7.01.011', 'No aplica en Mexico (cuenta de resguardo)');
    m('INVENTARIO', '1.1.15.001', 'Inventario (kardex)');
    m('COSTO_VENTAS', '5.01.001', 'Costo de venta (kardex)');
    m('FALTANTE_INVENTARIO', '5.01.090', 'Ajustes y toma fisica con faltante');
    m('SOBRANTE_INVENTARIO', '4.03.001', 'Ajustes y toma fisica con sobrante');
    m('APERTURA', '3.04.001', 'Saldo inicial del inventario');
    m('DIFERENCIAL_CAMBIARIO', '7.02.001', 'Diferencia de tasa (neta; a revisar con el contador)');
    m('GASTO_GENERAL', '6.01.084', 'Otros gastos generales');
    m('RESULTADO_EJERCICIO', '3.05.001', 'Cierre anual');
    m('RESULTADOS_ACUMULADOS', '3.04.001', 'Cierre anual');
    m('GRUPO_CAJA', '1.1.01.', 'Grupo de las cajas');
    m('GRUPO_BANCO_VES', '1.1.02.', 'Grupo de los bancos en moneda local');
    m('GRUPO_BANCO_DIVISA', '1.1.02.', 'Grupo de los bancos en divisa (bancos nacionales para el SAT)');
    commit;
end;
/
