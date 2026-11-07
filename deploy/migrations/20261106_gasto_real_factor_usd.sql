-- =============================================================================
-- 20261106_gasto_real_factor_usd.sql
--
-- Arregla la conversion a dolares de PKG_GASTO_REAL.
--
-- El bug: prc_guardar_gasto hacia `monto_base_usd = monto * tasa`, pero la tasa
-- de `tipo_cambio` es BOLIVARES POR UNIDAD de la moneda (USD->VES 896,12 ·
-- MXN->VES 47,91 · VES = 1). Resultado:
--     * 100 Bs   -> 100 USD      (1.000 veces su valor; el correcto es 0,11)
--     * 100 MXN  -> 4.791,07 USD (el correcto es 5,35)
--     * 100 USD  -> 100 USD      (el unico caso que acertaba)
--
-- Ahora: factor_usd = tasa_moneda_a_ves / tasa_usd_a_ves.
-- `tasa_real` guarda la tasa contra el bolivar que se aplico (la forzada o la
-- de la tabla), igual que `presupuestos.tipo_cambio`; para USD es Bs por dolar.
-- Si no hay tasa para la moneda, o no hay tasa USD->VES, lanza -20060 en vez de
-- inventarse un 1.
--
-- `GASTO_REAL` estaba vacia al aplicar esto (0 filas), asi que no hay datos que
-- migrar. Si tuviera filas, `monto_base_usd` habria que recalcularlo.
--
-- Solo cambia el BODY: la especificacion y la firma son las mismas.
--
-- Reversa: recompilar el body de `deploy/migrations/20261105_gasto_real.sql`.
--
-- Validacion al final: 0 objetos invalidos y
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261105_gasto_real_verificacion.sql
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/
create or replace PACKAGE BODY pkg_gasto_real AS

    -- ---------------------------------------------------------------------
    -- Alta / edicion
    --
    -- OJO CON LAS TASAS. `tipo_cambio` guarda BOLIVARES POR UNIDAD de la
    -- moneda (USD->VES 896,12 Â· MXN->VES 47,91 Â· VES = 1), que es lo que usa
    -- facturacion para los montos en Bs. NO es un factor a USD. Por eso el
    -- equivalente en dolares es:
    --
    --     factor_usd     = tasa_moneda_a_ves / tasa_usd_a_ves
    --     monto_base_usd = round(monto_origen * factor_usd, 2)
    --
    -- Hasta el 2026-11-05 aqui se hacia `monto * tasa`, asi que 100 Bs se
    -- guardaban como 100 USD (1.000 veces su valor) y 100 MXN como 4.791,07
    -- USD en vez de 5,35. Solo acertaba con gastos en dolares.
    --
    -- `tasa_real` guarda la tasa CONTRA EL BOLIVAR que se aplico (la forzada o
    -- la de la tabla), igual que `presupuestos.tipo_cambio`, para que la
    -- pantalla muestre el mismo numero que se tecleo. Para USD es Bs por dolar
    -- y el factor es exactamente 1.
    -- ---------------------------------------------------------------------
    PROCEDURE prc_guardar_gasto (
        p_id_gasto        IN OUT NUMBER,
        p_id_presupuesto  IN  NUMBER,
        p_fecha_gasto     IN  DATE,
        p_monto_origen    IN  NUMBER,
        p_moneda_origen   IN  VARCHAR2,
        p_tasa_real       IN  NUMBER   DEFAULT NULL,
        p_usuario         IN  VARCHAR2 DEFAULT NULL
    ) IS
        v_moneda    varchar2(5);
        v_tasa      number;   -- bolivares por unidad de la moneda del gasto
        v_tasa_usd  number;   -- bolivares por dolar: el comun denominador
        v_factor    number;   -- factor a USD
        v_usd       number;
        v_existe    number;
        v_fecha     date;
    begin
        if p_id_presupuesto is null then
            raise_application_error(-20040, 'El gasto necesita un presupuesto.');
        end if;

        if p_monto_origen is null or p_monto_origen <= 0 then
            raise_application_error(-20041, 'El monto del gasto debe ser mayor que cero.');
        end if;

        select count(*) into v_existe
          from presupuestos where id_presupuesto = p_id_presupuesto;

        if v_existe = 0 then
            raise_application_error(-20042, 'El presupuesto no existe.');
        end if;

        if p_usuario is not null and not fn_presupuesto_propio(p_id_presupuesto, p_usuario) then
            raise_application_error(-20003, 'No tiene permisos sobre este documento.');
        end if;

        v_moneda := upper(nvl(p_moneda_origen, 'USD'));
        v_fecha  := nvl(p_fecha_gasto, sysdate);

        if v_moneda = 'USD' then
            -- El dolar es la moneda base: el factor es 1 por definicion. La
            -- tasa del dia se guarda solo como dato (Bs por dolar); una tasa
            -- tecleada a mano no se usa, para no falsear el equivalente.
            v_tasa   := nvl(fn_tasa_ves(v_fecha, 'USD'), 1);
            v_factor := 1;
        else
            v_tasa := nvl(p_tasa_real, fn_tasa_ves(v_fecha, v_moneda));

            if v_tasa is null then
                raise_application_error(-20060,
                    'No hay tasa de cambio para ' || v_moneda || ' al '
                    || to_char(v_fecha, 'DD/MM/YYYY')
                    || '. Registrala antes de guardar el gasto.');
            end if;

            v_tasa_usd := fn_tasa_ves(v_fecha, 'USD');

            if v_tasa_usd is null or v_tasa_usd = 0 then
                raise_application_error(-20060,
                    'No hay tasa de cambio USD a bolivares al '
                    || to_char(v_fecha, 'DD/MM/YYYY')
                    || '. Sin ella no se puede calcular el equivalente en dolares.');
            end if;

            v_factor := v_tasa / v_tasa_usd;
        end if;

        v_usd := round(p_monto_origen * v_factor, 2);

        if p_id_gasto is null then
            insert into gasto_real (id_presupuesto, fecha_gasto, monto_origen,
                                    moneda_origen, tasa_real, monto_base_usd)
            values (p_id_presupuesto, v_fecha, p_monto_origen,
                    v_moneda, v_tasa, v_usd)
            returning id_gasto into p_id_gasto;
        else
            update gasto_real set
                   id_presupuesto = p_id_presupuesto,
                   fecha_gasto    = v_fecha,
                   monto_origen   = p_monto_origen,
                   moneda_origen  = v_moneda,
                   tasa_real      = v_tasa,
                   monto_base_usd = v_usd
             where id_gasto = p_id_gasto;

            if sql%rowcount = 0 then
                raise_application_error(-20043, 'El gasto no existe.');
            end if;
        end if;
    end prc_guardar_gasto;

    -- ---------------------------------------------------------------------
    -- Baja
    -- ---------------------------------------------------------------------
    PROCEDURE prc_eliminar_gasto (
        p_id_gasto IN NUMBER,
        p_usuario  IN VARCHAR2 DEFAULT NULL
    ) IS
        v_presupuesto number;
    begin
        select id_presupuesto into v_presupuesto
          from gasto_real where id_gasto = p_id_gasto;

        if p_usuario is not null and not fn_presupuesto_propio(v_presupuesto, p_usuario) then
            raise_application_error(-20003, 'No tiene permisos sobre este documento.');
        end if;

        delete from gasto_real where id_gasto = p_id_gasto;

    exception
        when no_data_found then
            raise_application_error(-20043, 'El gasto no existe.');
    end prc_eliminar_gasto;

    -- ---------------------------------------------------------------------
    -- Total gastado de un presupuesto, en USD
    -- ---------------------------------------------------------------------
    FUNCTION fn_total_gasto_usd (p_id_presupuesto IN NUMBER) RETURN NUMBER IS
        v_total number;
    begin
        select nvl(sum(monto_base_usd), 0) into v_total
          from gasto_real
         where id_presupuesto = p_id_presupuesto;

        return v_total;
    end fn_total_gasto_usd;

END pkg_gasto_real;
/

-- Recompila el esquema: tocar un body puede dejar dependientes en INVALID.
begin
    dbms_utility.compile_schema('WKSP_SYPEXWS', false);
end;
/
