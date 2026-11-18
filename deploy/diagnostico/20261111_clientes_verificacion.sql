-- =============================================================================
-- 20261111_clientes_verificacion.sql
--
-- Modulo de Clientes (2026-11-11): tipo de persona y RIF/RFC por pais y tipo.
--
-- Contrato del repo: no devuelve filas cuando todo va bien; el detalle viaja en
-- el mensaje de -20100.  FALLAS=0 es exito (el runner sale con codigo 1 igual).
--
-- Casos:
--   C1  J-30123456-0  VE juridica   -> valido
--   C2  V-12345678-9  VE natural    -> valido
--   C3  E-12345678-9  VE natural    -> valido
--   C4  J-...         VE natural    -> invalido
--   C5  V-...         VE juridica   -> invalido
--   C6  'abc'         VE juridica   -> invalido
--   C7  nulo/vacio    VE juridica   -> invalido
--   C8  MXE850101AB1  MX juridica   -> valido (12)
--   C9  MXE850101AB   MX juridica   -> invalido (11)
--   C10 MXEA850101AB1 MX natural    -> valido (13)
--   C11 alta y edicion con TIPO_PERSONA en la empresa 1
--   C12 el CHECK rechaza un tipo que no sea J/N
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;
/

declare
    v_fallas  number := 0;
    v_lista   varchar2(3000) := '';
    v_id      number;
    v_tipo    varchar2(1);
    v_n       number;

    procedure falla (p_caso in varchar2, p_detalle in varchar2) is
    begin
        v_fallas := v_fallas + 1;
        v_lista  := v_lista || ' | ' || p_caso || ': ' || p_detalle;
    end falla;

    procedure espera (p_caso varchar2, p_ok boolean, p_esperado boolean) is
    begin
        if p_ok <> p_esperado then
            falla(p_caso, 'devolvio ' || case when p_ok then 'valido' else 'invalido' end);
        end if;
    end;
begin
    espera('C1',  fn_rif_cliente_valido('J-30123456-0',  'VE', 'J'), true);
    espera('C13', fn_rif_cliente_valido('V12345678-9',   'VE', 'N'), true);
    espera('C14', fn_rif_cliente_valido('v12345678-9',   'VE', 'N'), true);
    espera('C15', fn_rif_cliente_valido('J12345678-9',   'VE', 'N'), false);
    espera('C16', fn_rif_cliente_valido('J-6454545',     'VE', 'J'), false);
    espera('C17', fn_rif_cliente_valido('V76554445677',  'VE', 'N'), false);
    espera('C2',  fn_rif_cliente_valido('V-12345678-9',  'VE', 'N'), true);
    espera('C3',  fn_rif_cliente_valido('E-12345678-9',  'VE', 'N'), true);
    espera('C4',  fn_rif_cliente_valido('J-30123456-0',  'VE', 'N'), false);
    espera('C5',  fn_rif_cliente_valido('V-12345678-9',  'VE', 'J'), false);
    espera('C6',  fn_rif_cliente_valido('abc',           'VE', 'J'), false);
    espera('C7a', fn_rif_cliente_valido(null,            'VE', 'J'), false);
    espera('C7b', fn_rif_cliente_valido('   ',           'VE', 'J'), false);
    espera('C8',  fn_rif_cliente_valido('MXE850101AB1',  'MX', 'J'), true);
    espera('C9',  fn_rif_cliente_valido('MXE850101AB',   'MX', 'J'), false);
    espera('C10', fn_rif_cliente_valido('MXEA850101AB1', 'MX', 'N'), true);

    -- 2026-11-19: el RIF de persona natural es la cedula (6 a 8 digitos) mas el
    -- digito verificador, asi que despues de la letra puede haber 7, 8 o 9
    -- digitos. Exigir exactamente 9 rechazaba cedulas de 7 digitos con
    -- verificador (V-4666778-9, reportado por el dueno en Proveedores).
    espera('C21', fn_rif_cliente_valido('V-4666778-9',   'VE', 'N'), true);
    espera('C22', fn_rif_cliente_valido('V-9877766',     'VE', 'N'), true);
    espera('C23', fn_rif_cliente_valido('J-1234567-8',   'VE', 'J'), false);
    espera('C24', fn_rif_cliente_valido('E-31234567-4',  'VE', 'N'), true);

    -- C11: alta y edicion con el tipo de persona
    insert into clientes (id_empresa, rif, razon_social, tipo_persona, cod_pais, estado)
    values (1, 'V-90000001-1', 'CLIENTE DE PRUEBA', 'N', 'VE', 'ACTIVO')
    returning id_cliente into v_id;
    commit;
    select tipo_persona into v_tipo from clientes where id_cliente = v_id;
    if v_tipo <> 'N' then
        falla('C11', 'el alta no guardo el tipo (' || v_tipo || ')');
    end if;
    update clientes set tipo_persona = 'J', rif = 'J-90000001-1' where id_cliente = v_id;
    commit;
    select count(*) into v_n from clientes
     where id_cliente = v_id and tipo_persona = 'J' and rif = 'J-90000001-1';
    if v_n <> 1 then
        falla('C11', 'la edicion no cambio tipo y RIF');
    end if;
    delete from clientes where id_cliente = v_id;
    commit;

    -- C12: el CHECK del tipo
    begin
        insert into clientes (id_empresa, rif, razon_social, tipo_persona, cod_pais, estado)
        values (1, 'X-90000002-2', 'TIPO MALO', 'X', 'VE', 'ACTIVO');
        falla('C12', 'acepto un tipo de persona X');
    exception
        when others then
            null;
    end;

    -- C16: la trampa que dejo el alta sin insertar (2026-11-11): fn_clean_num(NULL)
    -- devuelve 0, no NULL, asi que "v_id is null" era falso y el proceso iba por la
    -- rama de edicion sin insertar nada, pero decia "Cliente guardado".
    if fn_clean_num(null) is null then
        falla('C16', 'fn_clean_num(null) devuelve NULL: la trampa cambio, revisar la 21');
    end if;

    -- C17: el proceso de guardado tiene que usar nullif(...,0) para el id.
    select count(*) into v_n
      from apex_application_page_proc
     where application_id = 100 and page_id = 21
       and static_id = 'guardar-cliente'
       and instr(upper(process_source), 'NULLIF(FN_CLEAN_NUM(:P21_ID_CLIENTE)') > 0;
    if v_n <> 1 then
        falla('C17', 'el guardado no usa nullif(fn_clean_num(:P21_ID_CLIENTE),0)');
    end if;

    -- C18 (2026-11-18): la pantalla de clientes (20) — el dueño reportó que no se veía
    -- a qué empresa pertenece cada cliente y que el RIF inválido seguía en la base.
    --  (a) la lista filtra por la empresa activa y trae la empresa en la consulta
    select count(*) into v_n
      from apex_application_page_regions
     where application_id = 100 and page_id = 20
       and region_id = 43000000000000501
       and instr(upper(region_source), 'F_EMPRESA_ACTIVA') > 0
       and instr(upper(region_source), 'NOMBRE_EMPRESA AS EMPRESA') > 0;
    if v_n <> 1 then
        falla('C18a', 'la lista de clientes no filtra por la empresa activa o no trae la empresa');
    end if;

    --  (b) la columna «Empresa» está en el informe por defecto, y «País» y «Tipo» no
    select count(*) into v_n
      from apex_application_page_ir_rpt
     where application_id = 100 and region_id = 43000000000000501
       and application_user = 'APXWS_DEFAULT'
       and instr(upper(report_columns), 'EMPRESA') > 0
       and instr(upper(report_columns), 'COD_PAIS') = 0
       and instr(upper(report_columns), 'TIPO') = 0;
    if v_n = 0 then
        falla('C18b', 'el informe por defecto de clientes no muestra Empresa o sigue mostrando País/Tipo');
    end if;

    --  (c) el estado se pinta como insignia
    select count(*) into v_n
      from apex_application_page_ir_col
     where application_id = 100 and region_id = 43000000000000501
       and column_alias = 'ESTADO'
       and instr(html_expression, 'status-badge') > 0;
    if v_n <> 1 then
        falla('C18c', 'el estado de la lista de clientes no se pinta como insignia');
    end if;

    --  (d) el guardado rechaza un correo o un teléfono como nombre (-20028)
    select count(*) into v_n
      from apex_application_page_proc
     where application_id = 100 and page_id = 21
       and static_id = 'guardar-cliente'
       and instr(process_source, '-20028') > 0
       and instr(process_source, '@') > 0;
    if v_n <> 1 then
        falla('C18d', 'el guardado de cliente no rechaza un correo como nombre');
    end if;

    -- C19: no queda ningún cliente ACTIVO con un RIF que hoy no pase la regla
    select count(*) into v_n
      from clientes c
     where c.estado = 'ACTIVO'
       and not fn_rif_cliente_valido(
               c.rif,
               nvl(c.cod_pais, (select e.cod_pais from empresas e where e.id_empresa = c.id_empresa)),
               nvl(c.tipo_persona, 'J'));
    if v_n > 0 then
        falla('C19', v_n || ' cliente(s) ACTIVO con RIF invalido');
    end if;

    -- C20: los ítems ocultos de empresa no son obligatorios (con 2+ empresas y sin
    -- elegir valen NULL y APEX bloquearía el guardado con «Empresa debe tener algún valor»)
    select count(*) into v_n
      from apex_application_page_items
     where application_id = 100
       and item_name in ('P7_ID_EMPRESA', 'P9_ID_EMPRESA', 'P13_ID_EMPRESA')
       and is_required = 'Yes';
    if v_n > 0 then
        falla('C20', v_n || ' item(s) de empresa ocultos siguen siendo obligatorios');
    end if;

    raise_application_error(-20100, substrb('RESULTADO: FALLAS=' || v_fallas || v_lista, 1, 2000));
exception
    when others then
        if sqlcode = -20100 then
            raise;
        end if;
        begin
            delete from clientes where razon_social in ('CLIENTE DE PRUEBA', 'TIPO MALO');
            commit;
        exception when others then null;
        end;
        raise_application_error(-20100, substrb('RESULTADO: FALLAS=' || (v_fallas + 1)
                                || v_lista || ' | fallo la preparacion: ' || sqlerrm, 1, 2000));
end;
/
