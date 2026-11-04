create or replace procedure prc_actualizar_tasas_diarias is
    v_response   clob;
    v_tasa_usd   number;
    v_tasa_eur   number;
    v_tasa_mxn   number;
    v_usd_mxn    number;
    v_eff        varchar2(10);
    v_fecha      date;
begin
    -- 1. Tasas oficiales BCV (USD, EUR)
    v_response := apex_web_service.make_rest_request(
        p_url         => 'https://bcv.today/api/v1/rate.json',
        p_http_method => 'GET'
    );
    apex_json.parse(v_response);

    v_tasa_usd := apex_json.get_number(p_path => 'USD');
    v_tasa_eur := apex_json.get_number(p_path => 'EUR');
    v_eff      := apex_json.get_varchar2(p_path => 'effective_date');
    v_fecha    := to_date(v_eff, 'YYYY-MM-DD');

    -- 2. USD/MXN desde frankfurter.app (libre, sin clave); si falla, parámetro
    begin
        v_response := apex_web_service.make_rest_request(
            p_url         => 'https://api.frankfurter.app/latest?from=USD&to=MXN',
            p_http_method => 'GET'
        );
        apex_json.parse(v_response);
        v_usd_mxn := apex_json.get_number(p_path => 'rates.MXN');
    exception
        when others then
            v_usd_mxn := null;
    end;

    if v_usd_mxn is null then
        begin
            select valor into v_usd_mxn from syn_parametros where clave = 'USD_MXN';
        exception
            when no_data_found then v_usd_mxn := null;
        end;
    end if;

    -- 3. MXN -> VES por cruce: (VES/USD) / (MXN/USD)
    if v_usd_mxn is not null and v_usd_mxn > 0 then
        v_tasa_mxn := round(v_tasa_usd / v_usd_mxn, 6);
    end if;

    -- 4. USD -> VES
    merge into tipo_cambio target
    using (select 'USD' as moneda_origen, 'VES' as moneda_destino, 'REAL' as tipo_tasa,
                  v_tasa_usd as tasa_cambio, v_fecha as fecha_vigencia from dual) src
       on (target.moneda_origen = src.moneda_origen
           and target.moneda_destino = src.moneda_destino
           and target.tipo_tasa = src.tipo_tasa
           and target.fecha_vigencia = src.fecha_vigencia)
     when matched then update set target.tasa_cambio = src.tasa_cambio
     when not matched then
        insert (moneda_origen, moneda_destino, tipo_tasa, tasa_cambio, fecha_vigencia)
        values (src.moneda_origen, src.moneda_destino, src.tipo_tasa, src.tasa_cambio, src.fecha_vigencia);

    -- 5. EUR -> VES
    merge into tipo_cambio target
    using (select 'EUR' as moneda_origen, 'VES' as moneda_destino, 'REAL' as tipo_tasa,
                  v_tasa_eur as tasa_cambio, v_fecha as fecha_vigencia from dual) src
       on (target.moneda_origen = src.moneda_origen
           and target.moneda_destino = src.moneda_destino
           and target.tipo_tasa = src.tipo_tasa
           and target.fecha_vigencia = src.fecha_vigencia)
     when matched then update set target.tasa_cambio = src.tasa_cambio
     when not matched then
        insert (moneda_origen, moneda_destino, tipo_tasa, tasa_cambio, fecha_vigencia)
        values (src.moneda_origen, src.moneda_destino, src.tipo_tasa, src.tasa_cambio, src.fecha_vigencia);

    -- 6. MXN -> VES (si se pudo calcular)
    if v_tasa_mxn is not null then
        merge into tipo_cambio target
        using (select 'MXN' as moneda_origen, 'VES' as moneda_destino, 'REAL' as tipo_tasa,
                      v_tasa_mxn as tasa_cambio, v_fecha as fecha_vigencia from dual) src
           on (target.moneda_origen = src.moneda_origen
               and target.moneda_destino = src.moneda_destino
               and target.tipo_tasa = src.tipo_tasa
               and target.fecha_vigencia = src.fecha_vigencia)
         when matched then update set target.tasa_cambio = src.tasa_cambio
         when not matched then
            insert (moneda_origen, moneda_destino, tipo_tasa, tasa_cambio, fecha_vigencia)
            values (src.moneda_origen, src.moneda_destino, src.tipo_tasa, src.tasa_cambio, src.fecha_vigencia);
    end if;
end prc_actualizar_tasas_diarias;
