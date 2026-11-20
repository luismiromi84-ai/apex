-- =============================================================================
-- 20261120_nota_compra_lineas.sql
--
-- Nota de credito/debito de COMPRA: pkg_compra_detalle.copiar_desde_compra ya
-- existia pero no tenia guardas y ninguna pantalla la llamaba. Ahora la usa el
-- boton "Traer lineas" de la pagina 28, igual que el lado de ventas.
--
-- Guardas, ANTES de escribir nada:
--   - la compra destino tiene que ser de una empresa del usuario  -> -20003
--   - la factura que acredita tiene que ser de la MISMA empresa,
--     tipo_documento = 'FAC' y no estar ANULADA                 -> -20046
--   - cada linea copiada lleva ID_DETALLE_ORIGEN = la linea original
--
-- REGENERADO el 2026-11-20 desde los archivos canonicos: el copiado paso a ser
-- IDEMPOTENTE (se puede pulsar varias veces; copia solo las que faltan) y la
-- spec gano los dos parametros de salida, asi que este archivo lleva la spec
-- ANTES del body. -20045 quedo solo para "lineas copiadas de otra factura".
-- La migracion de ese cambio, para bases ya instaladas, es
-- 20261120_traer_lineas_sin_duplicar.sql.
--
-- Reversa: volver a la spec y al body anteriores.
-- Verificacion: deploy/diagnostico/20261119_compra_nota_afectada_verificacion.sql
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

-- =============================================================================
-- package/pkg_compra_detalle.sql  (la spec PRIMERO: cambio de firma)
-- =============================================================================

-- =============================================================================
-- package/pkg_compra_detalle.sql
--
-- Lineas de la factura de compra. El paquete CALCULA los importes: la pantalla
-- manda cantidad, precio, descuento y alicuota, y aqui se derivan subtotal,
-- IVA, total y sus equivalentes en bolivares. Asi no hay dos sitios que puedan
-- calcular distinto (fue el bug de los porcentajes de facturacion).
--
-- SUBTOTAL_LINEA es NETO de descuento, igual que en FACTURAS_DET.
-- =============================================================================

create or replace package pkg_compra_detalle as

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
        p_usuario              in varchar2);

    procedure eliminar_detalle(p_id_detalle in number, p_usuario in varchar2);

    -- Trae a la nota las lineas de la factura de compra que acredita. Es
    -- IDEMPOTENTE (2026-11-20): se puede pulsar las veces que haga falta. Copia
    -- solo las que faltan (se comparan por ID_DETALLE_ORIGEN), no borra ni
    -- reescribe lo que ya hay, y las lineas tecleadas a mano se quedan.
    --   p_agregadas   cuantas lineas se insertaron en esta pasada
    --   p_ya_estaban  cuantas de la factura ya estaban en la nota
    procedure copiar_desde_compra(p_id_compra in number, p_id_compra_origen in number,
                                  p_usuario in varchar2,
                                  p_agregadas out number, p_ya_estaban out number);

end pkg_compra_detalle;
/

-- =============================================================================
-- package_bodies/pkg_compra_detalle.sql
--
-- OJO con el runner: descarta las lineas que empiezan por "set ".
-- =============================================================================

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

    -- Trae a la nota las lineas de la factura de compra que acredita, igual que
    -- pkg_factura_detalle.copiar_desde_factura en el lado de ventas. Cada linea
    -- copiada apunta a la original en ID_DETALLE_ORIGEN (lo exige el SENIAT).
    -- El id de la compra llega de la pantalla (P28_ID_COMPRA no esta protegido),
    -- asi que la propiedad se valida AQUI, no solo en el proceso de la pagina.
    --
    -- IDEMPOTENTE (2026-11-20): con facturas de 20 o 50 lineas hay que poder
    -- pulsar "Traer lineas" mas de una vez sin duplicar ni perder lo tecleado.
    --   - nota vacia        -> copia todas las lineas de la factura
    --   - nota con copias   -> copia SOLO las que faltan, comparando por
    --                          ID_DETALLE_ORIGEN; no borra ni actualiza las que
    --                          ya estan (el usuario pudo ajustar cantidades)
    --   - ya estaban todas  -> no lanza: devuelve 0 en p_agregadas
    --   - lineas a mano     -> se quedan como estan: no son ambiguas, no apuntan
    --                          a ninguna linea de la factura
    -- -20045 queda SOLO para el caso realmente ambiguo: la nota ya tiene lineas
    -- copiadas de OTRA factura. Una nota acredita UNA factura; mezclar dos deja
    -- un documento que no cuadra con ninguna.
    procedure copiar_desde_compra(p_id_compra in number, p_id_compra_origen in number,
                                  p_usuario in varchar2,
                                  p_agregadas out number, p_ya_estaban out number) is
        v_estado    varchar2(20);
        v_id_emp    number;
        v_ori_emp   number;
        v_ori_tipo  varchar2(3);
        v_ori_est   varchar2(20);
        v_total_ori number;
        v_otras     number;
        v_max       number;
    begin
        p_agregadas  := 0;
        p_ya_estaban := 0;

        select estado, id_empresa into v_estado, v_id_emp
          from compras where id_compra = p_id_compra;

        if not fn_usuario_empresa_valida(p_usuario, v_id_emp) then
            raise_application_error(-20003, 'No tiene permisos sobre esta compra.');
        end if;

        if v_estado <> 'BORRADOR' then
            raise_application_error(-20083,
                'La compra esta ' || v_estado || ': no se puede copiar el detalle.');
        end if;

        -- La factura que acredita tiene que ser una FAC de la MISMA empresa y
        -- vigente: de una nota o de una anulada no se copia nada.
        if p_id_compra_origen is null then
            raise_application_error(-20046,
                'Elige la factura de compra que acredita la nota antes de traer las lineas.');
        end if;
        begin
            select id_empresa, tipo_documento, estado
              into v_ori_emp, v_ori_tipo, v_ori_est
              from compras where id_compra = p_id_compra_origen;
        exception
            when no_data_found then
                raise_application_error(-20046,
                    'La factura de compra que acredita no existe.');
        end;

        if v_ori_emp <> v_id_emp then
            raise_application_error(-20046,
                'La factura que acredita es de otra empresa.');
        end if;
        if nvl(v_ori_tipo, 'FAC') <> 'FAC' then
            raise_application_error(-20046,
                'Solo se pueden traer las lineas de una factura de compra (FAC), no de una nota.');
        end if;
        if v_ori_est = 'ANULADA' then
            raise_application_error(-20046,
                'La factura de compra esta ANULADA: no se pueden traer sus lineas.');
        end if;

        select count(*) into v_total_ori
          from compras_det where id_compra = p_id_compra_origen;

        -- Lineas copiadas de OTRA factura: mezclar dos facturas en una nota no
        -- es un caso de "faltan lineas", es otro documento. Se rechaza.
        select count(*) into v_otras
          from compras_det d
         where d.id_compra = p_id_compra
           and d.id_detalle_origen is not null
           and not exists (select 1
                             from compras_det o
                            where o.id_detalle = d.id_detalle_origen
                              and o.id_compra = p_id_compra_origen);
        if v_otras > 0 then
            raise_application_error(-20045,
                'La nota ya tiene ' || v_otras || ' lineas copiadas de otra factura. ' ||
                'Una nota acredita una sola factura: borralas antes de traer las de esta.');
        end if;

        -- Numeracion correlativa a partir de la ultima que haya en la nota.
        select nvl(max(num_linea), 0) into v_max
          from compras_det where id_compra = p_id_compra;

        insert into compras_det (id_compra, num_linea, id_producto_servicio, descripcion,
                                 cantidad, precio_unitario, porcentaje_descuento, monto_descuento,
                                 id_impuesto, porcentaje_impuesto, monto_impuesto,
                                 subtotal_linea, total_linea, tasa_cambio_aplicada,
                                 subtotal_bs, total_bs, id_detalle_origen, creado_por)
        select p_id_compra,
               v_max + row_number() over (order by o.num_linea, o.id_detalle),
               o.id_producto_servicio, o.descripcion,
               o.cantidad, o.precio_unitario, o.porcentaje_descuento, o.monto_descuento,
               o.id_impuesto, o.porcentaje_impuesto, o.monto_impuesto,
               o.subtotal_linea, o.total_linea, o.tasa_cambio_aplicada,
               o.subtotal_bs, o.total_bs, o.id_detalle, p_usuario
          from compras_det o
         where o.id_compra = p_id_compra_origen
           and not exists (select 1
                             from compras_det d
                            where d.id_compra = p_id_compra
                              and d.id_detalle_origen = o.id_detalle);

        p_agregadas  := sql%rowcount;
        p_ya_estaban := v_total_ori - p_agregadas;
    exception
        when no_data_found then
            raise_application_error(-20085, 'La compra ' || p_id_compra || ' no existe.');
    end copiar_desde_compra;

end pkg_compra_detalle;
/

begin
    dbms_utility.compile_schema('WKSP_SYPEXWS', false);
end;
/

declare
    v_n number;
begin
    select count(*) into v_n
      from all_objects
     where owner = 'WKSP_SYPEXWS' and object_name = 'PKG_COMPRA_DETALLE'
       and status = 'VALID';
    if v_n < 2 then
        raise_application_error(-20112, 'PKG_COMPRA_DETALLE quedo invalido');
    end if;

    select count(*) into v_n
      from all_source
     where owner = 'WKSP_SYPEXWS' and name = 'PKG_COMPRA_DETALLE'
       and type = 'PACKAGE BODY'
       and instr(text, '20046') > 0;
    if v_n = 0 then
        raise_application_error(-20112, 'el body no trae la guarda de la factura que acredita');
    end if;

    select count(*) into v_n
      from all_source
     where owner = 'WKSP_SYPEXWS' and name = 'PKG_COMPRA_DETALLE'
       and type = 'PACKAGE BODY'
       and instr(text, 'fn_usuario_empresa_valida') > 0;
    if v_n = 0 then
        raise_application_error(-20112, 'el body no trae la guarda de empresa del copiado');
    end if;
end;
/
