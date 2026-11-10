-- =============================================================================
-- 20261105_paginas_7_9_verificacion.sql
--
-- Verifica que un usuario de solo lectura (rol CONSULTA) pueda ABRIR los
-- documentos desde las listas, y que al hacerlo no pueda escribir ni leer los
-- documentos de otra empresa.
--
-- Contexto: el enlace «Editar» de la lista de Presupuestos (pagina 5) abre la
-- pagina 7, y el de Facturacion (pagina 8) abre la 9. Esas dos paginas tenian
-- una guarda que solo dejaba pasar a los roles de escritura, asi que un
-- CONSULTA recibia ORA-20003 al pulsar «Editar». El patron correcto ya existia
-- en las paginas 6 y 10: la guarda deja entrar al CONSULTA, los botones de
-- escritura se ocultan por rol y los procesos vuelven a comprobar el rol.
--
-- Ademas las regiones de formulario de las paginas 7 y 9 no filtraban por
-- empresa (las de 6 y 10 si), asi que con un id ajeno en la URL se leia la
-- cabecera de otra empresa.
--
-- Se ejecuta de arriba a abajo:
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261105_paginas_7_9_verificacion.sql
--
-- Todo vive en un solo bloque PL/SQL para que el resumen sea el unico que hay
-- que leer: el runner de python no imprime los SELECT. El bloque termina con
-- -20100 ('RESULTADO: FALLAS=0'); codigo de salida 1 con FALLAS=0 significa
-- EXITO, igual que en las otras verificaciones del repo.
--
-- Los documentos se eligen de la base, no por nombre, para que la verificacion
-- siga sirviendo despues de purgar el demo.
--
-- Casos:
--   C1  Existe la guarda de la pagina 7 y su lista de roles incluye CONSULTA.
--   C2  Existe la guarda de la pagina 9 y su lista de roles incluye CONSULTA.
--   C3  La guarda de la pagina 7 conserva exactamente los roles de escritura.
--   C4  La guarda de la pagina 9 conserva exactamente los roles de escritura.
--   C5  La region de formulario de la pagina 7 filtra por empresa del usuario.
--   C6  La region de formulario de la pagina 9 filtra por empresa del usuario.
--   C7  Con el WHERE real de la pagina 7: el usuario de la empresa duena ve su
--       presupuesto (1 fila) y un usuario de otra empresa ve 0.
--   C8  Lo mismo con el WHERE real de la pagina 9 sobre una factura.
--   C9  El boton Guardar y Cancelar de las paginas 7 y 9 siguen condicionados
--       por rol, y los dos procesos de guardado siguen comprobando el rol
--       dentro del cuerpo (defensa en profundidad: el CONSULTA no escribe).
--   C10 No queda ningun objeto INVALID en el esquema.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;
/

declare
  v_fallas number := 0;
  v_lista  varchar2(3000) := '';
  v_emp1   number;
  v_doc_p  number;
  v_doc_f  number;
  v_user1  varchar2(100);
  v_user2  varchar2(100);
  v_w7     varchar2(4000);
  v_w9     varchar2(4000);
  v_src    varchar2(4000);
  v_esperado7 constant varchar2(200) := 'fn_tiene_rol(''ADMIN,GERENCIA,VENTAS,CONSULTA,PRUEBA'')';
  v_esperado9 constant varchar2(200) := 'fn_tiene_rol(''ADMIN,GERENCIA,FACTURACION,CONSULTA,PRUEBA'')';
  v_cnt    number;

  procedure falla (p_caso in varchar2, p_detalle in varchar2) is
  begin
    v_fallas := v_fallas + 1;
    v_lista  := v_lista || ' | ' || p_caso || ': ' || p_detalle;
  end falla;

  procedure cierra is
  begin
    -- raise_application_error admite 2048 bytes: se recorta la lista para no
    -- enmascarar el resultado con un ORA-06502.
    raise_application_error(-20100, substr('RESULTADO: FALLAS=' || v_fallas
        || ' (presupuesto ' || nvl(to_char(v_doc_p), 'sin datos')
        || ', factura ' || nvl(to_char(v_doc_f), 'sin datos')
        || ', usuarios ' || nvl(v_user1, '?') || '/' || nvl(v_user2, '?')
        || ')' || v_lista, 1, 1900));
  end cierra;

  -- Ejecuta el WHERE real de la region con los binds sustituidos por literales.
  function cuenta (p_tabla in varchar2, p_where in varchar2, p_bind_id in varchar2,
                   p_id in number, p_usuario in varchar2) return number is
    l_sql varchar2(4000) := 'select count(*) from ' || p_tabla || ' where ' || p_where;
  begin
    l_sql := replace(l_sql, ':APP_USER', '''' || replace(p_usuario, '''', '''''') || '''');
    l_sql := replace(l_sql, p_bind_id, to_char(p_id));
    execute immediate l_sql into v_cnt;
    return v_cnt;
  end cuenta;
begin
  -- Documentos reales: una empresa con presupuesto y factura, y un usuario
  -- activo de esa empresa y otro de una empresa distinta.
  begin
    select min(p.id_empresa) into v_emp1 from presupuestos p;
  exception when others then
    v_emp1 := null;
  end;
  if v_emp1 is null then
    falla('PRE', 'no hay presupuestos cargados');
    cierra;
  end if;

  select min(p.id_presupuesto) into v_doc_p from presupuestos p where p.id_empresa = v_emp1;
  select min(f.id_factura)     into v_doc_f from facturas f     where f.id_empresa = v_emp1;

  select min(u.username) into v_user1
    from usuario u where u.id_empresa = v_emp1 and u.estado in ('ACTIVO', 'A', '1');
  select min(u.username) into v_user2
    from usuario u where u.id_empresa <> v_emp1 and u.estado in ('ACTIVO', 'A', '1');

  if v_doc_p is null or v_doc_f is null then
    falla('PRE', 'la empresa ' || v_emp1 || ' no tiene presupuesto y factura');
    cierra;
  end if;
  if v_user1 is null or v_user2 is null then
    falla('PRE', 'falta un usuario activo en la empresa ' || v_emp1 || ' o en otra');
    cierra;
  end if;

  -- C1 a C4: las dos guardas.
  begin
    select process_source into v_src
      from apex_260100.apex_application_page_proc
     where application_id = 100 and page_id = 7
       and static_id = 'valida-rol-editar-presupuestos';
    if v_src not like '%CONSULTA%' then
      falla('C1', 'la guarda de la pagina 7 no deja entrar al CONSULTA');
    end if;
    if instr(v_src, v_esperado7) = 0 then
      falla('C3', 'la guarda de la pagina 7 no es la esperada');
    end if;
  exception when no_data_found then
    falla('C1', 'no existe la guarda de la pagina 7');
  end;

  begin
    select process_source into v_src
      from apex_260100.apex_application_page_proc
     where application_id = 100 and page_id = 9
       and static_id = 'valida-rol-editar-facturacion';
    if v_src not like '%CONSULTA%' then
      falla('C2', 'la guarda de la pagina 9 no deja entrar al CONSULTA');
    end if;
    if instr(v_src, v_esperado9) = 0 then
      falla('C4', 'la guarda de la pagina 9 no es la esperada');
    end if;
  exception when no_data_found then
    falla('C2', 'no existe la guarda de la pagina 9');
  end;

  -- C5 y C6: las regiones filtran por la empresa del usuario.
  begin
    select where_clause into v_w7
      from apex_260100.apex_application_page_regions
     where application_id = 100 and page_id = 7 and source_type = 'Form';
  exception when no_data_found then
    v_w7 := null;
  end;
  begin
    select where_clause into v_w9
      from apex_260100.apex_application_page_regions
     where application_id = 100 and page_id = 9 and source_type = 'Form';
  exception when no_data_found then
    v_w9 := null;
  end;

  -- MEDIDO (2026-11-10, tarea 4 del plan de multiempresa): el filtro de
  -- empresa de las regiones de formulario de las paginas 7 y 9 ya NO lee la
  -- columna unica USUARIO.ID_EMPRESA: lee la vista V_EMPRESAS_USUARIO (la
  -- tabla de asociacion USUARIO_EMPRESA), para que un usuario con VARIAS
  -- empresas vea y edite lo de todas las suyas. El chequeo era LITERAL, asi
  -- que se acepta las DOS formas. Lo que el caso quiere decir -«la region
  -- filtra por empresa del usuario»- sigue siendo cierto en las dos, y lo
  -- comprueban de verdad C7 y C8, con el WHERE real ejecutado contra datos
  -- reales.
  if v_w7 is null
     or (instr(upper(v_w7), 'ID_EMPRESA IN (SELECT U.ID_EMPRESA FROM USUARIO U') = 0
         and instr(upper(v_w7), 'V_EMPRESAS_USUARIO') = 0) then
    falla('C5', 'la region de la pagina 7 no filtra por empresa');
  end if;
  if v_w9 is null
     or (instr(upper(v_w9), 'ID_EMPRESA IN (SELECT U.ID_EMPRESA FROM USUARIO U') = 0
         and instr(upper(v_w9), 'V_EMPRESAS_USUARIO') = 0) then
    falla('C6', 'la region de la pagina 9 no filtra por empresa');
  end if;

  -- C7 y C8: el WHERE real de cada pagina, con el usuario de la empresa duena
  -- y con el de otra empresa.
  if v_w7 is not null then
    begin
      if cuenta('presupuestos', v_w7, ':P7_ID_PRESUPUESTO', v_doc_p, v_user1) <> 1 then
        falla('C7', 'el usuario ' || v_user1 || ' no ve su propio presupuesto ' || v_doc_p);
      end if;
      if cuenta('presupuestos', v_w7, ':P7_ID_PRESUPUESTO', v_doc_p, v_user2) <> 0 then
        falla('C7', 'el usuario ' || v_user2 || ' ve el presupuesto ' || v_doc_p || ' de otra empresa');
      end if;
    exception when others then
      falla('C7', 'el WHERE de la pagina 7 no se puede ejecutar: ' || sqlerrm);
    end;
  end if;

  if v_w9 is not null then
    begin
      if cuenta('facturas', v_w9, ':P9_ID_FACTURA', v_doc_f, v_user1) <> 1 then
        falla('C8', 'el usuario ' || v_user1 || ' no ve su propia factura ' || v_doc_f);
      end if;
      if cuenta('facturas', v_w9, ':P9_ID_FACTURA', v_doc_f, v_user2) <> 0 then
        falla('C8', 'el usuario ' || v_user2 || ' ve la factura ' || v_doc_f || ' de otra empresa');
      end if;
    exception when others then
      falla('C8', 'el WHERE de la pagina 9 no se puede ejecutar: ' || sqlerrm);
    end;
  end if;

  -- C9: la escritura sigue cerrada para quien solo consulta.
  for r in (select page_id, button_name
              from apex_260100.apex_application_page_buttons
             where application_id = 100 and page_id in (7, 9)
               and button_name in ('BTN_GUARDAR', 'BTN_CANCELAR')) loop
    select count(*) into v_cnt
      from apex_260100.apex_application_page_buttons
     where application_id = 100 and page_id = r.page_id and button_name = r.button_name
       and condition_type_code = 'EXPRESSION'
       and instr(upper(condition_expression1), 'FN_TIENE_ROL') > 0;
    if v_cnt = 0 then
      falla('C9', 'el boton ' || r.button_name || ' de la pagina ' || r.page_id
                  || ' ya no esta condicionado por rol');
    end if;
  end loop;

  for r in (select page_id, static_id
              from apex_260100.apex_application_page_proc
             where application_id = 100 and page_id in (7, 9)
               and static_id = 'guardar-presupuesto') loop
    select count(*) into v_cnt
      from apex_260100.apex_application_page_proc
     where application_id = 100 and page_id = r.page_id and static_id = r.static_id
       and instr(process_source, 'raise_application_error(-20003') > 0;
    if v_cnt = 0 then
      falla('C9', 'el proceso de guardado de la pagina ' || r.page_id
                  || ' ya no comprueba el rol dentro del cuerpo');
    end if;
  end loop;

  -- C10: esquema limpio.
  select count(*) into v_cnt
    from all_objects
   where owner = 'WKSP_SYPEXWS' and status <> 'VALID'
     and object_type in ('FUNCTION', 'PROCEDURE', 'PACKAGE', 'PACKAGE BODY', 'TRIGGER', 'VIEW');
  if v_cnt > 0 then
    falla('C10', v_cnt || ' objetos INVALID en el esquema');
  end if;

  cierra;
end;
/
