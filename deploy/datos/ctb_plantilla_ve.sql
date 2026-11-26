-- =============================================================================
-- ctb_plantilla_ve.sql
--
-- Plantilla del plan de cuentas de Venezuela (2026-11-25). Estructura de cinco niveles
-- del contador (1. / 1.1. / 1.1.1. / 1.1.1.20. / 1.1.1.20.010): los codigos que terminan
-- en punto son de grupo; los demas aceptan movimiento. Origen SYNPEX = cuenta que Synpex
-- necesita y que no estaba en el plan del contador (a revisar con el).
-- Tambien la cuenta por defecto de cada concepto (CTB_PLANTILLA_MAPEO).
-- Idempotente (merge): actualiza el nombre si ya existe.
-- =============================================================================

declare
    procedure c(p_cod varchar2, p_nom varchar2, p_ori varchar2, p_nat varchar2) is
    begin
        merge into ctb_plantilla_cuentas t
        using (select 'VE' cod_pais, p_cod codigo from dual) s
           on (t.cod_pais = s.cod_pais and t.codigo = s.codigo)
         when matched then update set t.nombre = p_nom, t.origen = p_ori, t.naturaleza = p_nat
         when not matched then insert (cod_pais, codigo, nombre, origen, naturaleza)
              values ('VE', p_cod, p_nom, p_ori, p_nat);
    end c;
    procedure m(p_con varchar2, p_cod varchar2, p_des varchar2) is
    begin
        merge into ctb_plantilla_mapeo t
        using (select 'VE' cod_pais, p_con concepto from dual) s
           on (t.cod_pais = s.cod_pais and t.concepto = s.concepto)
         when matched then update set t.codigo = p_cod, t.descripcion = p_des
         when not matched then insert (cod_pais, concepto, codigo, descripcion)
              values ('VE', p_con, p_cod, p_des);
    end m;
begin
    c('1.', 'ACTIVO', 'CONTADOR', null);
    c('1.1.', 'ACTIVO CORRIENTE', 'CONTADOR', null);
    c('1.1.1.', 'EFECTIVO Y EQUIVALENTES DE EFECTIVO', 'CONTADOR', null);
    c('1.1.1.10.', 'CAJA', 'SYNPEX', null);
    c('1.1.1.20.', 'BANCOS EN MONEDA NACIONAL', 'CONTADOR', null);
    c('1.1.1.30.', 'BANCOS EN MONEDA EXTRANJERA', 'SYNPEX', null);
    c('1.1.2.', 'EFECTOS Y CUENTAS A COBRAR', 'CONTADOR', null);
    c('1.1.2.10.', 'EFECTOS Y CUENTAS A COBRAR COMERCIALES', 'CONTADOR', null);
    c('1.1.2.10.010', 'CUENTAS POR COBRAR CLIENTES', 'CONTADOR', null);
    c('1.1.2.20.', 'CUENTAS A COBRAR EMPLEADOS', 'CONTADOR', null);
    c('1.1.2.20.020', to_char(unistr('PR\00C9STAMOS EMPLEADOS')), 'CONTADOR', null);
    c('1.1.2.30.', 'CUENTAS A COBRAR ACCIONISTAS Y RELACIONADAS', 'CONTADOR', null);
    c('1.1.2.30.010', 'CUENTAS A COBRAR ACCIONISTAS', 'CONTADOR', null);
    c('1.1.4.', 'INVENTARIOS', 'CONTADOR', null);
    c('1.1.4.10.', 'INVENTARIOS', 'CONTADOR', null);
    c('1.1.4.10.010', 'INVENTARIO DE EQUIPOS EN DEMO', 'CONTADOR', null);
    c('1.1.4.10.020', to_char(unistr('INVENTARIO DE MERCANC\00CDA')), 'SYNPEX', null);
    c('1.1.5.', 'GASTOS PAGADOS POR ANTICIPADO', 'CONTADOR', null);
    c('1.1.5.10.', 'GASTOS PAGADOS POR ANTICIPADO', 'CONTADOR', null);
    c('1.1.5.10.010', 'PRIMAS DE SEGURO', 'CONTADOR', null);
    c('1.1.6.', 'ANTICIPO DE IMPUESTOS', 'CONTADOR', null);
    c('1.1.6.10.', to_char(unistr('IMPUESTO AL VALOR AGREGADO - CR\00C9DITOS FISCALES')), 'CONTADOR', null);
    c('1.1.6.10.010', to_char(unistr('I.V.A. CR\00C9DITO FISCAL')), 'CONTADOR', null);
    c('1.1.6.10.020', to_char(unistr('EXCEDENTE I.V.A. CR\00C9DITO FISCAL')), 'CONTADOR', null);
    c('1.1.6.10.030', to_char(unistr('RETENCI\00D3N IVA CLIENTES')), 'CONTADOR', null);
    c('1.1.6.20.', 'IMPUESTO SOBRE LA RENTA - ESTIMADA Y RETENCIONES', 'CONTADOR', null);
    c('1.1.6.20.010', to_char(unistr('DECLARACI\00D3N ESTIMADA I.S.L.R.')), 'CONTADOR', null);
    c('1.1.6.20.020', 'I.S.L.R. RETENIDO POR CLIENTES', 'CONTADOR', null);
    c('1.1.6.30.', 'I.G.T.F. PERCIBIDO', 'SYNPEX', null);
    c('1.1.6.30.010', 'I.G.T.F. PERCIBIDO EN COBROS (CONTRIBUYENTE ORDINARIO)', 'SYNPEX', null);
    c('1.1.9.', 'OTROS ACTIVOS CORRIENTES', 'CONTADOR', null);
    c('1.1.9.10.', 'ANTICIPOS OTORGADOS', 'CONTADOR', null);
    c('1.1.9.10.010', 'ANTICIPOS OTORGADOS A PROVEEDORES', 'CONTADOR', null);
    c('1.1.9.20.', 'DIFERENCIAL CAMBIARIO', 'SYNPEX', null);
    c('1.1.9.20.010', 'DIFERENCIAL CAMBIARIO (CONTROL)', 'SYNPEX', null);
    c('1.2.', 'ACTIVO NO CORRIENTE', 'CONTADOR', null);
    c('1.2.1.', 'CUENTAS POR COBRAR ACCIONISTAS Y RELACIONADAS', 'CONTADOR', null);
    c('1.2.1.30.', 'CUENTAS POR COBRAR ACCIONISTAS Y RELACIONADAS', 'CONTADOR', null);
    c('1.2.1.30.020', 'CUENTAS POR COBRAR RELACIONADAS', 'CONTADOR', null);
    c('1.3.', 'PROPIEDADES, PLANTA Y EQUIPO', 'CONTADOR', null);
    c('1.3.1.', 'ACTIVO FIJO', 'CONTADOR', null);
    c('1.3.1.90.', 'DEPRECIACIONES ACUMULADAS', 'CONTADOR', 'H');
    c('1.3.1.90.010', 'MOBILIARIO Y EQUIPOS DE OFICINA', 'CONTADOR', 'H');
    c('1.3.1.90.020', 'EQUIPOS Y ACCESORIOS PROCESAMIENTO DATOS', 'CONTADOR', 'H');
    c('1.3.1.90.040', to_char(unistr('VEH\00CDCULOS')), 'CONTADOR', 'H');
    c('2.', 'PASIVO', 'CONTADOR', null);
    c('2.1.', 'PASIVO CORRIENTE', 'CONTADOR', null);
    c('2.1.2.', 'EFECTOS Y CUENTAS A PAGAR', 'CONTADOR', null);
    c('2.1.2.10.', 'EFECTOS Y CUENTAS A PAGAR COMERCIALES', 'CONTADOR', null);
    c('2.1.2.10.010', 'CUENTAS POR PAGAR PROVEEDORES NACIONALES', 'CONTADOR', null);
    c('2.1.3.', 'GASTOS ACUMULADOS A PAGAR', 'CONTADOR', null);
    c('2.1.3.10.', 'GASTOS ACUMULADOS A PAGAR', 'CONTADOR', null);
    c('2.1.3.10.010', 'SUELDOS A PAGAR', 'CONTADOR', null);
    c('2.1.3.10.020', 'UTILIDADES A PAGAR', 'CONTADOR', null);
    c('2.1.3.10.030', 'VACACIONES A PAGAR', 'CONTADOR', null);
    c('2.1.3.10.100', 'LIQUIDACIONES A PAGAR', 'CONTADOR', null);
    c('2.1.3.10.150', 'INTERESES SOBRE PRESTACIONES SOCIALES', 'CONTADOR', null);
    c('2.1.4.', 'RETENCIONES Y CONTRIBUCIONES A PAGAR', 'CONTADOR', null);
    c('2.1.4.10.', 'RETENCIONES Y CONTRIBUCIONES A PAGAR', 'CONTADOR', null);
    c('2.1.4.10.010', 'I.S.L.R. RETENIDO A PAGAR', 'CONTADOR', null);
    c('2.1.4.10.020', 'I.V.A. RETENIDO A PROVEEDORES', 'CONTADOR', null);
    c('2.1.4.10.030', 'I.N.C.E.S. RETENIDO A EMPLEADOS', 'CONTADOR', null);
    c('2.1.4.10.040', 'I.N.C.E.S. EMPRESA (C.F.)', 'CONTADOR', null);
    c('2.1.4.10.050', 'S.S.O. RETENIDO A EMPLEADOS', 'CONTADOR', null);
    c('2.1.4.10.060', 'S.S.O. EMPRESA', 'CONTADOR', null);
    c('2.1.4.10.070', 'F.A.O.V. RETENIDO A EMPLEADOS', 'CONTADOR', null);
    c('2.1.4.10.080', 'F.A.O.V. EMPRESA', 'CONTADOR', null);
    c('2.1.6.', 'IMPUESTOS A PAGAR', 'CONTADOR', null);
    c('2.1.6.10.', 'IMPUESTO AL VALOR AGREGADO A PAGAR', 'CONTADOR', null);
    c('2.1.6.10.010', to_char(unistr('I.V.A. D\00C9BITO FISCAL')), 'CONTADOR', null);
    c('2.1.6.10.020', 'I.V.A. POR PAGAR', 'CONTADOR', null);
    c('2.1.6.20.', 'IMPUESTO SOBRE LA RENTA A PAGAR', 'CONTADOR', null);
    c('2.1.6.20.010', 'IMPUESTO SOBRE LA RENTA POR PAGAR', 'CONTADOR', null);
    c('2.1.6.30.', 'OTROS TRIBUTOS A PAGAR', 'CONTADOR', null);
    c('2.1.6.30.030', to_char(unistr('APORTE CIENCIA Y TECNOLOG\00CDA (LOCTI POR PAGAR)')), 'CONTADOR', null);
    c('2.1.6.30.040', 'I.G.T.F. POR ENTERAR (CONTRIBUYENTE ESPECIAL)', 'SYNPEX', null);
    c('2.1.9.', 'OTROS PASIVOS CORRIENTES', 'CONTADOR', null);
    c('2.1.9.90.', 'ANTICIPOS RECIBIDOS', 'CONTADOR', null);
    c('2.1.9.90.010', 'ANTICIPOS RECIBIDOS DE CLIENTES', 'CONTADOR', null);
    c('2.2.', 'PASIVOS NO CORRIENTES', 'CONTADOR', null);
    c('2.2.2.', 'EFECTOS Y CUENTAS A PAGAR LARGO PLAZO', 'CONTADOR', null);
    c('2.2.2.30.', 'CUENTAS A PAGAR ACCIONISTAS Y RELACIONADAS', 'CONTADOR', null);
    c('2.2.2.30.010', 'CUENTAS POR PAGAR ACCIONISTAS', 'CONTADOR', null);
    c('2.2.2.30.020', 'CUENTAS POR PAGAR RELACIONADAS', 'CONTADOR', null);
    c('2.3.', 'PASIVOS CONTINGENTES', 'CONTADOR', null);
    c('2.3.1.', 'PRESTACIONES SOCIALES A PAGAR', 'CONTADOR', null);
    c('2.3.1.10.', 'PRESTACIONES SOCIALES A PAGAR', 'CONTADOR', null);
    c('2.3.1.10.010', to_char(unistr('ACUMULACI\00D3N DE ANTIG\00DCEDAD')), 'CONTADOR', null);
    c('2.3.1.10.020', to_char(unistr('ANTICIPO S/ ANTIG\00DCEDAD')), 'CONTADOR', 'D');
    c('3.', 'PATRIMONIO', 'CONTADOR', null);
    c('3.1.', 'CAPITAL SOCIAL', 'SYNPEX', null);
    c('3.1.1.', 'CAPITAL SOCIAL', 'SYNPEX', null);
    c('3.1.1.10.', 'CAPITAL SOCIAL', 'SYNPEX', null);
    c('3.1.1.10.010', 'CAPITAL SOCIAL SUSCRITO Y PAGADO', 'SYNPEX', null);
    c('3.2.', to_char(unistr('UTILIDADES (P\00C9RDIDAS) ACUMULADAS')), 'CONTADOR', null);
    c('3.2.1.', to_char(unistr('UTILIDADES (P\00C9RDIDAS) ACUMULADAS')), 'CONTADOR', null);
    c('3.2.1.10.', to_char(unistr('UTILIDADES (P\00C9RDIDAS) ACUMULADAS')), 'CONTADOR', null);
    c('3.2.1.10.010', to_char(unistr('UTILIDADES (P\00C9RDIDAS) ACUMULADAS EJERCICIOS ANTERIORES')), 'CONTADOR', null);
    c('3.2.1.10.020', to_char(unistr('UTILIDAD (P\00C9RDIDA) DEL EJERCICIO')), 'CONTADOR', null);
    c('3.2.1.10.090', 'SALDOS DE APERTURA', 'SYNPEX', null);
    c('4.', 'INGRESOS', 'CONTADOR', null);
    c('4.1.', 'INGRESOS ORDINARIOS', 'CONTADOR', null);
    c('4.1.1.', 'INGRESOS POR SERVICIOS PRESTADOS', 'CONTADOR', null);
    c('4.1.1.10.', 'INGRESOS POR SERVICIOS PRESTADOS', 'CONTADOR', null);
    c('4.1.1.10.010', 'SERVICIOS PRESTADOS', 'SYNPEX', null);
    c('4.1.1.10.020', 'MANTENIMIENTO Y MONITOREO DE EQUIPOS', 'CONTADOR', null);
    c('4.1.2.', 'INGRESOS POR VENTAS', 'CONTADOR', null);
    c('4.1.2.10.', 'VENTAS BRUTAS', 'CONTADOR', null);
    c('4.1.2.10.010', 'VENTAS NACIONALES', 'CONTADOR', null);
    c('4.1.2.20.', 'DEVOLUCIONES Y DESCUENTOS EN VENTAS', 'SYNPEX', 'D');
    c('4.1.2.20.010', 'DEVOLUCIONES EN VENTAS', 'SYNPEX', 'D');
    c('4.3.', 'OTROS INGRESOS', 'CONTADOR', null);
    c('4.3.1.', 'OTROS INGRESOS', 'CONTADOR', null);
    c('4.3.1.10.', 'OTROS INGRESOS', 'CONTADOR', null);
    c('4.3.1.10.010', 'SOBRANTES DE INVENTARIO', 'SYNPEX', null);
    c('4.3.1.10.090', 'OTROS INGRESOS VARIOS', 'CONTADOR', null);
    c('5.', 'COSTOS', 'CONTADOR', null);
    c('5.1.', to_char(unistr('COSTOS DE MERCANC\00CDAS VENDIDAS')), 'CONTADOR', null);
    c('5.1.1.', 'COMPRAS NACIONALES NETAS', 'CONTADOR', null);
    c('5.1.1.10.', 'COMPRAS NACIONALES', 'CONTADOR', null);
    c('5.1.1.10.010', 'COMPRAS PROVEEDORES NACIONALES', 'CONTADOR', null);
    c('5.1.2.', 'COSTO DE VENTAS', 'SYNPEX', null);
    c('5.1.2.10.', 'COSTO DE VENTAS', 'SYNPEX', null);
    c('5.1.2.10.010', to_char(unistr('COSTO DE MERCANC\00CDA VENDIDA')), 'SYNPEX', null);
    c('5.1.2.10.020', 'FALTANTES DE INVENTARIO', 'SYNPEX', null);
    c('5.2.', to_char(unistr('COSTOS DE PRESTACI\00D3N DE SERVICIOS')), 'CONTADOR', null);
    c('5.2.1.', to_char(unistr('DEPARTAMENTO SOPORTE T\00C9CNICO')), 'CONTADOR', null);
    c('5.2.1.10.', to_char(unistr('COSTO DE PERSONAL SOPORTE T\00C9CNICO')), 'CONTADOR', null);
    c('5.2.1.10.010', 'SUELDOS', 'CONTADOR', null);
    c('5.2.1.10.050', 'VACACIONES', 'CONTADOR', null);
    c('5.2.1.10.070', 'UTILIDADES', 'CONTADOR', null);
    c('5.2.1.10.080', 'PRESTACIONES SOCIALES', 'CONTADOR', null);
    c('5.2.1.10.090', to_char(unistr('BONO ALIMENTACI\00D3N (TICKET)')), 'CONTADOR', null);
    c('5.2.1.10.110', 'INTERESES SOBRE PRESTACIONES SOCIALES', 'CONTADOR', null);
    c('5.2.1.10.120', 'SEGURO SOCIAL OBLIGATORIO', 'CONTADOR', null);
    c('5.2.1.10.130', to_char(unistr('R\00C9GIMEN PRESTACIONAL DE EMPLEO')), 'CONTADOR', null);
    c('5.2.1.10.140', to_char(unistr('APORTE VIVIENDA Y H\00C1BITAT (FAOV)')), 'CONTADOR', null);
    c('5.2.1.10.150', 'APORTE INCES', 'CONTADOR', null);
    c('5.2.1.10.180', 'SEGURO H.C.M.', 'CONTADOR', null);
    c('5.2.1.20.', to_char(unistr('OTROS COSTOS SOPORTE T\00C9CNICO')), 'CONTADOR', null);
    c('5.2.1.20.060', 'MATERIALES Y SUMINISTROS', 'CONTADOR', null);
    c('5.2.2.', 'DEPARTAMENTO HELP DESK', 'CONTADOR', null);
    c('5.2.2.10.', 'COSTO DE PERSONAL HELP DESK', 'CONTADOR', null);
    c('5.2.2.10.010', 'SUELDOS', 'CONTADOR', null);
    c('5.2.2.10.050', 'VACACIONES', 'CONTADOR', null);
    c('5.2.2.10.070', 'UTILIDADES', 'CONTADOR', null);
    c('5.2.2.10.080', 'PRESTACIONES SOCIALES', 'CONTADOR', null);
    c('5.2.2.10.090', to_char(unistr('BONO ALIMENTACI\00D3N (TICKET)')), 'CONTADOR', null);
    c('5.2.2.10.110', 'INTERESES SOBRE PRESTACIONES SOCIALES', 'CONTADOR', null);
    c('5.2.2.10.120', 'SEGURO SOCIAL OBLIGATORIO', 'CONTADOR', null);
    c('5.2.2.10.130', to_char(unistr('R\00C9GIMEN PRESTACIONAL DE EMPLEO')), 'CONTADOR', null);
    c('5.2.2.10.140', to_char(unistr('APORTE VIVIENDA Y H\00C1BITAT (FAOV)')), 'CONTADOR', null);
    c('5.2.2.20.', 'OTROS COSTOS HELP DESK', 'CONTADOR', null);
    c('5.2.2.20.020', 'TRANSPORTE Y TRASLADOS', 'CONTADOR', null);
    c('6.', 'GASTOS', 'CONTADOR', null);
    c('6.1.', 'GASTOS GENERALES', 'CONTADOR', null);
    c('6.1.1.', to_char(unistr('GASTOS DE ADMINISTRACI\00D3N Y DE VENTAS')), 'CONTADOR', null);
    c('6.1.1.10.', to_char(unistr('GASTOS DE PERSONAL DE ADMINISTRACI\00D3N')), 'CONTADOR', null);
    c('6.1.1.10.010', 'SUELDOS', 'CONTADOR', null);
    c('6.1.1.10.020', 'COMISIONES', 'CONTADOR', null);
    c('6.1.1.10.050', 'VACACIONES', 'CONTADOR', null);
    c('6.1.1.10.060', 'BONO VACACIONAL', 'CONTADOR', null);
    c('6.1.1.10.070', 'UTILIDADES', 'CONTADOR', null);
    c('6.1.1.10.080', 'PRESTACIONES SOCIALES', 'CONTADOR', null);
    c('6.1.1.10.090', to_char(unistr('BONO ALIMENTACI\00D3N (TICKET)')), 'CONTADOR', null);
    c('6.1.1.10.110', 'INTERESES SOBRE PRESTACIONES SOCIALES', 'CONTADOR', null);
    c('6.1.1.10.120', 'SEGURO SOCIAL OBLIGATORIO', 'CONTADOR', null);
    c('6.1.1.10.130', to_char(unistr('R\00C9GIMEN PRESTACIONAL DE EMPLEO')), 'CONTADOR', null);
    c('6.1.1.10.140', to_char(unistr('APORTE VIVIENDA Y H\00C1BITAT (FAOV)')), 'CONTADOR', null);
    c('6.1.1.10.150', 'APORTE INCES', 'CONTADOR', null);
    c('6.1.1.20.', 'GASTOS DE PERSONAL DE VENTAS', 'CONTADOR', null);
    c('6.1.1.20.010', 'SUELDOS', 'CONTADOR', null);
    c('6.1.1.20.020', 'COMISIONES', 'CONTADOR', null);
    c('6.1.1.20.050', 'VACACIONES', 'CONTADOR', null);
    c('6.1.1.20.080', 'PRESTACIONES SOCIALES', 'CONTADOR', null);
    c('6.1.1.20.090', to_char(unistr('BONO ALIMENTACI\00D3N (TICKET)')), 'CONTADOR', null);
    c('6.1.1.20.110', 'INTERESES SOBRE PRESTACIONES SOCIALES', 'CONTADOR', null);
    c('6.1.1.20.120', 'SEGURO SOCIAL OBLIGATORIO', 'CONTADOR', null);
    c('6.1.1.20.130', to_char(unistr('R\00C9GIMEN PRESTACIONAL DE EMPLEO')), 'CONTADOR', null);
    c('6.1.1.20.140', to_char(unistr('APORTE VIVIENDA Y H\00C1BITAT (FAOV)')), 'CONTADOR', null);
    c('6.1.1.20.150', 'APORTE INCES', 'CONTADOR', null);
    c('6.1.1.30.', 'IMPUESTOS, TASAS Y CONTRIBUCIONES', 'CONTADOR', null);
    c('6.1.1.30.010', to_char(unistr('IMPUESTO MUNICIPAL DE ACTIVIDADES ECON\00D3MICAS')), 'CONTADOR', null);
    c('6.1.1.40.', 'OTROS GASTOS GENERALES', 'CONTADOR', null);
    c('6.1.1.40.020', 'ARRENDAMIENTO DE INMUEBLES', 'CONTADOR', null);
    c('6.1.1.40.040', to_char(unistr('ENERG\00CDA EL\00C9CTRICA')), 'CONTADOR', null);
    c('6.1.1.40.070', to_char(unistr('SERVICIO DE TELEFON\00CDA Y CELULAR')), 'CONTADOR', null);
    c('6.1.1.40.080', 'SERVICIOS DE INTERNET', 'CONTADOR', null);
    c('6.1.1.40.090', 'REPARACIONES Y MANTENIMIENTO DE OFICINA', 'CONTADOR', null);
    c('6.1.1.40.100', to_char(unistr('REPARACIONES Y MANTENIMIENTO DE EQUIPOS Y VEH\00CDCULOS')), 'CONTADOR', null);
    c('6.1.1.40.110', 'LIMPIEZA DE LOCAL Y OFICINA', 'CONTADOR', null);
    c('6.1.1.40.150', 'MATERIALES Y SUMINISTROS', 'CONTADOR', null);
    c('6.1.1.40.160', 'ALOJAMIENTO Y COMIDA', 'CONTADOR', null);
    c('6.1.1.40.170', 'TRASLADOS DE PERSONAL', 'CONTADOR', null);
    c('6.1.1.40.240', 'CORREOS Y ENCOMIENDAS', 'CONTADOR', null);
    c('6.1.1.40.250', 'CURSOS Y ADIESTRAMIENTOS', 'CONTADOR', null);
    c('6.1.1.40.270', 'PRIMAS DE SEGUROS', 'CONTADOR', null);
    c('6.1.1.40.310', to_char(unistr('REGISTROS Y NOTAR\00CDAS')), 'CONTADOR', null);
    c('6.1.1.40.340', 'FIESTAS Y CELEBRACIONES', 'CONTADOR', null);
    c('6.1.1.40.370', to_char(unistr('DEPRECIACI\00D3N DE ACTIVOS')), 'CONTADOR', null);
    c('6.1.1.40.900', 'GASTOS VARIOS', 'CONTADOR', null);
    c('6.2.', 'GASTOS FINANCIEROS', 'CONTADOR', null);
    c('6.2.1.', 'INTERESES Y GASTOS BANCARIOS', 'CONTADOR', null);
    c('6.2.1.10.', to_char(unistr('INTERESES SOBRE CR\00C9DITOS BANCARIOS')), 'CONTADOR', null);
    c('6.2.1.10.010', 'INTERESES BANCARIOS', 'CONTADOR', null);
    c('6.2.1.20.', 'COMISIONES Y GASTOS BANCARIOS', 'CONTADOR', null);
    c('6.2.1.20.010', 'COMISIONES BANCARIAS', 'CONTADOR', null);
    c('6.2.2.', 'OTROS GASTOS FINANCIEROS', 'CONTADOR', null);
    c('6.2.2.10.', 'OTROS GASTOS FINANCIEROS', 'CONTADOR', null);
    c('6.2.2.10.090', 'IMPUESTO A LAS TRANSACCIONES FINANCIERAS', 'CONTADOR', null);
    c('6.3.', 'OTROS GASTOS', 'CONTADOR', null);
    c('6.3.1.', 'OTROS GASTOS', 'CONTADOR', null);
    c('6.3.1.10.', 'OTROS GASTOS', 'CONTADOR', null);
    c('6.3.1.10.010', 'MULTAS Y SANCIONES', 'CONTADOR', null);
    c('6.3.1.10.020', to_char(unistr('GASTOS DE A\00D1OS ANTERIORES')), 'CONTADOR', null);
    c('6.3.1.10.900', 'OTROS GASTOS VARIOS', 'CONTADOR', null);

    m('CXC', '1.1.2.10.010', 'Cuentas por cobrar clientes (ventas y cobros)');
    m('VENTAS', '4.1.2.10.010', 'Ventas de productos');
    m('VENTAS_SERVICIOS', '4.1.1.10.010', 'Ventas de servicios');
    m('DEVOLUCIONES_VENTAS', '4.1.2.20.010', 'Notas de credito de venta');
    m('IVA_DEBITO', '2.1.6.10.010', 'IVA de las ventas');
    m('IVA_CREDITO', '1.1.6.10.010', 'IVA de las compras');
    m('IVA_POR_PAGAR', '2.1.6.10.020', 'Liquidacion mensual del IVA');
    m('RET_IVA_CLIENTES', '1.1.6.10.030', 'Retencion de IVA que entrega el cliente');
    m('RET_ISLR_CLIENTES', '1.1.6.20.020', 'ISLR que retiene el cliente');
    m('ANTICIPO_CLIENTES', '2.1.9.90.010', 'Anticipos recibidos de clientes');
    m('CXP', '2.1.2.10.010', 'Cuentas por pagar proveedores');
    m('RET_IVA_PROVEEDORES', '2.1.4.10.020', 'Retencion de IVA que emitimos al proveedor');
    m('RET_ISLR_PROVEEDORES', '2.1.4.10.010', 'Retencion de ISLR que emitimos al proveedor');
    m('IGTF_POR_ENTERAR', '2.1.6.30.040', 'IGTF percibido en cobros (contribuyente especial)');
    m('IGTF_PERCIBIDO', '1.1.6.30.010', 'IGTF percibido en cobros (contribuyente ordinario)');
    m('IGTF_GASTO', '6.2.2.10.090', 'IGTF pagado en pagos');
    m('INVENTARIO', '1.1.4.10.020', 'Inventario de mercancia (kardex)');
    m('COSTO_VENTAS', '5.1.2.10.010', 'Costo de la mercancia vendida (kardex)');
    m('FALTANTE_INVENTARIO', '5.1.2.10.020', 'Ajustes y toma fisica con faltante');
    m('SOBRANTE_INVENTARIO', '4.3.1.10.010', 'Ajustes y toma fisica con sobrante');
    m('APERTURA', '3.2.1.10.090', 'Saldo inicial del inventario');
    m('DIFERENCIAL_CAMBIARIO', '1.1.9.20.010', 'Diferencia de tasa entre documento y cobro o pago');
    m('GASTO_GENERAL', '6.1.1.40.900', 'Compras de gasto sin cuenta del concepto ISLR');
    m('RESULTADO_EJERCICIO', '3.2.1.10.020', 'Cierre anual');
    m('RESULTADOS_ACUMULADOS', '3.2.1.10.010', 'Cierre anual');
    m('GRUPO_CAJA', '1.1.1.10.', 'Grupo de las cajas (una subcuenta por caja)');
    m('GRUPO_BANCO_VES', '1.1.1.20.', 'Grupo de los bancos en bolivares');
    m('GRUPO_BANCO_DIVISA', '1.1.1.30.', 'Grupo de los bancos en divisa');
    commit;
end;
/
