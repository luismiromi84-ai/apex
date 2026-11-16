-- =============================================================================
-- 20261109_empresa_fiscal_emision.sql
--
-- Indicador de COMO emite los documentos la empresa, porque no todas emiten igual:
--   * FORMA_LIBRE    -> factura impresa por una imprenta autorizada: la providencia
--                       SENIAT da el rango de numeracion y los datos de la imprenta.
--   * MAQUINA_FISCAL -> impresora fiscal registrada: lo que importa es el numero de
--                       registro de la maquina (y, en el papel, el numero de reporte).
--
-- Las notas de credito/debito tienen que citar el documento que modifican segun el
-- modo: numero y fecha, numero de control y, si aplica, el registro de la maquina.
--
-- Idempotente. Al final recompila el esquema.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
  v_n number;
begin
  select count(*) into v_n from all_tab_columns
   where owner = 'WKSP_SYPEXWS' and table_name = 'EMPRESA_FISCAL'
     and column_name = 'TIPO_EMISION';
  if v_n = 0 then
    execute immediate q'~alter table empresa_fiscal add (tipo_emision varchar2(20) default 'FORMA_LIBRE')~';
  end if;

  select count(*) into v_n from all_tab_columns
   where owner = 'WKSP_SYPEXWS' and table_name = 'EMPRESA_FISCAL'
     and column_name = 'NRO_REGISTRO_MAQUINA';
  if v_n = 0 then
    execute immediate 'alter table empresa_fiscal add (nro_registro_maquina varchar2(60))';
  end if;

  select count(*) into v_n from all_constraints
   where owner = 'WKSP_SYPEXWS' and table_name = 'EMPRESA_FISCAL'
     and constraint_name = 'CK_EMPRESA_FISCAL_EMISION';
  if v_n = 0 then
    execute immediate q'~alter table empresa_fiscal add constraint ck_empresa_fiscal_emision
        check (tipo_emision in ('FORMA_LIBRE', 'MAQUINA_FISCAL')) enable~';
  end if;
end;
/

update empresa_fiscal set tipo_emision = 'FORMA_LIBRE' where tipo_emision is null
/

begin
  dbms_utility.compile_schema('WKSP_SYPEXWS', false);
end;
/

commit
/

select id_empresa, nvl(tipo_emision, '(null)') tipo_emision,
       nvl(nro_registro_maquina, '-') maquina
  from empresa_fiscal order by id_empresa
/

select count(*) as invalidos from all_objects
 where owner = 'WKSP_SYPEXWS' and status <> 'VALID'
/
