-- =============================================================================
-- 20261122_favor_pantalla_verificacion.sql
--
-- "Usar saldo a favor" en la pantalla del pago (2026-11-22). El credito del
-- proveedor ya se podia consumir por la API (pkg_pagos.prc_usar_favor); lo que
-- falta es ofrecerlo en la pagina 37.
--
--   F1  pkg_pagos.fn_favor_disponible existe y esta VALIDA
--   F2  el credito disponible es SOLO el de pagos ACTIVOS y NO conciliados (es
--       el conjunto que consume prc_usar_favor); el conciliado no se ofrece
--   F3  la region de facturas abiertas de la 37 pinta el credito del proveedor
--       y un enlace "Usar" por fila (spxUsarFavor)
--   F4  existe el item oculto P37_FAVOR_COMPRA
--   F5  existe el proceso usar-favor, con REQUEST = USAR_FAVOR, y llama a
--       pkg_pagos.prc_usar_favor
--   F6  de punta a punta: usar el favor aplica el credito a la compra, baja su
--       saldo y la deja Abonada, sin tocar el pago conciliado
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261122_favor_pantalla_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000) := '';
    v_src    clob;
    v_n      number;
    v_val    number;

    procedure falla(p_caso varchar2, p_detalle varchar2) is
    begin
        v_fallas := v_fallas + 1;
        v_lista  := v_lista || ' | ' || p_caso || ': ' || substrb(p_detalle, 1, 170);
    end;
begin
    ------------------------------------------------------------------ F1 / F2
    begin
        -- Datos de prueba: un proveedor con un pago CONCILIADO de 100 y un
        -- anticipo (no conciliado) de 40. Todo dentro de un savepoint.
        savepoint sp_favor;
        declare
            v_prov number;
            v_p1   number;
            v_p2   number;
            v_comp number;
            v_apl  number;
            v_sal  number;
            v_est  varchar2(20);
            v_fav1 number;
            v_disp number;
            v_tot  number;
        begin
            insert into proveedores (id_empresa, rif, razon_social)
            values (1, 'FAV-TEST-1', 'Proveedor de prueba del credito')
            returning id_proveedor into v_prov;

            insert into pagos (id_empresa, id_proveedor, fecha_pago, cod_moneda, tipo_cambio,
                               monto, monto_bs, conciliado, estado, creado_por)
            values (1, v_prov, sysdate, 'VES', 1, 100, 100, 'S', 'ACTIVO', 'VERIF')
            returning id_pago into v_p1;

            insert into pagos (id_empresa, id_proveedor, fecha_pago, cod_moneda, tipo_cambio,
                               monto, monto_bs, conciliado, estado, creado_por)
            values (1, v_prov, sysdate, 'VES', 1, 40, 40, 'N', 'ACTIVO', 'VERIF')
            returning id_pago into v_p2;

            -- F1: la funcion existe (llamada dinamica: asi el bloque compila aunque
            -- todavia no exista, y el rojo es FALLA y no un PLS-00201 sin FALLAS).
            begin
                execute immediate 'select pkg_pagos.fn_favor_disponible(:1, :2) from dual'
                  into v_disp using v_prov, 'VES';
            exception
                when others then
                    falla('F1', sqlerrm);
                    v_disp := null;
            end;
            if v_disp is null then
                falla('F1', 'pkg_pagos.fn_favor_disponible no responde');
            end if;

            -- F2: solo el no conciliado.
            if v_disp is not null and nvl(v_disp, -1) <> 40 then
                falla('F2', 'el credito disponible es ' || v_disp || ' y deberia ser 40');
            end if;

            v_tot := pkg_pagos.fn_saldo_favor_proveedor(v_prov, 'VES');
            if nvl(v_tot, -1) <> 140 then
                falla('F2', 'fn_saldo_favor_proveedor es ' || v_tot || ' y deberia ser 140');
            end if;

            -- F6: usar el favor contra una factura de 100.
            insert into compras (id_empresa, id_proveedor, tipo_documento, folio_factura,
                                 fecha_emision, cod_moneda, tipo_cambio, monto_total, estado)
            values (1, v_prov, 'FAC', 'FAV-TEST-1', sysdate, 'VES', 1, 100, 'REGISTRADA')
            returning id_compra into v_comp;

            pkg_pagos.prc_usar_favor(v_prov, v_comp, 'admin', v_apl);
            if nvl(v_apl, -1) <> 40 then
                falla('F6', 'se aplicaron ' || v_apl || ' y deberian ser 40');
            end if;
            v_sal := fn_saldo_compra(v_comp);
            if v_sal <> 60 then
                falla('F6', 'el saldo de la compra quedo en ' || v_sal || ' y deberia ser 60');
            end if;
            select estado into v_est from compras where id_compra = v_comp;
            if v_est <> 'PARCIAL' then
                falla('F6', 'la compra quedo ' || v_est || ' y deberia quedar PARCIAL');
            end if;
            v_fav1 := pkg_pagos.fn_saldo_favor_proveedor(v_prov, 'VES');
            if v_fav1 <> 100 then
                falla('F6', 'quedo ' || v_fav1 || ' de favor y deberia quedar 100 (el conciliado)');
            end if;

            -- Fuera de la pantalla no debe haber quedado nada.
            rollback to sp_favor;
        end;
    exception
        when others then
            rollback to sp_favor;
            falla('F6', sqlerrm);
    end;

    ------------------------------------------------------------------ F3
    begin
        select region_source into v_src
          from apex_application_page_regions
         where application_id = 100 and page_id = 37
           and region_id = 43000000000001591;
        if instr(v_src, 'Credito del proveedor') = 0 then
            falla('F3', 'la tabla de facturas abiertas no muestra el credito del proveedor');
        end if;
        if instr(v_src, 'spxUsarFavor') = 0 then
            falla('F3', 'no hay enlace Usar (spxUsarFavor) por fila');
        end if;
        if instr(v_src, 'fn_favor_disponible') = 0 then
            falla('F3', 'la region no usa pkg_pagos.fn_favor_disponible');
        end if;
    exception
        when others then
            falla('F3', sqlerrm);
    end;

    ------------------------------------------------------------------ F4
    begin
        select count(*) into v_n
          from apex_application_page_items
         where application_id = 100 and page_id = 37
           and item_name = 'P37_FAVOR_COMPRA';
        if v_n <> 1 then
            falla('F4', 'no existe el item P37_FAVOR_COMPRA');
        end if;
    exception
        when others then
            falla('F4', sqlerrm);
    end;

    ------------------------------------------------------------------ F5
    begin
        select count(*) into v_n
          from apex_application_page_proc
         where application_id = 100 and page_id = 37
           and static_id = 'usar-favor'
           and instr(upper(process_source), 'PRC_USAR_FAVOR') > 0
           and instr(upper(process_source), 'USAR_FAVOR') > 0;
        if v_n <> 1 then
            falla('F5', 'no existe el proceso usar-favor (o no llama a prc_usar_favor)');
        end if;
    exception
        when others then
            falla('F5', sqlerrm);
    end;

    raise_application_error(-20100,
        substrb('RESULTADO: FALLAS=' || v_fallas || v_lista, 1, 3000));
end;
/
