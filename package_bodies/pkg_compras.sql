-- =============================================================================
-- package_bodies/pkg_compras.sql
--
-- OJO con el runner: descarta las lineas que empiezan por "set ", asi que los
-- UPDATE llevan el SET en la misma linea.
-- =============================================================================

create or replace package body pkg_compras as

    procedure prc_guardar_compra(
        p_id_compra            in out number,
        p_id_empresa           in number,
        p_id_proveedor         in number,
        p_tipo_documento       in varchar2 default 'FAC',
        p_folio_factura        in varchar2,
        p_nro_control          in varchar2 default null,
        p_fecha_emision        in date,
        p_cod_moneda           in varchar2 default 'VES',
        p_tipo_cambio          in number default 1,
        p_porcentaje_retencion in number default null,
        p_id_compra_origen     in number default null,
        p_observaciones        in varchar2 default null,
        p_usuario              in varchar2) is
        v_estado    varchar2(20);
        v_prov_emp  number;
        v_tasa      number;
        v_pct       number;
        v_fecha     date;
        v_folio     varchar2(50);
        v_control   varchar2(50);
    begin
        if p_id_proveedor is null then
            raise_application_error(-20087, 'La compra necesita un proveedor.');
        end if;

        if not fn_usuario_empresa_valida(p_usuario, p_id_empresa) then
            raise_application_error(-20003, 'No tiene permisos sobre esta empresa.');
        end if;

        begin
            select id_empresa into v_prov_emp
              from proveedores where id_proveedor = p_id_proveedor;
        exception
            when no_data_found then
                raise_application_error(-20084, 'El proveedor no existe.');
        end;
        if v_prov_emp <> p_id_empresa then
            raise_application_error(-20084, 'El proveedor no es de la empresa del documento.');
        end if;

        if p_porcentaje_retencion is not null
           and (p_porcentaje_retencion < 0 or p_porcentaje_retencion > 100) then
            raise_application_error(-20082, 'El porcentaje de retencion debe estar entre 0 y 100.');
        end if;

        v_fecha := nvl(p_fecha_emision, sysdate);

        if upper(nvl(p_cod_moneda, 'VES')) in ('VES', 'BS') then
            v_tasa := 1;
        else
            v_tasa := fn_validar_tasa_documento(p_cod_moneda, v_fecha, p_tipo_cambio);
        end if;

        if p_porcentaje_retencion is null then
            v_pct := pkg_retenciones.fn_porcentaje(p_id_proveedor);
        else
            v_pct := p_porcentaje_retencion;
        end if;

        -- Numeracion del PROVEEDOR (2026-11-18): la serie vive en FOLIO_CONTADOR
        -- (FAC_PROV y CONTROL_PROV) para que la pantalla la proponga sola. Al dar de
        -- alta se CONSUME solo si se dejo la propuesta (o vacio); si el usuario
        -- escribio otro numero, se respeta el suyo y la serie no se mueve.
        v_folio := trim(p_folio_factura);
        v_control := trim(p_nro_control);

        if p_id_compra is null then
            if v_folio is null
               or upper(v_folio) = upper(fn_siguiente_folio(p_id_empresa, 'FAC_PROV')) then
                v_folio := fn_asignar_folio(p_id_empresa, 'FAC_PROV');
            end if;
            if v_control is null
               or upper(v_control) = upper(fn_siguiente_folio(p_id_empresa, 'CONTROL_PROV')) then
                v_control := fn_asignar_folio(p_id_empresa, 'CONTROL_PROV');
            end if;
        end if;

        if v_folio is null then
            raise_application_error(-20087,
                'El numero de factura del proveedor es obligatorio.');
        end if;
        if v_control is not null and length(v_control) < 3 then
            raise_application_error(-20089,
                'El numero de control del proveedor no puede ser un numero suelto de 1 o 2 digitos. '
                || 'Escribelo como aparece en la factura (por ejemplo 00-000045).');
        end if;

        if p_id_compra is null then
            begin
                insert into compras (id_empresa, id_proveedor, tipo_documento, folio_factura,
                                     nro_control, fecha_emision, cod_moneda, tipo_cambio,
                                     porcentaje_retencion, estado, observaciones,
                                     id_compra_origen, creado_por)
                values (p_id_empresa, p_id_proveedor, nvl(p_tipo_documento, 'FAC'),
                        v_folio, v_control, v_fecha, nvl(p_cod_moneda, 'VES'),
                        v_tasa, v_pct, 'BORRADOR', p_observaciones,
                        p_id_compra_origen, p_usuario)
                returning id_compra into p_id_compra;
            exception
                when dup_val_on_index then
                    raise_application_error(-20080,
                        'Ya existe la factura ' || v_folio || ' de este proveedor.');
            end;
        else
            begin
                select estado into v_estado from compras where id_compra = p_id_compra;
            exception
                when no_data_found then
                    raise_application_error(-20085, 'La compra ' || p_id_compra || ' no existe.');
            end;
            if v_estado <> 'BORRADOR' then
                raise_application_error(-20083,
                    'La compra esta ' || v_estado || ': no se puede modificar.');
            end if;
            begin
                update compras set id_proveedor = p_id_proveedor,
                       tipo_documento = nvl(p_tipo_documento, 'FAC'),
                       folio_factura = v_folio, nro_control = v_control,
                       fecha_emision = v_fecha, cod_moneda = nvl(p_cod_moneda, 'VES'),
                       tipo_cambio = v_tasa, porcentaje_retencion = v_pct,
                       observaciones = p_observaciones, id_compra_origen = p_id_compra_origen,
                       modificado_por = p_usuario, fecha_modificacion = systimestamp
                 where id_compra = p_id_compra;
            exception
                when dup_val_on_index then
                    raise_application_error(-20080,
                        'Ya existe la factura ' || v_folio || ' de este proveedor.');
            end;
        end if;
    end prc_guardar_compra;

    procedure prc_registrar_compra(p_id_compra in number, p_usuario in varchar2) is
        v_estado varchar2(20);
        v_lineas number;
        v_idret  number;
    begin
        select estado into v_estado
          from compras where id_compra = p_id_compra for update;

        if v_estado <> 'BORRADOR' then
            raise_application_error(-20083,
                'La compra esta ' || v_estado || ': no se puede registrar.');
        end if;

        select count(*) into v_lineas from compras_det where id_compra = p_id_compra;
        if v_lineas = 0 then
            raise_application_error(-20085,
                'La compra no tiene lineas: agrega al menos una antes de registrarla.');
        end if;

        update compras set estado = 'REGISTRADA', modificado_por = p_usuario,
               fecha_modificacion = systimestamp
         where id_compra = p_id_compra;

        pkg_retenciones.prc_emitir(p_id_compra, v_idret, p_usuario);
    exception
        when no_data_found then
            raise_application_error(-20085, 'La compra ' || p_id_compra || ' no existe.');
    end prc_registrar_compra;

    procedure prc_anular_compra(p_id_compra in number, p_usuario in varchar2) is
        v_estado varchar2(20);
    begin
        select estado into v_estado
          from compras where id_compra = p_id_compra for update;

        if v_estado = 'ANULADA' then
            return;
        end if;

        update compras set estado = 'ANULADA', modificado_por = p_usuario,
               fecha_modificacion = systimestamp
         where id_compra = p_id_compra;

        pkg_retenciones.prc_anular(p_id_compra, p_usuario);
    exception
        when no_data_found then
            raise_application_error(-20085, 'La compra ' || p_id_compra || ' no existe.');
    end prc_anular_compra;

end pkg_compras;
/
