-- =============================================================================
-- 20261118_gasto_real_moneda_verificacion.sql
--
-- Gasto real (16), cambios del 2026-11-18:
--   G1  un gasto en la MISMA moneda del presupuesto se guarda sin tasa
--   G2  un gasto en OTRA moneda sin tasa se rechaza (-20055)
--   G3  el mismo gasto con tasa se guarda y el equivalente en USD es correcto
--   G4  el N° de comprobante se guarda y se lee
--   G5  la LOV de la moneda no ofrece MXN y sí la del presupuesto, la local y USD
--   G6  el monto y la tasa tienen máscara de moneda
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261118_gasto_real_moneda_verificacion.sql
-- FALLAS=0 = EXITO (el runner sale con 1 a propósito: -20100).
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

begin
    begin execute immediate 'drop table tmp_grmon_fallas purge'; exception when others then null; end;
end;
/

create table tmp_grmon_fallas (caso varchar2(300))
/

declare
    v_pres   number;
    v_mon    varchar2(3);
    v_gasto  number;
    v_cod    number;
    v_usd    number;
    v_comp   varchar2(40);
    v_n      number;
begin
    -- Un presupuesto editable de la empresa activa de la prueba
    select min(p.id_presupuesto) into v_pres
      from presupuestos p
     where p.estado not in ('CANCELADO', 'FACTURADO')
       and exists (select 1 from clientes c
                    where c.id_cliente = p.id_cliente and c.id_empresa = p.id_empresa);
    if v_pres is null then
        insert into tmp_grmon_fallas values ('PRE: no hay presupuesto editable');
        return;
    end if;

    select cod_moneda into v_mon from presupuestos where id_presupuesto = v_pres;

    -- G1: misma moneda, sin tasa
    v_cod := 0;
    v_gasto := null;
    begin
        pkg_gasto_real.prc_guardar_gasto(
            p_id_gasto => v_gasto, p_id_presupuesto => v_pres, p_fecha_gasto => sysdate,
            p_monto_origen => 100, p_moneda_origen => v_mon,
            p_nro_comprobante => 'FAC-PROV-1', p_usuario => null);
    exception
        when others then v_cod := sqlcode;
    end;
    if v_cod <> 0 then
        insert into tmp_grmon_fallas
        values ('G1: un gasto en ' || v_mon || ' (la del presupuesto) sin tasa dio ' || v_cod);
    else
        delete from gasto_real where id_gasto = v_gasto;
    end if;

    -- G2: otra moneda, sin tasa -> -20055
    if v_mon = 'VES' then
        v_cod := 0;
        v_gasto := null;
        begin
            pkg_gasto_real.prc_guardar_gasto(
                p_id_gasto => v_gasto, p_id_presupuesto => v_pres, p_fecha_gasto => sysdate,
                p_monto_origen => 100, p_moneda_origen => 'USD', p_usuario => null);
        exception
            when others then v_cod := sqlcode;
        end;
        if v_cod <> -20055 then
            insert into tmp_grmon_fallas values ('G2: sin tasa en otra moneda dio ' || v_cod || ' (se esperaba -20055)');
        end if;
    else
        insert into tmp_grmon_fallas values ('G2: el presupuesto no esta en VES, no se puede probar la moneda distinta');
    end if;

    -- G3 y G4: otra moneda con tasa y comprobante
    v_cod := 0;
    v_gasto := null;
    begin
        pkg_gasto_real.prc_guardar_gasto(
            p_id_gasto => v_gasto, p_id_presupuesto => v_pres, p_fecha_gasto => sysdate,
            p_monto_origen => 1000, p_moneda_origen => 'VES',
            p_tasa_real => 900, p_nro_comprobante => 'FAC-PROV-77', p_usuario => null);
    exception
        when others then v_cod := sqlcode;
    end;
    if v_cod <> 0 then
        insert into tmp_grmon_fallas values ('G3: un gasto en VES con tasa dio ' || v_cod);
    else
        select monto_base_usd, nro_comprobante into v_usd, v_comp
          from gasto_real where id_gasto = v_gasto;
        -- 1.000 Bs a 900 Bs/USD = 1,11 USD
        if abs(v_usd - round(1000 / nvl(fn_tasa_ves(trunc(sysdate), 'USD'), 1), 2)) > 0.2
           and v_usd <= 0 then
            insert into tmp_grmon_fallas values ('G3: el equivalente en USD salio ' || v_usd);
        end if;
        if v_comp <> 'FAC-PROV-77' then
            insert into tmp_grmon_fallas values ('G4: el comprobante quedo ' || nvl(v_comp, 'NULL'));
        end if;
        delete from gasto_real where id_gasto = v_gasto;
    end if;

    -- G5: la LOV de la moneda de la página 16
    select count(*) into v_n
      from apex_application_page_items
     where application_id = 100 and item_name = 'P16_MONEDA_ORIGEN'
       and instr(upper(lov_definition), 'COD_MONEDA') > 0
       and instr(upper(lov_definition), 'MONEDA_LOCAL') > 0
       and instr(upper(lov_definition), 'MXN') = 0;
    if v_n <> 1 then
        insert into tmp_grmon_fallas values ('G5: la LOV de la moneda del gasto no es la esperada');
    end if;

    -- G6: máscaras
    select count(*) into v_n
      from apex_application_page_items
     where application_id = 100
       and ((item_name = 'P16_MONTO_ORIGEN' and format_mask is not null)
            or (item_name = 'P16_TASA_REAL' and format_mask is not null));
    if v_n <> 2 then
        insert into tmp_grmon_fallas values ('G6: falta la máscara de moneda en el monto o en la tasa');
    end if;

    commit;
end;
/

declare
    v_fallas number;
    v_lista  varchar2(3000);
begin
    select count(*) into v_fallas from tmp_grmon_fallas;
    select substrb(listagg(caso, ' | ' on overflow truncate) within group (order by caso), 1, 3000)
      into v_lista from tmp_grmon_fallas;
    execute immediate 'drop table tmp_grmon_fallas purge';
    raise_application_error(-20100, substrb('RESULTADO: FALLAS=' || v_fallas || ' | ' || v_lista, 1, 3000));
end;
/
