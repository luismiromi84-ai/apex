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
