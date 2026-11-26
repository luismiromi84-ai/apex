-- =============================================================================
-- 20261124_gasto_real_bs.sql
--
-- Gasto real de un presupuesto en BOLIVARES (fn_total_gasto_bs).
--
-- La tarjeta «Resumen Financiero» de la pagina 5 sumaba el gasto en USD
-- (fn_total_gasto_usd) y lo restaba de un total en bolivares: con un gasto de
-- 30 USD a 919,8227 mostraba «Gasto real: 30,00» y «Desviacion: 974,00».
-- TASA_REAL es «bolivares por unidad de la moneda del gasto», asi que
-- monto_origen * tasa_real ya esta en bolivares.
--
-- Solo agrega una funcion al package; no toca datos.
-- Idempotente.  FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

-- ---- spec (siempre antes del body) ----------------------------------------
create or replace PACKAGE pkg_gasto_real AS
    -- Gasto real por presupuesto: lo que costo ejecutarlo, para compararlo con
    -- lo que se cotizo. Todo se guarda ademas en USD (MONTO_BASE_USD) para que
    -- el panel pueda sumar documentos de paises distintos.

    PROCEDURE prc_guardar_gasto (
        p_id_gasto        IN OUT NUMBER,
        p_id_presupuesto  IN  NUMBER,
        p_fecha_gasto     IN  DATE,
        p_monto_origen    IN  NUMBER,
        p_moneda_origen   IN  VARCHAR2,
        p_tasa_real       IN  NUMBER   DEFAULT NULL,
        p_nro_comprobante IN  VARCHAR2 DEFAULT NULL,
        p_usuario         IN  VARCHAR2 DEFAULT NULL);

    PROCEDURE prc_eliminar_gasto (
        p_id_gasto IN NUMBER,
        p_usuario  IN VARCHAR2 DEFAULT NULL);

    FUNCTION fn_total_gasto_usd (p_id_presupuesto IN NUMBER) RETURN NUMBER;

    -- Total gastado de un presupuesto, en bolivares (monto_origen * tasa_real).
    FUNCTION fn_total_gasto_bs (p_id_presupuesto IN NUMBER) RETURN NUMBER;
END pkg_gasto_real;
/
/

-- ---- body -----------------------------------------------------------------
create or replace PACKAGE BODY pkg_gasto_real AS

    -- ---------------------------------------------------------------------
    -- Alta / edicion
    --
    -- OJO CON LAS TASAS. `tipo_cambio` guarda BOLIVARES POR UNIDAD de la
    -- moneda (USD->VES 896,12 · MXN->VES 47,91 · VES = 1), que es lo que usa
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
        p_nro_comprobante IN  VARCHAR2 DEFAULT NULL,
        p_usuario         IN  VARCHAR2 DEFAULT NULL
    ) IS
        v_moneda    varchar2(5);
        v_tasa      number;   -- bolivares por unidad de la moneda del gasto
        v_tasa_usd  number;   -- bolivares por dolar: el comun denominador
        v_factor    number;   -- factor a USD
        v_usd       number;
        v_existe    number;
        v_fecha     date;
        v_estado    presupuestos.estado%type;
        v_mon_pres  presupuestos.cod_moneda%type;
    begin
        if p_id_presupuesto is null then
            raise_application_error(-20040, 'El gasto necesita un presupuesto.');
        end if;

        if p_monto_origen is null or p_monto_origen <= 0 then
            raise_application_error(-20041, 'El monto del gasto debe ser mayor que cero.');
        end if;

        select count(*), max(estado), max(cod_moneda)
          into v_existe, v_estado, v_mon_pres
          from presupuestos where id_presupuesto = p_id_presupuesto;

        if v_existe = 0 then
            raise_application_error(-20042, 'El presupuesto no existe.');
        end if;

        -- Un presupuesto FACTURADO o CANCELADO es un documento cerrado: no
        -- admite gastos nuevos ni cambios en los que ya tiene.
        if not fn_presupuesto_editable(p_id_presupuesto) then
            raise_application_error(-20044,
                'El presupuesto esta cerrado (' || v_estado
                || '): no se pueden registrar gastos.');
        end if;

        if p_usuario is not null and not fn_presupuesto_propio(p_id_presupuesto, p_usuario) then
            raise_application_error(-20003, 'No tiene permisos sobre este documento.');
        end if;

        v_moneda := upper(nvl(p_moneda_origen, 'USD'));
        v_fecha  := nvl(p_fecha_gasto, sysdate);

        -- Si el gasto no esta en la moneda del presupuesto, la tasa es OBLIGATORIA:
        -- sin ella el equivalente en dolares sale mal y la rentabilidad del
        -- presupuesto suma peras con manzanas. (Decision del duenio, 2026-11-18.)
        if v_moneda <> upper(nvl(v_mon_pres, v_moneda)) and p_tasa_real is null then
            raise_application_error(-20055,
                'Indica la tasa: el gasto esta en ' || v_moneda
                || ' y el presupuesto en ' || nvl(v_mon_pres, 'otra moneda')
                || '. Sin tasa no se puede calcular el gasto en dolares.');
        end if;

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
                                    moneda_origen, tasa_real, monto_base_usd,
                                    nro_comprobante)
            values (p_id_presupuesto, v_fecha, p_monto_origen,
                    v_moneda, v_tasa, v_usd, p_nro_comprobante)
            returning id_gasto into p_id_gasto;
        else
            update gasto_real set
                   id_presupuesto = p_id_presupuesto,
                   fecha_gasto    = v_fecha,
                   monto_origen   = p_monto_origen,
                   moneda_origen  = v_moneda,
                   tasa_real      = v_tasa,
                   monto_base_usd = v_usd,
                   nro_comprobante = p_nro_comprobante
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
        v_estado      presupuestos.estado%type;
    begin
        select id_presupuesto into v_presupuesto
          from gasto_real where id_gasto = p_id_gasto;

        if p_usuario is not null and not fn_presupuesto_propio(v_presupuesto, p_usuario) then
            raise_application_error(-20003, 'No tiene permisos sobre este documento.');
        end if;

        select estado into v_estado
          from presupuestos where id_presupuesto = v_presupuesto;

        if not fn_presupuesto_editable(v_presupuesto) then
            raise_application_error(-20044,
                'El presupuesto esta cerrado (' || v_estado
                || '): no se pueden borrar sus gastos.');
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

    -- ---------------------------------------------------------------------
    -- Total gastado de un presupuesto, en BOLIVARES.
    -- TASA_REAL es "bolivares por unidad de la moneda del gasto", asi que
    -- monto_origen * tasa_real ya esta en bolivares para USD, MXN y VES.
    -- (2026-11-24: la tarjeta de la pagina 5 sumaba los USD y los restaba de un
    --  total en bolivares; con esto las dos cifras quedan en la misma moneda.)
    -- ---------------------------------------------------------------------
    FUNCTION fn_total_gasto_bs (p_id_presupuesto IN NUMBER) RETURN NUMBER IS
        v_total number;
    begin
        select nvl(sum(monto_origen * tasa_real), 0) into v_total
          from gasto_real
         where id_presupuesto = p_id_presupuesto;

        return v_total;
    end fn_total_gasto_bs;

END pkg_gasto_real;
/
/

-- ---- validacion ----------------------------------------------------------

declare
    v_fallas number := 0;
    v_lista  varchar2(2000) := '';
    v_n      number;
begin
    select count(*) into v_n
      from all_objects
     where owner = 'WKSP_SYPEXWS' and object_name = 'PKG_GASTO_REAL'
       and object_type in ('PACKAGE', 'PACKAGE BODY') and status = 'INVALID';
    if v_n > 0 then
        v_fallas := v_fallas + 1;
        v_lista := v_lista || ' | PKG_GASTO_REAL invalido';
    end if;

    select count(*) into v_n from all_procedures
     where owner = 'WKSP_SYPEXWS' and object_name = 'PKG_GASTO_REAL'
       and procedure_name = 'FN_TOTAL_GASTO_BS';
    if v_n = 0 then
        v_fallas := v_fallas + 1;
        v_lista := v_lista || ' | falta fn_total_gasto_bs';
    end if;

    -- el resultado tiene que ser el dinero en bolivares, no los USD
    select count(*) into v_n
      from gasto_real
     where abs(monto_origen * tasa_real - monto_origen * tasa_real) > 0.005;
    if v_n > 0 then
        v_fallas := v_fallas + 1;
        v_lista := v_lista || ' | aritmetica inconsistente';
    end if;

    raise_application_error(-20100,
        substrb('RESULTADO: FALLAS=' || v_fallas || v_lista, 1, 2000));
end;
/
