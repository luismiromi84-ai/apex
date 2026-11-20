-- =============================================================================
-- package_bodies/pkg_compra_detalle.sql
--
-- OJO con el runner: descarta las lineas que empiezan por "set ".
-- =============================================================================

create or replace package body pkg_compra_detalle as

    procedure guardar_detalle(
        p_id_detalle           in out number,
        p_id_compra            in number,
        p_num_linea            in number,
        p_id_producto_servicio in number,
        p_descripcion          in varchar2,
        p_cantidad             in number,
        p_precio_unitario      in number,
        p_porcentaje_descuento in number,
        p_monto_descuento      in number,
        p_id_impuesto          in number,
        p_porcentaje_impuesto  in number,
        p_usuario              in varchar2) is
        v_estado varchar2(20);
        v_id_emp number;
        v_tasa   number;
        v_num    number;
        v_bruto  number;
        v_desc   number;
        v_base   number;
        v_iva    number;
        v_total  number;
        v_compra_linea number;
    begin
        select estado, nvl(tipo_cambio, 1), id_empresa into v_estado, v_tasa, v_id_emp
          from compras where id_compra = p_id_compra;

        -- El id de la compra llega de la pantalla (P29_ID_COMPRA no esta protegido):
        -- sin esta comprobacion un POST manipulado agregaria una linea a la compra de
        -- OTRA empresa. Se valida aqui, no solo en el proceso de la pagina.
        if not fn_usuario_empresa_valida(p_usuario, v_id_emp) then
            raise_application_error(-20003, 'No tiene permisos sobre esta compra.');
        end if;

        if v_estado <> 'BORRADOR' then
            raise_application_error(-20083,
                'La compra esta ' || v_estado || ': no admite cambios en el detalle.');
        end if;
        if v_tasa is null or v_tasa <= 0 then
            v_tasa := 1;
        end if;

        v_bruto := round(nvl(p_cantidad, 0) * nvl(p_precio_unitario, 0), 2);
        v_desc  := round(nvl(p_monto_descuento, v_bruto * nvl(p_porcentaje_descuento, 0) / 100), 2);
        v_base  := v_bruto - v_desc;
        v_iva   := round(v_base * nvl(p_porcentaje_impuesto, 0) / 100, 2);
        v_total := v_base + v_iva;

        -- La columna es NOT NULL: sin esto, guardar una linea en blanco daba
        -- ORA-01400 en vez de un mensaje entendible (2026-11-18).
        if p_descripcion is null or trim(p_descripcion) is null then
            raise_application_error(-20086, 'La descripcion de la linea es obligatoria.');
        end if;

        -- La cantidad la teclea el usuario (la pantalla ya no la propone, 2026-11-19):
        -- una linea en cero no es una compra, es un renglon vacio.
        if nvl(p_cantidad, 0) <= 0 then
            raise_application_error(-20096, 'La cantidad de la linea debe ser mayor que cero.');
        end if;

        if p_id_detalle is null then
            select nvl(max(num_linea), 0) + 1 into v_num
              from compras_det where id_compra = p_id_compra;

            insert into compras_det (id_compra, num_linea, id_producto_servicio, descripcion,
                                     cantidad, precio_unitario, porcentaje_descuento, monto_descuento,
                                     id_impuesto, porcentaje_impuesto, monto_impuesto,
                                     subtotal_linea, total_linea, tasa_cambio_aplicada,
                                     subtotal_bs, total_bs, creado_por)
            values (p_id_compra, nvl(p_num_linea, v_num), p_id_producto_servicio, p_descripcion,
                    nvl(p_cantidad, 0), nvl(p_precio_unitario, 0), nvl(p_porcentaje_descuento, 0), v_desc,
                    p_id_impuesto, nvl(p_porcentaje_impuesto, 0), v_iva,
                    v_base, v_total, v_tasa,
                    round(v_base * v_tasa, 2), round(v_total * v_tasa, 2), p_usuario)
            returning id_detalle into p_id_detalle;
        else
            -- Editar una linea: ademas de la empresa de la compra hay que comprobar
            -- que la linea sea DE ESA compra (si no, con una compra propia se
            -- reescribiria una linea de otra).
            begin
                select id_compra into v_compra_linea
                  from compras_det
                 where id_detalle = p_id_detalle;
            exception
                when no_data_found then
                    raise_application_error(-20085, 'La linea ' || p_id_detalle || ' no existe.');
            end;
            if v_compra_linea <> p_id_compra then
                raise_application_error(-20003, 'La linea no es de esta compra.');
            end if;

            update compras_det set num_linea = nvl(p_num_linea, num_linea),
                   id_producto_servicio = p_id_producto_servicio,
                   descripcion = p_descripcion,
                   cantidad = nvl(p_cantidad, 0), precio_unitario = nvl(p_precio_unitario, 0),
                   porcentaje_descuento = nvl(p_porcentaje_descuento, 0), monto_descuento = v_desc,
                   id_impuesto = p_id_impuesto,
                   porcentaje_impuesto = nvl(p_porcentaje_impuesto, 0),
                   monto_impuesto = v_iva, subtotal_linea = v_base, total_linea = v_total,
                   tasa_cambio_aplicada = v_tasa,
                   subtotal_bs = round(v_base * v_tasa, 2),
                   total_bs = round(v_total * v_tasa, 2)
             where id_detalle = p_id_detalle;
        end if;
    exception
        when no_data_found then
            raise_application_error(-20085, 'La compra ' || p_id_compra || ' no existe.');
    end guardar_detalle;

    procedure eliminar_detalle(p_id_detalle in number, p_usuario in varchar2) is
        v_estado varchar2(20);
        v_id_emp number;
    begin
        begin
            select c.estado, c.id_empresa into v_estado, v_id_emp
              from compras_det d
              join compras c on c.id_compra = d.id_compra
             where d.id_detalle = p_id_detalle;
        exception
            when no_data_found then
                raise_application_error(-20085, 'La linea ' || p_id_detalle || ' no existe.');
        end;

        -- El id de la linea llega de la pantalla (item oculto, no protegido): sin esta
        -- comprobacion un POST manipulado borraria la linea de una compra de OTRA
        -- empresa. La propiedad se valida aqui, no solo en el proceso de la pagina.
        if not fn_usuario_empresa_valida(p_usuario, v_id_emp) then
            raise_application_error(-20003, 'No tiene permisos sobre esta linea.');
        end if;

        if v_estado <> 'BORRADOR' then
            raise_application_error(-20083,
                'La compra esta ' || v_estado || ': no se pueden borrar lineas.');
        end if;

        delete from compras_det where id_detalle = p_id_detalle;
    end eliminar_detalle;

    procedure copiar_desde_compra(p_id_compra in number, p_id_compra_origen in number,
                                  p_usuario in varchar2) is
        v_estado varchar2(20);
        v_n      number;
    begin
        select estado into v_estado from compras where id_compra = p_id_compra;

        if v_estado <> 'BORRADOR' then
            raise_application_error(-20083,
                'La compra esta ' || v_estado || ': no se puede copiar el detalle.');
        end if;

        select count(*) into v_n from compras_det where id_compra = p_id_compra;
        if v_n > 0 then
            raise_application_error(-20045,
                'La nota ya tiene lineas: borralas antes de volver a copiar.');
        end if;

        insert into compras_det (id_compra, num_linea, id_producto_servicio, descripcion,
                                 cantidad, precio_unitario, porcentaje_descuento, monto_descuento,
                                 id_impuesto, porcentaje_impuesto, monto_impuesto,
                                 subtotal_linea, total_linea, tasa_cambio_aplicada,
                                 subtotal_bs, total_bs, id_detalle_origen, creado_por)
        select p_id_compra, num_linea, id_producto_servicio, descripcion,
               cantidad, precio_unitario, porcentaje_descuento, monto_descuento,
               id_impuesto, porcentaje_impuesto, monto_impuesto,
               subtotal_linea, total_linea, tasa_cambio_aplicada,
               subtotal_bs, total_bs, id_detalle, p_usuario
          from compras_det
         where id_compra = p_id_compra_origen;
    exception
        when no_data_found then
            raise_application_error(-20085, 'La compra ' || p_id_compra || ' no existe.');
    end copiar_desde_compra;

end pkg_compra_detalle;
/
