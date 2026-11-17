-- =============================================================================
-- package_bodies/pkg_retenciones.sql
--
-- OJO con el runner de importacion: descarta toda linea que empiece por "set ",
-- asi que los UPDATE llevan el SET en la misma linea que el UPDATE.
-- =============================================================================

create or replace package body pkg_retenciones as

    function fn_aplica(p_id_proveedor in number) return boolean is
        v_ret varchar2(1);
    begin
        select nvl(retener_iva, 'S') into v_ret
          from proveedores
         where id_proveedor = p_id_proveedor;
        return v_ret = 'S';
    exception
        when no_data_found then
            return false;
    end fn_aplica;

    function fn_porcentaje(p_id_proveedor in number) return number is
        v_pct number;
    begin
        select case
                 when nvl(p.retener_iva, 'S') <> 'S' then 0
                 when p.cod_pais is not null and e.cod_pais is not null
                      and p.cod_pais <> e.cod_pais then 100
                 else nvl(p.porcentaje_retencion, 75)
               end
          into v_pct
          from proveedores p
          join empresas e on e.id_empresa = p.id_empresa
         where p.id_proveedor = p_id_proveedor;
        return v_pct;
    exception
        when no_data_found then
            return 0;
    end fn_porcentaje;

    function fn_siguiente_numero(p_id_empresa in number, p_fecha in date) return varchar2 is
        v_periodo char(6);
        v_ultimo  number;
    begin
        v_periodo := to_char(nvl(p_fecha, sysdate), 'YYYYMM');
        select nvl(max(ultimo), 0) + 1 into v_ultimo
          from retencion_contador
         where id_empresa = p_id_empresa and periodo = v_periodo;
        return v_periodo || lpad(v_ultimo, 8, '0');
    end fn_siguiente_numero;

    function fn_base_imponible_bs(p_id_compra in number) return number is
        v_base number;
    begin
        select nvl(sum(d.subtotal_bs), 0) into v_base
          from compras_det d
         where d.id_compra = p_id_compra
           and nvl(d.porcentaje_impuesto, 0) > 0
           and not exists (select 1 from impuestos i
                            where i.id_impuesto = d.id_impuesto
                              and (i.cod_impuesto = 'IGTF' or nvl(i.es_retencion, 'N') = 'S'));
        return v_base;
    end fn_base_imponible_bs;

    function fn_iva_causado_bs(p_id_compra in number) return number is
        v_iva number;
    begin
        select nvl(sum(d.monto_impuesto * nvl(d.tasa_cambio_aplicada, 1)), 0) into v_iva
          from compras_det d
         where d.id_compra = p_id_compra
           and nvl(d.porcentaje_impuesto, 0) > 0
           and not exists (select 1 from impuestos i
                            where i.id_impuesto = d.id_impuesto
                              and (i.cod_impuesto = 'IGTF' or nvl(i.es_retencion, 'N') = 'S'));
        return v_iva;
    end fn_iva_causado_bs;

    function fn_retencion_bs(p_id_compra in number) return number is
        v_pct number;
    begin
        select nvl(porcentaje_retencion, 0) into v_pct
          from compras
         where id_compra = p_id_compra;
        if v_pct <= 0 then
            return 0;
        end if;
        return round(fn_iva_causado_bs(p_id_compra) * v_pct / 100, 2);
    exception
        when no_data_found then
            return 0;
    end fn_retencion_bs;

    procedure prc_emitir(p_id_compra in number, p_id_retencion out number, p_usuario in varchar2) is
        v_empresa   number;
        v_estado    varchar2(20);
        v_fecha     date;
        v_pct       number;
        v_base      number;
        v_iva       number;
        v_retenido  number;
        v_periodo   char(6);
        v_ultimo    number;
        v_numero    varchar2(14);
        v_ya_tiene  number;
    begin
        p_id_retencion := null;

        select id_empresa, estado, nvl(fecha_emision, sysdate), nvl(porcentaje_retencion, 0)
          into v_empresa, v_estado, v_fecha, v_pct
          from compras
         where id_compra = p_id_compra;

        if v_estado <> 'REGISTRADA' then
            raise_application_error(-20083,
                'Solo se emite comprobante de una compra REGISTRADA; esta esta ' || v_estado || '.');
        end if;

        select count(*) into v_ya_tiene from retenciones_iva where id_compra = p_id_compra;
        if v_ya_tiene > 0 then
            raise_application_error(-20086, 'La compra ya tiene comprobante de retencion.');
        end if;

        v_base     := fn_base_imponible_bs(p_id_compra);
        v_iva      := fn_iva_causado_bs(p_id_compra);
        v_retenido := round(v_iva * v_pct / 100, 2);

        -- 0 % (o un IVA que no da retencion) no consume numeracion.
        if v_pct <= 0 or v_retenido <= 0 then
            return;
        end if;

        v_periodo := to_char(sysdate, 'YYYYMM');

        update retencion_contador set ultimo = ultimo + 1
         where id_empresa = v_empresa and periodo = v_periodo
        returning ultimo into v_ultimo;

        if sql%rowcount = 0 then
            begin
                insert into retencion_contador (id_empresa, periodo, ultimo)
                values (v_empresa, v_periodo, 1);
                v_ultimo := 1;
            exception
                when dup_val_on_index then
                    update retencion_contador set ultimo = ultimo + 1
                     where id_empresa = v_empresa and periodo = v_periodo
                    returning ultimo into v_ultimo;
            end;
        end if;

        v_numero := v_periodo || lpad(v_ultimo, 8, '0');

        insert into retenciones_iva (id_empresa, id_compra, numero_comprobante, fecha_emision,
                                     periodo_anio, periodo_mes, base_imponible_bs, iva_causado_bs,
                                     porcentaje_retencion, iva_retenido_bs, estado, creado_por)
        values (v_empresa, p_id_compra, v_numero, sysdate,
                to_number(to_char(v_fecha, 'YYYY')), to_number(to_char(v_fecha, 'MM')),
                v_base, v_iva, v_pct, v_retenido, 'EMITIDO', p_usuario)
        returning id_retencion into p_id_retencion;

        update compras set retencion_iva_bs = v_retenido, porcentaje_retencion = v_pct
         where id_compra = p_id_compra;

    exception
        when no_data_found then
            raise_application_error(-20085, 'La compra ' || p_id_compra || ' no existe.');
    end prc_emitir;

    procedure prc_anular(p_id_compra in number, p_usuario in varchar2) is
    begin
        update retenciones_iva set estado = 'ANULADO'
         where id_compra = p_id_compra and estado = 'EMITIDO';
    end prc_anular;

end pkg_retenciones;
/
