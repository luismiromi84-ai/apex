-- =============================================================================
-- 20261125_contabilidad_verificacion.sql
--
-- Contabilidad, fase 2 (pkg_contabilidad + triggers):
--   K1 instalar el plan copia las 216 cuentas, los 28 conceptos y crea la subcuenta de cada
--      caja o banco (caja -> 1.1.1.10.010, banco en divisa -> 1.1.1.30.010); repetirlo no agrega nada
--   K2 una cuenta de grupo no acepta movimiento (-20183)
--   K3 un asiento descuadrado no se confirma (-20185)
--   K4 el asiento cuadrado se confirma con el numero 1 del mes y sus totales
--   K5 confirmado = inmutable: ni sus lineas (-20182) ni borrarlo (-20182)
--   K6 el reverso invierte las lineas, se confirma con el numero 2 y deja el original REVERSADO;
--      no se reversa dos veces (-20186)
--   K7 no se cierra un mes con borradores (-20187); cerrado, no admite asientos (-20184) y lo
--      que llega tarde va al primer dia del mes siguiente (regla del contador)
--   K8 el reverso de un asiento de un mes cerrado cae en el mes siguiente
--   K9 no se reabre un mes si hay uno posterior cerrado (-20189); en orden, si
--   K10 un usuario sin acceso a la empresa no instala ni asienta (-20190)
--   K11-K14 libros (balance, mayor, diario) y mantenimiento de cuentas y conceptos
--   K15-K18 estado de resultados, balance general, cierre anual y pago al SENIAT
--   K19 liquidacion del IVA (por pagar, excedente, retenciones de clientes); una por mes (-20194)
--   K20 pago al SENIAT del IVA por pagar
--   K21 flujo de efectivo exacto, resumen de impuestos, retenciones, patrimonio e inventarios
--
-- Empresa temporal 900280 (enero-marzo 2026) y usuario temporal; se purga al final.
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261125_contabilidad_verificacion.sql
-- FALLAS=0 = EXITO (el runner sale con codigo 1 aunque sea verde: se lee el mensaje).
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

begin
    begin execute immediate 'drop table tmp_ctb_fallas purge'; exception when others then null; end;
end;
/

create table tmp_ctb_fallas (caso varchar2(400))
/

begin
    begin pkg_contabilidad.prc_purgar_prueba(900280); commit; exception when others then null; end;
    for r in (select usuario_id from usuario where upper(username) in ('DIAG.CTB', 'DIAG.CTBX')) loop
        delete from usuario_empresa where usuario_id = r.usuario_id; commit;
        delete from usuario where usuario_id = r.usuario_id; commit;
    end loop;
    begin delete from cuentas_fondos where id_empresa = 900280; commit; exception when others then null; end;
    begin delete from usuario_empresa where id_empresa = 900280; commit; exception when others then null; end;
    begin delete from empresas where id_empresa = 900280; commit; exception when others then null; end;
end;
/

insert into empresas (id_empresa, nombre_empresa, cod_pais, tipo_ident_fiscal, rfc, estado)
values (900280, 'DIAG CONTABILIDAD', 'VE', 'RIF', 'J-90028000-1', 'ACTIVO')
/

commit
/

insert into usuario (username, email, password_hash, estado, id_empresa, rol_id, debe_cambiar_clave, reintentos_fallidos)
values ('diag.ctb', 'diag.ctb@synpex.local', 'x', 'ACTIVO', 900280,
        (select id_rol from syn_roles where codigo_rol = 'ADMIN'), 'N', 0)
/

-- sin acceso a 900280 (su empresa es la 1)
insert into usuario (username, email, password_hash, estado, id_empresa, rol_id, debe_cambiar_clave, reintentos_fallidos)
values ('diag.ctbx', 'diag.ctbx@synpex.local', 'x', 'ACTIVO', 1,
        (select id_rol from syn_roles where codigo_rol = 'CONTABILIDAD'), 'N', 0)
/

insert into cuentas_fondos (id_empresa, nombre, tipo, cod_moneda, es_principal, estado, creado_por)
values (900280, 'Caja principal', 'CAJA', 'VES', 'S', 'ACTIVO', 'DIAG')
/

insert into cuentas_fondos (id_empresa, nombre, tipo, banco, cod_moneda, es_principal, estado, creado_por)
values (900280, 'Banco DIAG USD', 'BANCO', 'Banco DIAG', 'USD', 'N', 'ACTIVO', 'DIAG')
/

commit
/

declare
    U     constant varchar2(20) := 'diag.ctb';
    E     constant number := 900280;
    v_n   number;
    v_n2  number;
    v_a   number;
    v_b   number;
    v_r   number;
    v_r2  number;
    v_txt varchar2(400);
    v_f   date;
    v_caja  number;
    v_cxc   number;
    v_vent  number;
    v_iva   number;
    v_grupo number;

    procedure falla(p varchar2) is
    begin
        insert into tmp_ctb_fallas values (substr(p, 1, 400));
        commit;
    end falla;

    function cta(p_cod varchar2) return number is
        v number;
    begin
        select id_cuenta_ctb into v from ctb_cuentas where id_empresa = E and codigo = p_cod;
        return v;
    end cta;

    function lineas(p_d1 number, p_c1 number, p_d2 number, p_c2 number, p_c3 number, p_h3 number) return clob is
    begin
        return '[{"id":' || p_c1 || ',"debe":' || p_d1 || ',"haber":0,"desc":"cliente"},'
            || '{"id":' || p_c2 || ',"debe":0,"haber":' || p_d2 || ',"desc":"venta"},'
            || '{"id":' || p_c3 || ',"debe":0,"haber":' || p_h3 || ',"desc":"iva"}]';
    end lineas;

    -- ejecuta un bloque y comprueba el codigo de error esperado
    procedure espera(p_caso varchar2, p_sql varchar2, p_code number) is
    begin
        execute immediate p_sql;
        rollback;
        falla(p_caso || ': no dio error (esperado ' || p_code || ')');
    exception
        when others then
            rollback;
            if sqlcode <> p_code then
                falla(p_caso || ': dio ' || sqlerrm);
            end if;
    end espera;
begin
    -- K1
    v_n := pkg_contabilidad.fn_instalar_plan(E, U);
    commit;
    select count(*) into v_a from ctb_cuentas where id_empresa = E;
    select count(*) into v_b from ctb_mapeo where id_empresa = E;
    select count(*) into v_n2 from cuentas_fondos f join ctb_cuentas c on c.id_cuenta_ctb = f.id_cuenta_ctb
     where f.id_empresa = E and ((f.tipo = 'CAJA' and c.codigo = '1.1.1.10.010')
                              or (f.tipo = 'BANCO' and c.codigo = '1.1.1.30.010'));
    if v_a <> 218 or v_b <> 29 or v_n2 <> 2 or v_n <> 218 then
        falla('K1 instalar plan: cuentas=' || v_a || ' conceptos=' || v_b || ' fondos=' || v_n2 || ' devuelto=' || v_n);
    end if;
    if pkg_contabilidad.fn_instalar_plan(E, U) <> 0 then
        falla('K1 instalar otra vez agrego cuentas');
    end if;
    commit;

    v_cxc  := pkg_contabilidad.fn_cuenta(E, 'CXC');
    v_vent := pkg_contabilidad.fn_cuenta(E, 'VENTAS');
    v_iva  := pkg_contabilidad.fn_cuenta(E, 'IVA_DEBITO');
    v_grupo := cta('1.1.');
    if v_cxc <> cta('1.1.2.10.010') or v_iva <> cta('2.1.6.10.010') then
        falla('K1 mapeo CXC / IVA_DEBITO no apunta a la cuenta del contador');
    end if;

    -- K2
    espera('K2 cuenta de grupo', 'declare v number; begin pkg_contabilidad.prc_guardar_asiento(v, 900280, date ''2026-01-10'', ''x'', ''[{"id":'
           || v_grupo || ',"debe":10,"haber":0},{"id":' || v_vent || ',"debe":0,"haber":10}]'', ''diag.ctb''); end;', -20183);

    -- K3
    v_a := null;
    pkg_contabilidad.prc_guardar_asiento(v_a, E, date '2026-01-10', 'Factura prueba', lineas(116, v_cxc, 100, v_vent, v_iva, 15), U);
    commit;
    espera('K3 descuadrado', 'begin pkg_contabilidad.prc_confirmar(' || v_a || ', ''diag.ctb''); end;', -20185);

    -- K4
    pkg_contabilidad.prc_guardar_asiento(v_a, E, date '2026-01-10', 'Factura prueba', lineas(116, v_cxc, 100, v_vent, v_iva, 16), U);
    pkg_contabilidad.prc_confirmar(v_a, U);
    commit;
    select count(*) into v_n from ctb_asientos
     where id_asiento = v_a and estado = 'CONFIRMADO' and numero = 1 and anio = 2026 and mes = 1
       and total_debe = 116 and total_haber = 116;
    if v_n <> 1 then
        falla('K4 el asiento cuadrado no quedo CONFIRMADO con el numero 1 y totales 116');
    end if;

    -- K5
    espera('K5 editar linea confirmada', 'update ctb_asiento_det set debe = 1 where id_asiento = ' || v_a || ' and linea = 1', -20182);
    espera('K5 borrar asiento confirmado', 'begin pkg_contabilidad.prc_eliminar(' || v_a || ', ''diag.ctb''); end;', -20182);

    -- K6
    v_r := pkg_contabilidad.fn_reversar(v_a, 'prueba de reverso', U);
    commit;
    select count(*) into v_n from ctb_asientos o join ctb_asientos r on r.id_asiento = o.id_asiento_reverso
     where o.id_asiento = v_a and o.estado = 'REVERSADO' and r.id_asiento = v_r
       and r.estado = 'CONFIRMADO' and r.numero = 2 and r.origen = 'REVERSO' and r.id_asiento_original = v_a;
    select count(*) into v_n2 from ctb_asiento_det o join ctb_asiento_det r
        on r.id_asiento = v_r and r.linea = o.linea and r.debe = o.haber and r.haber = o.debe
     where o.id_asiento = v_a;
    if v_n <> 1 or v_n2 <> 3 then
        falla('K6 reverso: enlace=' || v_n || ' lineas invertidas=' || v_n2);
    end if;
    espera('K6 reversar dos veces', 'declare v number; begin v := pkg_contabilidad.fn_reversar(' || v_a || ', ''otra'', ''diag.ctb''); end;', -20186);

    -- K7
    v_b := null;
    pkg_contabilidad.prc_guardar_asiento(v_b, E, date '2026-01-20', 'Borrador pendiente', lineas(116, v_cxc, 100, v_vent, v_iva, 16), U);
    commit;
    espera('K7 cerrar con borrador', 'begin pkg_contabilidad.prc_cerrar_periodo(900280, 2026, 1, ''diag.ctb''); end;', -20187);
    pkg_contabilidad.prc_confirmar(v_b, U);
    pkg_contabilidad.prc_cerrar_periodo(E, 2026, 1, U);
    commit;
    espera('K7 asiento en mes cerrado', 'declare v number; begin pkg_contabilidad.prc_guardar_asiento(v, 900280, date ''2026-01-25'', ''x'', ''[]'', ''diag.ctb''); end;', -20184);
    v_f := pkg_contabilidad.fn_fecha_contable(E, date '2026-01-25');
    if v_f <> date '2026-02-01' or pkg_contabilidad.fn_periodo_abierto(E, date '2026-01-05') <> 'N' then
        falla('K7 fecha contable de un mes cerrado = ' || to_char(v_f, 'DD/MM/YYYY'));
    end if;

    -- K8
    v_r2 := pkg_contabilidad.fn_reversar(v_b, 'anulacion tardia', U);
    commit;
    select count(*) into v_n from ctb_asientos
     where id_asiento = v_r2 and fecha = date '2026-02-01' and anio = 2026 and mes = 2 and numero = 1;
    if v_n <> 1 then
        falla('K8 el reverso de un asiento de enero cerrado no cayo el 01/02/2026 con el numero 1 de febrero');
    end if;

    -- K9
    pkg_contabilidad.prc_cerrar_periodo(E, 2026, 2, U);
    commit;
    espera('K9 reabrir enero con febrero cerrado', 'begin pkg_contabilidad.prc_reabrir_periodo(900280, 2026, 1, ''diag.ctb''); end;', -20189);
    pkg_contabilidad.prc_reabrir_periodo(E, 2026, 2, U);
    pkg_contabilidad.prc_reabrir_periodo(E, 2026, 1, U);
    commit;
    if pkg_contabilidad.fn_periodo_abierto(E, date '2026-01-05') <> 'S' then
        falla('K9 enero no quedo abierto al reabrir en orden');
    end if;

    -- K10
    espera('K10 instalar sin acceso', 'declare v number; begin v := pkg_contabilidad.fn_instalar_plan(900280, ''diag.ctbx''); end;', -20190);
    espera('K10 asentar sin acceso', 'declare v number; begin pkg_contabilidad.prc_guardar_asiento(v, 900280, date ''2026-03-01'', ''x'', ''[]'', ''diag.ctbx''); end;', -20190);

    -- K11 balance de comprobacion: de enero a marzo cuadra; desde febrero, cuentas por cobrar
    -- arranca con 116 (el asiento de enero que se reverso en febrero) y termina en 0
    declare
        v_x clob;
        F constant varchar2(60) := '<td style="mso-number-format:''#\,##0\.00''">';
    begin
        v_x := fn_ctb_libro('BALANCE', date '2026-01-01', date '2026-03-31', null, E, 'XLS');
        if instr(v_x, 'NO CUADRA') > 0 or instr(v_x, 'Cuadra') = 0 or instr(v_x, '1.1.2.10.010') = 0 then
            falla('K11 el balance de enero a marzo no cuadra o no trae cuentas por cobrar');
        end if;
        v_x := fn_ctb_libro('BALANCE', date '2026-02-01', date '2026-03-31', null, E, 'XLS');
        if instr(v_x, F || '116</td>' || F || '0</td>' || F || '116</td>' || F || '0</td>') = 0 then
            falla('K11 cuentas por cobrar desde febrero: se esperaba inicial 116, debe 0, haber 116, actual 0');
        end if;
        -- K12 mayor analitico de cuentas por cobrar en enero: saldo inicial, movimientos y total
        v_x := fn_ctb_libro('MAYOR', date '2026-01-01', date '2026-01-31', v_cxc, E, 'XLS');
        if instr(v_x, 'Saldo inicial') = 0 or instr(v_x, 'Total 1.1.2.10.010') = 0 or instr(v_x, '01/2026-0002') = 0 then
            falla('K12 el mayor analitico no trae saldo inicial, el asiento 01/2026-0002 y el total');
        end if;
        -- K13 libro diario de enero: los asientos, el reversado marcado y los totales
        v_x := fn_ctb_libro('DIARIO', date '2026-01-01', date '2026-01-31', null, E, 'HTML');
        if instr(v_x, '(reversado)') = 0 or instr(v_x, 'TOTALES') = 0 or instr(v_x, 'Factura prueba') = 0 then
            falla('K13 el libro diario no trae los asientos de enero con sus totales');
        end if;
    end;

    -- K14 mantenimiento: cuenta nueva bajo su grupo, grupo inexistente, asignar concepto
    pkg_contabilidad.prc_guardar_cuenta(E, '6.1.1.40.950', 'gastos de prueba', 'ACTIVO', U);
    commit;
    v_grupo := cta('6.1.1.40.');
    select count(*) into v_n from ctb_cuentas
     where id_empresa = E and codigo = '6.1.1.40.950' and nombre = 'GASTOS DE PRUEBA'
       and tipo = 'GASTO' and naturaleza = 'D' and nivel = 5 and acepta_movimiento = 'S'
       and id_padre = v_grupo;
    if v_n <> 1 then
        falla('K14 la cuenta nueva no hereda tipo, naturaleza y nivel de su grupo');
    end if;
    espera('K14 grupo inexistente', 'begin pkg_contabilidad.prc_guardar_cuenta(900280, ''6.9.9.10.010'', ''x'', ''ACTIVO'', ''diag.ctb''); end;', -20191);
    pkg_contabilidad.prc_asignar_concepto(E, 'GASTO_GENERAL', cta('6.1.1.40.950'), U);
    commit;
    if pkg_contabilidad.fn_cuenta(E, 'GASTO_GENERAL') <> cta('6.1.1.40.950') then
        falla('K14 el concepto GASTO_GENERAL no quedo en la cuenta nueva');
    end if;
    espera('K14 grupo de caja con una cuenta de movimiento', 'begin pkg_contabilidad.prc_asignar_concepto(900280, ''GRUPO_CAJA'', '
           || cta('6.1.1.40.950') || ', ''diag.ctb''); end;', -20183);

    -- fase 5: en marzo, una venta de 100 + 16 de IVA, un gasto de 50 pagado en caja y una retencion
    -- de IVA de 30 practicada a un proveedor
    declare
        v_x    clob;
        v_caja number;
        v_cajf number;
        v_id   number;
        F constant varchar2(60) := '<td style="mso-number-format:''#\,##0\.00'';font-weight:bold">';
    begin
        select id_cuenta, id_cuenta_ctb into v_cajf, v_caja from cuentas_fondos where id_empresa = E and tipo = 'CAJA';
        v_id := null;
        pkg_contabilidad.prc_guardar_asiento(v_id, E, date '2026-03-05', 'Venta de marzo', lineas(116, v_cxc, 100, v_vent, v_iva, 16), U);
        pkg_contabilidad.prc_confirmar(v_id, U);
        v_id := null;
        pkg_contabilidad.prc_guardar_asiento(v_id, E, date '2026-03-06', 'Gasto de marzo',
            '[{"id":' || cta('6.1.1.40.950') || ',"debe":50,"haber":0},{"id":' || v_caja || ',"debe":0,"haber":50}]', U);
        pkg_contabilidad.prc_confirmar(v_id, U);
        v_id := null;
        pkg_contabilidad.prc_guardar_asiento(v_id, E, date '2026-03-07', 'Retencion de IVA practicada',
            '[{"id":' || pkg_contabilidad.fn_cuenta(E, 'CXP') || ',"debe":30,"haber":0},{"id":'
            || pkg_contabilidad.fn_cuenta(E, 'RET_IVA_PROVEEDORES') || ',"debe":0,"haber":30}]', U);
        pkg_contabilidad.prc_confirmar(v_id, U);
        commit;

        -- K15 estado de resultados del ano: utilidad 100 - 50 = 50
        v_x := fn_ctb_libro('RESULTADOS', date '2026-01-01', date '2026-12-31', null, E, 'XLS');
        if instr(v_x, 'UTILIDAD') = 0 or instr(v_x, F || '50</td></tr>') = 0 then
            falla('K15 el estado de resultados no da utilidad 50');
        end if;
        -- K16 balance general al 31/12: cuadra con el resultado aun no cerrado
        v_x := fn_ctb_libro('SITUACION', date '2026-01-01', date '2026-12-31', null, E, 'XLS');
        if instr(v_x, 'Cuadra: activo') = 0 then
            falla('K16 el balance general no cuadra antes del cierre');
        end if;
        -- K17 cierre anual: el resultado pasa al patrimonio, el balance sigue cuadrando y no se repite
        pkg_contabilidad.prc_cierre_anual(E, 2026, U, v_id);
        commit;
        select count(*) into v_n from ctb_asientos
         where id_asiento = v_id and origen = 'CIERRE' and estado = 'CONFIRMADO' and fecha = date '2026-12-31';
        v_x := fn_ctb_libro('SITUACION', date '2026-01-01', date '2026-12-31', null, E, 'XLS');
        if v_n <> 1 or instr(v_x, 'Cuadra: activo') = 0
           or pkg_contabilidad.fn_saldo_concepto(E, 'RESULTADO_EJERCICIO') <> 50 then
            falla('K17 cierre anual: asiento=' || v_n || ', resultado del ejercicio='
                  || pkg_contabilidad.fn_saldo_concepto(E, 'RESULTADO_EJERCICIO'));
        end if;
        v_x := fn_ctb_libro('RESULTADOS', date '2026-01-01', date '2026-12-31', null, E, 'XLS');
        if instr(v_x, F || '50</td></tr>') = 0 then
            falla('K17 tras el cierre, el estado de resultados del ano deberia seguir en 50');
        end if;
        espera('K17 cerrar dos veces', 'declare v number; begin pkg_contabilidad.prc_cierre_anual(900280, 2026, ''diag.ctb'', v); end;', -20192);
        -- K18 pago al SENIAT: de 30 retenidos se enteran 20; quedan 10 y no se puede pagar 15
        pkg_contabilidad.prc_pagar_seniat(E, 'RET_IVA_PROVEEDORES', date '2026-03-20', v_cajf, 20, 'REF-1', U, v_id);
        commit;
        if pkg_contabilidad.fn_saldo_concepto(E, 'RET_IVA_PROVEEDORES') <> 10 then
            falla('K18 tras enterar 20 de 30 deberian quedar 10, quedan '
                  || pkg_contabilidad.fn_saldo_concepto(E, 'RET_IVA_PROVEEDORES'));
        end if;
        espera('K18 enterar mas de lo pendiente', 'declare v number; begin pkg_contabilidad.prc_pagar_seniat(900280, '
               || '''RET_IVA_PROVEEDORES'', date ''2026-03-21'', ' || v_cajf || ', 15, ''X'', ''diag.ctb'', v); end;', -20193);

        -- K19 liquidacion del IVA en tres meses
        --   marzo: debito 16 -> 16 por pagar
        pkg_contabilidad.prc_liquidar_iva(E, 2026, 3, U, v_id);
        commit;
        if pkg_contabilidad.fn_saldo_concepto(E, 'IVA_POR_PAGAR') <> 16 or pkg_contabilidad.fn_saldo_concepto(E, 'IVA_DEBITO', date '2026-03-31') <> 0 then
            falla('K19 marzo: por pagar=' || pkg_contabilidad.fn_saldo_concepto(E, 'IVA_POR_PAGAR'));
        end if;
        espera('K19 liquidar marzo dos veces', 'declare v number; begin pkg_contabilidad.prc_liquidar_iva(900280, 2026, 3, ''diag.ctb'', v); end;', -20194);
        --   abril: solo credito 40 -> 40 de excedente
        v_id := null;
        pkg_contabilidad.prc_guardar_asiento(v_id, E, date '2026-04-10', 'Compra de abril',
            '[{"id":' || pkg_contabilidad.fn_cuenta(E, 'IVA_CREDITO') || ',"debe":40,"haber":0},{"id":'
            || pkg_contabilidad.fn_cuenta(E, 'CXP') || ',"debe":0,"haber":40}]', U);
        pkg_contabilidad.prc_confirmar(v_id, U);
        pkg_contabilidad.prc_liquidar_iva(E, 2026, 4, U, v_id);
        commit;
        if pkg_contabilidad.fn_saldo_concepto(E, 'IVA_EXCEDENTE') <> -40 or pkg_contabilidad.fn_saldo_concepto(E, 'IVA_POR_PAGAR') <> 16 then
            falla('K19 abril: excedente=' || -pkg_contabilidad.fn_saldo_concepto(E, 'IVA_EXCEDENTE'));
        end if;
        --   mayo: debito 50 - excedente 40 = 10; la retencion del cliente (5) lo deja en 5 por pagar
        v_id := null;
        pkg_contabilidad.prc_guardar_asiento(v_id, E, date '2026-05-10', 'Venta de mayo',
            '[{"id":' || v_cxc || ',"debe":50,"haber":0},{"id":' || v_iva || ',"debe":0,"haber":50}]', U);
        pkg_contabilidad.prc_confirmar(v_id, U);
        v_id := null;
        pkg_contabilidad.prc_guardar_asiento(v_id, E, date '2026-05-12', 'Retencion del cliente',
            '[{"id":' || pkg_contabilidad.fn_cuenta(E, 'RET_IVA_CLIENTES') || ',"debe":5,"haber":0},{"id":' || v_cxc || ',"debe":0,"haber":5}]', U);
        pkg_contabilidad.prc_confirmar(v_id, U);
        pkg_contabilidad.prc_liquidar_iva(E, 2026, 5, U, v_id);
        commit;
        if pkg_contabilidad.fn_saldo_concepto(E, 'IVA_POR_PAGAR') <> 21 or pkg_contabilidad.fn_saldo_concepto(E, 'IVA_EXCEDENTE') <> 0
           or pkg_contabilidad.fn_saldo_concepto(E, 'RET_IVA_CLIENTES') <> 0 then
            falla('K19 mayo: por pagar=' || pkg_contabilidad.fn_saldo_concepto(E, 'IVA_POR_PAGAR')
                  || ' excedente=' || pkg_contabilidad.fn_saldo_concepto(E, 'IVA_EXCEDENTE'));
        end if;
        -- K20 pago al SENIAT del IVA por pagar
        pkg_contabilidad.prc_pagar_seniat(E, 'IVA_POR_PAGAR', date '2026-06-05', v_cajf, 21, 'PLANILLA-5', U, v_id);
        commit;
        if pkg_contabilidad.fn_saldo_concepto(E, 'IVA_POR_PAGAR') <> 0 then
            falla('K20 tras pagar el IVA queda ' || pkg_contabilidad.fn_saldo_concepto(E, 'IVA_POR_PAGAR'));
        end if;
        -- K21 libros nuevos (la empresa no tiene documentos: se mira la estructura y el flujo exacto)
        v_x := fn_ctb_libro('FLUJO', date '2026-01-01', date '2026-12-31', null, E, 'XLS');
        if instr(v_x, 'Pagos de impuestos (SENIAT)') = 0 or instr(v_x, F || '-91</td></tr>') = 0 then
            falla('K21 flujo de efectivo: se esperaba efectivo final -91 (gasto 50 + SENIAT 20 + 21)');
        end if;
        v_x := fn_ctb_libro('IMPUESTOS', date '2026-01-01', date '2026-12-31', null, E, 'XLS');
        if instr(v_x, 'Cuota del per') = 0 or instr(v_x, 'IGTF percibido') = 0 then
            falla('K21 el resumen de impuestos no trae sus secciones');
        end if;
        v_x := fn_ctb_libro('RETENCIONES', date '2026-01-01', date '2026-12-31', null, E, 'XLS');
        if instr(v_x, 'Total recibidas') = 0 or instr(v_x, 'Total practicadas de ISLR') = 0 then
            falla('K21 el libro de retenciones no trae sus totales');
        end if;
        v_x := fn_ctb_libro('PATRIMONIO', date '2026-01-01', date '2026-12-31', null, E, 'XLS');
        if instr(v_x, 'Total patrimonio') = 0 or instr(v_x, '3.2.1.10.020') = 0 then
            falla('K21 cambios en el patrimonio: falta el resultado del ejercicio cerrado');
        end if;
        v_x := fn_ctb_libro('INVENTARIOS', date '2026-01-01', date '2026-12-31', null, E, 'HTML');
        if instr(v_x, 'No hay movimientos de inventario') = 0 then
            falla('K21 libro de inventarios sin kardex deberia decirlo');
        end if;
    end;
exception
    when others then
        v_txt := substr(sqlerrm, 1, 300);
        rollback;
        falla('error inesperado: ' || v_txt || ' ' || substr(dbms_utility.format_error_backtrace, 1, 90));
end;
/

begin
    pkg_contabilidad.prc_purgar_prueba(900280);
    commit;
    delete from cuentas_fondos where id_empresa = 900280;
    commit;
    for r in (select usuario_id from usuario where upper(username) in ('DIAG.CTB', 'DIAG.CTBX')) loop
        delete from usuario_empresa where usuario_id = r.usuario_id; commit;
        delete from usuario where usuario_id = r.usuario_id; commit;
    end loop;
    delete from usuario_empresa where id_empresa = 900280;
    commit;
    delete from empresas where id_empresa = 900280;
    commit;
end;
/

declare
    v_n   number;
    v_txt varchar2(4000);
begin
    select count(*) into v_n from tmp_ctb_fallas;
    for r in (select caso from tmp_ctb_fallas) loop
        v_txt := substr(v_txt || ' | ' || r.caso, 1, 3500);
    end loop;
    execute immediate 'drop table tmp_ctb_fallas purge';
    raise_application_error(-20100, 'RESULTADO: FALLAS=' || v_n || v_txt);
end;
/
