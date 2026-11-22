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
        p_id_forma_pago        in number default null,
        p_id_concepto_islr     in number default -1,
        p_usuario              in varchar2) is
        v_estado    varchar2(20);
        v_prov_emp  number;
        v_prov_con  number;
        v_con       number;
        v_tasa      number;
        v_tasa_ant  number;
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
            select id_empresa, id_concepto_islr into v_prov_emp, v_prov_con
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

        -- Una nota (NC/ND) tiene que decir que factura de compra afecta: es lo que
        -- pide la providencia del SENIAT y lo que cruza el libro de compras.
        --
        -- CORRELACION DE LA TASA (2026-11-20): la nota lleva la TASA de la factura
        -- que acredita, no la del dia en que se emite, igual que las notas de venta
        -- desde el 2026-11-09. Sin esto la cabecera quedaba a la tasa del dia y las
        -- lineas copiadas con la de la factura: el libro suma las filas por el
        -- detalle y los totales del mes por la cabecera, y los dos numeros no
        -- cuadraban (nota de compra 1462: 1.294,71 Bs de diferencia).
        -- Si la factura que acredita esta ANULADA se mantiene la tasa recibida (de
        -- un documento anulado no se hereda nada). Y si la nota esta en otra moneda
        -- que la factura, la tasa de la factura no significa nada en esa moneda:
        -- se respeta la que llega (la pantalla copia la moneda del origen).
        if upper(nvl(p_tipo_documento, 'FAC')) in ('NC', 'ND') then
            if p_id_compra_origen is null then
                raise_application_error(-20097,
                    'Una nota de credito o debito necesita la factura de compra que afecta.');
            end if;
            declare
                v_tipo_origen varchar2(10);
                v_emp_origen  number;
                v_est_origen  varchar2(20);
                v_tasa_origen number;
                v_mon_origen  varchar2(5);
            begin
                select tipo_documento, id_empresa, estado, tipo_cambio, cod_moneda
                  into v_tipo_origen, v_emp_origen, v_est_origen, v_tasa_origen, v_mon_origen
                  from compras where id_compra = p_id_compra_origen;
                if v_tipo_origen <> 'FAC' or v_emp_origen <> p_id_empresa then
                    raise_application_error(-20097,
                        'La factura afectada tiene que ser una factura de compra de esta empresa.');
                end if;
                if v_est_origen <> 'ANULADA'
                   and v_tasa_origen is not null
                   and upper(nvl(v_mon_origen, 'VES')) = upper(nvl(p_cod_moneda, 'VES')) then
                    v_tasa := v_tasa_origen;
                end if;
            exception
                when no_data_found then
                    raise_application_error(-20097, 'La factura afectada no existe.');
            end;
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
            -- Concepto de ISLR con CENTINELA (ver la spec): -1 o nulo = no se envio y
            -- se HEREDA del proveedor; 0 = sin concepto; otro = ese concepto. Un nulo
            -- no puede significar a la vez "borralo" y "no lo mande": el llamador que
            -- no pasa el parametro borraba el concepto heredado en cada guardado y el
            -- comprobante de ISLR dejaba de emitirse en silencio.
            v_con := p_id_concepto_islr;
            if v_con is null or v_con = -1 then
                v_con := v_prov_con;
            elsif v_con = 0 then
                v_con := null;
            end if;

            begin
                insert into compras (id_empresa, id_proveedor, tipo_documento, folio_factura,
                                     nro_control, fecha_emision, cod_moneda, tipo_cambio,
                                     porcentaje_retencion, estado, observaciones,
                                     id_compra_origen, id_forma_pago, id_concepto_islr,
                                     creado_por)
                values (p_id_empresa, p_id_proveedor, nvl(p_tipo_documento, 'FAC'),
                        v_folio, v_control, v_fecha, nvl(p_cod_moneda, 'VES'),
                        v_tasa, v_pct, 'BORRADOR', p_observaciones,
                        p_id_compra_origen, p_id_forma_pago, v_con, p_usuario)
                returning id_compra into p_id_compra;
            exception
                when dup_val_on_index then
                    raise_application_error(-20080,
                        'Ya existe la factura ' || v_folio || ' de este proveedor.');
            end;
        else
            begin
                select estado, tipo_cambio into v_estado, v_tasa_ant
                  from compras where id_compra = p_id_compra;
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
                       id_forma_pago = p_id_forma_pago,
                       -- Centinela: -1 (el defecto) deja el concepto que ya tenia la
                       -- compra; 0 o nulo lo borran (sin concepto); otro pone ese
                       -- concepto. Es lo que cierra la fuga de guardar un borrador y
                       -- perder el ISLR.
                       id_concepto_islr = case when p_id_concepto_islr = -1
                                             then id_concepto_islr
                                             else nullif(p_id_concepto_islr, 0) end,
                       modificado_por = p_usuario, fecha_modificacion = systimestamp
                 where id_compra = p_id_compra
                   -- Defensa en profundidad: el documento tiene que ser de la empresa
                   -- que se esta guardando. El id llega del navegador y no esta
                   -- protegido; sin este predicado un POST con el id de una compra ajena
                   -- la reescribia y le cambiaba la empresa.
                   and id_empresa = p_id_empresa;
                if sql%rowcount = 0 then
                    raise_application_error(-20003,
                        'No tiene permisos sobre esta compra.');
                end if;
            exception
                when dup_val_on_index then
                    raise_application_error(-20080,
                        'Ya existe la factura ' || v_folio || ' de este proveedor.');
            end;

            -- Si la TASA de la cabecera cambio en un borrador, el detalle se queda con
            -- la vieja y los dos comprobantes salen en monedas distintas: el de IVA usa
            -- la tasa de la LINEA (compras_det.tasa_cambio_aplicada) y el de ISLR la de
            -- la CABECERA. Se reprecian las lineas del borrador en el mismo guardado;
            -- un documento que ya no es BORRADOR no llega aqui (arriba se corta).
            if nvl(v_tasa_ant, 1) <> nvl(v_tasa, 1) then
                update compras_det set tasa_cambio_aplicada = v_tasa,
                       subtotal_bs = round(nvl(subtotal_linea, 0) * v_tasa, 2),
                       total_bs = round(nvl(total_linea, 0) * v_tasa, 2)
                 where id_compra = p_id_compra;
            end if;
        end if;
    end prc_guardar_compra;

    procedure prc_registrar_compra(p_id_compra in number, p_usuario in varchar2) is
        v_estado  varchar2(20);
        v_tipo    varchar2(10);
        v_empresa number;
        v_lineas  number;
        v_idret   number;
        v_es_spe  varchar2(1);
        v_genera  varchar2(1);
        v_moneda  varchar2(3);
        v_tc      number;
        v_total   number;
        v_dias    number;
        v_igtf    number;
    begin
        select estado, nvl(tipo_documento, 'FAC'), id_empresa
          into v_estado, v_tipo, v_empresa
          from compras where id_compra = p_id_compra for update;

        -- La compra es de OTRA empresa si el usuario no la administra. Se valida en el
        -- package y ANTES de tocar nada: registrar quema la numeracion de ESA empresa
        -- (los comprobantes de IVA e ISLR consumen RETENCION_CONTADOR) y el id llega
        -- del navegador sin proteger. Los procesos de la pagina solo miran el rol.
        if not fn_usuario_empresa_valida(p_usuario, v_empresa) then
            raise_application_error(-20003, 'No tiene permisos sobre esta compra.');
        end if;

        if v_estado <> 'BORRADOR' then
            raise_application_error(-20083,
                'La compra esta ' || v_estado || ': no se puede registrar.');
        end if;

        select count(*) into v_lineas from compras_det where id_compra = p_id_compra;
        if v_lineas = 0 then
            raise_application_error(-20085,
                'La compra no tiene lineas: agrega al menos una antes de registrarla.');
        end if;

        -- Fotos historicas (2026-11-21): el IGTF del documento y el vencimiento se
        -- congelan AHORA. Cambiar despues la marca SPE, la forma de pago o la tasa
        -- del dia no puede mover la deuda de un documento ya cerrado.
        select nvl(e.es_spe, 'N'), nvl(c.cod_moneda, 'VES'),
               nvl(nullif(c.tipo_cambio, 0), 1), nvl(c.monto_total, 0),
               nvl(fp.genera_igtf, 'N'), nvl(p.dias_credito, 0)
          into v_es_spe, v_moneda, v_tc, v_total, v_genera, v_dias
          from compras c
          join empresas e on e.id_empresa = c.id_empresa
          left join forma_pago fp on fp.id_forma_pago = c.id_forma_pago
          left join proveedores p on p.id_proveedor = c.id_proveedor
         where c.id_compra = p_id_compra;

        v_igtf := 0;
        if v_es_spe = 'S' and v_genera = 'S'
           and upper(v_moneda) not in ('VES', 'BS') then
            v_igtf := round(round(v_total * nvl(fn_alicuota_igtf(v_empresa), 0) / 100, 2) * v_tc, 2);
        end if;

        update compras set estado = 'REGISTRADA', igtf_bs = v_igtf, fecha_vencimiento = nvl(fecha_vencimiento, nvl(fecha_emision, trunc(sysdate)) + v_dias), modificado_por = p_usuario, fecha_modificacion = systimestamp where id_compra = p_id_compra;

        -- SOLO LAS FACTURAS EMITEN COMPROBANTE (decision del dueno, 2026-11-19): una
        -- nota de credito o de debito no emite, no consume numeracion y no toca el
        -- comprobante de la factura original. Antes la nota emitia un comprobante de
        -- IVA por el importe de la nota y en positivo, lo que sobre-retiene.
        if v_tipo = 'FAC' then
            pkg_retenciones.prc_emitir(p_id_compra, v_idret, p_usuario);
            pkg_retenciones.prc_emitir_islr(p_id_compra, v_idret, p_usuario);
        else
            -- Una nota cambia la deuda de la factura que acredita (2026-11-22):
            -- su estado se recalcula aqui o quedaria PAGADA con saldo pendiente.
            declare
                v_origen number;
            begin
                select c.id_compra_origen into v_origen
                  from compras c where c.id_compra = p_id_compra;
                pkg_pagos.prc_recalcular_compra(v_origen);
            exception
                when no_data_found then
                    null;
            end;
        end if;
    exception
        when no_data_found then
            raise_application_error(-20085, 'La compra ' || p_id_compra || ' no existe.');
    end prc_registrar_compra;

    procedure prc_anular_compra(p_id_compra in number, p_usuario in varchar2) is
        v_estado  varchar2(20);
        v_empresa number;
        v_pagos   number;
    begin
        select estado, id_empresa into v_estado, v_empresa
          from compras where id_compra = p_id_compra for update;

        -- Anular es escritura: sin esta guarda un POST con el id de una compra ajena
        -- la anulaba (y de paso los comprobantes de retencion de esa empresa).
        if not fn_usuario_empresa_valida(p_usuario, v_empresa) then
            raise_application_error(-20003, 'No tiene permisos sobre esta compra.');
        end if;

        if v_estado = 'ANULADA' then
            return;
        end if;

        -- Con dinero de por medio no se anula a ciegas (2026-11-21): si hay pagos
        -- vivos, primero se anulan ellos (que liberan las compras).
        select count(*) into v_pagos
          from pagos_detalle d
          join pagos pg on pg.id_pago = d.id_pago
         where d.id_compra = p_id_compra
           and pg.estado = 'ACTIVO';

        if v_pagos > 0 then
            raise_application_error(-20118,
                'La compra ' || p_id_compra || ' tiene ' || v_pagos
                || ' pagos activos. Anulalos primero para poder anular la compra.');
        end if;

        update compras set estado = 'ANULADA', modificado_por = p_usuario,
               fecha_modificacion = systimestamp
         where id_compra = p_id_compra;

        pkg_retenciones.prc_anular(p_id_compra, p_usuario);

        -- si era una nota, la factura que acreditaba vuelve a estar pendiente
        declare
            v_origen number;
        begin
            select c.id_compra_origen into v_origen
              from compras c where c.id_compra = p_id_compra;
            pkg_pagos.prc_recalcular_compra(v_origen);
        exception
            when no_data_found then
                null;
        end;
    exception
        when no_data_found then
            raise_application_error(-20085, 'La compra ' || p_id_compra || ' no existe.');
    end prc_anular_compra;

end pkg_compras;
/
