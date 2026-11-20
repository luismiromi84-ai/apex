-- =============================================================================
-- 20261116_retencion_numeracion_verificacion.sql
--
-- Retencion de IVA y numeracion del comprobante (Task 3). Todo el DML va dentro
-- de un SAVEPOINT y se revierte.
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261116_retencion_numeracion_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

begin
    begin execute immediate 'drop table tmp_ret_fallas purge'; exception when others then null; end;
end;
/

create table tmp_ret_fallas (caso varchar2(300))
/

declare
    type t_lista is table of varchar2(300);
    v_fallas  t_lista := t_lista();
    v_msg     varchar2(300);

    v_prov    number;
    v_prov_mx number;
    v_a       number;
    v_b       number;
    v_c       number;
    v_anulada number;
    v_borr    number;
    v_idret   number;
    v_num     varchar2(14);
    v_num2    varchar2(14);
    v_pct     number;
    v_ret     number;
    v_periodo char(6) := to_char(sysdate, 'YYYYMM');
    v_base    number;   -- ultimo comprobante del periodo antes de la prueba
    v_otro    char(6) := to_char(add_months(sysdate, 1), 'YYYYMM');

    procedure falla(p_texto varchar2) is
    begin
        v_fallas.extend;
        v_fallas(v_fallas.last) := substrb(p_texto, 1, 300);
    end;

    function nueva_compra(p_prov number, p_estado varchar2, p_folio varchar2) return number is
        v_id number;
    begin
        insert into compras (id_empresa, id_proveedor, folio_factura, fecha_emision, estado,
                             porcentaje_retencion)
        values (1, p_prov, p_folio, sysdate, p_estado, 75)
        returning id_compra into v_id;
        return v_id;
    end;

    procedure linea(p_compra number, p_num number, p_subtotal_bs number, p_iva_bs number,
                    p_pct number, p_impuesto number) is
    begin
        insert into compras_det (id_compra, num_linea, descripcion, cantidad, precio_unitario,
                                 id_impuesto, porcentaje_impuesto, monto_impuesto,
                                 subtotal_linea, total_linea, tasa_cambio_aplicada,
                                 subtotal_bs, total_bs)
        values (p_compra, p_num, 'Linea ' || p_num, 1, p_subtotal_bs,
                p_impuesto, p_pct, p_iva_bs,
                p_subtotal_bs, p_subtotal_bs + p_iva_bs, 1,
                p_subtotal_bs, p_subtotal_bs + p_iva_bs);
    end;
begin
    savepoint sp_ret;

    insert into proveedores (id_empresa, rif, razon_social, cod_pais)
    values (1, 'J-TESTRET-1', 'Proveedor domiciliado', 'VE')
    returning id_proveedor into v_prov;

    insert into proveedores (id_empresa, rif, razon_social, cod_pais)
    values (1, 'X-TESTRET-2', 'Proveedor del exterior', 'MX')
    returning id_proveedor into v_prov_mx;

    -- la numeracion es correlativa por empresa y periodo: se parte del ultimo emitido
    -- (los comprobantes reales de la empresa 1 avanzan el contador)
    select nvl(max(ultimo), 0) into v_base
      from retencion_contador
     where id_empresa = 1 and periodo = v_periodo;

    -- R1: la vista previa da el siguiente numero y NO mueve el contador.
    v_num  := pkg_retenciones.fn_siguiente_numero(1, sysdate);
    v_num2 := pkg_retenciones.fn_siguiente_numero(1, sysdate);
    if v_num <> v_periodo || lpad(v_base + 1, 8, '0') or v_num2 <> v_num or length(v_num) <> 14 then
        falla('R1: vista previa ' || v_num || ' / ' || v_num2 || ' (esperado '
              || v_periodo || lpad(v_base + 1, 8, '0') || ' dos veces)');
    end if;

    -- R5: porcentaje por pais.
    v_pct := pkg_retenciones.fn_porcentaje(v_prov);
    if v_pct <> 75 then falla('R5: domiciliado dio ' || v_pct || ' en vez de 75'); end if;
    v_pct := pkg_retenciones.fn_porcentaje(v_prov_mx);
    if v_pct <> 100 then falla('R5: extranjero dio ' || v_pct || ' en vez de 100'); end if;

    -- Compra A: 16 % (1.000 + 160), exenta (500) e IGTF (200 + 6).
    v_a := nueva_compra(v_prov, 'REGISTRADA', 'T-RET-A');
    linea(v_a, 1, 1000, 160, 16, 1);
    linea(v_a, 2, 500, 0, 0, 3);
    linea(v_a, 3, 200, 6, 3, 2);

    -- R6: la retencion es el 75 % del IVA del 16 %, sin exenta ni IGTF.
    v_ret := pkg_retenciones.fn_retencion_bs(v_a);
    if v_ret <> 120 then falla('R6: retencion ' || v_ret || ' en vez de 120'); end if;

    -- R2: emitir numera ...00000001. El comprobante vive en RETENCIONES desde la
    -- tarea 5 del spec de retenciones (RETENCIONES_IVA dejo de tener escritores).
    pkg_retenciones.prc_emitir(v_a, v_idret, 'TEST');
    select numero_comprobante into v_num from retenciones where id_retencion = v_idret;
    if v_num <> v_periodo || lpad(v_base + 1, 8, '0') or length(v_num) <> 14 then
        falla('R2: numero ' || v_num || ' en vez de ' || v_periodo || lpad(v_base + 1, 8, '0'));
    end if;

    -- R3: la siguiente emision da ...00000002.
    v_b := nueva_compra(v_prov, 'REGISTRADA', 'T-RET-B');
    linea(v_b, 1, 1000, 160, 16, 1);
    pkg_retenciones.prc_emitir(v_b, v_idret, 'TEST');
    select numero_comprobante into v_num from retenciones where id_retencion = v_idret;
    if v_num <> v_periodo || lpad(v_base + 2, 8, '0') then
        falla('R3: segundo numero ' || v_num || ' en vez de ' || v_periodo || lpad(v_base + 2, 8, '0'));
    end if;

    -- R4: otro mes arranca en 1.
    v_num := pkg_retenciones.fn_siguiente_numero(1, add_months(sysdate, 1));
    if v_num <> v_otro || '00000001' then
        falla('R4: otro mes dio ' || v_num || ' en vez de ' || v_otro || '00000001');
    end if;

    -- R7: emitir dos veces la misma compra.
    begin
        pkg_retenciones.prc_emitir(v_a, v_idret, 'TEST');
        falla('R7: emitir dos veces no fallo');
    exception
        when others then
            if sqlcode <> -20086 then falla('R7: codigo ' || sqlcode || ' en vez de -20086'); end if;
    end;

    -- R8: compra anulada.
    v_anulada := nueva_compra(v_prov, 'ANULADA', 'T-RET-ANU');
    linea(v_anulada, 1, 1000, 160, 16, 1);
    begin
        pkg_retenciones.prc_emitir(v_anulada, v_idret, 'TEST');
        falla('R8: emitio sobre una compra anulada');
    exception
        when others then
            if sqlcode <> -20083 then falla('R8: codigo ' || sqlcode || ' en vez de -20083'); end if;
    end;

    -- R9: compra en borrador.
    v_borr := nueva_compra(v_prov, 'BORRADOR', 'T-RET-BOR');
    linea(v_borr, 1, 1000, 160, 16, 1);
    begin
        pkg_retenciones.prc_emitir(v_borr, v_idret, 'TEST');
        falla('R9: emitio sobre una compra en borrador');
    exception
        when others then
            if sqlcode <> -20083 then falla('R9: codigo ' || sqlcode || ' en vez de -20083'); end if;
    end;

    -- R10: anular deja la retencion ANULADA y el numero no se reutiliza.
    pkg_retenciones.prc_anular(v_a, 'TEST');
    select count(*) into v_ret from retenciones
     where id_compra = v_a and estado = 'ANULADO';
    if v_ret <> 1 then falla('R10: la retencion no quedo ANULADO'); end if;

    v_c := nueva_compra(v_prov, 'REGISTRADA', 'T-RET-C');
    linea(v_c, 1, 1000, 160, 16, 1);
    pkg_retenciones.prc_emitir(v_c, v_idret, 'TEST');
    select numero_comprobante into v_num from retenciones where id_retencion = v_idret;
    if v_num <> v_periodo || lpad(v_base + 3, 8, '0') then
        falla('R10: tras anular el numero fue ' || v_num || ' en vez de '
              || v_periodo || lpad(v_base + 3, 8, '0'));
    end if;

    rollback to sp_ret;

    for i in 1 .. v_fallas.count loop
        insert into tmp_ret_fallas values (v_fallas(i));
    end loop;
exception
    when others then
        rollback to sp_ret;
        v_msg := substrb('R?: el caso revento: ' || sqlerrm, 1, 300);
        insert into tmp_ret_fallas values (v_msg);
end;
/

declare
    v_fallas number;
    v_lista  varchar2(3000);
begin
    select count(*) into v_fallas from tmp_ret_fallas;
    select substrb(listagg(caso, ' | ' on overflow truncate) within group (order by caso), 1, 3000)
      into v_lista from tmp_ret_fallas;
    execute immediate 'drop table tmp_ret_fallas purge';
    raise_application_error(-20100, substrb('RESULTADO: FALLAS=' || v_fallas || ' | ' || v_lista, 1, 3000));
end;
/
