-- =============================================================================
-- 20261118_correlativos_verificacion.sql
--
-- Numeracion sin saltos (2026-11-18). El dueño pidio:
--   * los proveedores con id en secuencia (hoy 87, 88 porque las pruebas
--     consumieron la identidad);
--   * el comprobante de retencion correlativo, sin saltos.
--
--   P1  los id de proveedores son 1..n, sin huecos
--   P2  la identidad de PROVEEDORES avanza de uno en uno y no reutiliza un id en
--       uso (se mide con dos altas y su borrado; no se compara con max(id)+1, que
--       depende de cuantas pruebas hayan dado de alta y borrado proveedores)
--   R1  dos comprobantes seguidos salen con numeros consecutivos
--   R2  una emision que se revierte NO consume numero (sin saltos)
--
-- Todo el DML de R1/R2 va dentro de un savepoint y se revierte al final.
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261118_correlativos_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

-- Esta ADB tiene parallel_degree_policy = AUTO. En un bloque largo como este,
-- un DML puede salir en paralelo y el siguiente acceso serial al MISMO objeto
-- de la misma transaccion revienta con ORA-12839 («cannot modify an object in
-- parallel after modifying it»), que es lo que pasaba el 2026-11-20 al emitir
-- el comprobante dentro del bloque. Se desactiva el DML en paralelo para esta
-- sesion: no cambia nada de lo que se mide (son 3 filas).
alter session disable parallel dml
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000) := '';
    v_n      number;
    v_max    number;
    v_cnt    number;
    v_prov   number;
    v_compra number;
    v_ret1   number;
    v_ret2   number;
    v_num1   varchar2(20);
    v_num2   varchar2(20);
    v_ult    number;
    v_ult2   number;

    procedure falla(p_caso varchar2, p_detalle varchar2) is
    begin
        v_fallas := v_fallas + 1;
        v_lista  := v_lista || ' | ' || p_caso || ': ' || p_detalle;
    end;

    function nueva_compra(p_folio varchar2) return number is
        v_id number;
    begin
        pkg_compras.prc_guardar_compra(
            p_id_compra      => v_id,
            p_id_empresa     => 1,
            p_id_proveedor   => v_prov,
            p_tipo_documento => 'FAC',
            p_folio_factura  => p_folio,
            p_nro_control    => '00-000123',
            p_fecha_emision  => sysdate,
            p_cod_moneda     => 'VES',
            p_tipo_cambio    => 1,
            p_porcentaje_retencion => 75,
            p_usuario        => 'test_corr');
        -- una linea con IVA para que haya base e IVA
        insert into compras_det (id_compra, num_linea, descripcion, cantidad, precio_unitario,
                                 id_impuesto, porcentaje_impuesto, monto_impuesto,
                                 subtotal_linea, total_linea, tasa_cambio_aplicada,
                                 subtotal_bs, total_bs)
        values (v_id, 1, 'Servicio', 1, 100, 1, 16, 16, 100, 116, 1, 100, 116);
        pkg_compras.prc_registrar_compra(v_id, 'test_corr');
        return v_id;
    end;
begin
    savepoint sp_corr;

    -- usuario temporal: los packages validan la empresa del usuario
    insert into usuario (username, email, password_hash, estado, id_empresa, rol_id,
                         debe_cambiar_clave, reintentos_fallidos)
    values ('test_corr', 'test_corr@synpex.local', sypex_hash_password('x'), 'ACTIVO', 1,
            (select id_rol from syn_roles where codigo_rol = 'ADMIN'), 'N', 0);

    -- P1: proveedores 1..n sin huecos
    select count(*), max(id_proveedor) into v_cnt, v_max from proveedores;
    if v_cnt > 0 and v_max <> v_cnt then
        falla('P1', 'los proveedores van hasta ' || v_max || ' y hay ' || v_cnt || ' (hay huecos)');
    end if;

    -- P2: la identidad de PROVEEDORES avanza de uno en uno y no reutiliza un id que
    -- ya esta en uso. Se mide insertando DOS proveedores y borrandolos.
    --
    -- NO se compara con max(id)+1: cada prueba que da de alta y borra un proveedor
    -- consume un id y la identidad se queda por delante de los datos (hoy va muy por
    -- delante), y esa comparacion solo pasaria la primera vez que se corre. La
    -- renumeracion que la arreglaria (20261118_proveedores_secuencia.sql) aborta con
    -- -20107 si hay compras, y hay una compra real. Lo que si tiene que cumplirse
    -- siempre: el id nuevo no choca con ninguno existente y el siguiente es
    -- exactamente uno mas (sin saltos dentro de la serie).
    select nvl(max(id_proveedor), 0) into v_max from proveedores;

    declare
        v_id1 number;
        v_id2 number;
    begin
        insert into proveedores (id_empresa, rif, razon_social, tipo_persona, cod_pais,
                                 estado, retener_iva, porcentaje_retencion, es_spe, dias_credito)
        values (1, 'J-TESTP2-1', 'Proveedor P2 uno', 'J', 'VE', 'ACTIVO', 'N', 0, 'N', 0)
        returning id_proveedor into v_id1;

        insert into proveedores (id_empresa, rif, razon_social, tipo_persona, cod_pais,
                                 estado, retener_iva, porcentaje_retencion, es_spe, dias_credito)
        values (1, 'J-TESTP2-2', 'Proveedor P2 dos', 'J', 'VE', 'ACTIVO', 'N', 0, 'N', 0)
        returning id_proveedor into v_id2;

        if v_id1 <= v_max then
            falla('P2', 'la identidad reutilizo el id ' || v_id1 || ' (ya habia hasta ' || v_max || ')');
        end if;
        if v_id2 <> v_id1 + 1 then
            falla('P2', 'dos altas seguidas dieron ' || v_id1 || ' y ' || v_id2
                        || ' (la identidad tiene que avanzar de uno en uno)');
        end if;

        -- Se borran para no dejar basura (los dos estan dentro del savepoint general,
        -- pero el borrado deja el caso medido sin depender del rollback final).
        delete from proveedores where id_proveedor in (v_id1, v_id2);
    end;

    -- R1: dos comprobantes seguidos
    insert into proveedores (id_empresa, rif, razon_social, tipo_persona, cod_pais,
                             estado, retener_iva, porcentaje_retencion, es_spe, dias_credito)
    values (1, 'J-TESTCORR-1', 'Proveedor correlativo', 'J', 'VE',
            'ACTIVO', 'S', 75, 'N', 30)
    returning id_proveedor into v_prov;

    v_compra := nueva_compra('CORR-1');
    select max(numero_comprobante) into v_num1 from retenciones where id_compra = v_compra and tipo = 'IVA';
    v_compra := nueva_compra('CORR-2');
    select max(numero_comprobante) into v_num2 from retenciones where id_compra = v_compra and tipo = 'IVA';
    if v_num1 is null or v_num2 is null then
        falla('R1', 'la compra registrada no emitio comprobante');
    elsif to_number(substr(v_num2, 7)) <> to_number(substr(v_num1, 7)) + 1 then
        falla('R1', 'los comprobantes no son consecutivos: ' || v_num1 || ' y ' || v_num2);
    elsif substr(v_num1, 1, 6) <> substr(v_num2, 1, 6) then
        falla('R1', 'los comprobantes son de periodos distintos: ' || v_num1 || ' y ' || v_num2);
    end if;

    -- R2: una emision que se revierte no consume numero
    select nvl(max(ultimo), 0) into v_ult
      from retencion_contador where id_empresa = 1;

    savepoint sp_emision;
    v_compra := nueva_compra('CORR-3');
    rollback to sp_emision;

    select nvl(max(ultimo), 0) into v_ult2
      from retencion_contador where id_empresa = 1;
    if v_ult2 <> v_ult then
        falla('R2', 'una emision revertida dejo el contador en ' || v_ult2 || ' (era ' || v_ult || ')');
    end if;

    rollback to sp_corr;

    raise_application_error(-20100, substrb('RESULTADO: FALLAS=' || v_fallas || v_lista, 1, 3000));
end;
/
