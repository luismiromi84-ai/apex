-- =============================================================================
-- 20261105_propiedad_documentos_verificacion.sql
--
-- Verificacion de fn_presupuesto_propio y fn_factura_propio. Se ejecuta de
-- arriba a abajo:
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261105_propiedad_documentos_verificacion.sql
--
-- Los SELECT devuelven filas solo cuando algo FALLA. El bloque PL/SQL del final
-- resume con -20100 ('RESULTADO: FALLAS=0'); codigo de salida 1 con FALLAS=0
-- significa EXITO, igual que en las otras verificaciones del repo.
--
-- La segunda empresa no tiene documentos cargados hoy, asi que el bloque crea
-- un presupuesto y una factura temporales de esa empresa, prueba con ellos y
-- hace ROLLBACK. No deja nada escrito.
--
-- Los datos de prueba se eligen de la base, no por nombre: la empresa con
-- documentos, la otra empresa, un cliente de esa otra empresa y un usuario
-- activo de cada una. Asi la verificacion sigue sirviendo despues de cargar
-- datos reales o de purgar el demo.
--
-- Casos:
--   C1  Las dos funciones existen y estan VALID.
--   C2  PUBLIC tiene EXECUTE sobre las dos.
--   C3  presupuesto de la empresa con documentos, con su propio usuario -> TRUE
--   C4  factura de la misma empresa, con su propio usuario        -> TRUE
--   C5  presupuesto de la otra empresa, con su propio usuario     -> TRUE
--   C6  factura de la otra empresa, con su propio usuario         -> TRUE
--   C7  presupuesto de la otra empresa, con usuario de la primera -> FALSE
--   C8  factura de la otra empresa, con usuario de la primera     -> FALSE
--   C9  presupuesto de la primera, con usuario de la otra         -> FALSE
--   C10 factura de la primera, con usuario de la otra             -> FALSE
--   C11 id nulo (presupuesto y factura) -> FALSE
--   C12 id inexistente 999999 (presupuesto y factura) -> FALSE
--   C13 usuario inexistente -> FALSE
--   C14 usuario nulo y usuario inactivo -> FALSE
--   C15 El rollback dejo limpias las tablas (no quedo documento de prueba).
--   C16 Ningun objeto del esquema quedo INVALID.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;
/

select 'FALLA: falta fn_presupuesto_propio o no esta VALID' as caso from dual
 where not exists (select 1 from all_objects
                    where owner='WKSP_SYPEXWS' and object_name='FN_PRESUPUESTO_PROPIO'
                      and object_type='FUNCTION' and status='VALID');
/

select 'FALLA: falta fn_factura_propio o no esta VALID' as caso from dual
 where not exists (select 1 from all_objects
                    where owner='WKSP_SYPEXWS' and object_name='FN_FACTURA_PROPIO'
                      and object_type='FUNCTION' and status='VALID');
/

select 'FALLA: PUBLIC no tiene EXECUTE sobre ' || t.nombre as caso
  from (select 'FN_PRESUPUESTO_PROPIO' as nombre from dual
        union all
        select 'FN_FACTURA_PROPIO' from dual) t
 where not exists (select 1 from all_tab_privs p
                    where p.table_schema='WKSP_SYPEXWS'
                      and p.table_name=t.nombre
                      and p.grantee='PUBLIC'
                      and p.privilege='EXECUTE');
/

select 'FALLA: hay objetos INVALID en el esquema' as caso
  from all_objects
 where owner='WKSP_SYPEXWS' and status <> 'VALID'
   and object_type in ('FUNCTION','PROCEDURE','PACKAGE','PACKAGE BODY','TRIGGER','VIEW');
/

declare
  v_fallas  number := 0;
  v_lista   varchar2(3000) := '';
  v_emp1    number;
  v_emp2    number;
  v_p1      number;
  v_f1      number;
  v_p2      number;
  v_f2      number;
  v_cli2    number;
  v_user1   varchar2(100);
  v_user2   varchar2(100);
  v_user1b  varchar2(100);
  v_inact   varchar2(100);
  v_doc_p   number;
  v_doc_f   number;
  v_restos  number;

  procedure falla (p_caso in varchar2, p_detalle in varchar2) is
  begin
    v_fallas := v_fallas + 1;
    v_lista  := v_lista || ' | ' || p_caso || ': ' || p_detalle;
  end falla;

  procedure comprueba (p_caso in varchar2, p_obtenido in boolean, p_esperado in boolean) is
  begin
    if (case when p_obtenido then 1 else 0 end) <>
       (case when p_esperado then 1 else 0 end) then
      falla(p_caso, 'devolvio ' || case when p_obtenido then 'TRUE' else 'FALSE' end
                   || ' y se esperaba ' || case when p_esperado then 'TRUE' else 'FALSE' end);
    end if;
  end comprueba;

  procedure cierra is
  begin
    -- raise_application_error admite 2048 bytes: se recorta la lista para no
    -- enmascarar el resultado con un ORA-06502.
    raise_application_error(-20100, substr('RESULTADO: FALLAS=' || v_fallas
        || ' (presupuesto empresa ' || v_emp1 || ' = ' || nvl(to_char(v_p1), 'sin datos')
        || ', factura = ' || nvl(to_char(v_f1), 'sin datos')
        || ', documentos temporales empresa ' || nvl(to_char(v_emp2), '?')
        || ' = ' || nvl(to_char(v_p2), '?') || '/' || nvl(to_char(v_f2), '?')
        || ', revertidos)' || v_lista, 1, 1900));
  end cierra;
begin
  -- Empresas y documentos reales: la empresa que tiene documentos y otra
  -- distinta para probar el cruce.
  select min(p.id_empresa)          into v_emp1 from presupuestos p;
  select min(e.id_empresa)          into v_emp2 from empresas e where e.id_empresa <> nvl(v_emp1, -1);

  if v_emp1 is null then
    falla('PRE', 'no hay presupuestos cargados: no se puede probar la propiedad');
    cierra;
  end if;
  if v_emp2 is null then
    falla('PRE', 'no hay una segunda empresa con la que probar el cruce');
    cierra;
  end if;

  select min(p.id_presupuesto) into v_p1 from presupuestos p where p.id_empresa = v_emp1;
  select min(f.id_factura)     into v_f1 from facturas f     where f.id_empresa = v_emp1;

  if v_p1 is null or v_f1 is null then
    falla('PRE', 'la empresa ' || v_emp1 || ' no tiene presupuestos y facturas para probar');
    cierra;
  end if;

  select min(c.id_cliente) into v_cli2 from clientes c where c.id_empresa = v_emp2;
  if v_cli2 is null then
    falla('PRE', 'la empresa ' || v_emp2 || ' no tiene clientes para el documento temporal');
    cierra;
  end if;

  select min(u.username) into v_user1
    from usuario u where u.id_empresa = v_emp1 and u.estado in ('ACTIVO', 'A', '1');
  select min(u.username) into v_user2
    from usuario u where u.id_empresa = v_emp2 and u.estado in ('ACTIVO', 'A', '1');
  select min(u.username) into v_user1b
    from usuario u
   where u.id_empresa = v_emp1 and u.estado in ('ACTIVO', 'A', '1')
     and u.username <> v_user1;

  if v_user1 is null or v_user2 is null then
    falla('PRE', 'falta un usuario activo en la empresa ' || v_emp1 || ' o en la ' || v_emp2);
    cierra;
  end if;

  v_inact := nvl(v_user1b, v_user2);

  -- Documentos temporales de la segunda empresa (se revierten con el rollback).
  insert into presupuestos (id_empresa, folio, id_cliente, cod_moneda, estado)
  values (v_emp2, 999000001, v_cli2, 'USD', 'PENDIENTE')
  returning id_presupuesto into v_p2;

  insert into facturas (id_empresa, id_cliente, folio_factura, tipo_documento, cod_moneda, estado)
  values (v_emp2, v_cli2, 'ZZ-PROP-TEST', 'FAC', 'USD', 'PENDIENTE')
  returning id_factura into v_f2;

  -- C3 y C4: la empresa con documentos con su propio usuario.
  comprueba('C3', fn_presupuesto_propio(v_p1, v_user1), true);
  comprueba('C4', fn_factura_propio(v_f1, v_user1), true);

  -- C5 y C6: la otra empresa con su propio usuario. Sin esto, un FALSE
  -- constante pasaria todos los casos negativos.
  comprueba('C5', fn_presupuesto_propio(v_p2, v_user2), true);
  comprueba('C6', fn_factura_propio(v_f2, v_user2), true);

  -- C7 y C8: documento de la otra empresa mirado por un usuario de la primera.
  comprueba('C7', fn_presupuesto_propio(v_p2, v_user1), false);
  comprueba('C8', fn_factura_propio(v_f2, v_user1), false);

  -- C9 y C10: documento de la primera mirado por un usuario de la otra.
  comprueba('C9',  fn_presupuesto_propio(v_p1, v_user2), false);
  comprueba('C10', fn_factura_propio(v_f1, v_user2), false);

  -- C11: id nulo.
  comprueba('C11-p', fn_presupuesto_propio(null, v_user1), false);
  comprueba('C11-f', fn_factura_propio(null, v_user1), false);

  -- C12: id inexistente.
  comprueba('C12-p', fn_presupuesto_propio(999999, v_user1), false);
  comprueba('C12-f', fn_factura_propio(999999, v_user1), false);

  -- C13: usuario inexistente.
  comprueba('C13-p', fn_presupuesto_propio(v_p1, 'usuario_que_no_existe'), false);
  comprueba('C13-f', fn_factura_propio(v_f1, 'usuario_que_no_existe'), false);

  -- C14: usuario nulo y usuario inactivo. El documento es de la empresa del
  -- usuario que se desactiva, para que el FALSE solo pueda venir del estado.
  comprueba('C14-null', fn_presupuesto_propio(v_p1, null), false);

  v_inact := nvl(v_user1b, v_user2);
  if v_user1b is not null then
    v_doc_p := v_p1;
    v_doc_f := v_f1;
  else
    v_doc_p := v_p2;
    v_doc_f := v_f2;
  end if;

  update usuario set estado = 'INACTIVO' where username = v_inact;
  comprueba('C14-inact-p', fn_presupuesto_propio(v_doc_p, v_inact), false);
  comprueba('C14-inact-f', fn_factura_propio(v_doc_f, v_inact), false);

  -- C15: el rollback deja las tablas como estaban.
  rollback;

  select count(*) into v_restos
    from presupuestos
   where folio = 999000001 and id_empresa = v_emp2;
  if v_restos <> 0 then
    falla('C15', 'quedo el presupuesto temporal tras el rollback');
  end if;

  select count(*) into v_restos
    from facturas
   where folio_factura = 'ZZ-PROP-TEST' and id_empresa = v_emp2;
  if v_restos <> 0 then
    falla('C15', 'quedo la factura temporal tras el rollback');
  end if;

  cierra;
end;
/
