-- =============================================================================
-- 20261117_rif_empresa_verificacion.sql
--
-- El RIF/RFC de la empresa emisora (2026-11-17):
--   F1  acepta los RIF venezolanos de verdad, con y sin guiones
--   F2  rechaza EMP123456789 (el relleno del PDF de ejemplo)
--   F3  rechaza letras que no son de RIF venezolano y numeros sueltos
--   F4  Mexico: 12 o 13 alfanumericos
--   F5  la pestana «Empresa» valida con la funcion al guardar
--   F6  fn_rif_cliente_valido sigue igual (no se rompio el de los clientes)
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261117_rif_empresa_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

begin
    begin execute immediate 'drop table tmp_rifemp_fallas purge'; exception when others then null; end;
end;
/

create table tmp_rifemp_fallas (caso varchar2(300))
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000);

    procedure exige(p_rif varchar2, p_pais varchar2, p_esperado boolean, p_texto varchar2) is
        v_ok boolean;
    begin
        v_ok := fn_rif_empresa_valido(p_rif, p_pais);
        if v_ok <> p_esperado then
            insert into tmp_rifemp_fallas
            values (substrb(p_texto || ': ' || nvl(p_rif, '(nulo)')
                            || case when p_esperado then ' deberia valer' else ' deberia rechazarse' end, 1, 300));
        end if;
    end;
begin
    -- F1
    exige('J-12345678-9', 'VE', true,  'F1 juridica con guiones');
    exige('J123456789',   'VE', true,  'F1 juridica sin guiones');
    exige('V-12345678-9', 'VE', true,  'F1 venezolano');
    exige('E-12345678-9', 'VE', true,  'F1 extranjero');
    exige('G-20000000-1', 'VE', true,  'F1 gubernamental');
    exige('P-123456789',  'VE', true,  'F1 pasaporte');
    exige('C-12345678-9', 'VE', true,  'F1 consejo comunal');
    exige('J-97364742',   'VE', false, 'F1 juridica de 8 digitos (ahora se exigen 9)');
    exige('J-6454545',    'VE', false, 'F1 juridica de 7 digitos (el caso reportado)');

    -- F7 (2026-11-19): el emisor puede ser persona natural, y su RIF es la cedula
    -- (6 a 8 digitos) mas el verificador: 7 a 9 digitos, no solo 9.
    exige('V-4666778-9',  'VE', true,  'F7 emisor natural con cedula de 7 digitos');
    exige('V-9877766',    'VE', true,  'F7 emisor natural sin verificador');
    exige('V1234567-8',   'VE', true,  'F7 emisor natural de 8 digitos sin guiones');
    exige('J-1234567-8',  'VE', false, 'F7 juridica de 8 digitos sigue rechazada');

    -- F2
    exige('EMP123456789', 'VE', false, 'F2 el relleno del PDF');
    exige('123456789',    'VE', false, 'F2 solo numeros');

    -- F3
    exige('A-12345678-9', 'VE', false, 'F3 letra que no es de RIF');
    exige('J-ABC12345',   'VE', false, 'F3 letras en los digitos');
    exige(null,           'VE', false, 'F3 nulo');

    -- F4
    exige('MXE010101AAA', 'MX', true,  'F4 RFC moral de 12');
    exige('AABC010101AB1', 'MX', true, 'F4 RFC fisica de 13');
    exige('MXE010101AA',  'MX', false, 'F4 RFC de 11');

    -- F5: el proceso de la pestana Empresa llama a la funcion
    select count(*) into v_fallas from apex_application_page_proc
     where application_id = 100 and page_id = 19
       and process_name = 'Guardar empresa'
       and instr(lower(to_clob(process_source)), 'fn_rif_empresa_valido') > 0;
    if v_fallas = 0 then
        insert into tmp_rifemp_fallas values ('F5 la pestana Empresa no valida el RIF con la funcion');
    end if;

    -- F6
    if not fn_rif_cliente_valido('J-12345678-9', 'VE', 'J') then
        insert into tmp_rifemp_fallas values ('F6 fn_rif_cliente_valido dejo de aceptar un RIF juridico');
    end if;
    if fn_rif_cliente_valido('EMP123456789', 'VE', 'J') then
        insert into tmp_rifemp_fallas values ('F6 fn_rif_cliente_valido acepta el relleno del PDF');
    end if;
end;
/

declare
    v_fallas number;
    v_lista  varchar2(3000);
begin
    select count(*) into v_fallas from tmp_rifemp_fallas;
    select substrb(listagg(caso, ' | ' on overflow truncate) within group (order by caso), 1, 3000)
      into v_lista from tmp_rifemp_fallas;
    execute immediate 'drop table tmp_rifemp_fallas purge';
    raise_application_error(-20100, substrb('RESULTADO: FALLAS=' || v_fallas || ' | ' || v_lista, 1, 3000));
end;
/
