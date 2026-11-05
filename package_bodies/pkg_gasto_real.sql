create or replace PACKAGE BODY pkg_gasto_real AS

    -- ---------------------------------------------------------------------
    -- Alta / edicion
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
        v_moneda varchar2(5);
        v_tasa   number;
        v_usd    number;
        v_existe number;
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

        if v_moneda = 'USD' then
            v_tasa := 1;
        else
            v_tasa := nvl(p_tasa_real,
                          fn_tasa_cambio(nvl(p_fecha_gasto, sysdate), v_moneda));
        end if;

        v_usd := round(p_monto_origen * nvl(v_tasa, 1), 2);

        if p_id_gasto is null then
            insert into gasto_real (id_presupuesto, fecha_gasto, monto_origen,
                                    moneda_origen, tasa_real, monto_base_usd)
            values (p_id_presupuesto, nvl(p_fecha_gasto, sysdate), p_monto_origen,
                    v_moneda, nvl(v_tasa, 1), v_usd)
            returning id_gasto into p_id_gasto;
        else
            update gasto_real set
                   id_presupuesto = p_id_presupuesto,
                   fecha_gasto    = nvl(p_fecha_gasto, sysdate),
                   monto_origen   = p_monto_origen,
                   moneda_origen  = v_moneda,
                   tasa_real      = nvl(v_tasa, 1),
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
