-- =============================================================================
-- 20261123_secuencias_verificacion.sql
--
-- Pestana «Secuencias» de Administracion (2026-11-23): el tope del maximo real,
-- el fijado desde la pantalla y la resincronizacion.
--
--   S1  fn_maximo_real devuelve el maximo de PRESUPUESTO
--   S2  ... y el de FAC (sufijo numerico de F-n)
--   S3  ... y el del codigo de barras del catalogo
--   S4  las series del proveedor no tienen tope (NULL)
--   S5  la vista previa de CONTROL sale con la forma de la providencia
--   S6  fijar por debajo del maximo real se rechaza con -20140
--   S7  fijar por encima mueve el contador y el siguiente sale con su formato
--   S8  un usuario que no es ADMIN recibe -20003
--   S9  resincronizar deja el contador en el maximo real
--   S10 resincronizar una serie del proveedor se rechaza con -20142
--   S11 la pestana existe en la 19, con su guarda, el informe y los dos botones
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261123_secuencias_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000) := '';
    v_n      number;
    v_otro   number;
    v_txt    varchar2(60);
    v_esp    varchar2(60);

    procedure falla(p_caso varchar2, p_detalle varchar2) is
    begin
        v_fallas := v_fallas + 1;
        v_lista  := v_lista || ' | ' || p_caso || ': ' || substrb(p_detalle, 1, 170);
    end;

    procedure espera_num(p_caso varchar2, p_valor number, p_esperado number) is
    begin
        if (p_valor is null and p_esperado is not null)
           or (p_valor is not null and (p_esperado is null or p_valor <> p_esperado)) then
            falla(p_caso, 'esperaba ' || nvl(to_char(p_esperado), 'NULL')
                      || ' y hay ' || nvl(to_char(p_valor), 'NULL'));
        end if;
    end;

    procedure espera_txt(p_caso varchar2, p_valor varchar2, p_esperado varchar2) is
    begin
        if (p_valor is null and p_esperado is not null)
           or (p_valor is not null and (p_esperado is null or p_valor <> p_esperado)) then
            falla(p_caso, 'esperaba ' || nvl(p_esperado, 'NULL')
                      || ' y hay ' || nvl(p_valor, 'NULL'));
        end if;
    end;
begin
    ------------------------------------------------------------------ S1
    select nvl(max(folio), 0) into v_n
      from presupuestos where id_empresa = 1 and regexp_like(folio, '^[0-9]+$');
    espera_num('S1 maximo real de PRESUPUESTO', fn_maximo_real(1, 'PRESUPUESTO'), v_n);

    ------------------------------------------------------------------ S2
    select nvl(max(to_number(regexp_substr(folio_factura, '[0-9]+$'))), 0) into v_n
      from facturas where id_empresa = 1 and regexp_like(folio_factura, '^F-[0-9]+$');
    espera_num('S2 maximo real de FAC', fn_maximo_real(1, 'FAC'), v_n);

    ------------------------------------------------------------------ S3
    -- ARTICULO: la serie guarda el contador, no el codigo (10000011 -> 11).
    select nvl(max(to_number(codigo_barras)) - 10000000, 0) into v_n
      from producto_servicio
     where id_empresa = 1 and regexp_like(codigo_barras, '^[0-9]+$')
       and to_number(codigo_barras) > 10000000;
    espera_num('S3 maximo real de ARTICULO en unidades del contador',
               fn_maximo_real(1, 'ARTICULO'), v_n);
    if nvl(fn_maximo_real(1, 'ARTICULO'), 0) >= 10000000 then
        falla('S3 ARTICULO no puede devolver el codigo de barras',
              to_char(fn_maximo_real(1, 'ARTICULO')));
    end if;
    if not regexp_like(fn_siguiente_folio(1, 'ARTICULO'), '^[0-9]{8}$') then
        falla('S3 el siguiente codigo de barras tiene 8 digitos',
              fn_siguiente_folio(1, 'ARTICULO'));
    end if;

    ------------------------------------------------------------------ S3b
    -- Los codigos viejos del catalogo (SERV-001) no son de la serie nueva.
    select nvl(max(to_number(regexp_substr(codigo, '[0-9]+$'))), 0) into v_n
      from producto_servicio
     where id_empresa = 1 and regexp_like(codigo, '^SERV-[0-9]{5}$');
    espera_num('S3b la serie SERV solo cuenta la forma nueva de 5 digitos',
               fn_maximo_real(1, 'SERV'), v_n);

    savepoint s3b;
    begin
        insert into producto_servicio (id_empresa, codigo, codigo_barras, nombre, tipo)
        values (1, 'SERV-777', '19999999', 'PRUEBA SERIE VIEJA', 'SERVICIO');
        espera_num('S3b un codigo viejo no empuja la serie',
                   fn_maximo_real(1, 'SERV'), v_n);
    exception
        when others then
            falla('S3b un codigo viejo no empuja la serie', sqlerrm);
    end;
    rollback to savepoint s3b;

    ------------------------------------------------------------------ S4
    if fn_maximo_real(1, 'FAC_PROV') is not null or fn_maximo_real(1, 'CONTROL_PROV') is not null then
        falla('S4 las series del proveedor no tienen tope', 'devolvio un maximo');
    end if;

    ------------------------------------------------------------------ S5
    -- La vista previa de CONTROL tiene que salir con el prefijo y el ancho del
    -- rango configurado en la empresa (no con una forma fija: la 1 lo tiene
    -- como 000001 y otra empresa puede tenerlo como 00-000001).
    declare
        v_desde varchar2(30);
        v_ancho pls_integer;
        v_pref  varchar2(30);
    begin
        select control_desde into v_desde
          from empresa_fiscal where id_empresa = 1;
        if v_desde is not null then
            v_ancho := length(regexp_substr(v_desde, '[0-9]+$'));
            v_pref  := substr(v_desde, 1, length(v_desde) - v_ancho);
            v_txt   := fn_siguiente_folio(1, 'CONTROL');
            if v_txt is null
               or length(v_txt) <> length(v_desde)
               or substr(v_txt, 1, length(v_pref)) <> v_pref then
                falla('S5 la vista previa de CONTROL', nvl(v_txt, 'NULL') || ' para el rango ' || v_desde);
            end if;
        end if;
    exception
        when no_data_found then null;
    end;

    ------------------------------------------------------------------ S6
    savepoint s6;
    begin
        prc_fijar_secuencia(1, 'FAC', fn_maximo_real(1, 'FAC') - 1, 'admin');
        falla('S6 fijar por debajo del maximo real', 'no lo rechazo');
    exception
        when others then
            if sqlcode <> -20140 then
                falla('S6 fijar por debajo del maximo real', 'codigo ' || sqlcode || ': ' || sqlerrm);
            end if;
    end;
    rollback to savepoint s6;

    ------------------------------------------------------------------ S7
    savepoint s7;
    begin
        v_otro := nvl(fn_maximo_real(1, 'PROD'), 0) + 4;
        prc_fijar_secuencia(1, 'PROD', v_otro, 'admin');
        v_esp := 'PROD-' || lpad(to_char(v_otro + 1), 5, '0');
        v_txt := fn_siguiente_folio(1, 'PROD');
        select ultimo into v_n from folio_contador where id_empresa = 1 and tipo = 'PROD';
        espera_num('S7 el contador queda en el valor fijado', v_n, v_otro);
        espera_txt('S7 el siguiente sale con su formato', v_txt, v_esp);
    exception
        when others then
            falla('S7 fijar por encima', sqlcode || ': ' || sqlerrm);
    end;
    rollback to savepoint s7;

    ------------------------------------------------------------------ S8
    savepoint s8;
    begin
        prc_fijar_secuencia(1, 'PROD', 1, 'no.existe.este.usuario');
        falla('S8 un usuario sin ADMIN no fija', 'no lo rechazo');
    exception
        when others then
            if sqlcode <> -20003 then
                falla('S8 un usuario sin ADMIN no fija', 'codigo ' || sqlcode);
            end if;
    end;
    rollback to savepoint s8;

    ------------------------------------------------------------------ S9
    savepoint s9;
    begin
        update folio_contador set ultimo = ultimo + 7 where id_empresa = 1 and tipo = 'ARTICULO';
        prc_resincronizar_secuencia(1, 'ARTICULO', 'admin');
        v_esp := to_char(fn_maximo_real(1, 'ARTICULO'));
        select to_char(ultimo) into v_txt from folio_contador where id_empresa = 1 and tipo = 'ARTICULO';
        espera_txt('S9 resincronizar deja el maximo real', v_txt, v_esp);
    exception
        when others then
            falla('S9 resincronizar', sqlcode || ': ' || sqlerrm);
    end;
    rollback to savepoint s9;

    ------------------------------------------------------------------ S10
    savepoint s10;
    begin
        prc_resincronizar_secuencia(1, 'FAC_PROV', 'admin');
        falla('S10 resincronizar una serie del proveedor', 'no lo rechazo');
    exception
        when others then
            if sqlcode <> -20142 then
                falla('S10 resincronizar una serie del proveedor', 'codigo ' || sqlcode);
            end if;
    end;
    rollback to savepoint s10;

    ------------------------------------------------------------------ S11
    select count(*) into v_n
      from apex_application_page_regions
     where application_id = 100 and page_id = 19 and region_static_id = 'admin-secuencias'
       and display_region_selector = 'Yes';
    espera_num('S11 la pestana esta en el selector', v_n, 1);

    select count(*) into v_n
      from apex_application_page_regions
     where application_id = 100 and page_id = 19 and region_static_id = 'admin-secuencias'
       and upper(condition_expression1) like '%ADMIN%';
    espera_num('S11 la pestana es solo de ADMIN', v_n, 1);

    select count(*) into v_n
      from apex_application_page_items
     where application_id = 100 and page_id = 19
       and item_name in ('P19S_SERIE', 'P19S_ULTIMO')
       and region_id = 43000000000001900;
    espera_num('S11 los dos campos, dentro de la pestana', v_n, 2);

    select count(*) into v_n
      from apex_application_page_buttons
     where application_id = 100 and page_id = 19
       and button_name in ('BTN_FIJA_SERIE', 'BTN_RESINC_SERIE')
       and condition_expression1 like '%ADMIN%';
    espera_num('S11 los dos botones con su rol', v_n, 2);

    select count(*) into v_n
      from apex_application_page_proc
     where application_id = 100 and page_id = 19
       and static_id in ('fija-siguiente', 'resincroniza-serie');
    espera_num('S11 los dos procesos', v_n, 2);

    ------------------------------------------------------------- resultado
    if v_fallas = 0 then
        raise_application_error(-20100, 'RESULTADO: FALLAS=0');
    else
        raise_application_error(-20101, 'RESULTADO: FALLAS=' || v_fallas || v_lista);
    end if;
exception
    when others then
        if sqlcode in (-20100, -20101) then
            raise;
        end if;
        raise_application_error(-20102, 'RESULTADO: FALLAS=1 excepcion: ' || sqlerrm);
end;
/
