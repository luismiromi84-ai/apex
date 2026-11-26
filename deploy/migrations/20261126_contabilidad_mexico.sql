-- =============================================================================
-- 20261126_contabilidad_mexico.sql
--
-- Borrador del plan de cuentas de Mexico con el codigo agrupador del SAT (Anexo 24 RMF 2024):
--   * CTB_PLANTILLA_CUENTAS.CODIGO_AGRUPADOR_SAT (nueva columna)
--   * plantilla MX (80 cuentas, 27 conceptos), todas «Revisar» hasta que las valide el contador
--   * pkg_contabilidad: copia el agrupador al instalar y la subcuenta de caja/banco lo hereda;
--     el cierre anual incluye la clase 7 (resultado integral de financiamiento)
--   * fn_ctb_libro: la clase 7 en el estado de resultados, el balance general y el patrimonio
-- Idempotente.
--
--   python deploy/conexion/importar_export.py deploy/migrations/20261126_contabilidad_mexico.sql
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_n number;
begin
    select count(*) into v_n from all_tab_columns
     where owner = 'WKSP_SYPEXWS' and table_name = 'CTB_PLANTILLA_CUENTAS' and column_name = 'CODIGO_AGRUPADOR_SAT';
    if v_n = 0 then
        execute immediate 'alter table ctb_plantilla_cuentas add (codigo_agrupador_sat varchar2(20))';
    end if;
end;
/

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

create or replace package pkg_contabilidad as

    -- Copia a la empresa la plantilla de su pais (cuentas y mapeo por concepto) y crea una
    -- subcuenta por cada caja o banco. Repetible: solo agrega lo que falta. Devuelve cuantas
    -- cuentas agrego.
    function fn_instalar_plan(p_id_empresa in number, p_usuario in varchar2) return number;

    -- Subcuenta contable de una caja o banco de CUENTAS_FONDOS (la crea si no existe).
    function fn_cuenta_fondo(p_id_cuenta in number, p_usuario in varchar2) return number;

    -- Cuenta asignada a un concepto (CXC, VENTAS, IVA_DEBITO...). -20181 si falta.
    function fn_cuenta(p_id_empresa in number, p_concepto in varchar2) return number;

    -- 'S' si el mes de la fecha esta abierto (un mes sin fila cuenta como abierto).
    function fn_periodo_abierto(p_id_empresa in number, p_fecha in date) return varchar2;

    -- La fecha si su mes esta abierto; si esta cerrado, el primer dia del siguiente mes
    -- abierto (regla del contador para anulaciones y documentos tardios).
    function fn_fecha_contable(p_id_empresa in number, p_fecha in date) return date;

    -- Crea una cuenta bajo su grupo (el grupo padre debe existir) o cambia el nombre y el
    -- estado de una existente. Un codigo que termina en punto es de grupo.
    procedure prc_guardar_cuenta(p_id_empresa in number, p_codigo in varchar2, p_nombre in varchar2,
                                 p_estado in varchar2, p_usuario in varchar2);

    -- Cambia la cuenta de un concepto. Los conceptos GRUPO_* llevan una cuenta de grupo; los
    -- demas, una que acepte movimiento.
    procedure prc_asignar_concepto(p_id_empresa in number, p_concepto in varchar2,
                                   p_id_cuenta_ctb in number, p_usuario in varchar2);

    -- Crea (p_id_asiento nulo) o reemplaza un asiento MANUAL en borrador.
    -- p_lineas: JSON [{"id": id_cuenta_ctb, "debe": 10, "haber": 0, "desc": "..."}, ...]
    procedure prc_guardar_asiento(p_id_asiento in out number,
                                  p_id_empresa in number,
                                  p_fecha      in date,
                                  p_concepto   in varchar2,
                                  p_lineas     in clob,
                                  p_usuario    in varchar2);

    -- Confirma: cuadra, periodo abierto y numero correlativo del mes.
    procedure prc_confirmar(p_id_asiento in number, p_usuario in varchar2);

    -- Reversa un asiento confirmado con otro de lineas invertidas, ya confirmado. Su fecha
    -- es p_fecha (o la del original) llevada al primer mes abierto. Devuelve el id nuevo.
    function fn_reversar(p_id_asiento in number, p_motivo in varchar2,
                         p_usuario in varchar2, p_fecha in date default null) return number;

    -- Borra un asiento en borrador.
    procedure prc_eliminar(p_id_asiento in number, p_usuario in varchar2);

    -- Cierra el mes (sin borradores pendientes) / lo reabre (si no hay uno posterior cerrado).
    procedure prc_cerrar_periodo(p_id_empresa in number, p_anio in number, p_mes in number,
                                 p_usuario in varchar2);
    procedure prc_reabrir_periodo(p_id_empresa in number, p_anio in number, p_mes in number,
                                  p_usuario in varchar2);

    -- Contabiliza el mes (fase 4): genera y confirma los asientos automaticos de las facturas,
    -- notas, cobros, compras, comprobantes de retencion, pagos y kardex con fecha hasta el fin del
    -- mes que aun no los tengan, y reversa los de documentos anulados. Lo que cae en un mes cerrado
    -- va al siguiente mes abierto. Repetible. Un documento que falla se anota y el lote sigue.
    procedure prc_contabilizar_periodo(p_id_empresa in number, p_anio in number, p_mes in number,
                                       p_usuario in varchar2, p_creados out number, p_reversos out number,
                                       p_errores out number, p_detalle out varchar2);

    -- Saldo pendiente de un concepto de pasivo (haber - debe) hasta una fecha.
    function fn_saldo_concepto(p_id_empresa in number, p_concepto in varchar2, p_hasta in date default null) return number;

    -- Cierre anual (fase 5): un asiento al 31/12 que salda los ingresos, costos y gastos del ano
    -- contra RESULTADO_EJERCICIO. Uno por ano (-20192); se rehace reversandolo.
    procedure prc_cierre_anual(p_id_empresa in number, p_anio in number, p_usuario in varchar2,
                               p_id_asiento out number);

    -- Pago al SENIAT de lo retenido o percibido: debita IVA_POR_PAGAR, RET_IVA_PROVEEDORES, RET_ISLR_PROVEEDORES o
    -- IGTF_POR_ENTERAR y acredita el banco. No paga mas de lo pendiente a la fecha (-20193).
    procedure prc_pagar_seniat(p_id_empresa in number, p_concepto in varchar2, p_fecha in date,
                               p_id_cuenta in number, p_monto in number, p_referencia in varchar2,
                               p_usuario in varchar2, p_id_asiento out number);

    -- Liquidacion mensual del IVA: salda debito y credito fiscal al fin del mes, descuenta el
    -- excedente de meses anteriores y las retenciones que nos hicieron los clientes, y deja el
    -- resultado en IVA_POR_PAGAR (o en IVA_EXCEDENTE si el credito es mayor). Una por mes (-20194).
    procedure prc_liquidar_iva(p_id_empresa in number, p_anio in number, p_mes in number,
                               p_usuario in varchar2, p_id_asiento out number);

    -- Solo pruebas: borra toda la contabilidad de una empresa del rango de fixtures
    -- (900000..900999), con commit entre pasos (DML paralelo de Autonomous DB, ORA-12839).
    -- Los triggers la dejan pasar mientras corre (fn_purgando).
    procedure prc_purgar_prueba(p_id_empresa in number);
    function fn_purgando return boolean;

end pkg_contabilidad;
/

create or replace package body pkg_contabilidad as

    g_purgando boolean := false;
    g_interno  boolean := false;   -- el lote reversa asientos automaticos (fn_reversar lo permite)
    -- lineas del asiento automatico en construccion (lote de la fase 4)
    type t_lin is record (id_cta number, debe number, haber number, descr varchar2(400),
                          mon varchar2(3), monto number, tasa number, tt varchar2(1), idt number);
    type t_lins is table of t_lin index by pls_integer;
    g_l t_lins;

    procedure valida_empresa(p_usuario in varchar2, p_id_empresa in number) is
    begin
        if not fn_usuario_empresa_valida(p_usuario, p_id_empresa) then
            raise_application_error(-20190, 'No tiene acceso a la empresa indicada.');
        end if;
    end valida_empresa;

    -- El asiento, bloqueado y validado contra la empresa del usuario.
    function lee_asiento(p_id_asiento in number, p_usuario in varchar2) return ctb_asientos%rowtype is
        r ctb_asientos%rowtype;
    begin
        begin
            select * into r from ctb_asientos where id_asiento = p_id_asiento for update;
        exception
            when no_data_found then
                raise_application_error(-20190, 'El asiento no existe.');
        end;
        valida_empresa(p_usuario, r.id_empresa);
        return r;
    end lee_asiento;

    -- Codigo del padre: '1.1.1.20.010' -> '1.1.1.20.' ; '1.1.1.20.' -> '1.1.1.' ; '1.' -> null
    function codigo_padre(p_codigo in varchar2) return varchar2 is
        v varchar2(30) := rtrim(p_codigo, '.');
        i pls_integer;
    begin
        i := instr(v, '.', -1);
        if i = 0 then
            return null;
        end if;
        return substr(v, 1, i);
    end codigo_padre;

    function fn_instalar_plan(p_id_empresa in number, p_usuario in varchar2) return number is
        v_pais  empresas.cod_pais%type;
        v_n     number := 0;
        v_padre number;
        v_id    number;
        v_cp    varchar2(30);
    begin
        valida_empresa(p_usuario, p_id_empresa);
        select cod_pais into v_pais from empresas where id_empresa = p_id_empresa;
        select count(*) into v_id from ctb_plantilla_cuentas where cod_pais = v_pais;
        if v_id = 0 then
            raise_application_error(-20180, 'No hay plantilla de plan de cuentas para el pais ' || v_pais || '.');
        end if;

        -- los padres primero (por nivel), para enlazar id_padre
        for r in (select p.codigo, p.nombre, p.origen, p.naturaleza, p.codigo_agrupador_sat,
                         regexp_count(rtrim(p.codigo, '.'), '\.') + 1 nivel
                    from ctb_plantilla_cuentas p
                   where p.cod_pais = v_pais
                     and not exists (select 1 from ctb_cuentas c
                                      where c.id_empresa = p_id_empresa and c.codigo = p.codigo)
                   order by regexp_count(rtrim(p.codigo, '.'), '\.'), p.codigo) loop
            v_padre := null;
            v_cp := codigo_padre(r.codigo);
            if v_cp is not null then
                begin
                    select id_cuenta_ctb into v_padre from ctb_cuentas
                     where id_empresa = p_id_empresa and codigo = v_cp;
                exception
                    when no_data_found then
                        v_padre := null;
                end;
            end if;
            insert into ctb_cuentas (id_empresa, codigo, nombre, nivel, id_padre, tipo, naturaleza,
                                     acepta_movimiento, origen, creado_por, codigo_agrupador_sat)
            values (p_id_empresa, r.codigo, r.nombre, r.nivel, v_padre,
                    case substr(r.codigo, 1, 1)
                        when '1' then 'ACTIVO' when '2' then 'PASIVO' when '3' then 'PATRIMONIO'
                        when '4' then 'INGRESO' when '5' then 'COSTO' else 'GASTO' end,
                    nvl(r.naturaleza, case when substr(r.codigo, 1, 1) in ('1', '5', '6') then 'D' else 'H' end),
                    case when r.codigo like '%.' then 'N' else 'S' end,
                    r.origen, p_usuario, r.codigo_agrupador_sat);
            v_n := v_n + 1;
        end loop;

        insert into ctb_mapeo (id_empresa, concepto, id_cuenta_ctb, descripcion)
        select p_id_empresa, m.concepto, c.id_cuenta_ctb, m.descripcion
          from ctb_plantilla_mapeo m
          join ctb_cuentas c on c.id_empresa = p_id_empresa and c.codigo = m.codigo
         where m.cod_pais = v_pais
           and not exists (select 1 from ctb_mapeo x
                            where x.id_empresa = p_id_empresa and x.concepto = m.concepto);

        for f in (select id_cuenta from cuentas_fondos
                   where id_empresa = p_id_empresa and id_cuenta_ctb is null) loop
            v_id := fn_cuenta_fondo(f.id_cuenta, p_usuario);
            v_n := v_n + 1;
        end loop;
        return v_n;
    exception
        when no_data_found then
            raise_application_error(-20190, 'La empresa no existe.');
    end fn_instalar_plan;

    function fn_cuenta(p_id_empresa in number, p_concepto in varchar2) return number is
        v_id number;
    begin
        select id_cuenta_ctb into v_id from ctb_mapeo
         where id_empresa = p_id_empresa and concepto = upper(p_concepto);
        return v_id;
    exception
        when no_data_found then
            raise_application_error(-20181,
                'Falta asignar la cuenta contable del concepto ' || upper(p_concepto) || '.');
    end fn_cuenta;

    function fn_cuenta_fondo(p_id_cuenta in number, p_usuario in varchar2) return number is
        f       cuentas_fondos%rowtype;
        g       ctb_cuentas%rowtype;
        v_local varchar2(3);
        v_suf   number;
        v_id    number;
    begin
        select * into f from cuentas_fondos where id_cuenta = p_id_cuenta for update;
        valida_empresa(p_usuario, f.id_empresa);
        if f.id_cuenta_ctb is not null then
            return f.id_cuenta_ctb;
        end if;
        select max(pa.moneda_local) into v_local
          from empresas e left join paises pa on pa.cod_pais = e.cod_pais
         where e.id_empresa = f.id_empresa;
        select * into g from ctb_cuentas
         where id_cuenta_ctb = fn_cuenta(f.id_empresa,
                   case when f.tipo = 'CAJA' then 'GRUPO_CAJA'
                        when f.cod_moneda = nvl(v_local, f.cod_moneda) then 'GRUPO_BANCO_VES'
                        else 'GRUPO_BANCO_DIVISA' end);
        select nvl(max(to_number(substr(codigo, length(g.codigo) + 1))), 0) + 10 into v_suf
          from ctb_cuentas
         where id_padre = g.id_cuenta_ctb
           and regexp_like(substr(codigo, length(g.codigo) + 1), '^[0-9]+$');
        -- la subcuenta hereda el codigo agrupador del SAT de su grupo (Mexico: 101.01 / 102.01)
        insert into ctb_cuentas (id_empresa, codigo, nombre, nivel, id_padre, tipo, naturaleza,
                                 acepta_movimiento, origen, creado_por, codigo_agrupador_sat)
        values (f.id_empresa, g.codigo || lpad(v_suf, 3, '0'),
                substr(upper(f.nombre) || ' (' || f.cod_moneda || ')', 1, 150),
                g.nivel + 1, g.id_cuenta_ctb, g.tipo, g.naturaleza, 'S', 'EMPRESA', p_usuario,
                g.codigo_agrupador_sat)
        returning id_cuenta_ctb into v_id;
        update cuentas_fondos set id_cuenta_ctb = v_id where id_cuenta = p_id_cuenta;
        return v_id;
    exception
        when no_data_found then
            raise_application_error(-20190, 'La caja o banco no existe.');
    end fn_cuenta_fondo;

    function fn_periodo_abierto(p_id_empresa in number, p_fecha in date) return varchar2 is
        v_estado ctb_periodos.estado%type;
    begin
        select max(estado) into v_estado from ctb_periodos
         where id_empresa = p_id_empresa
           and anio = extract(year from p_fecha) and mes = extract(month from p_fecha);
        return case when nvl(v_estado, 'ABIERTO') = 'ABIERTO' then 'S' else 'N' end;
    end fn_periodo_abierto;

    function fn_fecha_contable(p_id_empresa in number, p_fecha in date) return date is
        v_f date := trunc(nvl(p_fecha, sysdate));
    begin
        for i in 1 .. 36 loop
            if fn_periodo_abierto(p_id_empresa, v_f) = 'S' then
                return v_f;
            end if;
            v_f := add_months(trunc(v_f, 'MM'), 1);
        end loop;
        raise_application_error(-20184, 'No hay un periodo contable abierto despues de esa fecha.');
    end fn_fecha_contable;

    procedure prc_guardar_cuenta(p_id_empresa in number, p_codigo in varchar2, p_nombre in varchar2,
                                 p_estado in varchar2, p_usuario in varchar2) is
        v_cod varchar2(30) := trim(p_codigo);
        v_nom varchar2(150) := upper(trim(p_nombre));
        v_cp  varchar2(30);
        g     ctb_cuentas%rowtype;
        v_n   number;
    begin
        valida_empresa(p_usuario, p_id_empresa);
        if v_cod is null or not regexp_like(v_cod, '^[0-9]+(\.[0-9]+)*\.?$') or v_nom is null then
            raise_application_error(-20191, 'Indica un codigo valido (por ejemplo 6.1.1.40.950) y el nombre de la cuenta.');
        end if;
        if nvl(p_estado, 'ACTIVO') not in ('ACTIVO', 'INACTIVO') then
            raise_application_error(-20191, 'Estado de cuenta invalido.');
        end if;
        select count(*) into v_n from ctb_cuentas where id_empresa = p_id_empresa and codigo = v_cod;
        if v_n > 0 then
            update ctb_cuentas set nombre = v_nom, estado = nvl(p_estado, 'ACTIVO')
             where id_empresa = p_id_empresa and codigo = v_cod;
            return;
        end if;
        v_cp := codigo_padre(v_cod);
        begin
            select * into g from ctb_cuentas
             where id_empresa = p_id_empresa and codigo = v_cp and acepta_movimiento = 'N';
        exception
            when no_data_found then
                raise_application_error(-20191, 'El grupo ' || nvl(v_cp, '(ninguno)') ||
                    ' no existe: crea primero el grupo (codigo terminado en punto).');
        end;
        insert into ctb_cuentas (id_empresa, codigo, nombre, nivel, id_padre, tipo, naturaleza,
                                 acepta_movimiento, estado, origen, creado_por)
        values (p_id_empresa, v_cod, v_nom, g.nivel + 1, g.id_cuenta_ctb, g.tipo, g.naturaleza,
                case when v_cod like '%.' then 'N' else 'S' end, nvl(p_estado, 'ACTIVO'), 'EMPRESA', p_usuario);
    end prc_guardar_cuenta;

    procedure prc_asignar_concepto(p_id_empresa in number, p_concepto in varchar2,
                                   p_id_cuenta_ctb in number, p_usuario in varchar2) is
        v_con varchar2(40) := upper(trim(p_concepto));
        v_n   number;
        c     ctb_cuentas%rowtype;
    begin
        valida_empresa(p_usuario, p_id_empresa);
        select count(*) into v_n from ctb_mapeo where id_empresa = p_id_empresa and concepto = v_con;
        if v_n = 0 then
            raise_application_error(-20191, 'Concepto contable desconocido: ' || v_con || '.');
        end if;
        begin
            select * into c from ctb_cuentas
             where id_cuenta_ctb = p_id_cuenta_ctb and id_empresa = p_id_empresa and estado = 'ACTIVO';
        exception
            when no_data_found then
                raise_application_error(-20183, 'La cuenta no es de la empresa o esta inactiva.');
        end;
        if substr(v_con, 1, 6) = 'GRUPO_' and c.acepta_movimiento = 'S' then
            raise_application_error(-20183, 'Este concepto necesita una cuenta de grupo (codigo terminado en punto).');
        elsif substr(v_con, 1, 6) <> 'GRUPO_' and c.acepta_movimiento = 'N' then
            raise_application_error(-20183, 'Este concepto necesita una cuenta que acepte movimiento, no un grupo.');
        end if;
        update ctb_mapeo set id_cuenta_ctb = p_id_cuenta_ctb where id_empresa = p_id_empresa and concepto = v_con;
    end prc_asignar_concepto;

    procedure prc_guardar_asiento(p_id_asiento in out number,
                                  p_id_empresa in number,
                                  p_fecha      in date,
                                  p_concepto   in varchar2,
                                  p_lineas     in clob,
                                  p_usuario    in varchar2) is
        r     ctb_asientos%rowtype;
        v_lin number := 0;
    begin
        valida_empresa(p_usuario, p_id_empresa);
        if p_fecha is null or trim(p_concepto) is null then
            raise_application_error(-20191, 'El asiento necesita fecha y concepto.');
        end if;
        if fn_periodo_abierto(p_id_empresa, p_fecha) = 'N' then
            raise_application_error(-20184, 'El periodo ' || to_char(p_fecha, 'MM/YYYY') || ' esta cerrado.');
        end if;

        if p_id_asiento is null then
            insert into ctb_asientos (id_empresa, anio, mes, fecha, concepto, origen, estado, creado_por)
            values (p_id_empresa, extract(year from p_fecha), extract(month from p_fecha), trunc(p_fecha),
                    substr(trim(p_concepto), 1, 400), 'MANUAL', 'BORRADOR', p_usuario)
            returning id_asiento into p_id_asiento;
        else
            r := lee_asiento(p_id_asiento, p_usuario);
            if r.estado <> 'BORRADOR' then
                raise_application_error(-20182, 'El asiento esta ' || r.estado || ': no se modifica, se corrige con un reverso.');
            end if;
            if r.id_empresa <> p_id_empresa or r.origen <> 'MANUAL' then
                raise_application_error(-20190, 'El asiento no es un asiento manual de esta empresa.');
            end if;
            delete from ctb_asiento_det where id_asiento = p_id_asiento;
            update ctb_asientos set fecha = trunc(p_fecha), anio = extract(year from p_fecha), mes = extract(month from p_fecha),
                   concepto = substr(trim(p_concepto), 1, 400)
             where id_asiento = p_id_asiento;
        end if;

        for l in (select j.id_cta, round(nvl(j.debe, 0), 2) debe, round(nvl(j.haber, 0), 2) haber, j.descr
                    from json_table(nvl(p_lineas, '[]'), '$[*]'
                           columns (id_cta number path '$.id',
                                    debe   number path '$.debe',
                                    haber  number path '$.haber',
                                    descr  varchar2(400) path '$.desc')) j) loop
            if l.debe = 0 and l.haber = 0 then
                continue;
            end if;
            if l.debe < 0 or l.haber < 0 or (l.debe > 0 and l.haber > 0) then
                raise_application_error(-20191,
                    'Cada linea lleva un importe positivo en el debe o en el haber, no en los dos.');
            end if;
            v_lin := v_lin + 1;
            insert into ctb_asiento_det (id_asiento, linea, id_cuenta_ctb, descripcion, debe, haber)
            values (p_id_asiento, v_lin, l.id_cta, l.descr, l.debe, l.haber);
        end loop;
    end prc_guardar_asiento;

    -- Numero correlativo del mes (bloquea la fila del periodo). Exige el mes abierto.
    function siguiente_numero(p_id_empresa in number, p_anio in number, p_mes in number) return number is
        v_estado ctb_periodos.estado%type;
        v_num    number;
    begin
        merge into ctb_periodos t
        using (select p_id_empresa e, p_anio a, p_mes m from dual) s
           on (t.id_empresa = s.e and t.anio = s.a and t.mes = s.m)
         when not matched then insert (id_empresa, anio, mes, estado, ultimo_numero)
              values (s.e, s.a, s.m, 'ABIERTO', 0);
        select estado, ultimo_numero + 1 into v_estado, v_num from ctb_periodos
         where id_empresa = p_id_empresa and anio = p_anio and mes = p_mes for update;
        if v_estado <> 'ABIERTO' then
            raise_application_error(-20184, 'El periodo ' || lpad(p_mes, 2, '0') || '/' || p_anio || ' esta cerrado.');
        end if;
        update ctb_periodos set ultimo_numero = v_num
         where id_empresa = p_id_empresa and anio = p_anio and mes = p_mes;
        return v_num;
    end siguiente_numero;

    procedure prc_confirmar(p_id_asiento in number, p_usuario in varchar2) is
        r   ctb_asientos%rowtype;
        v_n number;
        v_num number;
    begin
        r := lee_asiento(p_id_asiento, p_usuario);
        if r.estado <> 'BORRADOR' then
            raise_application_error(-20182, 'El asiento ya esta ' || r.estado || '.');
        end if;
        select count(*) into v_n from ctb_asiento_det where id_asiento = p_id_asiento;
        if v_n < 2 or r.total_debe <= 0 or r.total_debe <> r.total_haber then
            raise_application_error(-20185,
                'El asiento no cuadra: debe ' || to_char(r.total_debe, 'FM999G999G999G990D00') ||
                ', haber ' || to_char(r.total_haber, 'FM999G999G999G990D00') || ' (minimo dos lineas).');
        end if;
        v_num := siguiente_numero(r.id_empresa, r.anio, r.mes);
        update ctb_asientos set estado = 'CONFIRMADO', numero = v_num,
               confirmado_por = p_usuario, fecha_confirmacion = sysdate
         where id_asiento = p_id_asiento;
    end prc_confirmar;

    function fn_reversar(p_id_asiento in number, p_motivo in varchar2,
                         p_usuario in varchar2, p_fecha in date default null) return number is
        r     ctb_asientos%rowtype;
        v_f   date;
        v_id  number;
    begin
        r := lee_asiento(p_id_asiento, p_usuario);
        if r.estado <> 'CONFIRMADO' then
            raise_application_error(-20186, 'Solo se reversa un asiento CONFIRMADO (este esta ' || r.estado || ').');
        end if;
        if r.origen = 'AUTOMATICO' and not g_interno then
            raise_application_error(-20186,
                'Un asiento automatico no se reversa a mano: anula el documento de origen y contabiliza el periodo.');
        end if;
        if trim(p_motivo) is null then
            raise_application_error(-20191, 'Indica el motivo del reverso.');
        end if;
        v_f := fn_fecha_contable(r.id_empresa, nvl(p_fecha, r.fecha));
        insert into ctb_asientos (id_empresa, anio, mes, fecha, concepto, origen, doc_tipo, id_doc, evento,
                                  estado, id_asiento_original, creado_por)
        values (r.id_empresa, extract(year from v_f), extract(month from v_f), v_f,
                substr('Reverso del asiento ' || r.numero || ' de ' || lpad(r.mes, 2, '0') || '/' || r.anio
                       || ': ' || trim(p_motivo), 1, 400),
                'REVERSO', r.doc_tipo, r.id_doc, r.evento, 'BORRADOR', r.id_asiento, p_usuario)
        returning id_asiento into v_id;
        insert into ctb_asiento_det (id_asiento, linea, id_cuenta_ctb, descripcion, debe, haber,
                                     cod_moneda, monto_moneda, tasa, tercero_tipo, id_tercero)
        select v_id, linea, id_cuenta_ctb, descripcion, haber, debe,
               cod_moneda, monto_moneda, tasa, tercero_tipo, id_tercero
          from ctb_asiento_det where id_asiento = p_id_asiento;
        prc_confirmar(v_id, p_usuario);
        update ctb_asientos set estado = 'REVERSADO', id_asiento_reverso = v_id where id_asiento = p_id_asiento;
        return v_id;
    end fn_reversar;

    procedure prc_eliminar(p_id_asiento in number, p_usuario in varchar2) is
        r ctb_asientos%rowtype;
    begin
        r := lee_asiento(p_id_asiento, p_usuario);
        if r.estado <> 'BORRADOR' then
            raise_application_error(-20182, 'Un asiento ' || r.estado || ' no se borra: se reversa.');
        end if;
        delete from ctb_asiento_det where id_asiento = p_id_asiento;
        delete from ctb_asientos where id_asiento = p_id_asiento;
    end prc_eliminar;

    procedure prc_cerrar_periodo(p_id_empresa in number, p_anio in number, p_mes in number,
                                 p_usuario in varchar2) is
        v_n      number;
        v_estado ctb_periodos.estado%type;
    begin
        valida_empresa(p_usuario, p_id_empresa);
        select count(*) into v_n from ctb_asientos
         where id_empresa = p_id_empresa and anio = p_anio and mes = p_mes and estado = 'BORRADOR';
        if v_n > 0 then
            raise_application_error(-20187,
                'Hay ' || v_n || ' asiento(s) en borrador en el periodo: confirmalos o borralos antes de cerrar.');
        end if;
        merge into ctb_periodos t
        using (select p_id_empresa e, p_anio a, p_mes m from dual) s
           on (t.id_empresa = s.e and t.anio = s.a and t.mes = s.m)
         when not matched then insert (id_empresa, anio, mes, estado, ultimo_numero)
              values (s.e, s.a, s.m, 'ABIERTO', 0);
        select estado into v_estado from ctb_periodos
         where id_empresa = p_id_empresa and anio = p_anio and mes = p_mes for update;
        if v_estado = 'CERRADO' then
            raise_application_error(-20188, 'El periodo ya esta cerrado.');
        end if;
        update ctb_periodos set estado = 'CERRADO', cerrado_por = p_usuario, fecha_cierre = sysdate
         where id_empresa = p_id_empresa and anio = p_anio and mes = p_mes;
    end prc_cerrar_periodo;

    procedure prc_reabrir_periodo(p_id_empresa in number, p_anio in number, p_mes in number,
                                  p_usuario in varchar2) is
        v_n      number;
        v_estado ctb_periodos.estado%type;
    begin
        valida_empresa(p_usuario, p_id_empresa);
        begin
            select estado into v_estado from ctb_periodos
             where id_empresa = p_id_empresa and anio = p_anio and mes = p_mes for update;
        exception
            when no_data_found then
                v_estado := 'ABIERTO';
        end;
        if v_estado <> 'CERRADO' then
            raise_application_error(-20188, 'El periodo ya esta abierto.');
        end if;
        select count(*) into v_n from ctb_periodos
         where id_empresa = p_id_empresa and estado = 'CERRADO' and anio * 100 + mes > p_anio * 100 + p_mes;
        if v_n > 0 then
            raise_application_error(-20189, 'Hay un periodo posterior cerrado: reabre primero el mas reciente.');
        end if;
        update ctb_periodos set estado = 'ABIERTO', cerrado_por = null, fecha_cierre = null
         where id_empresa = p_id_empresa and anio = p_anio and mes = p_mes;
    end prc_reabrir_periodo;

    -- ===================================================================== lote (fase 4)

    procedure l_add(p_cta number, p_imp number, p_lado varchar2, p_desc varchar2 default null,
                    p_mon varchar2 default null, p_monto number default null, p_tasa number default null,
                    p_tt varchar2 default null, p_idt number default null) is
        v_imp number := round(nvl(p_imp, 0), 2);
        v_lado varchar2(1) := p_lado;
        k pls_integer;
    begin
        if v_imp = 0 then
            return;
        end if;
        if v_imp < 0 then
            v_imp := -v_imp;
            v_lado := case p_lado when 'D' then 'H' else 'D' end;
        end if;
        k := g_l.count + 1;
        g_l(k).id_cta := p_cta;
        g_l(k).debe := case v_lado when 'D' then v_imp else 0 end;
        g_l(k).haber := case v_lado when 'H' then v_imp else 0 end;
        g_l(k).descr := substr(p_desc, 1, 400);
        g_l(k).mon := p_mon;
        g_l(k).monto := p_monto;
        g_l(k).tasa := p_tasa;
        g_l(k).tt := p_tt;
        g_l(k).idt := p_idt;
    end l_add;

    function hecho(p_emp number, p_doc varchar2, p_id number, p_evento varchar2) return boolean is
        v_n number;
    begin
        select count(*) into v_n from ctb_asientos
         where id_empresa = p_emp and origen = 'AUTOMATICO' and doc_tipo = p_doc and id_doc = p_id and evento = p_evento;
        return v_n > 0;
    end hecho;

    -- Crea y confirma el asiento automatico con las lineas de g_l. Devuelve el id (null si no hay importe).
    function asentar(p_emp number, p_fecha date, p_concepto varchar2, p_doc varchar2, p_id number,
                     p_evento varchar2, p_usuario varchar2, p_origen varchar2 default 'AUTOMATICO') return number is
        v_f  date := fn_fecha_contable(p_emp, p_fecha);
        v_id number;
        v_d  number := 0;
        v_h  number := 0;
    begin
        for k in 1 .. g_l.count loop
            v_d := v_d + g_l(k).debe;
            v_h := v_h + g_l(k).haber;
        end loop;
        if g_l.count = 0 or v_d = 0 then
            g_l.delete;
            return null;
        end if;
        if v_d <> v_h then
            g_l.delete;
            raise_application_error(-20185, 'El asiento de ' || p_concepto || ' no cuadra (debe ' || v_d || ', haber ' || v_h || ').');
        end if;
        insert into ctb_asientos (id_empresa, anio, mes, fecha, concepto, origen, doc_tipo, id_doc, evento, estado, creado_por)
        values (p_emp, extract(year from v_f), extract(month from v_f), v_f, substr(p_concepto, 1, 400), p_origen,
                p_doc, p_id, p_evento, 'BORRADOR', p_usuario)
        returning id_asiento into v_id;
        for k in 1 .. g_l.count loop
            insert into ctb_asiento_det (id_asiento, linea, id_cuenta_ctb, descripcion, debe, haber,
                                         cod_moneda, monto_moneda, tasa, tercero_tipo, id_tercero)
            values (v_id, k, g_l(k).id_cta, g_l(k).descr, g_l(k).debe, g_l(k).haber,
                    g_l(k).mon, g_l(k).monto, g_l(k).tasa, g_l(k).tt, g_l(k).idt);
        end loop;
        g_l.delete;
        prc_confirmar(v_id, p_usuario);
        return v_id;
    end asentar;

    -- Reversa los asientos automaticos confirmados de un documento anulado. Devuelve cuantos.
    function reversar_doc(p_emp number, p_doc varchar2, p_id number, p_fecha date, p_usuario varchar2) return number is
        v_n  number := 0;
        v_id number;
    begin
        for a in (select id_asiento from ctb_asientos
                   where id_empresa = p_emp and origen = 'AUTOMATICO' and doc_tipo = p_doc and id_doc = p_id
                     and estado = 'CONFIRMADO') loop
            g_interno := true;
            v_id := fn_reversar(a.id_asiento, 'documento anulado', p_usuario, p_fecha);
            g_interno := false;
            v_n := v_n + 1;
        end loop;
        return v_n;
    exception
        when others then
            g_interno := false;
            raise;
    end reversar_doc;

    -- Cuenta de un concepto opcional (null si la empresa no lo tiene asignado).
    function cuenta_opc(p_emp number, p_concepto varchar2) return number is
        v_id number;
    begin
        select max(id_cuenta_ctb) into v_id from ctb_mapeo where id_empresa = p_emp and concepto = p_concepto;
        return v_id;
    end cuenta_opc;

    procedure prc_contabilizar_periodo(p_id_empresa in number, p_anio in number, p_mes in number,
                                       p_usuario in varchar2, p_creados out number, p_reversos out number,
                                       p_errores out number, p_detalle out varchar2) is
        E      constant number := p_id_empresa;
        v_ini  date := to_date(p_anio || lpad(p_mes, 2, '0') || '01', 'YYYYMMDD');
        v_fin  date := last_day(v_ini);
        v_spe  varchar2(1);
        v_id   number;
        v_tc   number;
        v_base number;
        v_iva  number;
        v_inv  number;
        v_cxc  number;
        v_cxp  number;
        v_fon  number;
        v_pri  number;
        v_gas  number;

        procedure falla(p_doc varchar2) is
        begin
            p_errores := p_errores + 1;
            if nvl(length(p_detalle), 0) < 3500 then
                p_detalle := p_detalle || p_doc || ': ' || regexp_replace(sqlerrm, '^ORA-[0-9]+: ', '') || ' | ';
            end if;
        end falla;

        function fondo(p_id_cuenta number) return number is
        begin
            return fn_cuenta_fondo(nvl(p_id_cuenta, v_pri), p_usuario);
        end fondo;
    begin
        valida_empresa(p_usuario, E);
        p_creados := 0;
        p_reversos := 0;
        p_errores := 0;
        p_detalle := null;
        if fn_periodo_abierto(E, v_ini) = 'N' then
            raise_application_error(-20184, 'El periodo ' || lpad(p_mes, 2, '0') || '/' || p_anio || ' esta cerrado.');
        end if;
        select nvl(max(es_spe), 'N') into v_spe from empresas where id_empresa = E;
        select max(id_cuenta) into v_pri from cuentas_fondos where id_empresa = E and es_principal = 'S';

        -- 1. facturas, notas de debito y notas de credito de venta (las procesadas)
        for f in (select x.id_factura, x.tipo_documento, x.folio_factura, x.fecha_emision, x.cod_moneda, x.tipo_cambio,
                         x.subtotal, x.monto_impuesto, x.monto_total, x.id_cliente
                    from facturas x
                   where x.id_empresa = E and trunc(x.fecha_emision) <= v_fin
                     and x.tipo_documento in ('FAC', 'ND', 'NC')
                     and x.estado <> 'PENDIENTE' and not (x.estado = 'ANULADA' and x.nro_control is null)
                     and not exists (select 1 from ctb_asientos a where a.id_empresa = E and a.origen = 'AUTOMATICO'
                                        and a.doc_tipo = 'FACTURA' and a.id_doc = x.id_factura and a.evento = 'EMISION')
                   order by x.fecha_emision, x.id_factura) loop
            savepoint sp_doc;
            begin
                v_tc := nvl(nullif(f.tipo_cambio, 0), 1);
                v_base := round(abs(f.subtotal) * v_tc, 2);
                v_iva := round(abs(f.monto_impuesto) * v_tc, 2);
                if f.tipo_documento = 'NC' then
                    l_add(fn_cuenta(E, 'DEVOLUCIONES_VENTAS'), v_base, 'D', 'Nota de credito ' || f.folio_factura);
                    l_add(fn_cuenta(E, 'IVA_DEBITO'), v_iva, 'D', 'IVA de la nota ' || f.folio_factura);
                    l_add(fn_cuenta(E, 'CXC'), v_base + v_iva, 'H', 'Nota de credito ' || f.folio_factura,
                          f.cod_moneda, abs(f.monto_total), v_tc, 'C', f.id_cliente);
                else
                    l_add(fn_cuenta(E, 'CXC'), v_base + v_iva, 'D', f.folio_factura,
                          f.cod_moneda, abs(f.monto_total), v_tc, 'C', f.id_cliente);
                    l_add(fn_cuenta(E, 'VENTAS'), v_base, 'H', 'Venta ' || f.folio_factura);
                    l_add(fn_cuenta(E, 'IVA_DEBITO'), v_iva, 'H', 'IVA ' || f.folio_factura);
                end if;
                v_id := asentar(E, f.fecha_emision,
                                case f.tipo_documento when 'NC' then 'Nota de credito ' when 'ND' then 'Nota de debito '
                                     else 'Factura ' end || f.folio_factura, 'FACTURA', f.id_factura, 'EMISION', p_usuario);
                if v_id is not null then p_creados := p_creados + 1; end if;
            exception
                when others then
                    g_l.delete;
                    rollback to sp_doc;
                    falla('Factura ' || f.folio_factura);
            end;
        end loop;

        -- 2. cobros: caja o banco + retencion del cliente contra cuentas por cobrar a la tasa de la factura
        for r in (select x.id_recibo, x.fecha_cobro, x.cod_moneda, x.tipo_cambio, x.monto_cobrado, x.monto_bs,
                         x.monto_factura, x.igtf_bs, x.retencion_iva_bs, x.id_cuenta,
                         f.folio_factura, f.tipo_cambio tc_fact, f.cod_moneda mon_fact, f.id_cliente
                    from recibos x join facturas f on f.id_factura = x.id_factura
                   where x.id_empresa = E and trunc(x.fecha_cobro) <= v_fin and x.estado = 'ACTIVO'
                     and not exists (select 1 from ctb_asientos a where a.id_empresa = E and a.origen = 'AUTOMATICO'
                                        and a.doc_tipo = 'RECIBO' and a.id_doc = x.id_recibo and a.evento = 'COBRO')
                   order by x.fecha_cobro, x.id_recibo) loop
            savepoint sp_doc;
            begin
                v_cxc := round(nvl(r.monto_factura, 0) * nvl(nullif(r.tc_fact, 0), 1), 2);
                l_add(fondo(r.id_cuenta), nvl(r.monto_bs, 0) - nvl(r.retencion_iva_bs, 0) + nvl(r.igtf_bs, 0), 'D',
                      'Cobro de ' || r.folio_factura, r.cod_moneda, r.monto_cobrado, r.tipo_cambio);
                l_add(fn_cuenta(E, 'RET_IVA_CLIENTES'), r.retencion_iva_bs, 'D', 'Retencion de IVA del cliente');
                l_add(fn_cuenta(E, 'CXC'), v_cxc, 'H', 'Cobro de ' || r.folio_factura,
                      r.mon_fact, r.monto_factura, r.tc_fact, 'C', r.id_cliente);
                if nvl(r.igtf_bs, 0) <> 0 then
                    l_add(fn_cuenta(E, case v_spe when 'S' then 'IGTF_POR_ENTERAR' else 'IGTF_PERCIBIDO' end),
                          r.igtf_bs, 'H', 'IGTF del cobro');
                end if;
                l_add(fn_cuenta(E, 'DIFERENCIAL_CAMBIARIO'), nvl(r.monto_bs, 0) - v_cxc, 'H', 'Diferencia de tasa');
                v_id := asentar(E, r.fecha_cobro, 'Cobro de ' || r.folio_factura, 'RECIBO', r.id_recibo, 'COBRO', p_usuario);
                if v_id is not null then p_creados := p_creados + 1; end if;
            exception
                when others then
                    g_l.delete;
                    rollback to sp_doc;
                    falla('Cobro de ' || r.folio_factura);
            end;
        end loop;

        -- 3. compras: inventario (lo que entro al kardex) + gasto + IVA credito contra cuentas por pagar
        for c in (select x.id_compra, x.tipo_documento, x.folio_factura, x.nro_control, x.fecha_emision, x.cod_moneda,
                         x.tipo_cambio, x.subtotal, x.monto_impuesto, x.monto_total, x.id_proveedor, x.id_concepto_islr
                    from compras x
                   where x.id_empresa = E and trunc(x.fecha_emision) <= v_fin and x.estado not in ('BORRADOR', 'ANULADA')
                     and not exists (select 1 from ctb_asientos a where a.id_empresa = E and a.origen = 'AUTOMATICO'
                                        and a.doc_tipo = 'COMPRA' and a.id_doc = x.id_compra and a.evento = 'REGISTRO')
                   order by x.fecha_emision, x.id_compra) loop
            savepoint sp_doc;
            begin
                v_tc := nvl(nullif(c.tipo_cambio, 0), 1);
                v_base := round(abs(c.subtotal) * v_tc, 2);
                v_iva := round(abs(c.monto_impuesto) * v_tc, 2);
                select least(v_base, round(abs(nvl(sum(costo_total_bs), 0)), 2)) into v_inv from kardex_mov
                 where id_empresa = E and doc_tipo = 'COMPRA' and id_doc = c.id_compra;
                v_gas := nvl(cuenta_opc(E, 'ISLR_' || c.id_concepto_islr), fn_cuenta(E, 'GASTO_GENERAL'));
                if c.tipo_documento = 'NC' then
                    l_add(fn_cuenta(E, 'CXP'), v_base + v_iva, 'D', 'Nota de credito ' || c.folio_factura,
                          c.cod_moneda, abs(c.monto_total), v_tc, 'P', c.id_proveedor);
                    l_add(fn_cuenta(E, 'INVENTARIO'), v_inv, 'H', 'Devolucion al proveedor');
                    l_add(v_gas, v_base - v_inv, 'H', 'Nota de credito ' || c.folio_factura);
                    l_add(fn_cuenta(E, 'IVA_CREDITO'), v_iva, 'H', 'IVA de la nota ' || c.folio_factura);
                else
                    l_add(fn_cuenta(E, 'INVENTARIO'), v_inv, 'D', 'Mercancia de la compra ' || c.folio_factura);
                    l_add(v_gas, v_base - v_inv, 'D', 'Compra ' || c.folio_factura);
                    l_add(fn_cuenta(E, 'IVA_CREDITO'), v_iva, 'D', 'IVA de la compra ' || c.folio_factura);
                    l_add(fn_cuenta(E, 'CXP'), v_base + v_iva, 'H', 'Compra ' || c.folio_factura,
                          c.cod_moneda, abs(c.monto_total), v_tc, 'P', c.id_proveedor);
                end if;
                v_id := asentar(E, c.fecha_emision, case c.tipo_documento when 'NC' then 'Nota de credito de compra '
                                else 'Compra ' end || c.folio_factura || ' (control ' || c.nro_control || ')',
                                'COMPRA', c.id_compra, 'REGISTRO', p_usuario);
                if v_id is not null then p_creados := p_creados + 1; end if;
            exception
                when others then
                    g_l.delete;
                    rollback to sp_doc;
                    falla('Compra ' || c.folio_factura);
            end;
        end loop;

        -- 4. comprobantes de retencion que emitimos al proveedor
        for t in (select x.id_retencion, x.tipo, x.numero_comprobante, x.fecha_emision, x.retenido_bs, x.id_proveedor
                    from retenciones x
                   where x.id_empresa = E and trunc(x.fecha_emision) <= v_fin and x.estado not in ('ANULADO', 'ANULADA')
                     and not exists (select 1 from ctb_asientos a where a.id_empresa = E and a.origen = 'AUTOMATICO'
                                        and a.doc_tipo = 'RETENCION' and a.id_doc = x.id_retencion and a.evento = 'EMISION')
                   order by x.fecha_emision, x.id_retencion) loop
            savepoint sp_doc;
            begin
                l_add(fn_cuenta(E, 'CXP'), t.retenido_bs, 'D', 'Retencion ' || t.tipo || ' ' || t.numero_comprobante,
                      null, null, null, 'P', t.id_proveedor);
                l_add(fn_cuenta(E, case t.tipo when 'ISLR' then 'RET_ISLR_PROVEEDORES' else 'RET_IVA_PROVEEDORES' end),
                      t.retenido_bs, 'H', 'Comprobante ' || t.numero_comprobante);
                v_id := asentar(E, t.fecha_emision, 'Retencion de ' || t.tipo || ' comprobante ' || t.numero_comprobante,
                                'RETENCION', t.id_retencion, 'EMISION', p_usuario);
                if v_id is not null then p_creados := p_creados + 1; end if;
            exception
                when others then
                    g_l.delete;
                    rollback to sp_doc;
                    falla('Retencion ' || t.numero_comprobante);
            end;
        end loop;

        -- 5. pagos a proveedores: cuentas por pagar (a la tasa de cada compra) + IGTF contra caja o banco
        for p in (select x.id_pago, x.fecha_pago, x.cod_moneda, x.tipo_cambio, x.monto, x.monto_bs, x.igtf_bs,
                         x.id_cuenta, x.id_proveedor, x.referencia
                    from pagos x
                   where x.id_empresa = E and trunc(x.fecha_pago) <= v_fin and x.estado = 'ACTIVO'
                     and not exists (select 1 from ctb_asientos a where a.id_empresa = E and a.origen = 'AUTOMATICO'
                                        and a.doc_tipo = 'PAGO' and a.id_doc = x.id_pago and a.evento = 'PAGO')
                   order by x.fecha_pago, x.id_pago) loop
            savepoint sp_doc;
            begin
                select round(sum(d.monto_aplicado * nvl(nullif(c.tipo_cambio, 0), 1)), 2) into v_cxp
                  from pagos_detalle d join compras c on c.id_compra = d.id_compra
                 where d.id_pago = p.id_pago;
                v_cxp := nvl(v_cxp, nvl(p.monto_bs, 0));
                l_add(fn_cuenta(E, 'CXP'), v_cxp, 'D', 'Pago ' || p.referencia, p.cod_moneda, p.monto, p.tipo_cambio,
                      'P', p.id_proveedor);
                l_add(fn_cuenta(E, 'IGTF_GASTO'), p.igtf_bs, 'D', 'IGTF del pago');
                l_add(fondo(p.id_cuenta), nvl(p.monto_bs, 0) + nvl(p.igtf_bs, 0), 'H', 'Pago ' || p.referencia,
                      p.cod_moneda, p.monto, p.tipo_cambio);
                l_add(fn_cuenta(E, 'DIFERENCIAL_CAMBIARIO'), nvl(p.monto_bs, 0) - v_cxp, 'D', 'Diferencia de tasa');
                v_id := asentar(E, p.fecha_pago, 'Pago a proveedor ' || p.referencia, 'PAGO', p.id_pago, 'PAGO', p_usuario);
                if v_id is not null then p_creados := p_creados + 1; end if;
            exception
                when others then
                    g_l.delete;
                    rollback to sp_doc;
                    falla('Pago ' || p.referencia);
            end;
        end loop;

        -- 6. kardex (menos las entradas de compra, que van en el asiento de la compra)
        for k in (select m.doc_tipo, nvl(m.id_doc, min(m.id_movimiento)) id_doc, m.tipo_movimiento,
                         min(trunc(m.fecha_movimiento)) fecha,
                         round(sum(pkg_inventario.fn_signo(m.tipo_movimiento) * m.costo_total_bs), 2) imp
                    from kardex_mov m
                   where m.id_empresa = E and m.doc_tipo <> 'COMPRA' and trunc(m.fecha_movimiento) <= v_fin
                   group by m.doc_tipo, m.id_doc, m.tipo_movimiento
                   order by 4, 2) loop
            if not hecho(E, substr('KARDEX_' || k.doc_tipo, 1, 20), k.id_doc, substr(k.tipo_movimiento, 1, 20)) then
                savepoint sp_doc;
                begin
                    l_add(fn_cuenta(E, 'INVENTARIO'), k.imp, 'D', initcap(replace(k.tipo_movimiento, '_', ' ')));
                    l_add(fn_cuenta(E, case
                              when k.tipo_movimiento in ('SALIDA_FACTURA', 'SALIDA_ND_CLIENTE', 'ENTRADA_NC_CLIENTE') then 'COSTO_VENTAS'
                              when k.tipo_movimiento = 'SALDO_INICIAL' then 'APERTURA'
                              when k.imp > 0 then 'SOBRANTE_INVENTARIO'
                              else 'FALTANTE_INVENTARIO' end),
                          k.imp, 'H', initcap(replace(k.tipo_movimiento, '_', ' ')));
                    v_id := asentar(E, k.fecha, case
                                        when k.tipo_movimiento in ('SALIDA_FACTURA', 'SALIDA_ND_CLIENTE') then 'Costo de venta'
                                        when k.tipo_movimiento = 'ENTRADA_NC_CLIENTE' then 'Devolucion de mercancia (costo)'
                                        when k.tipo_movimiento = 'SALDO_INICIAL' then 'Saldo inicial de inventario'
                                        else 'Ajuste de inventario' end
                                    || ' (' || lower(k.doc_tipo) || ' ' || k.id_doc || ')',
                                    substr('KARDEX_' || k.doc_tipo, 1, 20), k.id_doc, substr(k.tipo_movimiento, 1, 20), p_usuario);
                    if v_id is not null then p_creados := p_creados + 1; end if;
                exception
                    when others then
                        g_l.delete;
                        rollback to sp_doc;
                        falla('Kardex ' || k.doc_tipo || ' ' || k.id_doc);
                end;
            end if;
        end loop;

        -- 7. anulaciones de documentos ya contabilizados: su reverso en el mes abierto
        for a in (select 'RECIBO' doc, x.id_recibo id, nvl(x.fecha_modificacion, sysdate) fecha
                    from recibos x where x.id_empresa = E and x.estado = 'ANULADO'
                  union all
                  select 'PAGO', x.id_pago, nvl(x.fecha_modificacion, sysdate) from pagos x
                   where x.id_empresa = E and x.estado = 'ANULADO'
                  union all
                  select 'COMPRA', x.id_compra, nvl(x.fecha_modificacion, sysdate) from compras x
                   where x.id_empresa = E and x.estado = 'ANULADA'
                  union all
                  select 'RETENCION', x.id_retencion, sysdate from retenciones x
                   where x.id_empresa = E and x.estado in ('ANULADO', 'ANULADA')) loop
            if trunc(a.fecha) <= v_fin then
                savepoint sp_doc;
                begin
                    p_reversos := p_reversos + reversar_doc(E, a.doc, a.id, a.fecha, p_usuario);
                exception
                    when others then
                        rollback to sp_doc;
                        falla('Anulacion ' || lower(a.doc) || ' ' || a.id);
                end;
            end if;
        end loop;
        p_detalle := rtrim(p_detalle, ' |');
    end prc_contabilizar_periodo;

    -- ===================================================================== fase 5
    function fn_saldo_concepto(p_id_empresa in number, p_concepto in varchar2, p_hasta in date default null) return number is
        v number;
    begin
        select nvl(sum(d.haber - d.debe), 0) into v
          from ctb_asiento_det d join ctb_asientos a on a.id_asiento = d.id_asiento
         where a.id_empresa = p_id_empresa and a.estado in ('CONFIRMADO', 'REVERSADO')
           and a.fecha <= nvl(p_hasta, date '2999-12-31')
           and d.id_cuenta_ctb = fn_cuenta(p_id_empresa, p_concepto);
        return v;
    end fn_saldo_concepto;

    procedure prc_cierre_anual(p_id_empresa in number, p_anio in number, p_usuario in varchar2,
                               p_id_asiento out number) is
        v_ini   date := to_date(p_anio || '0101', 'YYYYMMDD');
        v_fin   date := to_date(p_anio || '1231', 'YYYYMMDD');
        v_total number := 0;
        v_n     number;
        v_res   number;
    begin
        valida_empresa(p_usuario, p_id_empresa);
        select count(*) into v_n from ctb_asientos
         where id_empresa = p_id_empresa and origen = 'CIERRE' and doc_tipo = 'CIERRE_ANUAL' and id_doc = p_anio
           and estado = 'CONFIRMADO';
        if v_n > 0 then
            raise_application_error(-20192, 'El ejercicio ' || p_anio || ' ya esta cerrado. Para rehacerlo, reversa su asiento de cierre.');
        end if;
        if fn_periodo_abierto(p_id_empresa, v_fin) = 'N' then
            raise_application_error(-20184, 'Diciembre de ' || p_anio || ' esta cerrado: reabrelo para registrar el cierre anual.');
        end if;
        v_res := fn_cuenta(p_id_empresa, 'RESULTADO_EJERCICIO');
        g_l.delete;
        for c in (select d.id_cuenta_ctb, sum(d.debe - d.haber) s
                    from ctb_asiento_det d
                    join ctb_asientos a on a.id_asiento = d.id_asiento
                    join ctb_cuentas cu on cu.id_cuenta_ctb = d.id_cuenta_ctb
                   where a.id_empresa = p_id_empresa and a.estado in ('CONFIRMADO', 'REVERSADO')
                     and a.fecha between v_ini and v_fin and substr(cu.codigo, 1, 1) in ('4', '5', '6', '7')
                   group by d.id_cuenta_ctb
                  having sum(d.debe - d.haber) <> 0) loop
            l_add(c.id_cuenta_ctb, c.s, 'H', 'Cierre del ejercicio ' || p_anio);
            v_total := v_total + c.s;
        end loop;
        if g_l.count = 0 then
            raise_application_error(-20192, 'No hay ingresos, costos ni gastos en ' || p_anio || ': no hay nada que cerrar.');
        end if;
        l_add(v_res, v_total, 'D', case when v_total <= 0 then 'Utilidad' else 'Perdida' end || ' del ejercicio ' || p_anio);
        p_id_asiento := asentar(p_id_empresa, v_fin, 'Cierre del ejercicio ' || p_anio, 'CIERRE_ANUAL', p_anio,
                                'CIERRE', p_usuario, 'CIERRE');
    end prc_cierre_anual;

    procedure prc_pagar_seniat(p_id_empresa in number, p_concepto in varchar2, p_fecha in date,
                               p_id_cuenta in number, p_monto in number, p_referencia in varchar2,
                               p_usuario in varchar2, p_id_asiento out number) is
        v_con   varchar2(40) := upper(trim(p_concepto));
        v_monto number := round(nvl(p_monto, 0), 2);
        v_pend  number;
    begin
        valida_empresa(p_usuario, p_id_empresa);
        if v_con is null or v_con not in ('RET_IVA_PROVEEDORES', 'RET_ISLR_PROVEEDORES', 'IGTF_POR_ENTERAR', 'IVA_POR_PAGAR') then
            raise_application_error(-20191, 'Elige que se paga: IVA por pagar, retenciones de IVA, retenciones de ISLR o IGTF.');
        end if;
        if p_fecha is null or p_id_cuenta is null or v_monto <= 0 then
            raise_application_error(-20191, 'Indica la fecha, el banco y un monto mayor que cero.');
        end if;
        v_pend := fn_saldo_concepto(p_id_empresa, v_con, p_fecha);
        if v_monto > v_pend + 0.01 then
            raise_application_error(-20193, 'El monto supera lo pendiente por enterar a esa fecha ('
                || to_char(v_pend, 'FM999G999G999G990D00') || ').');
        end if;
        g_l.delete;
        l_add(fn_cuenta(p_id_empresa, v_con), v_monto, 'D', 'Entero al SENIAT ' || p_referencia);
        l_add(fn_cuenta_fondo(p_id_cuenta, p_usuario), v_monto, 'H', 'Entero al SENIAT ' || p_referencia);
        p_id_asiento := asentar(p_id_empresa, p_fecha,
                                'Pago al SENIAT: ' || case v_con when 'RET_IVA_PROVEEDORES' then 'retenciones de IVA'
                                    when 'RET_ISLR_PROVEEDORES' then 'retenciones de ISLR'
                                    when 'IVA_POR_PAGAR' then 'IVA del periodo' else 'IGTF' end
                                || case when trim(p_referencia) is not null then ' (ref. ' || trim(p_referencia) || ')' end,
                                'SENIAT', null, v_con, p_usuario, 'MANUAL');
    end prc_pagar_seniat;

    procedure prc_liquidar_iva(p_id_empresa in number, p_anio in number, p_mes in number,
                               p_usuario in varchar2, p_id_asiento out number) is
        v_fin   date := last_day(to_date(p_anio || lpad(p_mes, 2, '0') || '01', 'YYYYMMDD'));
        v_n     number;
        v_deb   number;
        v_cre   number;
        v_exc   number;
        v_ret   number;
        v_cuota number;
        v_retu  number;

        function saldo(p_concepto varchar2) return number is
            v number;
        begin
            select nvl(sum(d.debe - d.haber), 0) into v
              from ctb_asiento_det d join ctb_asientos a on a.id_asiento = d.id_asiento
             where a.id_empresa = p_id_empresa and a.estado in ('CONFIRMADO', 'REVERSADO') and a.fecha <= v_fin
               and d.id_cuenta_ctb = fn_cuenta(p_id_empresa, p_concepto);
            return v;
        end saldo;
    begin
        valida_empresa(p_usuario, p_id_empresa);
        if fn_periodo_abierto(p_id_empresa, v_fin) = 'N' then
            raise_application_error(-20184, 'El periodo ' || lpad(p_mes, 2, '0') || '/' || p_anio || ' esta cerrado.');
        end if;
        select count(*) into v_n from ctb_asientos
         where id_empresa = p_id_empresa and doc_tipo = 'LIQ_IVA' and id_doc = p_anio * 100 + p_mes and estado = 'CONFIRMADO';
        if v_n > 0 then
            raise_application_error(-20194, 'El IVA de ' || lpad(p_mes, 2, '0') || '/' || p_anio
                || ' ya esta liquidado. Para rehacerlo, reversa ese asiento.');
        end if;
        v_deb := -saldo('IVA_DEBITO');            -- acreedor
        v_cre := saldo('IVA_CREDITO');            -- deudor
        v_exc := saldo('IVA_EXCEDENTE');          -- deudor (excedente de meses anteriores)
        v_ret := saldo('RET_IVA_CLIENTES');       -- deudor (retenciones que nos hicieron)
        if v_deb = 0 and v_cre = 0 then
            raise_application_error(-20194, 'No hay IVA que liquidar hasta ' || to_char(v_fin, 'DD/MM/YYYY')
                || ': contabiliza el mes primero.');
        end if;
        v_cuota := v_deb - v_cre - v_exc;
        v_retu := least(v_ret, greatest(v_cuota, 0));
        g_l.delete;
        l_add(fn_cuenta(p_id_empresa, 'IVA_DEBITO'), v_deb, 'D', 'Debito fiscal del periodo');
        l_add(fn_cuenta(p_id_empresa, 'IVA_CREDITO'), v_cre, 'H', 'Credito fiscal del periodo');
        l_add(fn_cuenta(p_id_empresa, 'IVA_EXCEDENTE'), greatest(-v_cuota, 0) - v_exc, 'D', 'Excedente de credito fiscal');
        l_add(fn_cuenta(p_id_empresa, 'RET_IVA_CLIENTES'), v_retu, 'H', 'Retenciones de clientes descontadas');
        l_add(fn_cuenta(p_id_empresa, 'IVA_POR_PAGAR'), greatest(v_cuota, 0) - v_retu, 'H', 'IVA a pagar al SENIAT');
        p_id_asiento := asentar(p_id_empresa, v_fin, 'Liquidacion del IVA ' || lpad(p_mes, 2, '0') || '/' || p_anio,
                                'LIQ_IVA', p_anio * 100 + p_mes, 'LIQUIDACION', p_usuario, 'MANUAL');
    end prc_liquidar_iva;

    function fn_purgando return boolean is
    begin
        return g_purgando;
    end fn_purgando;

    procedure prc_purgar_prueba(p_id_empresa in number) is
    begin
        if p_id_empresa is null or p_id_empresa not between 900000 and 900999 then
            raise_application_error(-20190, 'La purga solo se permite en empresas de prueba (900000-900999).');
        end if;
        g_purgando := true;
        delete from ctb_asiento_det where id_asiento in (select id_asiento from ctb_asientos where id_empresa = p_id_empresa);
        commit;
        update ctb_asientos set id_asiento_original = null, id_asiento_reverso = null where id_empresa = p_id_empresa;
        commit;
        delete from ctb_asientos where id_empresa = p_id_empresa;
        commit;
        delete from ctb_periodos where id_empresa = p_id_empresa;
        commit;
        delete from ctb_mapeo where id_empresa = p_id_empresa;
        commit;
        update cuentas_fondos set id_cuenta_ctb = null where id_empresa = p_id_empresa;
        commit;
        update ctb_cuentas set id_padre = null where id_empresa = p_id_empresa;
        commit;
        delete from ctb_cuentas where id_empresa = p_id_empresa;
        commit;
        g_purgando := false;
    exception
        when others then
            g_purgando := false;
            raise;
    end prc_purgar_prueba;

end pkg_contabilidad;
/

create or replace function fn_ctb_libro (
    p_libro     in varchar2,
    p_desde     in date,
    p_hasta     in date,
    p_id_cuenta in number,
    p_empresa   in number,
    p_formato   in varchar2 default 'HTML'
) return clob is
    v_xls   boolean := upper(p_formato) = 'XLS';
    v_lib   varchar2(20) := upper(nvl(p_libro, 'BALANCE'));
    v_desde date := trunc(nvl(p_desde, trunc(sysdate, 'YYYY')));
    v_hasta date := trunc(nvl(p_hasta, sysdate));
    v_html  clob;
    v_emp   varchar2(200);
    v_rif   varchar2(40);
    v_tit   varchar2(100);
    v_td    number := 0;
    v_th    number := 0;
    v_ts    number := 0;
    v_saldo number;
    v_cxx   number;
    v_hay   boolean := false;

    procedure w(s varchar2) is
    begin
        v_html := v_html || s;
    end w;

    -- celda de texto; p_css = estilo adicional (sangria, negrita)
    function t(s varchar2, p_css varchar2 default null) return varchar2 is
        v_css varchar2(200) := case when v_xls then 'mso-number-format:''\@'';' end || p_css;
    begin
        return '<td' || case when v_css is not null then ' style="' || v_css || '"' end || '>'
            || sys.htf.escape_sc(s) || '</td>';
    end t;

    function n(x number, p_negrita boolean default false) return varchar2 is
    begin
        if v_xls then
            return '<td style="mso-number-format:''#\,##0\.00''' || case when p_negrita then ';font-weight:bold' end
                || '">' || to_char(nvl(x, 0), 'TM9', 'NLS_NUMERIC_CHARACTERS=''.,''') || '</td>';
        end if;
        return '<td class="num"' || case when p_negrita then ' style="font-weight:600"' end || '>'
            || to_char(nvl(x, 0), 'FM999G999G999G990D00') || '</td>';
    end n;

    function asiento_ref(p_mes number, p_anio number, p_num number) return varchar2 is
    begin
        return lpad(p_mes, 2, '0') || '/' || p_anio || '-' || lpad(p_num, 4, '0');
    end asiento_ref;

    -- Saldo con signo de presentacion (p_signo = 1: debe - haber; -1: haber - debe) de las cuentas
    -- del prefijo entre p_d y p_h, con sus grupos; escribe las filas y devuelve el total.
    function seccion(p_pref varchar2, p_titulo varchar2, p_signo number, p_d date, p_h date,
                     p_sin_cierre boolean) return number is
        v_tot number := 0;
        v_sc  varchar2(1) := case when p_sin_cierre then 'S' else 'N' end;
    begin
        w('<tr class="spx-grp"><td colspan="3"><b>' || p_titulo || '</b></td></tr>');
        for b in (with mov as (
                      select d.id_cuenta_ctb, sum(d.debe - d.haber) s
                        from ctb_asiento_det d join ctb_asientos a on a.id_asiento = d.id_asiento
                       where a.id_empresa = p_empresa and a.estado in ('CONFIRMADO', 'REVERSADO')
                         and a.fecha between p_d and p_h
                         and (v_sc = 'N' or a.origen <> 'CIERRE')
                       group by d.id_cuenta_ctb),
                  hoja as (
                      select c.codigo, m.s from ctb_cuentas c join mov m on m.id_cuenta_ctb = c.id_cuenta_ctb
                       where c.codigo like p_pref || '%')
                  select c.codigo, c.nombre, c.nivel, c.acepta_movimiento, sum(h.s) s
                    from ctb_cuentas c
                    join hoja h on (h.codigo = c.codigo
                                    or (c.acepta_movimiento = 'N' and substr(h.codigo, 1, length(c.codigo)) = c.codigo))
                   where c.id_empresa = p_empresa and c.codigo like p_pref || '%' and c.codigo <> p_pref
                   group by c.codigo, c.nombre, c.nivel, c.acepta_movimiento
                  having sum(h.s) <> 0
                   order by c.codigo) loop
            w('<tr' || case when b.acepta_movimiento = 'N' then ' class="spx-grp"' end || '>' || t(b.codigo)
              || t(b.nombre, 'padding-left:' || to_char((b.nivel - 1) * 14 + 6) || 'px'
                   || case when b.acepta_movimiento = 'N' then ';font-weight:bold' end)
              || n(p_signo * b.s, b.acepta_movimiento = 'N') || '</tr>');
            if b.acepta_movimiento = 'S' then
                v_tot := v_tot + p_signo * b.s;
            end if;
        end loop;
        w('<tr class="spx-tot"><td colspan="2"><b>Total ' || lower(p_titulo) || '</b></td>' || n(v_tot, true) || '</tr>');
        return v_tot;
    end seccion;
begin
    select e.nombre_empresa, e.rfc into v_emp, v_rif from empresas e where e.id_empresa = p_empresa;
    v_tit := case v_lib when 'DIARIO' then 'Libro diario'
                        when 'MAYOR' then 'Mayor anal&iacute;tico'
                        when 'RESULTADOS' then 'Estado de resultados'
                        when 'SITUACION' then 'Balance general (estado de situaci&oacute;n financiera)'
                        when 'IMPUESTOS' then 'Resumen de impuestos del per&iacute;odo'
                        when 'RETENCIONES' then 'Retenciones de IVA e ISLR'
                        when 'FLUJO' then 'Estado de flujo de efectivo (m&eacute;todo directo)'
                        when 'PATRIMONIO' then 'Estado de cambios en el patrimonio'
                        when 'INVENTARIOS' then 'Libro de inventarios'
                        else 'Balance de comprobaci&oacute;n' end;

    if v_xls then
        w('<html><head><meta charset="utf-8"></head><body><table border="1">'
          || '<tr><td colspan="7" style="font-weight:bold;font-size:14pt">' || sys.htf.escape_sc(v_emp) || '</td></tr>'
          || '<tr><td colspan="7">RIF: ' || sys.htf.escape_sc(v_rif) || '</td></tr>'
          || '<tr><td colspan="7" style="font-weight:bold">' || v_tit || '</td></tr>'
          || '<tr><td colspan="7">' || case when v_lib = 'SITUACION' then 'Al ' || to_char(v_hasta, 'DD/MM/YYYY')
             else 'Del ' || to_char(v_desde, 'DD/MM/YYYY') || ' al ' || to_char(v_hasta, 'DD/MM/YYYY') end
          || ' - generado el ' || to_char(sysdate, 'DD/MM/YYYY HH24:MI') || '</td></tr><tr></tr>');
    else
        w('<table class="spx-cc spx-libro">');
    end if;

    if v_lib = 'DIARIO' then
        w('<tr class="spx-th"><th>Fecha</th><th>Asiento</th><th>C&oacute;digo</th><th>Cuenta</th>'
          || '<th>Descripci&oacute;n</th><th class="num">Debe</th><th class="num">Haber</th></tr>');
        for a in (select id_asiento, fecha, anio, mes, numero, concepto, estado
                    from ctb_asientos
                   where id_empresa = p_empresa and estado in ('CONFIRMADO', 'REVERSADO')
                     and fecha between v_desde and v_hasta
                   order by fecha, anio, mes, numero) loop
            v_hay := true;
            w('<tr class="spx-grp">' || t(to_char(a.fecha, 'DD/MM/YYYY')) || t(asiento_ref(a.mes, a.anio, a.numero))
              || '<td colspan="5"' || case when v_xls then ' style="font-weight:bold"' end || '>'
              || sys.htf.escape_sc(a.concepto) || case when a.estado = 'REVERSADO' then ' (reversado)' end
              || '</td></tr>');
            for l in (select c.codigo, c.nombre, d.descripcion, d.debe, d.haber
                        from ctb_asiento_det d join ctb_cuentas c on c.id_cuenta_ctb = d.id_cuenta_ctb
                       where d.id_asiento = a.id_asiento order by d.linea) loop
                w('<tr><td></td><td></td>' || t(l.codigo) || t(l.nombre) || t(l.descripcion)
                  || n(l.debe) || n(l.haber) || '</tr>');
                v_td := v_td + l.debe;
                v_th := v_th + l.haber;
            end loop;
        end loop;
        if not v_hay then
            w('<tr><td colspan="7">No hay asientos confirmados en el periodo.</td></tr>');
        end if;
        w('<tr class="spx-tot"><td colspan="5"><b>TOTALES</b></td>' || n(v_td, true) || n(v_th, true) || '</tr>');

    elsif v_lib = 'RESULTADOS' then
        w('<tr class="spx-th"><th>C&oacute;digo</th><th>Cuenta</th><th class="num">Importe</th></tr>');
        v_ts := seccion('4.', 'INGRESOS', -1, v_desde, v_hasta, true);
        v_td := seccion('5.', 'COSTOS', 1, v_desde, v_hasta, true);
        v_th := seccion('6.', 'GASTOS', 1, v_desde, v_hasta, true);
        -- clase 7 del codigo agrupador del SAT (Mexico): resultado integral de financiamiento
        v_cxx := 0;
        select count(*) into v_saldo from ctb_cuentas where id_empresa = p_empresa and codigo = '7.';
        if v_saldo > 0 then
            v_cxx := seccion('7.', 'RESULTADO INTEGRAL DE FINANCIAMIENTO', 1, v_desde, v_hasta, true);
        end if;
        w('<tr class="spx-tot"><td colspan="2"><b>' || case when v_ts - v_td - v_th - v_cxx >= 0 then 'UTILIDAD' else 'P&Eacute;RDIDA' end
          || ' DEL PER&Iacute;ODO</b> (ingresos - costos - gastos' || case when v_saldo > 0 then ' - financiamiento' end
          || ')</td>' || n(v_ts - v_td - v_th - v_cxx, true) || '</tr>');

    elsif v_lib = 'SITUACION' then
        w('<tr class="spx-th"><th>C&oacute;digo</th><th>Cuenta</th><th class="num">Saldo</th></tr>');
        v_ts := seccion('1.', 'ACTIVO', 1, date '1900-01-01', v_hasta, false);
        v_td := seccion('2.', 'PASIVO', -1, date '1900-01-01', v_hasta, false);
        v_th := seccion('3.', 'PATRIMONIO', -1, date '1900-01-01', v_hasta, false);
        -- resultado aun no llevado al patrimonio por el cierre anual
        select nvl(sum(d.haber - d.debe), 0) into v_saldo
          from ctb_asiento_det d join ctb_asientos a on a.id_asiento = d.id_asiento
          join ctb_cuentas c on c.id_cuenta_ctb = d.id_cuenta_ctb
         where a.id_empresa = p_empresa and a.estado in ('CONFIRMADO', 'REVERSADO') and a.fecha <= v_hasta
           and substr(c.codigo, 1, 1) in ('4', '5', '6', '7');
        w('<tr><td></td><td>Resultado del ejercicio a&uacute;n no cerrado</td>' || n(v_saldo, true) || '</tr>');
        w('<tr class="spx-tot"><td colspan="2"><b>Total pasivo + patrimonio + resultado</b></td>'
          || n(v_td + v_th + v_saldo, true) || '</tr>');
        w('<tr><td colspan="3">' || case when abs(v_ts - (v_td + v_th + v_saldo)) < 0.005 then 'Cuadra: activo = pasivo + patrimonio + resultado'
          else 'NO CUADRA: diferencia ' || to_char(v_ts - (v_td + v_th + v_saldo), 'FM999G999G999G990D00') end || '</td></tr>');

    elsif v_lib = 'IMPUESTOS' then
        -- desde los documentos del periodo (no hace falta haber contabilizado)
        declare
            v_bv number; v_iv number; v_bc number; v_ic number; v_rr number; v_ri number; v_rs number;
            v_gc number; v_gp number; v_nr number;
        begin
            select nvl(sum(case when f.tipo_documento = 'NC' then -1 else 1 end * round(abs(f.subtotal) * nvl(nullif(f.tipo_cambio, 0), 1), 2)), 0),
                   nvl(sum(case when f.tipo_documento = 'NC' then -1 else 1 end * round(abs(f.monto_impuesto) * nvl(nullif(f.tipo_cambio, 0), 1), 2)), 0)
              into v_bv, v_iv
              from facturas f
             where f.id_empresa = p_empresa and f.tipo_documento in ('FAC', 'ND', 'NC')
               and f.estado <> 'PENDIENTE' and not (f.estado = 'ANULADA' and f.nro_control is null)
               and trunc(f.fecha_emision) between v_desde and v_hasta;
            select nvl(sum(case when c.tipo_documento = 'NC' then -1 else 1 end * round(abs(c.subtotal) * nvl(nullif(c.tipo_cambio, 0), 1), 2)), 0),
                   nvl(sum(case when c.tipo_documento = 'NC' then -1 else 1 end * round(abs(c.monto_impuesto) * nvl(nullif(c.tipo_cambio, 0), 1), 2)), 0)
              into v_bc, v_ic
              from compras c
             where c.id_empresa = p_empresa and c.estado not in ('BORRADOR', 'ANULADA')
               and trunc(c.fecha_emision) between v_desde and v_hasta;
            select nvl(sum(r.retencion_iva_bs), 0), nvl(sum(r.igtf_bs), 0), count(case when r.retencion_iva_bs > 0 then 1 end)
              into v_rr, v_gc, v_nr
              from recibos r
             where r.id_empresa = p_empresa and r.estado = 'ACTIVO' and trunc(r.fecha_cobro) between v_desde and v_hasta;
            select nvl(sum(case when x.tipo = 'IVA' then x.retenido_bs end), 0), nvl(sum(case when x.tipo = 'ISLR' then x.retenido_bs end), 0)
              into v_ri, v_rs
              from retenciones x
             where x.id_empresa = p_empresa and x.estado not in ('ANULADO', 'ANULADA')
               and trunc(x.fecha_emision) between v_desde and v_hasta;
            select nvl(sum(p.igtf_bs), 0) into v_gp
              from pagos p
             where p.id_empresa = p_empresa and p.estado = 'ACTIVO' and trunc(p.fecha_pago) between v_desde and v_hasta;
            w('<tr class="spx-th"><th>Concepto</th><th class="num">Base (Bs)</th><th class="num">Impuesto (Bs)</th></tr>');
            w('<tr class="spx-grp"><td colspan="3"><b>IVA</b></td></tr>');
            w('<tr>' || '<td>Ventas (d&eacute;bito fiscal), notas de cr&eacute;dito restadas</td>' || n(v_bv) || n(v_iv) || '</tr>');
            w('<tr>' || '<td>Compras (cr&eacute;dito fiscal), notas de cr&eacute;dito restadas</td>' || n(v_bc) || n(v_ic) || '</tr>');
            w('<tr class="spx-tot"><td colspan="2"><b>Cuota del per&iacute;odo (d&eacute;bito - cr&eacute;dito)</b></td>' || n(v_iv - v_ic, true) || '</tr>');
            w('<tr>' || '<td>Retenciones de IVA que te hicieron los clientes (' || to_char(v_nr) || ' comprobantes)</td>' || '<td></td>' || n(v_rr) || '</tr>');
            w('<tr class="spx-tot"><td colspan="2"><b>'
              || case when v_iv - v_ic - v_rr >= 0 then 'IVA a pagar estimado' else 'Excedente de cr&eacute;dito estimado' end
              || '</b> (sin excedentes de meses anteriores)</td>' || n(abs(v_iv - v_ic - v_rr), true) || '</tr>');
            w('<tr class="spx-grp"><td colspan="3"><b>RETENCIONES QUE SE ENTERAN AL SENIAT</b></td></tr>');
            w('<tr>' || '<td>Retenciones de IVA practicadas a proveedores</td>' || '<td></td>' || n(v_ri) || '</tr>');
            w('<tr>' || '<td>Retenciones de ISLR practicadas a proveedores</td>' || '<td></td>' || n(v_rs) || '</tr>');
            w('<tr class="spx-grp"><td colspan="3"><b>IGTF</b></td></tr>');
            w('<tr>' || '<td>IGTF percibido en cobros en divisa</td>' || '<td></td>' || n(v_gc) || '</tr>');
            w('<tr>' || '<td>IGTF pagado en pagos a proveedores (gasto)</td>' || '<td></td>' || n(v_gp) || '</tr>');
        end;

    elsif v_lib = 'RETENCIONES' then
        w('<tr class="spx-grp"><td colspan="6"><b>RETENCIONES DE IVA RECIBIDAS (las que te hicieron los clientes)</b></td></tr>');
        w('<tr class="spx-th"><th>Fecha</th><th>Comprobante</th><th>RIF</th><th>Cliente</th><th>Factura</th><th class="num">Retenido (Bs)</th></tr>');
        for r in (select r.fecha_cobro, r.nro_comprobante_retencion, c.rif, c.razon_social, f.folio_factura, r.retencion_iva_bs
                    from recibos r join facturas f on f.id_factura = r.id_factura
                    left join clientes c on c.id_cliente = f.id_cliente
                   where r.id_empresa = p_empresa and r.estado = 'ACTIVO' and nvl(r.retencion_iva_bs, 0) > 0
                     and trunc(r.fecha_cobro) between v_desde and v_hasta
                   order by r.fecha_cobro, r.id_recibo) loop
            v_hay := true;
            v_td := v_td + r.retencion_iva_bs;
            w('<tr>' || t(to_char(r.fecha_cobro, 'DD/MM/YYYY')) || t(r.nro_comprobante_retencion) || t(r.rif)
              || t(r.razon_social) || t(r.folio_factura) || n(r.retencion_iva_bs) || '</tr>');
        end loop;
        w('<tr class="spx-tot"><td colspan="5"><b>Total recibidas</b></td>' || n(v_td, true) || '</tr>');
        w('<tr class="spx-grp"><td colspan="6"><b>RETENCIONES PRACTICADAS A PROVEEDORES (se enteran al SENIAT)</b></td></tr>');
        w('<tr class="spx-th"><th>Fecha</th><th>Tipo / comprobante</th><th>RIF</th><th>Proveedor</th><th class="num">Base (Bs)</th><th class="num">Retenido (Bs)</th></tr>');
        for x in (select x.fecha_emision, x.tipo, x.numero_comprobante, p.rif, p.razon_social, x.base_imponible_bs, x.retenido_bs
                    from retenciones x left join proveedores p on p.id_proveedor = x.id_proveedor
                   where x.id_empresa = p_empresa and x.estado not in ('ANULADO', 'ANULADA')
                     and trunc(x.fecha_emision) between v_desde and v_hasta
                   order by x.tipo, x.fecha_emision, x.numero_comprobante) loop
            v_hay := true;
            if x.tipo = 'IVA' then v_th := v_th + x.retenido_bs; else v_ts := v_ts + x.retenido_bs; end if;
            w('<tr>' || t(to_char(x.fecha_emision, 'DD/MM/YYYY')) || t(x.tipo || ' ' || x.numero_comprobante) || t(x.rif)
              || t(x.razon_social) || n(x.base_imponible_bs) || n(x.retenido_bs) || '</tr>');
        end loop;
        w('<tr class="spx-tot"><td colspan="5"><b>Total practicadas de IVA</b></td>' || n(v_th, true) || '</tr>');
        w('<tr class="spx-tot"><td colspan="5"><b>Total practicadas de ISLR</b></td>' || n(v_ts, true) || '</tr>');

    elsif v_lib = 'FLUJO' then
        -- metodo directo: los movimientos de las cuentas de caja y bancos (1.1.1.) por su origen
        select nvl(sum(d.debe - d.haber), 0) into v_saldo
          from ctb_asiento_det d join ctb_asientos a on a.id_asiento = d.id_asiento
          join ctb_cuentas c on c.id_cuenta_ctb = d.id_cuenta_ctb
         where a.id_empresa = p_empresa and a.estado in ('CONFIRMADO', 'REVERSADO') and a.fecha < v_desde
           and c.codigo like '1.1.1.%';
        w('<tr class="spx-th"><th>Concepto</th><th class="num">Entradas</th><th class="num">Salidas</th><th class="num">Neto</th></tr>');
        w('<tr class="spx-grp"><td><b>Efectivo al inicio (caja y bancos)</b></td><td></td><td></td>' || n(v_saldo, true) || '</tr>');
        for f in (select case a.doc_tipo when 'RECIBO' then '1 Cobros a clientes'
                                        when 'PAGO' then '2 Pagos a proveedores'
                                        when 'SENIAT' then '3 Pagos de impuestos (SENIAT)'
                                        else '4 Otros movimientos (asientos manuales y traspasos)' end grupo,
                         sum(d.debe) entra, sum(d.haber) sale
                    from ctb_asiento_det d join ctb_asientos a on a.id_asiento = d.id_asiento
                    join ctb_cuentas c on c.id_cuenta_ctb = d.id_cuenta_ctb
                   where a.id_empresa = p_empresa and a.estado in ('CONFIRMADO', 'REVERSADO')
                     and a.fecha between v_desde and v_hasta and c.codigo like '1.1.1.%'
                   group by case a.doc_tipo when 'RECIBO' then '1 Cobros a clientes'
                                           when 'PAGO' then '2 Pagos a proveedores'
                                           when 'SENIAT' then '3 Pagos de impuestos (SENIAT)'
                                           else '4 Otros movimientos (asientos manuales y traspasos)' end
                   order by 1) loop
            v_hay := true;
            v_td := v_td + f.entra;
            v_th := v_th + f.sale;
            w('<tr>' || t(substr(f.grupo, 3)) || n(f.entra) || n(f.sale) || n(f.entra - f.sale) || '</tr>');
        end loop;
        if not v_hay then
            w('<tr><td colspan="4">No hubo movimientos de caja ni de bancos en el per&iacute;odo.</td></tr>');
        end if;
        w('<tr class="spx-tot"><td><b>Variaci&oacute;n del per&iacute;odo</b></td>' || n(v_td, true) || n(v_th, true) || n(v_td - v_th, true) || '</tr>');
        w('<tr class="spx-tot"><td><b>Efectivo al final</b></td><td></td><td></td>' || n(v_saldo + v_td - v_th, true) || '</tr>');

    elsif v_lib = 'PATRIMONIO' then
        w('<tr class="spx-th"><th>C&oacute;digo</th><th>Cuenta</th><th class="num">Saldo inicial</th><th class="num">Aumentos</th>'
          || '<th class="num">Disminuciones</th><th class="num">Saldo final</th></tr>');
        for c in (select c.codigo, c.nombre,
                         nvl(sum(case when a.fecha < v_desde then d.haber - d.debe end), 0) ini,
                         nvl(sum(case when a.fecha >= v_desde then d.haber end), 0) aum,
                         nvl(sum(case when a.fecha >= v_desde then d.debe end), 0) dis
                    from ctb_cuentas c
                    join ctb_asiento_det d on d.id_cuenta_ctb = c.id_cuenta_ctb
                    join ctb_asientos a on a.id_asiento = d.id_asiento
                   where c.id_empresa = p_empresa and c.codigo like '3.%'
                     and a.estado in ('CONFIRMADO', 'REVERSADO') and a.fecha <= v_hasta
                   group by c.codigo, c.nombre
                   order by c.codigo) loop
            v_hay := true;
            v_ts := v_ts + c.ini;
            v_td := v_td + c.aum;
            v_th := v_th + c.dis;
            w('<tr>' || t(c.codigo) || t(c.nombre) || n(c.ini) || n(c.aum) || n(c.dis) || n(c.ini + c.aum - c.dis) || '</tr>');
        end loop;
        -- resultado aun no llevado al patrimonio (antes y durante el periodo)
        select nvl(sum(case when a.fecha < v_desde then d.haber - d.debe end), 0),
               nvl(sum(case when a.fecha >= v_desde then d.haber - d.debe end), 0)
          into v_saldo, v_cxx
          from ctb_asiento_det d join ctb_asientos a on a.id_asiento = d.id_asiento
          join ctb_cuentas c on c.id_cuenta_ctb = d.id_cuenta_ctb
         where a.id_empresa = p_empresa and a.estado in ('CONFIRMADO', 'REVERSADO') and a.fecha <= v_hasta
           and substr(c.codigo, 1, 1) in ('4', '5', '6', '7');
        w('<tr><td></td>' || '<td>Resultado del ejercicio a&uacute;n no cerrado</td>' || n(v_saldo) || n(greatest(v_cxx, 0)) || n(greatest(-v_cxx, 0))
          || n(v_saldo + v_cxx) || '</tr>');
        w('<tr class="spx-tot"><td colspan="2"><b>Total patrimonio</b></td>' || n(v_ts + v_saldo, true)
          || n(v_td + greatest(v_cxx, 0), true) || n(v_th + greatest(-v_cxx, 0), true)
          || n(v_ts + v_td - v_th + v_saldo + v_cxx, true) || '</tr>');

    elsif v_lib = 'INVENTARIOS' then
        w('<tr class="spx-th"><th>C&oacute;digo</th><th>Art&iacute;culo</th><th class="num">Exist. inicial</th><th class="num">Entradas</th>'
          || '<th class="num">Salidas</th><th class="num">Exist. final</th><th class="num">Valor inicial (Bs)</th>'
          || '<th class="num">Valor final (Bs)</th></tr>');
        for k in (select p.codigo, p.nombre,
                         nvl(sum(case when m.fecha_movimiento < v_desde then pkg_inventario.fn_signo(m.tipo_movimiento) * m.cantidad end), 0) qi,
                         nvl(sum(case when m.fecha_movimiento >= v_desde and pkg_inventario.fn_signo(m.tipo_movimiento) > 0 then m.cantidad end), 0) qe,
                         nvl(sum(case when m.fecha_movimiento >= v_desde and pkg_inventario.fn_signo(m.tipo_movimiento) < 0 then m.cantidad end), 0) qs,
                         nvl(sum(case when m.fecha_movimiento < v_desde then pkg_inventario.fn_signo(m.tipo_movimiento) * m.costo_total_bs end), 0) vi,
                         nvl(sum(pkg_inventario.fn_signo(m.tipo_movimiento) * m.costo_total_bs), 0) vf
                    from kardex_mov m join producto_servicio p on p.id_producto_servicio = m.id_producto_servicio
                   where m.id_empresa = p_empresa and m.fecha_movimiento < v_hasta + 1
                   group by p.codigo, p.nombre
                   order by p.nombre) loop
            v_hay := true;
            v_ts := v_ts + k.vi;
            v_td := v_td + k.vf;
            w('<tr>' || t(k.codigo) || t(k.nombre) || n(k.qi) || n(k.qe) || n(k.qs) || n(k.qi + k.qe - k.qs)
              || n(k.vi) || n(k.vf) || '</tr>');
        end loop;
        if not v_hay then
            w('<tr><td colspan="8">No hay movimientos de inventario hasta la fecha de corte.</td></tr>');
        end if;
        w('<tr class="spx-tot"><td colspan="6"><b>Total del inventario</b></td>' || n(v_ts, true) || n(v_td, true) || '</tr>');
        begin
            select nvl(sum(d.debe - d.haber), 0) into v_saldo
              from ctb_asiento_det d join ctb_asientos a on a.id_asiento = d.id_asiento
             where a.id_empresa = p_empresa and a.estado in ('CONFIRMADO', 'REVERSADO') and a.fecha <= v_hasta
               and d.id_cuenta_ctb = pkg_contabilidad.fn_cuenta(p_empresa, 'INVENTARIO');
            w('<tr><td colspan="7">Inventario seg&uacute;n la contabilidad (cuenta de inventario)'
              || case when abs(v_saldo - v_td) < 0.05 then ': coincide con el kardex'
                      else ': difiere del kardex (contabiliza los meses pendientes)' end || '</td>' || n(v_saldo, true) || '</tr>');
        exception
            when others then
                null;   -- sin plan de cuentas: solo el kardex
        end;

    elsif v_lib = 'MAYOR' then
        w('<tr class="spx-th"><th>Fecha</th><th>Asiento</th><th>Concepto</th><th>Descripci&oacute;n</th>'
          || '<th class="num">Debe</th><th class="num">Haber</th><th class="num">Saldo</th></tr>');
        for c in (select c.id_cuenta_ctb, c.codigo, c.nombre,
                         nvl(sum(case when a.fecha < v_desde then d.debe - d.haber end), 0) ini,
                         count(case when a.fecha >= v_desde then 1 end) movs
                    from ctb_cuentas c
                    join ctb_asiento_det d on d.id_cuenta_ctb = c.id_cuenta_ctb
                    join ctb_asientos a on a.id_asiento = d.id_asiento
                   where c.id_empresa = p_empresa
                     and (p_id_cuenta is null or c.id_cuenta_ctb = p_id_cuenta)
                     and a.estado in ('CONFIRMADO', 'REVERSADO') and a.fecha <= v_hasta
                   group by c.id_cuenta_ctb, c.codigo, c.nombre
                  having count(case when a.fecha >= v_desde then 1 end) > 0
                      or nvl(sum(case when a.fecha < v_desde then d.debe - d.haber end), 0) <> 0
                   order by c.codigo) loop
            v_hay := true;
            v_saldo := c.ini;
            w('<tr class="spx-grp"><td colspan="7"' || case when v_xls then ' style="font-weight:bold"' end || '>'
              || sys.htf.escape_sc(c.codigo || '  ' || c.nombre) || '</td></tr>');
            w('<tr><td colspan="4">Saldo inicial</td><td></td><td></td>' || n(c.ini) || '</tr>');
            v_td := 0;
            v_th := 0;
            for l in (select a.fecha, a.anio, a.mes, a.numero, a.concepto, d.descripcion, d.debe, d.haber
                        from ctb_asiento_det d join ctb_asientos a on a.id_asiento = d.id_asiento
                       where d.id_cuenta_ctb = c.id_cuenta_ctb and a.estado in ('CONFIRMADO', 'REVERSADO')
                         and a.fecha between v_desde and v_hasta
                       order by a.fecha, a.anio, a.mes, a.numero, d.linea) loop
                v_saldo := v_saldo + l.debe - l.haber;
                v_td := v_td + l.debe;
                v_th := v_th + l.haber;
                w('<tr>' || t(to_char(l.fecha, 'DD/MM/YYYY')) || t(asiento_ref(l.mes, l.anio, l.numero))
                  || t(l.concepto) || t(l.descripcion) || n(l.debe) || n(l.haber) || n(v_saldo) || '</tr>');
            end loop;
            w('<tr class="spx-tot"><td colspan="4"><b>Total ' || sys.htf.escape_sc(c.codigo) || '</b></td>'
              || n(v_td, true) || n(v_th, true) || n(v_saldo, true) || '</tr>');
        end loop;
        if not v_hay then
            w('<tr><td colspan="7">La cuenta no tiene movimientos ni saldo en el periodo.</td></tr>');
        end if;

    else
        w('<tr class="spx-th"><th>C&oacute;digo</th><th>Descripci&oacute;n</th><th class="num">Saldo inicial</th>'
          || '<th class="num">Debe</th><th class="num">Haber</th><th class="num">Saldo actual</th><th></th></tr>');
        for b in (with mov as (
                      select d.id_cuenta_ctb,
                             sum(case when a.fecha < v_desde then d.debe - d.haber else 0 end) ini,
                             sum(case when a.fecha >= v_desde then d.debe else 0 end) debe,
                             sum(case when a.fecha >= v_desde then d.haber else 0 end) haber
                        from ctb_asiento_det d join ctb_asientos a on a.id_asiento = d.id_asiento
                       where a.id_empresa = p_empresa and a.estado in ('CONFIRMADO', 'REVERSADO')
                         and a.fecha <= v_hasta
                       group by d.id_cuenta_ctb),
                  hoja as (
                      select c.codigo, m.ini, m.debe, m.haber
                        from ctb_cuentas c join mov m on m.id_cuenta_ctb = c.id_cuenta_ctb)
                  select c.codigo, c.nombre, c.nivel, c.acepta_movimiento,
                         sum(h.ini) ini, sum(h.debe) debe, sum(h.haber) haber
                    from ctb_cuentas c
                    join hoja h on (h.codigo = c.codigo
                                    or (c.acepta_movimiento = 'N' and substr(h.codigo, 1, length(c.codigo)) = c.codigo))
                   where c.id_empresa = p_empresa
                   group by c.codigo, c.nombre, c.nivel, c.acepta_movimiento
                  having sum(h.ini) <> 0 or sum(h.debe) <> 0 or sum(h.haber) <> 0
                   order by c.codigo) loop
            v_hay := true;
            w('<tr' || case when b.acepta_movimiento = 'N' then ' class="spx-grp"' end || '>'
              || t(b.codigo) || t(b.nombre, 'padding-left:' || ((b.nivel - 1) * 14 + 6) || 'px'
                                   || case when b.acepta_movimiento = 'N' then ';font-weight:bold' end)
              || n(b.ini, b.acepta_movimiento = 'N') || n(b.debe, b.acepta_movimiento = 'N')
              || n(b.haber, b.acepta_movimiento = 'N') || n(b.ini + b.debe - b.haber, b.acepta_movimiento = 'N')
              || '<td></td></tr>');
            if b.acepta_movimiento = 'S' then
                v_ts := v_ts + b.ini;
                v_td := v_td + b.debe;
                v_th := v_th + b.haber;
            end if;
        end loop;
        if not v_hay then
            w('<tr><td colspan="7">No hay movimientos hasta la fecha de corte.</td></tr>');
        end if;
        w('<tr class="spx-tot"><td colspan="2"><b>Total balance de comprobaci&oacute;n</b></td>'
          || n(v_ts, true) || n(v_td, true) || n(v_th, true) || n(v_ts + v_td - v_th, true)
          || '<td>' || case when v_td = v_th then 'Cuadra' else 'NO CUADRA' end || '</td></tr>');
    end if;

    w('</table>');
    if v_xls then
        w('<p>Saldos = debe - haber (los acreedores salen negativos). Moneda funcional de la empresa.</p></body></html>');
    end if;
    return v_html;
exception
    when no_data_found then
        return null;
end fn_ctb_libro;
/

begin
    dbms_utility.compile_schema('WKSP_SYPEXWS', false);
end;
/

declare
    v_inv number; v_c number; v_m number; v_s number;
begin
    select count(*) into v_inv from all_objects where owner = 'WKSP_SYPEXWS' and status = 'INVALID';
    select count(*), count(codigo_agrupador_sat) into v_c, v_s from ctb_plantilla_cuentas where cod_pais = 'MX';
    select count(*) into v_m from ctb_plantilla_mapeo where cod_pais = 'MX';
    if v_inv > 0 or v_c < 80 or v_s < 80 or v_m < 27 then
        raise_application_error(-20100, 'VALIDACION FALLIDA: invalidos=' || v_inv || ' cuentas=' || v_c
            || ' con_agrupador=' || v_s || ' conceptos=' || v_m);
    end if;
    raise_application_error(-20100, 'RESULTADO: FALLAS=0 (MX: ' || v_c || ' cuentas con agrupador, ' || v_m || ' conceptos)');
end;
/
