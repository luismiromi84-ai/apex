-- =============================================================================
-- 20261119_compra_nota_afectada_verificacion.sql
--
-- Nota de credito/debito de COMPRA: tiene que decir que factura afecta
-- (requisito de la providencia del SENIAT). pkg_compras lo exige con -20097 y
-- comprueba que sea una FAC de la misma empresa.
--
--   V1 una NC sin factura afectada se rechaza (-20097)
--   V2 una NC con una FAC de la misma empresa se guarda
--   V3 una NC que apunta a una compra de otra empresa se rechaza (-20097)
--   V4 una ND con factura afectada tambien se guarda
--
-- Y desde el 2026-11-20 la nota TRAE las lineas de la factura que acredita
-- (pkg_compra_detalle.copiar_desde_compra, boton "Traer lineas" de la 28) de
-- forma IDEMPOTENTE: se puede pulsar las veces que haga falta.
--
--   V5  la nota copia las lineas de la factura, con ID_DETALLE_ORIGEN relleno
--   V6  una segunda pasada NO duplica: agrega 0 y dice cuantas ya estaban
--   V7  una linea tecleada a mano sobrevive a otra pasada
--   V8  si se borra una copia, la pasada siguiente trae SOLO la que falta
--   V9  lineas copiadas de OTRA factura se rechazan (-20045)
--   V10 copiar en una compra de OTRA empresa se rechaza (-20003)
--   V11 copiar de una fuente que no es una FAC se rechaza (-20046)
--
-- Todo va dentro de un SAVEPOINT y se revierte.
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261119_compra_nota_afectada_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000) := '';
    v_prov   number;
    v_fac    number;
    v_fac2   number;
    v_otra   number;
    v_nc     number;
    v_nd     number;
    v_nc2    number;
    v_id     number;
    v_n      number;
    v_add    number;
    v_ya     number;
    v_msg    varchar2(300);

    procedure falla(p_caso varchar2, p_detalle varchar2) is
    begin
        v_fallas := v_fallas + 1;
        v_lista  := v_lista || ' | ' || p_caso || ': ' || substrb(p_detalle, 1, 140);
    end;

    function guarda(p_tipo varchar2, p_folio varchar2, p_origen number) return number is
        v_new number;
    begin
        pkg_compras.prc_guardar_compra(
            p_id_compra        => v_new,
            p_id_empresa       => 1,
            p_id_proveedor     => v_prov,
            p_tipo_documento   => p_tipo,
            p_folio_factura    => p_folio,
            p_nro_control      => '00-000991',
            p_fecha_emision    => trunc(sysdate),
            p_cod_moneda       => 'VES',
            p_tipo_cambio      => 1,
            p_porcentaje_retencion => 75,
            p_id_compra_origen => p_origen,
            p_usuario          => 'admin');
        return 0;
    exception
        when others then
            v_msg := sqlerrm;
            return sqlcode;
    end;

    -- Devuelve 0 o el sqlcode, y deja en p_add / p_ya lo que diga el paquete.
    -- Si falla, se quedan en -1 (los OUT no se copian cuando hay excepcion).
    function copia(p_destino number, p_origen number, p_add out number, p_ya out number)
        return number is
    begin
        p_add := -1;
        p_ya  := -1;
        pkg_compra_detalle.copiar_desde_compra(
            p_id_compra        => p_destino,
            p_id_compra_origen => p_origen,
            p_usuario          => 'admin',
            p_agregadas        => p_add,
            p_ya_estaban       => p_ya);
        return 0;
    exception
        when others then
            v_msg := sqlerrm;
            return sqlcode;
    end;

    procedure lineas(p_compra number, p_caso varchar2, p_esperadas number) is
    begin
        select count(*) into v_n from compras_det where id_compra = p_compra;
        if v_n <> p_esperadas then
            falla(p_caso, 'la nota tiene ' || v_n || ' lineas y se esperaban ' || p_esperadas);
        end if;
    end;
begin
    savepoint sp_nota;

    insert into proveedores (id_empresa, rif, razon_social, cod_pais)
    values (1, 'J-TESTNOTA-1', 'Proveedor de la nota', 'VE')
    returning id_proveedor into v_prov;

    -- una factura de compra de la misma empresa
    insert into compras (id_empresa, id_proveedor, tipo_documento, folio_factura,
                         nro_control, fecha_emision, cod_moneda, tipo_cambio,
                         porcentaje_retencion, estado)
    values (1, v_prov, 'FAC', 'NOTA-1', '00-000900', trunc(sysdate), 'VES', 1, 75, 'REGISTRADA')
    returning id_compra into v_fac;

    -- y otra de OTRA empresa (2), para el caso cruzado
    insert into compras (id_empresa, id_proveedor, tipo_documento, folio_factura,
                         nro_control, fecha_emision, cod_moneda, tipo_cambio,
                         porcentaje_retencion, estado)
    values (2, v_prov, 'FAC', 'NOTA-2', '00-000901', trunc(sysdate), 'VES', 1, 0, 'REGISTRADA')
    returning id_compra into v_otra;

    -- V1
    if guarda('NC', 'NC-SIN', null) <> -20097 then
        falla('V1', 'acepto una NC sin factura afectada (' || v_msg || ')');
    end if;

    -- V2
    if guarda('NC', 'NC-OK', v_fac) <> 0 then
        falla('V2', 'no dejo guardar la NC con su factura (' || v_msg || ')');
    end if;

    -- V3
    if guarda('NC', 'NC-CRUZ', v_otra) <> -20097 then
        falla('V3', 'acepto una NC apuntando a una compra de otra empresa (' || v_msg || ')');
    end if;

    -- V4
    if guarda('ND', 'ND-OK', v_fac) <> 0 then
        falla('V4', 'no dejo guardar la ND con su factura (' || v_msg || ')');
    end if;

    -- =====================================================================
    -- Traer las lineas de la factura que acredita (2026-11-20)
    -- =====================================================================
    -- dos lineas en la factura, para que el copiado tenga algo que traer
    insert into compras_det (id_compra, num_linea, descripcion, cantidad, precio_unitario,
                             porcentaje_descuento, monto_descuento, porcentaje_impuesto,
                             monto_impuesto, subtotal_linea, total_linea)
    values (v_fac, 1, 'Linea uno de la factura', 1, 100, 0, 0, 16, 16, 100, 116);
    insert into compras_det (id_compra, num_linea, descripcion, cantidad, precio_unitario,
                             porcentaje_descuento, monto_descuento, porcentaje_impuesto,
                             monto_impuesto, subtotal_linea, total_linea)
    values (v_fac, 2, 'Linea dos de la factura', 2, 50, 0, 0, 16, 16, 100, 116);

    select max(id_compra) into v_nc from compras where folio_factura = 'NC-OK';
    select max(id_compra) into v_nd from compras where folio_factura = 'ND-OK';

    -- V5: la nota trae las dos lineas y cada una apunta a la original
    if copia(v_nc, v_fac, v_add, v_ya) <> 0 then
        falla('V5', 'no dejo copiar las lineas de la factura (' || v_msg || ')');
    else
        if v_add <> 2 or v_ya <> 0 then
            falla('V5a', 'la primera copia agrego ' || v_add || ' y ya estaban ' || v_ya);
        end if;
        lineas(v_nc, 'V5b', 2);
        select count(*) into v_n
          from compras_det d
         where d.id_compra = v_nc
           and d.id_detalle_origen in (select o.id_detalle
                                         from compras_det o
                                        where o.id_compra = v_fac);
        if v_n <> 2 then
            falla('V5c', 'las lineas copiadas no apuntan a la factura (' || v_n || ' de 2)');
        end if;
    end if;

    -- V6: la segunda pasada NO duplica ni lanza: agrega 0 y avisa que ya estaban
    if copia(v_nc, v_fac, v_add, v_ya) <> 0 then
        falla('V6', 'la segunda pasada fallo en vez de no hacer nada (' || v_msg || ')');
    else
        if v_add <> 0 or v_ya <> 2 then
            falla('V6a', 'la segunda pasada agrego ' || v_add || ' y ya estaban ' || v_ya);
        end if;
        lineas(v_nc, 'V6b', 2);
    end if;

    -- V7: una linea tecleada a mano no se toca ni desaparece
    insert into compras_det (id_compra, num_linea, descripcion, cantidad, precio_unitario,
                             porcentaje_descuento, monto_descuento, porcentaje_impuesto,
                             monto_impuesto, subtotal_linea, total_linea)
    values (v_nc, 99, 'Linea a mano del usuario', 3, 10, 0, 0, 16, 4.8, 30, 34.8);
    if copia(v_nc, v_fac, v_add, v_ya) <> 0 then
        falla('V7', 'copiar con una linea a mano fallo (' || v_msg || ')');
    else
        if v_add <> 0 then
            falla('V7a', 'la pasada agrego ' || v_add || ' lineas con la nota ya completa');
        end if;
        lineas(v_nc, 'V7b', 3);
        select count(*) into v_n
          from compras_det
         where id_compra = v_nc
           and id_detalle_origen is null
           and descripcion = 'Linea a mano del usuario'
           and cantidad = 3;
        if v_n <> 1 then
            falla('V7c', 'la linea a mano no sobrevivio como se tecleo');
        end if;
    end if;

    -- V8: si se borra una copia, la pasada siguiente trae SOLO la que falta
    delete from compras_det
     where id_compra = v_nc
       and id_detalle_origen in (select o.id_detalle
                                   from compras_det o
                                  where o.id_compra = v_fac
                                    and o.num_linea = 1);
    lineas(v_nc, 'V8a', 2);
    if copia(v_nc, v_fac, v_add, v_ya) <> 0 then
        falla('V8', 'no pudo reponer la linea que faltaba (' || v_msg || ')');
    else
        if v_add <> 1 or v_ya <> 1 then
            falla('V8b', 'la reposicion agrego ' || v_add || ' y ya estaban ' || v_ya);
        end if;
        lineas(v_nc, 'V8c', 3);
    end if;

    -- V9: lineas copiadas de OTRA factura -> -20045 (una nota acredita UNA factura)
    insert into compras (id_empresa, id_proveedor, tipo_documento, folio_factura,
                         nro_control, fecha_emision, cod_moneda, tipo_cambio,
                         porcentaje_retencion, estado)
    values (1, v_prov, 'FAC', 'NOTA-3', '00-000902', trunc(sysdate), 'VES', 1, 75, 'REGISTRADA')
    returning id_compra into v_fac2;
    insert into compras_det (id_compra, num_linea, descripcion, cantidad, precio_unitario,
                             porcentaje_descuento, monto_descuento, porcentaje_impuesto,
                             monto_impuesto, subtotal_linea, total_linea)
    values (v_fac2, 1, 'Linea de la otra factura', 1, 70, 0, 0, 16, 11.2, 70, 81.2);
    if guarda('NC', 'NC-DOS', v_fac2) <> 0 then
        falla('V9-pre', 'no dejo guardar la nota de la segunda factura (' || v_msg || ')');
    else
        select max(id_compra) into v_nc2 from compras where folio_factura = 'NC-DOS';
        if copia(v_nc2, v_fac2, v_add, v_ya) <> 0 then
            falla('V9-pre2', 'no dejo copiar la segunda factura (' || v_msg || ')');
        elsif copia(v_nc2, v_fac, v_add, v_ya) <> -20045 then
            falla('V9', 'acepto mezclar dos facturas en la misma nota (' || v_msg || ')');
        end if;
    end if;

    -- V10: la compra destino es de otra empresa
    if copia(v_otra, v_fac, v_add, v_ya) <> -20003 then
        falla('V10', 'acepto copiar en una compra de otra empresa (' || v_msg || ')');
    end if;

    -- V11: la fuente no es una FAC (es una nota de credito)
    if copia(v_nd, v_nc, v_add, v_ya) <> -20046 then
        falla('V11', 'acepto copiar de una fuente que no es una FAC (' || v_msg || ')');
    end if;

    rollback to sp_nota;

    raise_application_error(-20100,
        substrb('RESULTADO: FALLAS=' || v_fallas || v_lista, 1, 3000));
end;
/
