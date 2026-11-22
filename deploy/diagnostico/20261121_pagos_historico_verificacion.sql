-- =============================================================================
-- 20261121_pagos_historico_verificacion.sql
--
-- Las cantidades historicas de la compra y el cierre de la anulacion (2026-11-21):
--
--   H1  registrar una compra en divisa, de empresa SPE y con forma de pago que
--       genera IGTF, deja IGTF_BS = 3 % del total en bolivares
--   H2  apagar ES_SPE DESPUES no cambia el IGTF de la compra ya registrada
--   H3  emitir el comprobante de ISLR deja RETENCION_ISLR_BS igual a lo retenido
--   H4  mover la tasa del dia no cambia ninguna de las dos fotos
--   H5  registrar deja FECHA_VENCIMIENTO = emision + dias de credito del proveedor
--   H6  anular una compra con pagos activos -> -20118; sin pagos -> funciona
--
-- Todo dentro de un savepoint y revertido: no toca datos del cliente.
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261121_pagos_historico_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000) := '';
    v_emp    number;
    v_prov   number;
    v_user   varchar2(100);
    v_forma  number;
    v_prod   number;
    v_imp    number;
    v_compra number;
    v_det    number;
    v_folio  number;
    v_pago   number;
    v_num    number;
    v_num2   number;
    v_dias   number;
    v_igtf_ok number;
    v_islr_ok number;
    v_concepto number;

    procedure falla(p_caso varchar2, p_detalle varchar2) is
    begin
        v_fallas := v_fallas + 1;
        v_lista  := v_lista || ' | ' || p_caso || ': ' || p_detalle;
    end;

    procedure espera_num(p_caso varchar2, p_valor number, p_esperado number, p_que varchar2) is
    begin
        if p_valor is null or p_valor <> p_esperado then
            falla(p_caso, p_que || ' = ' || nvl(to_char(p_valor), 'NULL')
                        || ' (esperado ' || to_char(p_esperado) || ')');
        end if;
    end;

begin
    -- punto de partida --------------------------------------------------------
    select min(e.id_empresa) into v_emp
      from empresas e
     where e.cod_pais = 'VE' and nvl(e.es_spe, 'N') = 'S';

    select min(u.username) into v_user
      from usuario u
      join usuario_empresa ue on ue.usuario_id = u.usuario_id
     where ue.id_empresa = v_emp;

    -- un proveedor con concepto de ISLR (si no lo hay, se le pone)
    select min(p.id_proveedor) into v_prov
      from proveedores p
     where p.id_empresa = v_emp and p.id_concepto_islr is not null;

    if v_prov is null then
        select min(p.id_proveedor) into v_prov from proveedores p where p.id_empresa = v_emp;
    end if;

    select min(fp.id_forma_pago) into v_forma
      from forma_pago fp
     where nvl(fp.genera_igtf, 'N') = 'S';

    select min(ps.id_producto_servicio) into v_prod from producto_servicio ps;

    select min(i.id_impuesto) into v_imp
      from impuestos i
     where i.cod_pais = 'VE' and nvl(i.aplica_en, 'LINEA') = 'LINEA' and i.porcentage = 16;

    if v_emp is null or v_prov is null or v_user is null or v_forma is null
       or v_prod is null or v_imp is null then
        raise_application_error(-20100,
            'RESULTADO: FALLAS=0 OMITIDO: falta empresa SPE, proveedor, usuario, forma con IGTF, '
            || 'producto o impuesto al 16 %');
    end if;

    savepoint sp_hist;

    -- se le asegura concepto de ISLR al proveedor
    select count(*) into v_num
      from proveedores p
     where p.id_proveedor = v_prov and p.id_concepto_islr is not null;

    if v_num = 0 then
        update proveedores set id_concepto_islr = (select min(c.id_concepto) from islr_conceptos c where c.activo = 'S' and c.tarifa is not null) where id_proveedor = v_prov;
    end if;

    select nvl(p.dias_credito, 0) into v_dias
      from proveedores p where p.id_proveedor = v_prov;

    -- una compra en divisa, con forma de pago que genera IGTF ------------------
    select nvl(max(id_compra), 0) + 1 into v_folio from compras;

    -- el concepto de ISLR se hereda del proveedor al dar de alta la compra (aqui
    -- se inserta a mano, asi que se copia explicitamente)
    select p.id_concepto_islr into v_concepto
      from proveedores p where p.id_proveedor = v_prov;

    insert into compras (id_empresa, id_proveedor, tipo_documento, folio_factura, fecha_emision,
                         cod_moneda, tipo_cambio, estado, id_forma_pago, id_concepto_islr)
    values (v_emp, v_prov, 'FAC', 'VERIF-H-' || v_folio, date '2026-11-21',
            'USD', 900, 'BORRADOR', v_forma, v_concepto)
    returning id_compra into v_compra;

    pkg_compra_detalle.guardar_detalle(v_det, v_compra, 1, v_prod, 'Verif historico',
                                       1, 100, 0, 0, v_imp, 16, v_user);

    pkg_compras.prc_registrar_compra(v_compra, v_user);

    -- H1: IGTF congelado = 3 % del total en bolivares
    select round(round(nvl(c.monto_total, 0) * nvl(fn_alicuota_igtf(c.id_empresa), 0) / 100, 2)
                 * nvl(c.tipo_cambio, 1), 2)
      into v_num2
      from compras c where c.id_compra = v_compra;

    select nvl(c.igtf_bs, 0) into v_num from compras c where c.id_compra = v_compra;
    espera_num('H1', v_num, v_num2, 'IGTF_BS de la compra registrada');
    if v_num2 <= 0 then
        falla('H1', 'el escenario no causa IGTF: revisa empresa SPE y forma de pago');
    end if;
    v_igtf_ok := v_num;

    -- H2: apagar SPE despues no mueve el IGTF ya guardado
    update empresas set es_spe = 'N' where id_empresa = v_emp;
    select nvl(c.igtf_bs, 0) into v_num from compras c where c.id_compra = v_compra;
    espera_num('H2', v_num, v_igtf_ok, 'IGTF_BS con ES_SPE apagado despues');
    update empresas set es_spe = 'S' where id_empresa = v_emp;

    -- H3: el ISLR retenido queda en la compra
    select nvl(sum(r.retenido_bs), 0) into v_num2
      from retenciones r
     where r.id_compra = v_compra and r.tipo = 'ISLR' and r.estado = 'EMITIDO';

    select nvl(c.retencion_islr_bs, 0) into v_num from compras c where c.id_compra = v_compra;
    espera_num('H3', v_num, v_num2, 'RETENCION_ISLR_BS contra el comprobante');
    if v_num2 <= 0 then
        falla('H3', 'el escenario no retuvo ISLR: revisa el concepto del proveedor');
    end if;
    v_islr_ok := v_num;

    -- H4: mover la tasa del dia no toca las fotos
    update tipo_cambio set tasa_cambio = tasa_cambio + 10
     where trunc(fecha_vigencia) = trunc(sysdate);

    select nvl(c.retencion_islr_bs, 0) into v_num from compras c where c.id_compra = v_compra;
    espera_num('H4', v_num, v_islr_ok, 'RETENCION_ISLR_BS despues de mover la tasa');

    select nvl(c.igtf_bs, 0) into v_num from compras c where c.id_compra = v_compra;
    espera_num('H4', v_num, v_igtf_ok, 'IGTF_BS despues de mover la tasa');

    -- H5: vencimiento = emision + dias de credito
    select nvl(c.fecha_vencimiento, date '1900-01-01') - c.fecha_emision
      into v_num
      from compras c where c.id_compra = v_compra;
    espera_num('H5', v_num, v_dias, 'dias entre emision y vencimiento');

    -- H6: anular con pagos activos
    -- el pago tiene que estar APLICADO a la compra: un anticipo suelto no la ata,
    -- y anular la compra en ese caso es legitimo
    pkg_pagos.prc_registrar_pago(
        p_id_proveedor => v_prov, p_fecha => date '2026-11-21', p_moneda => 'USD', p_tasa => 900,
        p_monto => 10, p_id_forma_pago => null,
        p_aplicaciones => '[{"id_compra":' || v_compra || ',"monto":10}]',
        p_usuario => v_user, p_id_pago => v_pago);

    begin
        pkg_compras.prc_anular_compra(v_compra, v_user);
        falla('H6', 'anulo una compra que tiene pagos activos');
    exception
        when others then
            if sqlcode <> -20118 then
                falla('H6', 'codigo ' || sqlcode || ' en vez de -20118');
            end if;
    end;

    pkg_pagos.prc_anular_pago(v_pago, v_user);
    pkg_compras.prc_anular_compra(v_compra, v_user);
    select count(*) into v_num from compras where id_compra = v_compra and estado = 'ANULADA';
    espera_num('H6', v_num, 1, 'compra anulada despues de quitar el pago');

    rollback to sp_hist;

    raise_application_error(-20100,
        substrb('RESULTADO: FALLAS=' || v_fallas || v_lista, 1, 3000));
end;
/
