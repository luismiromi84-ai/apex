-- =============================================================================
-- 20261110_multiempresa_verificacion.sql
--
-- Verificacion del modelo multiempresa (tabla USUARIO_EMPRESA, vista
-- V_EMPRESAS_USUARIO y siembra de datos). Se ejecuta de arriba a abajo:
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261110_multiempresa_verificacion.sql
--
-- PATRON DE CONTEO: dbms_output no se puede leer en este entorno y
-- importar_export.py no imprime los SELECT, asi que cada caso registra su
-- propio fallo en una tabla temporal y el bloque final cuenta y lista. El
-- detalle viaja en el mensaje de -20100:
--   ORA-20100: RESULTADO: FALLAS=n | caso1 | caso2 ...
-- FALLAS=0 = EXITO (el runner sale con codigo 1 igualmente: se lee el mensaje).
--
-- Los casos de las tareas siguientes del plan se ANADEN a este mismo archivo con
-- su propio 'insert into tmp_multi_fallas'; no hay que tocar nada mas.
--
-- TRAMPAS MEDIDAS EN ESTA BASE (Oracle 26ai), ya aplicadas aqui:
--   1. La tabla de fallos es una tabla NORMAL, no una temporal global. Con
--      'create global temporary table' esta base da ORA-12838 ('cannot
--      read/modify an object after modifying it in parallel') al segundo
--      INSERT, y la temporal global que ya se leyo en la sesion no se puede
--      dropear (ORA-14452). Con una tabla normal no hay que hacer 'commit'
--      entre INSERT y el DROP del bloque final funciona, que es lo que pide el
--      patron de conteo. El DROP va al principio (por si una corrida anterior
--      dejo la tabla) y tambien al final.
--   2. Un SELECT que NOMBRA la tabla USUARIO_EMPRESA o la vista
--      V_EMPRESAS_USUARIO no compila mientras no existan (ORA-00942), por mas
--      que la sentencia traiga un 'exists (select 1 from all_tables ...)' que
--      la protegeria: el compilador resuelve el nombre antes de ejecutar. Los
--      casos M3, M4 y M5, que necesitan leer esos objetos, van por eso en
--      bloques PL/SQL que los consultan con SQL dinamico.
--   3. 'execute immediate ... bulk collect into <tipo local>' no compila en
--      esta version (ORA-00984 y 'SQL Statement ignored'): el SQL dinamico no
--      ve el tipo declarado en el bloque. Por eso cada consulta devuelve una
--      sola fila con 'listagg' y se recoge en un VARCHAR2.
--   4. SQLERRM SI se puede usar en una expresion PL/SQL dentro de un
--      manejador de excepcion: 'v_error := sqlerrm', 'v_error := ''x'' ||
--      sqlerrm' y 'falla(''x'' || sqlerrm)' funcionan (medido). Lo que NO
--      funciona es usarlo como identificador suelto DENTRO de una sentencia
--      SQL (por ejemplo 'insert into t values (sqlerrm)' o
--      'insert into t values (''x'' || sqlerrm)'): ahi da ORA-00984
--      'column not allowed here' y la sentencia se marca 'SQL Statement
--      ignored'. Por eso los manejadores de este archivo hacen
--      'v_error := sqlerrm' y pasan la variable ya concatenada al INSERT.
--
--   5. TODOS los recortes de texto van en BYTES, no en caracteres. En esta
--      base NLS_CHARACTERSET=AL32UTF8 y NLS_LENGTH_SEMANTICS=BYTE, asi que
--      'tmp_multi_fallas.caso varchar2(300)' son 300 BYTES y
--      'v_lista varchar2(2000)' son 2000 BYTES, mientras que 'substr(x,1,N)'
--      recorta N CARACTERES. Con texto no ASCII un recorte por caracteres se
--      pasa de largo: 'substr(rpad(''x'',290,''x'')||rpad(''ÃƒÂ¡'',10,''ÃƒÂ¡''),1,300)'
--      son 310 bytes contra 300 de la columna y revienta con ORA-12899.
--      Por eso los recortes usan 'substrb(...)', que recorta bytes:
--        - los 15 'insert into tmp_multi_fallas' (columna 'caso');
--        - el 'listagg' del bloque de cierre, que alimenta 'v_lista';
--        - el 'substr' del mensaje de 'raise_application_error', que tambien
--          cuenta bytes (el limite de ese error es 2048 bytes).
--
--   6. El 'listagg' del bloque de cierre lleva 'on overflow truncate' Y un
--      'substrb' por fuera. Los dos hacen falta y no son redundantes:
--        - sin 'on overflow truncate', la agregacion revienta con ORA-01489
--          ANTES de llegar al recorte y se pierde el 'RESULTADO: FALLAS=n';
--        - con 'on overflow truncate' a secas, en esta version el recorte es
--          al maximo de la propia lista (medido: 5857 caracteres con 20
--          elementos de 290), NO al tamano de la variable destino, asi que el
--          'INTO' de un VARCHAR2(2000) revienta con ORA-06502 y se pierde
--          igual el 'RESULTADO: FALLAS=n'.
--      Los 'listagg' internos de M3, M4 y M5 llevan los dos por lo mismo.
--
-- Casos (tarea 1: tabla, vista y siembra):
--   M1  Existe USUARIO_EMPRESA con PK compuesta, indice por ID_EMPRESA y las
--       FK a USUARIO(USUARIO_ID) y a EMPRESAS(ID_EMPRESA).
--   M2  Existe V_EMPRESAS_USUARIO y es VALID.
--   M3  Todo usuario ACTIVO con ID_EMPRESA no nulo tiene su par en USUARIO_EMPRESA.
--   M4  La vista devuelve MONEDA_LOCAL no nula para la empresa 1 (VE) y la 2 (MX).
--   M5  Ninguna empresa queda huerfana: toda fila de EMPRESAS tiene al menos un
--       par en USUARIO_EMPRESA (hoy cubre las tres 'dotech', 3/4/5). Si en el
--       futuro una empresa se deja sin usuarios a proposito, este caso avisa.
--
-- Casos (tarea 2: guardas y login por asociacion):
--   M6  Usuario de prueba con pares en DOS empresas: fn_usuario_empresa_valida
--       devuelve true para las dos.
--   M7  El mismo usuario contra una TERCERA empresa sin par: false.
--   M8  Usuario inactivo con par: false; usuario/empresa nulos: false;
--       empresa inexistente: false.
--   M9  Usuario ACTIVO con rol y pares, pero USUARIO.ID_EMPRESA nulo:
--       fn_autenticar_usuario con clave correcta devuelve true.
--   M10 La consulta de prc_post_login (copiada con el usuario como literal)
--       devuelve 1 fila para el usuario con pares y 0 para uno sin asociacion.
--
-- Casos (tarea 3: la LOV EMPRESA lista todas las empresas del usuario):
--   M11 El texto guardado de la LOV EMPRESA (APEX_APPLICATION_LOVS) lee
--       V_EMPRESAS_USUARIO y conserva el filtro e.estado = 'ACTIVO'.
--   M12 Ejecutando ese texto guardado: un usuario con pares en dos empresas
--       ve las dos; uno con un solo par ve una.
--   M13 El mismo texto con un usuario que tiene un par en una empresa ACTIVA
--       y otro en una INACTIVA: solo sale la ACTIVA.
--
-- Casos (tarea 6: pagina 19 Ã‚Â«AdministracionÃ‚Â»):
--   M14 (AMPLIADO por la tarea 6) Ninguna consulta guardada por APEX Ã¢â‚¬â€regiones,
--       items, LOVs y TAMBIEN los procesos de pagina, ya incluida la pagina 19Ã¢â‚¬â€
--       sigue leyendo la columna unica USUARIO.ID_EMPRESA.
--   M23 El listado Ã‚Â«Mis empresasÃ‚Â» de la pagina 19, ejecutado con el TEXTO
--       GUARDADO por APEX, devuelve las empresas del usuario: 2 para un usuario
--       con 2 pares, 1 para uno con 1 par y 0 para uno sin pares.
--   M24 El proceso real Ã‚Â«Guardar empresaÃ‚Â» (ALTA) inserta la empresa Y deja el
--       par en USUARIO_EMPRESA para el usuario que la creo.
--   M25 El proceso real Ã‚Â«Guardar empresaÃ‚Â» (EDICION) con una empresa que no es
--       del usuario lanza -20003 y no cambia nada.
--   M26 El proceso real Ã‚Â«Carga la empresa del usuarioÃ‚Â» (BEFORE_HEADER) NO
--       lanza NO_DATA_FOUND (ORA-01403) cuando el usuario tiene DOS empresas:
--       el 'having count(*) = 1' deja la consulta sin filas y, sin manejador,
--       tumbaba la pagina entera (medido el 2026-11-10).
--
-- Casos (tarea 5: pagina 3 con la columna Ã‚Â«EmpresasÃ‚Â»):
--   M21 La consulta GUARDADA de la region Ã‚Â«Gestion de UsuariosÃ‚Â» (pagina 3)
--       devuelve una columna EMPRESAS con las empresas COMPARTIDAS con el
--       administrador que mira, separadas por ', ' y ordenadas por nombre.
--       Ademas la columna EMPRESAS esta declarada en el informe por defecto.
--   M22 Para un usuario que ademas tiene una empresa que el administrador NO
--       tiene, esa tercera empresa NO aparece en EMPRESAS (no se filtra el
--       nombre de la empresa de otro cliente: decision 13.6 del spec).
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;
/

-- Por si una corrida anterior dejo la tabla (el DROP del bloque final la
-- borra, pero una corrida interrumpida puede no llegar ahi).
declare
    v_existe number;
begin
    select count(*) into v_existe from all_tables
     where owner = 'WKSP_SYPEXWS' and table_name = 'TMP_MULTI_FALLAS';
    if v_existe > 0 then
        execute immediate 'drop table tmp_multi_fallas purge';
    begin
        execute immediate 'drop table tmp_multi_notas purge';
    exception when others then null;
    end;
    end if;
    select count(*) into v_existe from all_tables
     where owner = 'WKSP_SYPEXWS' and table_name = 'TMP_MULTI_NOTAS';
    if v_existe > 0 then
        execute immediate 'drop table tmp_multi_notas purge';
    end if;
end;
/

create table tmp_multi_fallas (caso varchar2(300));
/
-- (La tabla de AVISOS 'tmp_multi_notas' se retiro el 2026-11-11: se creaba y
-- nunca se escribia, y dejaba una tabla de trabajo en el esquema de produccion
-- -- la detectaba 20261107_install_limpio_inventario.py. El bloque del principio
-- sigue borrandola, para limpiar bases donde hubiera quedado.)

-- -----------------------------------------------------------------------------
-- M1: la tabla existe, con la PK compuesta, el indice y las dos FK.
--    Solo consulta el diccionario, asi que no necesita que la tabla exista.
-- -----------------------------------------------------------------------------
insert into tmp_multi_fallas
select substrb('M1: falta USUARIO_EMPRESA', 1, 300) from dual
 where not exists (select 1 from all_tables
                    where owner = 'WKSP_SYPEXWS' and table_name = 'USUARIO_EMPRESA');
/

insert into tmp_multi_fallas
select substrb('M1: falta la PK PK_USUARIO_EMPRESA (usuario_id, id_empresa)', 1, 300) from dual
 where exists (select 1 from all_tables
                where owner = 'WKSP_SYPEXWS' and table_name = 'USUARIO_EMPRESA')
   and (select count(*) from all_constraints c
             join all_cons_columns cc on cc.owner = c.owner
                                    and cc.constraint_name = c.constraint_name
        where c.owner = 'WKSP_SYPEXWS'
          and c.constraint_name = 'PK_USUARIO_EMPRESA'
          and c.constraint_type = 'P'
          and cc.column_name in ('USUARIO_ID', 'ID_EMPRESA')) <> 2;
/

insert into tmp_multi_fallas
select substrb('M1: falta el indice IX_UE_EMPRESA (id_empresa)', 1, 300) from dual
 where exists (select 1 from all_tables
                where owner = 'WKSP_SYPEXWS' and table_name = 'USUARIO_EMPRESA')
   and not exists (select 1 from all_indexes
                    where owner = 'WKSP_SYPEXWS' and index_name = 'IX_UE_EMPRESA');
/

insert into tmp_multi_fallas
select substrb('M1: falta la FK de USUARIO_EMPRESA a USUARIO(USUARIO_ID)', 1, 300) from dual
 where exists (select 1 from all_tables
                where owner = 'WKSP_SYPEXWS' and table_name = 'USUARIO_EMPRESA')
   and not exists (select 1 from all_constraints c
                    join all_cons_columns cc on cc.owner = c.owner
                                           and cc.constraint_name = c.constraint_name
                   where c.owner = 'WKSP_SYPEXWS'
                     and c.table_name = 'USUARIO_EMPRESA'
                     and c.constraint_type = 'R'
                     and cc.column_name = 'USUARIO_ID'
                     and c.r_constraint_name in (select constraint_name from all_constraints
                                                 where owner = 'WKSP_SYPEXWS'
                                                   and table_name = 'USUARIO'
                                                   and constraint_type = 'P'));
/

insert into tmp_multi_fallas
select substrb('M1: falta la FK de USUARIO_EMPRESA a EMPRESAS(ID_EMPRESA)', 1, 300) from dual
 where exists (select 1 from all_tables
                where owner = 'WKSP_SYPEXWS' and table_name = 'USUARIO_EMPRESA')
   and not exists (select 1 from all_constraints c
                    join all_cons_columns cc on cc.owner = c.owner
                                           and cc.constraint_name = c.constraint_name
                   where c.owner = 'WKSP_SYPEXWS'
                     and c.table_name = 'USUARIO_EMPRESA'
                     and c.constraint_type = 'R'
                     and cc.column_name = 'ID_EMPRESA'
                     and c.r_constraint_name in (select constraint_name from all_constraints
                                                 where owner = 'WKSP_SYPEXWS'
                                                   and table_name = 'EMPRESAS'
                                                   and constraint_type = 'P'));
/

-- -----------------------------------------------------------------------------
-- M2: la vista existe y es VALID. Solo diccionario.
-- -----------------------------------------------------------------------------
insert into tmp_multi_fallas
select substrb('M2: falta V_EMPRESAS_USUARIO o no esta VALID', 1, 300) from dual
 where not exists (select 1 from all_objects
                    where owner = 'WKSP_SYPEXWS' and object_name = 'V_EMPRESAS_USUARIO'
                      and object_type = 'VIEW' and status = 'VALID');
/

-- -----------------------------------------------------------------------------
-- M3, M4 y M5: necesitan leer USUARIO_EMPRESA y V_EMPRESAS_USUARIO, asi que
-- van en PL/SQL con SQL dinamico: si el objeto no existe todavia, el caso se
-- registra con su propio mensaje en vez de reventar con ORA-00942.
--
-- Cada consulta devuelve UNA fila con 'listagg' y se recoge en un VARCHAR2
-- (trampa 3: 'bulk collect into' con tipo local no compila aqui).
--
-- OJO, Important 1 (revision del 2026-11-10): el manejador de cada caso
-- REGISTRA un fallo, no lo calla. Los guardas 'v_tiene_tabla'/'v_tiene_vista'
-- ya cubren el caso de que el objeto no exista, asi que lo unico que el
-- manejador puede atrapar es un fallo real de la medicion (un 'listagg'
-- interno que revienta, una vista INVALID en M4...). Si ahi se hiciera
-- 'v_detalle := null', una medicion rota se convertiria en un PASS
-- silencioso y este archivo dejaria de ser la reja de regresiÃƒÂ³n.
-- -----------------------------------------------------------------------------
declare
    v_tiene_tabla number;
    v_tiene_vista number;
    v_detalle     varchar2(2000);
    v_error       varchar2(300);
begin
    select count(*) into v_tiene_tabla from all_tables
     where owner = 'WKSP_SYPEXWS' and table_name = 'USUARIO_EMPRESA';
    select count(*) into v_tiene_vista from all_objects
     where owner = 'WKSP_SYPEXWS' and object_name = 'V_EMPRESAS_USUARIO'
       and object_type = 'VIEW';

    -- M3: todo usuario ACTIVO con ID_EMPRESA no nulo tiene su par sembrado.
    -- Sin esto, la vista devolveria 0 filas para ese usuario y todas sus
    -- listas saldrian vacias en silencio.
    if v_tiene_tabla = 0 then
        insert into tmp_multi_fallas
        values (substrb('M3: no se puede medir, falta la tabla USUARIO_EMPRESA', 1, 300));
    else
        v_detalle := null;
        begin
            execute immediate
                q'[select substrb(listagg(u.username || ' (empresa ' || u.id_empresa || ')', ' | '
                              on overflow truncate) within group (order by u.username), 1, 2000)
                     from usuario u
                    where u.estado in ('ACTIVO','A','1')
                      and u.id_empresa is not null
                      and not exists (select 1 from usuario_empresa ue
                                       where ue.usuario_id = u.usuario_id
                                         and ue.id_empresa  = u.id_empresa)]'
                into v_detalle;
        exception
            when others then
                v_error := sqlerrm;
                insert into tmp_multi_fallas
                values (substrb('M3: error al medir: ' || v_error, 1, 300));
        end;
        if v_detalle is not null then
            insert into tmp_multi_fallas
            values (substrb('M3: sin par en USUARIO_EMPRESA: ' || v_detalle, 1, 300));
        end if;
    end if;

    -- M5: ninguna empresa huerfana. Toda fila de EMPRESAS tiene al menos un
    -- par en USUARIO_EMPRESA (hoy cubre las tres 'dotech', 3/4/5).
    if v_tiene_tabla = 0 then
        insert into tmp_multi_fallas
        values (substrb('M5: no se puede medir, falta la tabla USUARIO_EMPRESA', 1, 300));
    else
        v_detalle := null;
        begin
            execute immediate
                q'[select substrb(listagg(e.id_empresa || ' (' || e.nombre_empresa || ')', ' | '
                              on overflow truncate) within group (order by e.id_empresa), 1, 2000)
                     from empresas e
                    where not exists (select 1 from usuario_empresa ue
                                       where ue.id_empresa = e.id_empresa)]'
                into v_detalle;
        exception
            when others then
                v_error := sqlerrm;
                insert into tmp_multi_fallas
                values (substrb('M5: error al medir: ' || v_error, 1, 300));
        end;
        if v_detalle is not null then
            insert into tmp_multi_fallas
            values (substrb('M5: empresas sin ningun usuario asociado: ' || v_detalle, 1, 300));
        end if;
    end if;

    -- M4: la vista devuelve MONEDA_LOCAL no nula para la empresa 1 (VE) y la 2 (MX).
    if v_tiene_vista = 0 then
        insert into tmp_multi_fallas
        values (substrb('M4: no se puede medir, falta la vista V_EMPRESAS_USUARIO', 1, 300));
    else
        v_detalle := null;
        begin
            execute immediate
                q'[select substrb(listagg(e.id_empresa || ' (' || e.cod_pais || ')', ' | '
                              on overflow truncate) within group (order by e.id_empresa), 1, 2000)
                     from empresas e
                    where e.cod_pais in ('VE','MX')
                      and not exists (select 1 from v_empresas_usuario v
                                       where v.id_empresa = e.id_empresa
                                         and v.moneda_local is not null)]'
                into v_detalle;
        exception
            when others then
                v_error := sqlerrm;
                insert into tmp_multi_fallas
                values (substrb('M4: error al medir: ' || v_error, 1, 300));
        end;
        if v_detalle is not null then
            insert into tmp_multi_fallas
            values (substrb('M4: la vista no devuelve MONEDA_LOCAL para: ' || v_detalle, 1, 300));
        end if;
    end if;
end;
/

-- -----------------------------------------------------------------------------
-- M6, M7, M8, M9 y M10: guardas y login por la tabla de asociacion.
--
-- Los usuarios de prueba se crean aqui (rango reservado 900000+), con clave
-- 'Diag#2026', y se BORRAN al final del bloque (no dependen del fixture de la
-- tarea anterior). Se usa SQL dinamico para los INSERT/DELETE porque USUARIO
-- y USUARIO_EMPRESA son objetos que podrian no existir todavia en una base
-- donde la tarea 1 todavia no se aplico.
-- -----------------------------------------------------------------------------
declare
    v_existe      number;
    v_error       varchar2(300);
    v_resultado   varchar2(10);
    v_cuenta      number;
    v_hash        varchar2(512);
    v_usuario_ok  varchar2(50) := 'DIAG_MULTI_01';
    v_usuario_sin varchar2(50) := 'DIAG_MULTI_02';
    v_empresa_a   number := 1;
    v_empresa_b   number := 2;
    v_empresa_c   number := 3;
begin
    select count(*) into v_existe from all_tables
     where owner = 'WKSP_SYPEXWS' and table_name = 'USUARIO_EMPRESA';
    if v_existe = 0 then
        insert into tmp_multi_fallas
        values (substrb('M6-M10: no se puede medir, falta la tabla USUARIO_EMPRESA', 1, 300));
    else
        begin
            -- M9/M10: usuario ACTIVO, con rol, con pares, pero ID_EMPRESA nulo.
            select sypex_hash_password('Diag#2026') into v_hash from dual;
            execute immediate
                q'[insert into usuario (usuario_id, username, email, password_hash, estado,
                                        rol_id, id_empresa, debe_cambiar_clave)
                   values (900001, :u, 'diag.multi.01@synpex.local', :h, 'ACTIVO',
                           (select min(id_rol) from syn_roles where codigo_rol = 'ADMIN'),
                           null, 'N')]'
                using v_usuario_ok, v_hash;

            execute immediate
                q'[insert into usuario_empresa (usuario_id, id_empresa)
                   values (900001, :e1)]' using v_empresa_a;
            execute immediate
                q'[insert into usuario_empresa (usuario_id, id_empresa)
                   values (900001, :e2)]' using v_empresa_b;

            -- Usuario sin ninguna asociacion (para M10).
            execute immediate
                q'[insert into usuario (usuario_id, username, email, password_hash, estado,
                                        rol_id, id_empresa, debe_cambiar_clave)
                   values (900002, :u, 'diag.multi.02@synpex.local', :h, 'ACTIVO',
                           (select min(id_rol) from syn_roles where codigo_rol = 'ADMIN'),
                           null, 'N')]'
                using v_usuario_sin, v_hash;

            -- M6: la guarda acepta las DOS empresas asociadas.
            if case when fn_usuario_empresa_valida(v_usuario_ok, v_empresa_a) then 1 else 0 end = 0 then
                insert into tmp_multi_fallas
                values (substrb('M6: fn_usuario_empresa_valida devolvio false para la empresa asociada 1', 1, 300));
            end if;
            if case when fn_usuario_empresa_valida(v_usuario_ok, v_empresa_b) then 1 else 0 end = 0 then
                insert into tmp_multi_fallas
                values (substrb('M6: fn_usuario_empresa_valida devolvio false para la empresa asociada 2', 1, 300));
            end if;

            -- M7: una tercera empresa sin par NO debe validar.
            if case when fn_usuario_empresa_valida(v_usuario_ok, v_empresa_c) then 1 else 0 end = 1 then
                insert into tmp_multi_fallas
                values (substrb('M7: fn_usuario_empresa_valida devolvio true para una empresa sin asociacion', 1, 300));
            end if;

            -- M8: inactivo con par, nulos y empresa inexistente.
            execute immediate
                q'[update usuario set estado = 'INACTIVO' where usuario_id = 900001]';
            if case when fn_usuario_empresa_valida(v_usuario_ok, v_empresa_a) then 1 else 0 end = 1 then
                insert into tmp_multi_fallas
                values (substrb('M8: fn_usuario_empresa_valida devolvio true para un usuario inactivo', 1, 300));
            end if;
            execute immediate
                q'[update usuario set estado = 'ACTIVO' where usuario_id = 900001]';
            if case when fn_usuario_empresa_valida(null, v_empresa_a) then 1 else 0 end = 1 then
                insert into tmp_multi_fallas
                values (substrb('M8: fn_usuario_empresa_valida devolvio true con usuario nulo', 1, 300));
            end if;
            if case when fn_usuario_empresa_valida(v_usuario_ok, null) then 1 else 0 end = 1 then
                insert into tmp_multi_fallas
                values (substrb('M8: fn_usuario_empresa_valida devolvio true con empresa nula', 1, 300));
            end if;
            if case when fn_usuario_empresa_valida(v_usuario_ok, 999999) then 1 else 0 end = 1 then
                insert into tmp_multi_fallas
                values (substrb('M8: fn_usuario_empresa_valida devolvio true para una empresa inexistente', 1, 300));
            end if;

            -- M9: usuario con ID_EMPRESA nulo pero con pares entra con la clave.
            v_resultado := case when fn_autenticar_usuario(v_usuario_ok, 'Diag#2026')
                                then 'TRUE' else 'FALSE' end;
            if v_resultado <> 'TRUE' then
                insert into tmp_multi_fallas
                values (substrb('M9: fn_autenticar_usuario devolvio ' || v_resultado
                                || ' para un usuario con ID_EMPRESA nulo y pares', 1, 300));
            end if;

            -- M10: la consulta de prc_post_login, con el usuario como literal.
            execute immediate
                q'[select count(*) from usuario u
                    join syn_roles r on r.id_rol = u.rol_id
                   where upper(u.username) = upper(:u)
                     and u.estado in ('ACTIVO', 'A', '1')
                     and exists (select 1 from usuario_empresa ue where ue.usuario_id = u.usuario_id)]'
                into v_cuenta using v_usuario_ok;
            if v_cuenta <> 1 then
                insert into tmp_multi_fallas
                values (substrb('M10: la consulta de prc_post_login devolvio ' || v_cuenta
                                || ' filas para un usuario con pares (se esperaba 1)', 1, 300));
            end if;

            execute immediate
                q'[select count(*) from usuario u
                    join syn_roles r on r.id_rol = u.rol_id
                   where upper(u.username) = upper(:u)
                     and u.estado in ('ACTIVO', 'A', '1')
                     and exists (select 1 from usuario_empresa ue where ue.usuario_id = u.usuario_id)]'
                into v_cuenta using v_usuario_sin;
            if v_cuenta <> 0 then
                insert into tmp_multi_fallas
                values (substrb('M10: la consulta de prc_post_login devolvio ' || v_cuenta
                                || ' filas para un usuario sin asociacion (se esperaba 0)', 1, 300));
            end if;
        exception
            when others then
                v_error := sqlerrm;
                insert into tmp_multi_fallas
                values (substrb('M6-M10: error al medir: ' || v_error, 1, 300));
        end;

        -- Limpieza: primero las asociaciones, luego los usuarios.
        begin
            execute immediate q'[delete from usuario_empresa where usuario_id in (900001, 900002)]';
        exception when others then null;
        end;
        begin
            execute immediate q'[delete from usuario where usuario_id in (900001, 900002)]';
        exception when others then null;
        end;
    end if;
end;
/

-- -----------------------------------------------------------------------------
-- M11, M12 y M13: la LOV EMPRESA lista TODAS las empresas del usuario.
--
-- El caso mide la CONSULTA REAL guardada por APEX (APEX_APPLICATION_LOVS.
-- LIST_OF_VALUES_QUERY), no una copia escrita a mano: si el texto guardado y
-- el que se espera divergen, el caso tiene que fallar.
--
-- Para ejecutarla hace falta un usuario de prueba:
--   DIAG_LOV_01  -> pares en las empresas 1 y 2 (las dos ACTIVO)
--   DIAG_LOV_02  -> par solo en la empresa 1
--   DIAG_LOV_03  -> par en la empresa 1 y en una empresa INACTIVA de prueba
-- Se borran al final (rango reservado 900003+ y la empresa 900010).
--
-- OJO: en M13 el usuario tiene DOS pares (una empresa ACTIVO y otra INACTIVA)
-- y su USUARIO.ID_EMPRESA apunta a la INACTIVA. Asi el caso mide las dos
-- cosas de una vez: la consulta tiene que LEER EL PAR (si leyera la columna
-- unica devolveria 0 filas en vez de 1) y tiene que FILTRAR LAS EMPRESAS
-- INACTIVAS (si no filtrara, devolveria 2 filas en vez de 1).
--
-- El texto guardado se envuelve en 'select count(*) from (<texto>)' para
-- poder contarlo: la LOV devuelve dos columnas (display_value, return_value)
-- y un 'execute immediate ... into' de un escalar no compila (ORA-00932).
-- Se le quita el ';' final: el texto viejo de la LOV lo traia y dentro de
-- un parentesis es ORA-00911.
--
-- TRAMPA MEDIDA (ORA-12839): en esta base, varias DML seguidas sobre tablas
-- con identity en la MISMA transaccion dan 'cannot modify an object in
-- parallel after modifying it'. Por eso la siembra, la medicion y la
-- limpieza van en bloques separados, con 'commit' entre ellos. Por lo mismo
-- el bloque de siembra empieza barriendo lo que dejo una corrida anterior
-- (los nombres son propios de esta verificacion, 'DIAG LOV ...'), y el de
-- limpieza esta al final aunque la medicion falle.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- M11: el texto guardado en APEX_APPLICATION_LOVS para la LOV 'EMPRESA'
--      menciona V_EMPRESAS_USUARIO y conserva el filtro e.estado = 'ACTIVO'.
-- -----------------------------------------------------------------------------
declare
    v_error varchar2(300);
    v_texto varchar2(4000);
begin
    begin
        select l.list_of_values_query into v_texto
          from apex_application_lovs l
         where l.list_of_values_name = 'EMPRESA';
    exception
        when no_data_found then
            v_texto := null;
        when others then
            v_error := sqlerrm;
            insert into tmp_multi_fallas
            values (substrb('M11: error al leer la LOV EMPRESA: ' || v_error, 1, 300));
    end;

    if v_texto is null and v_error is null then
        insert into tmp_multi_fallas
        values (substrb('M11: no se encuentra la LOV EMPRESA en APEX_APPLICATION_LOVS', 1, 300));
    elsif v_texto is not null then
        if lower(v_texto) not like '%v_empresas_usuario%' then
            insert into tmp_multi_fallas
            values (substrb('M11: la LOV EMPRESA no lee V_EMPRESAS_USUARIO: '
                            || substrb(v_texto, 1, 200), 1, 300));
        end if;
        if upper(v_texto) not like '%ESTADO = ''ACTIVO''%' then
            insert into tmp_multi_fallas
            values (substrb('M11: la LOV EMPRESA no conserva el filtro e.estado = ''ACTIVO'': '
                            || substrb(v_texto, 1, 200), 1, 300));
        end if;
    end if;
end;
/

-- -----------------------------------------------------------------------------
-- Siembra de los datos de prueba de M12 y M13. Barre primero lo que quedo de
-- una corrida anterior (por si una corrida se interrumpio entre la siembra y
-- la limpieza) y luego crea la empresa INACTIVA y los tres usuarios.
-- -----------------------------------------------------------------------------
declare
    v_error varchar2(300);
begin
    -- Barrido de restos de una corrida anterior. Un 'commit' despues de
    -- cada DELETE: en esta base, dos DML sobre tablas con identity en la
    -- misma transaccion dan ORA-12839 (medido).
    begin
        execute immediate q'[delete from usuario_empresa
                            where usuario_id in (900003, 900004, 900005)
                               or id_empresa = 900010]';
        commit;
    exception when others then null;
    end;
    begin
        execute immediate q'[delete from usuario where usuario_id in (900003, 900004, 900005)]';
        commit;
    exception when others then null;
    end;
    begin
        execute immediate q'[delete from empresas where id_empresa = 900010]';
        commit;
    exception when others then null;
    end;

    begin
        -- Empresa de prueba INACTIVA (id manual para poder borrarla sin
        -- depender de la secuencia).
        execute immediate
            q'[insert into empresas (id_empresa, nombre_empresa, estado, cod_pais, tipo_ident_fiscal)
               values (900010, 'DIAG LOV INACTIVA', 'INACTIVO', 'VE', 'RIF')]';
        commit;
    exception
        when others then
            v_error := sqlerrm;
            insert into tmp_multi_fallas
            values (substrb('M12-M13: no se pudo crear la empresa de prueba: ' || v_error, 1, 300));
    end;

    -- Los tres usuarios de prueba. USUARIO.ID_EMPRESA se deja en la empresa
    -- principal (salvo el tercero): la consulta nueva NO debe mirarlo (lee
    -- los pares), asi que ponerlo no cambia el resultado esperado.
    begin
        execute immediate
            q'[insert into usuario (usuario_id, username, email, password_hash, estado,
                                    rol_id, id_empresa, debe_cambiar_clave)
               values (900003, 'DIAG_LOV_01', 'diag.lov.01@synpex.local', 'x', 'ACTIVO',
                       (select min(id_rol) from syn_roles where codigo_rol = 'ADMIN'), 1, 'N')]';
        commit;
        execute immediate
            q'[insert into usuario (usuario_id, username, email, password_hash, estado,
                                    rol_id, id_empresa, debe_cambiar_clave)
               values (900004, 'DIAG_LOV_02', 'diag.lov.02@synpex.local', 'x', 'ACTIVO',
                       (select min(id_rol) from syn_roles where codigo_rol = 'ADMIN'), 1, 'N')]';
        commit;
        execute immediate
            q'[insert into usuario (usuario_id, username, email, password_hash, estado,
                                    rol_id, id_empresa, debe_cambiar_clave)
               values (900005, 'DIAG_LOV_03', 'diag.lov.03@synpex.local', 'x', 'ACTIVO',
                       (select min(id_rol) from syn_roles where codigo_rol = 'ADMIN'), 900010, 'N')]';
        commit;

        execute immediate
            q'[insert into usuario_empresa (usuario_id, id_empresa)
               select u, e from (
                   select 900003 u, 1 e from dual
               union all select 900003 u, 2 e from dual
               union all select 900004 u, 1 e from dual
               union all select 900005 u, 1 e from dual
               union all select 900005 u, 900010 e from dual) p
                where not exists (select 1 from usuario_empresa x
                                   where x.usuario_id = p.u and x.id_empresa = p.e)]';
        commit;
    exception
        when others then
            v_error := sqlerrm;
            insert into tmp_multi_fallas
            values (substrb('M12-M13: no se pudieron crear los usuarios de prueba: ' || v_error, 1, 300));
    end;
end;
/

-- -----------------------------------------------------------------------------
-- M12 y M13: se ejecuta el texto GUARDADO de la LOV con cada usuario de
-- prueba y se cuentan las empresas que devuelve.
-- -----------------------------------------------------------------------------
declare
    v_existe number;
    v_cuenta number;
    v_lista  varchar2(2000);

    -- Cuenta las filas que devuelve el texto guardado de la LOV para un
    -- usuario dado. Si la consulta no se puede ejecutar (texto roto, objeto
    -- que no existe), devuelve -1 para que el caso lo reporte como fallo.
    function contar_lov(p_usuario varchar2) return number is
        v_txt varchar2(4000);
        v_cnt number;
    begin
        select l.list_of_values_query into v_txt
          from apex_application_lovs l
         where l.list_of_values_name = 'EMPRESA';
        v_txt := rtrim(rtrim(v_txt), ';');
        execute immediate 'select count(*) from (' || v_txt || ')'
           into v_cnt using p_usuario;
        return v_cnt;
    exception
        when others then
            return -1;
    end contar_lov;

    -- Devuelve la lista de ID_EMPRESA que la LOV guardada devuelve para un
    -- usuario, separada por '|'. Si la consulta no se puede ejecutar,
    -- devuelve la cadena 'ERROR'.
    function ids_lov(p_usuario varchar2) return varchar2 is
        v_txt varchar2(4000);
        v_lis varchar2(2000);
    begin
        select l.list_of_values_query into v_txt
          from apex_application_lovs l
         where l.list_of_values_name = 'EMPRESA';
        v_txt := rtrim(rtrim(v_txt), ';');
        execute immediate
            q'[select listagg(t.return_value, '|') within group (order by t.return_value)
                  from (]'
            || v_txt
            || q'[) t]'
            into v_lis using p_usuario;
        return v_lis;
    exception
        when others then
            return 'ERROR';
    end ids_lov;
begin
    select count(*) into v_existe from all_tables
     where owner = 'WKSP_SYPEXWS' and table_name = 'USUARIO_EMPRESA';

    if v_existe = 0 then
        insert into tmp_multi_fallas
        values (substrb('M12-M13: no se puede medir, falta la tabla USUARIO_EMPRESA', 1, 300));
    else
        -- M12: el usuario de dos empresas ve las DOS; el de una, ve UNA.
        v_cuenta := contar_lov('DIAG_LOV_01');
        if v_cuenta <> 2 then
            insert into tmp_multi_fallas
            values (substrb('M12: la LOV devolvio ' || v_cuenta
                            || ' empresas para un usuario con 2 pares (se esperaba 2)', 1, 300));
        end if;
        v_lista := ids_lov('DIAG_LOV_01');
        if v_lista <> '1|2' then
            insert into tmp_multi_fallas
            values (substrb('M12: la LOV devolvio las empresas ' || v_lista
                            || ' para un usuario con pares en la 1 y la 2 (se esperaba 1|2)', 1, 300));
        end if;

        v_cuenta := contar_lov('DIAG_LOV_02');
        if v_cuenta <> 1 then
            insert into tmp_multi_fallas
            values (substrb('M12: la LOV devolvio ' || v_cuenta
                            || ' empresas para un usuario con 1 par (se esperaba 1)', 1, 300));
        end if;
        v_lista := ids_lov('DIAG_LOV_02');
        if v_lista <> '1' then
            insert into tmp_multi_fallas
            values (substrb('M12: la LOV devolvio las empresas ' || v_lista
                            || ' para un usuario con un solo par en la 1 (se esperaba 1)', 1, 300));
        end if;

        -- M13: la empresa INACTIVA no aparece, pero la ACTIVA si.
        v_cuenta := contar_lov('DIAG_LOV_03');
        if v_cuenta <> 1 then
            insert into tmp_multi_fallas
            values (substrb('M13: la LOV devolvio ' || v_cuenta
                            || ' empresas para un usuario con un par ACTIVO y otro INACTIVO'
                            || ' (se esperaba 1, solo la ACTIVA)', 1, 300));
        end if;
        v_lista := ids_lov('DIAG_LOV_03');
        if v_lista <> '1' then
            insert into tmp_multi_fallas
            values (substrb('M13: la LOV devolvio las empresas ' || v_lista
                            || ' para un usuario con un par ACTIVO y otro INACTIVO'
                            || ' (se esperaba 1: la INACTIVA no debe salir)', 1, 300));
        end if;
    end if;
end;
/

-- -----------------------------------------------------------------------------
-- Limpieza de los datos de prueba de M12 y M13. Va SIEMPRE, aunque la
-- medicion haya fallado: los datos de prueba no se quedan en la base.
-- -----------------------------------------------------------------------------
begin
    begin
        execute immediate q'[delete from usuario_empresa
                            where usuario_id in (900003, 900004, 900005)
                               or id_empresa = 900010]';
        commit;
    exception when others then null;
    end;
    begin
        execute immediate q'[delete from usuario where usuario_id in (900003, 900004, 900005)]';
        commit;
    exception when others then null;
    end;
    begin
        execute immediate q'[delete from empresas where id_empresa = 900010]';
        commit;
    exception when others then null;
    end;
end;
/

-- =============================================================================
-- Tarea 6: pagina 19 Ã‚Â«AdministracionÃ‚Â» Ã¢â‚¬â€ listado de empresas del usuario y
-- alta que asocia al creador.
--
--   M14 Ampliado: NINGUNA consulta guardada por APEX (regiones, items, LOVs,
--       condiciones y TAMBIEN los procesos de pagina) sigue leyendo
--       'id_empresa from usuario' ni 'min(u.id_empresa)'. La tarea 4 lo
--       excluia a proposito (el proceso Ã‚Â«Carga la empresa del usuarioÃ‚Â» de la
--       pagina 19); aqui ya se incluye, porque la tarea 6 lo cambia.
--   M23 Un usuario con DOS empresas ve las DOS en el listado de la pagina 19:
--       se ejecuta el TEXTO GUARDADO de la region Ã‚Â«Mis empresasÃ‚Â» con
--       ':APP_USER' sustituido.
--   M24 El proceso real Ã‚Â«Guardar empresaÃ‚Â» (alta) inserta la empresa Y deja el
--       par en USUARIO_EMPRESA para ':APP_USER'.
--   M25 Editar una empresa que NO es del usuario lanza -20003 y no cambia nada.
--
-- PATRON (R3 del ledger): los procesos de pagina no se pueden ejecutar desde
-- el runner, asi que se COPIAN desde APEX_APPLICATION_PAGE_PROC (el texto
-- guardado, no una copia a mano) y se ejecutan con los binds sustituidos.
-- El cuerpo se envuelve en un bloque anonimo y se ejecuta con
-- 'execute immediate', de modo que un 'raise_application_error' se puede
-- capturar con el manejador y comprobar el codigo (-20003).
--
-- El proceso Ã‚Â«Guardar empresaÃ‚Â» llama a fn_tiene_rol, que mira
-- apex_application.g_user: en una sesion SQL esa variable es nula y la
-- funcion devuelve FALSE. Por eso, ANTES de ejecutarlo, se fija
-- apex_application.g_user con el usuario de prueba (en el MISMO bloque, porque
-- el valor no sobrevive a un cambio de sentencia).
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Siembra de los datos de prueba de M23, M24 y M25 (rango reservado 900000+).
--
--   DIAG_P19_A  -> pares en las empresas 1 y 3 (las dos del usuario)
--   DIAG_P19_B  -> par solo en la empresa 1 (regresion: una sola empresa)
--   La empresa 900020 es de prueba y se borra al final.
--
-- Se usa SQL dinamico porque USUARIO_EMPRESA y EMPRESAS podrian no existir en
-- una base donde la tarea 1 todavia no se aplico.
-- -----------------------------------------------------------------------------
declare
    v_error varchar2(300);
    v_hash  varchar2(512);
begin
    select sypex_hash_password('Diag#2026') into v_hash from dual;

    -- Barrido de restos de una corrida anterior.
    begin
        execute immediate q'[delete from usuario_empresa
                            where usuario_id in (900020, 900021)
                               or id_empresa = 900020]';
        commit;
    exception when others then null;
    end;
    begin
        execute immediate q'[delete from usuario where usuario_id in (900020, 900021)]';
        commit;
    exception when others then null;
    end;
    begin
        execute immediate q'[delete from empresas where id_empresa = 900020]';
        commit;
    exception when others then null;
    end;

    begin
        execute immediate
            q'[insert into usuario (usuario_id, username, email, password_hash, estado,
                                    id_empresa, rol_id, debe_cambiar_clave)
               values (900020, 'DIAG_P19_A', 'diag.p19.a@synpex.local', :h, 'ACTIVO',
                       1, (select min(id_rol) from syn_roles where codigo_rol = 'ADMIN'), 'N')]'
            using v_hash;
        commit;
        execute immediate
            q'[insert into usuario (usuario_id, username, email, password_hash, estado,
                                    id_empresa, rol_id, debe_cambiar_clave)
               values (900021, 'DIAG_P19_B', 'diag.p19.b@synpex.local', :h, 'ACTIVO',
                       1, (select min(id_rol) from syn_roles where codigo_rol = 'ADMIN'), 'N')]'
            using v_hash;
        commit;
    exception
        when others then
            v_error := sqlerrm;
            insert into tmp_multi_fallas
            values (substrb('M23-M25: no se pudieron crear los usuarios de prueba: ' || v_error, 1, 300));
    end;

    begin
        execute immediate
            q'[insert into usuario_empresa (usuario_id, id_empresa)
               select u, e from (
                   select 900020 u, 1 e from dual
               union all select 900020 u, 3 e from dual
               union all select 900021 u, 1 e from dual) p
                where not exists (select 1 from usuario_empresa x
                                   where x.usuario_id = p.u and x.id_empresa = p.e)]';
        commit;
    exception
        when others then
            v_error := sqlerrm;
            insert into tmp_multi_fallas
            values (substrb('M23-M25: no se pudieron crear las asociaciones de prueba: ' || v_error, 1, 300));
    end;
end;
/

-- -----------------------------------------------------------------------------
-- M23: el listado de la pagina 19 (region Ã‚Â«Mis empresasÃ‚Â») devuelve TODAS las
-- empresas del usuario.
--
-- Se mide el TEXTO GUARDADO por APEX (APEX_APPLICATION_PAGE_REGIONS.
-- REGION_SOURCE de la region con STATIC_ID 'admin-mis-empresas'), no una copia
-- escrita a mano: si el texto guardado y el que se espera divergen, el caso
-- tiene que fallar. La consulta se envuelve en 'select count(*) from (...)'
-- para poder contarla, y se ejecuta con ':APP_USER' sustituido por el usuario
-- de prueba.
-- -----------------------------------------------------------------------------
declare
    v_error   varchar2(300);
    v_texto   clob;
    v_cuenta  number;
    v_estado  number;
begin
    select count(*) into v_estado
      from apex_application_page_regions
     where application_id = 100 and page_id = 19
       and region_static_id = 'admin-mis-empresas';

    if v_estado = 0 then
        insert into tmp_multi_fallas
        values (substrb('M23: la pagina 19 no tiene la region Ã‚Â«Mis empresasÃ‚Â» (static_id admin-mis-empresas)', 1, 300));
    else
        begin
            select region_source into v_texto
              from apex_application_page_regions
             where application_id = 100 and page_id = 19
               and region_static_id = 'admin-mis-empresas';

            -- Con dos empresas: el listado tiene que devolver las DOS.
            execute immediate 'select count(*) from (' || v_texto || ')' into v_cuenta using 'DIAG_P19_A';
            if v_cuenta <> 2 then
                insert into tmp_multi_fallas
                values (substrb('M23: el listado devolvio ' || v_cuenta
                                || ' empresas para un usuario con 2 pares (se esperaba 2)', 1, 300));
            end if;

            -- Con una empresa: el listado tiene que devolver UNA (regresion).
            execute immediate 'select count(*) from (' || v_texto || ')' into v_cuenta using 'DIAG_P19_B';
            if v_cuenta <> 1 then
                insert into tmp_multi_fallas
                values (substrb('M23: el listado devolvio ' || v_cuenta
                                || ' empresas para un usuario con 1 par (se esperaba 1)', 1, 300));
            end if;

            -- Y el listado no puede traer empresas de otro usuario: con un
            -- usuario sin pares tiene que devolver 0.
            execute immediate 'select count(*) from (' || v_texto || ')' into v_cuenta using 'DIAG_P19_SIN_PAR';
            if v_cuenta <> 0 then
                insert into tmp_multi_fallas
                values (substrb('M23: el listado devolvio ' || v_cuenta
                                || ' empresas para un usuario sin pares (se esperaba 0)', 1, 300));
            end if;
        exception
            when others then
                v_error := sqlerrm;
                insert into tmp_multi_fallas
                values (substrb('M23: no se pudo ejecutar el texto guardado de la region: ' || v_error, 1, 300));
        end;
    end if;
end;
/

-- -----------------------------------------------------------------------------
-- M24 y M25: el proceso real Ã‚Â«Guardar empresaÃ‚Â» (pÃƒÂ¡gina 19).
--
-- El cuerpo sale de APEX_APPLICATION_PAGE_PROC (texto guardado) y se ejecuta
-- con los binds sustituidos por literales. Se ejecuta con 'execute immediate'
-- para poder capturar el 'raise_application_error' del manejador y leer su
-- codigo (M25 espera -20003).
--
-- MEDIDO en esta base (2026-11-10): 'apex_util.set_session_state' y
-- 'apex_application.g_print_success_message' funcionan fuera de una peticion
-- de APEX, asi que el cuerpo guardado se puede ejecutar TAL CUAL, sin
-- mutilarlo. Lo unico que hay que preparar es apex_application.g_user, que
-- fn_tiene_rol lee para la guarda de rol: se fija en el MISMO bloque (el valor
-- no sobrevive al cambio de sentencia) y se restaura al final.
--
-- M24 (ALTA): el proceso tiene que insertar la empresa Y el par en
--      USUARIO_EMPRESA para ':APP_USER'.
-- M25 (EDICION AJENA): con un id de empresa que no es del usuario, el proceso
--      tiene que lanzar -20003 y NO cambiar nada.
--
-- El alta real de M24 se hace con un nombre propio de la verificacion
-- ('DIAG P19 ALTA') y la empresa se borra al final. La transaccion NO se
-- revierte (el proceso inserta y hace falta comprobarlo), asi que la limpieza
-- va en un bloque aparte.
-- -----------------------------------------------------------------------------
declare
    v_error  varchar2(300);
    v_cuerpo clob;
    v_codigo number;
    v_cuenta number;
    v_id     number;
    v_nombre constant varchar2(50) := 'DIAG P19 ALTA';
    v_g_user_anterior varchar2(100);
begin
    -- El cuerpo guardado del proceso Ã‚Â«Guardar empresaÃ‚Â».
    begin
        select process_source into v_cuerpo
          from apex_application_page_proc
         where application_id = 100 and page_id = 19
           and process_name = 'Guardar empresa';
    exception
        when no_data_found then
            insert into tmp_multi_fallas
            values (substrb('M24-M25: no se encuentra el proceso Ã‚Â«Guardar empresaÃ‚Â» de la pagina 19', 1, 300));
            v_cuerpo := null;
        when others then
            v_error := sqlerrm;
            insert into tmp_multi_fallas
            values (substrb('M24-M25: error al leer el proceso: ' || v_error, 1, 300));
            v_cuerpo := null;
    end;

    if v_cuerpo is not null then
        v_g_user_anterior := apex_application.g_user;

        -- ---------------------------------------------------------------------
        -- M24: ALTA. Binds sustituidos por literales.
        --
        -- ':P19_ID_EMPRESA' -> 'null' (sin id = alta).
        -- OJO: el orden de los 'replace' importa: si se reemplazara 'null'
        -- despues, se romperia el 'null' del alta. Por eso el id se
        -- sustituye por un texto que no aparece en el cuerpo ('<ID_VACIO>')
        -- y se cambia a 'null' al final.
        -- ---------------------------------------------------------------------
        declare
            v_c clob := v_cuerpo;
        begin
            v_c := replace(v_c, ':P19_ID_EMPRESA', '<ID_VACIO>');
            v_c := replace(v_c, ':P19_NOMBRE_EMPRESA', '''' || v_nombre || '''');
            v_c := replace(v_c, ':P19_COD_PAIS', '''VE''');
            v_c := replace(v_c, ':P19_TIPO_IDENT_FISCAL', '''RIF''');
            v_c := replace(v_c, ':P19_RFC', '''DIAG-P19-RIF''');
            v_c := replace(v_c, ':P19_ESTADO', '''ACTIVO''');
            v_c := replace(v_c, ':APP_USER', '''DIAG_P19_A''');
            v_c := replace(v_c, '<ID_VACIO>', 'null');

            apex_application.g_user := 'DIAG_P19_A';
            begin
                execute immediate 'begin ' || v_c || ' end;';
                v_codigo := 0;
            exception
                when others then
                    v_codigo := sqlcode;
            end;
        end;

        if v_codigo <> 0 then
            insert into tmp_multi_fallas
            values (substrb('M24: el alta devolvio el codigo ' || v_codigo || ' (se esperaba 0)', 1, 300));
        end if;

        -- La empresa se creo y el par quedo en USUARIO_EMPRESA.
        select count(*) into v_cuenta
          from empresas e
         where e.nombre_empresa = v_nombre;
        if v_cuenta <> 1 then
            insert into tmp_multi_fallas
            values (substrb('M24: el alta no dejo una empresa llamada Ã‚Â«' || v_nombre
                            || 'Ã‚Â» (se esperaba 1, se hallaron ' || v_cuenta || ')', 1, 300));
        else
            select min(id_empresa) into v_id
              from empresas where nombre_empresa = v_nombre;
            select count(*) into v_cuenta
              from usuario_empresa ue
              join usuario u on u.usuario_id = ue.usuario_id
             where upper(u.username) = 'DIAG_P19_A'
               and ue.id_empresa = v_id;
            if v_cuenta <> 1 then
                insert into tmp_multi_fallas
                values (substrb('M24: el alta no dejo el par en USUARIO_EMPRESA para el creador'
                                || ' (se esperaba 1, se hallaron ' || v_cuenta || ')', 1, 300));
            end if;
        end if;

        -- ---------------------------------------------------------------------
        -- M25: EDICION de una empresa AJENA.
        --
        -- Se usa la empresa 5 (una 'dotech' real, que NO es de DIAG_P19_A):
        -- se guarda su nombre y su RIF, se intenta editarla y se comprueba que
        -- el proceso da -20003 y que los datos NO cambian.
        -- ---------------------------------------------------------------------
        declare
            v_ajena number := 5;
            v_nombre_ajeno varchar2(150);
            v_rfc_ajeno varchar2(20);
            v_c clob := v_cuerpo;
            v_cod number;
        begin
            select nombre_empresa, rfc into v_nombre_ajeno, v_rfc_ajeno
              from empresas where id_empresa = v_ajena;

            v_c := replace(v_c, ':P19_ID_EMPRESA', to_char(v_ajena));
            v_c := replace(v_c, ':P19_NOMBRE_EMPRESA', '''DIAG P19 AJENA''');
            v_c := replace(v_c, ':P19_COD_PAIS', '''VE''');
            v_c := replace(v_c, ':P19_TIPO_IDENT_FISCAL', '''RIF''');
            v_c := replace(v_c, ':P19_RFC', '''DIAG-ALTERADO''');
            v_c := replace(v_c, ':P19_ESTADO', '''ACTIVO''');
            v_c := replace(v_c, ':APP_USER', '''DIAG_P19_A''');

            apex_application.g_user := 'DIAG_P19_A';
            begin
                execute immediate 'begin ' || v_c || ' end;';
                v_cod := 0;
            exception
                when others then
                    v_cod := sqlcode;
            end;

            if v_cod <> -20003 then
                insert into tmp_multi_fallas
                values (substrb('M25: editar una empresa ajena no dio -20003 (dio el codigo '
                                || v_cod || ')', 1, 300));
            end if;

            select count(*) into v_cuenta
              from empresas
             where id_empresa = v_ajena
               and nombre_empresa = v_nombre_ajeno
               and rfc = v_rfc_ajeno;
            if v_cuenta <> 1 then
                insert into tmp_multi_fallas
                values (substrb('M25: la edicion de una empresa ajena CAMBIO sus datos'
                                || ' (se esperaba que quedaran intactos)', 1, 300));
            end if;
        end;

        apex_application.g_user := v_g_user_anterior;
    end if;
end;
/

-- -----------------------------------------------------------------------------
-- M26 (regresion, anadida el 2026-11-10 tras un fallo real): el proceso
-- Ã‚Â«Carga la empresa del usuarioÃ‚Â» (BEFORE_HEADER de la pagina 19) NO puede
-- lanzar NO_DATA_FOUND cuando el usuario tiene DOS empresas.
--
-- MEDIDO: el 'select min(id_empresa) ... having count(*) = 1' deja la consulta
-- SIN filas si el usuario tiene mas de una empresa, y eso es NO_DATA_FOUND
-- (ORA-01403). Sin manejador, el proceso tumbaba la pagina entera con la
-- pantalla de error Ã‚Â«No se ha encontrado ningun datoÃ‚Â».
--
-- Se ejecuta el CUERPO GUARDADO del proceso (no una copia) con los binds
-- sustituidos:
--   - ':P19_ID_EMPRESA' -> 'null'   (el listado no trajo ninguna)
--   - ':APP_USER'      -> 'DIAG_P19_A' (el usuario de DOS empresas)
-- Se espera codigo 0 (sin excepcion). Con una empresa y con el id del listado
-- tambien tiene que salir sin excepcion.
-- -----------------------------------------------------------------------------
declare
    v_error  varchar2(300);
    v_cuerpo clob;
    v_codigo number;
    v_g_user_anterior varchar2(100);
begin
    begin
        select process_source into v_cuerpo
          from apex_application_page_proc
         where application_id = 100 and page_id = 19
           and process_name = 'Carga la empresa del usuario';
    exception
        when no_data_found then
            insert into tmp_multi_fallas
            values (substrb('M26: no se encuentra el proceso Ã‚Â«Carga la empresa del usuarioÃ‚Â» de la pagina 19', 1, 300));
            v_cuerpo := null;
        when others then
            v_error := sqlerrm;
            insert into tmp_multi_fallas
            values (substrb('M26: error al leer el proceso: ' || v_error, 1, 300));
            v_cuerpo := null;
    end;

    if v_cuerpo is not null then
        v_g_user_anterior := apex_application.g_user;
        apex_application.g_user := 'DIAG_P19_A';

        -- (a) Usuario de DOS empresas y sin id en el listado: no debe fallar.
        -- OJO: hay que sustituir TODOS los binds del cuerpo. Si se queda uno
        -- sin sustituir, la ejecucion falla con ORA-01008 ('value for bind
        -- variable placeholder 1 was not provided'), que no es un fallo del
        -- proceso pero tapa el resultado real.
        declare
            v_c clob := v_cuerpo;
        begin
            v_c := replace(v_c, ':P19_ID_EMPRESA', 'null');
            v_c := replace(v_c, ':P19_MODO', '''VER''');
            v_c := replace(v_c, ':P19_ESTADO', '''ACTIVO''');
            v_c := replace(v_c, ':APP_USER', '''DIAG_P19_A''');
            begin
                execute immediate 'begin ' || v_c || ' end;';
                v_codigo := 0;
            exception
                when others then
                    v_codigo := sqlcode;
            end;
            if v_codigo <> 0 then
                insert into tmp_multi_fallas
                values (substrb('M26: la carga con un usuario de 2 empresas dio el codigo '
                                || v_codigo || ' (se esperaba 0; NO_DATA_FOUND = -1 '
                                || 'tumba la pagina con ORA-01403)', 1, 300));
            end if;
        end;

        -- (b) Usuario de UNA empresa: tampoco debe fallar.
        declare
            v_c clob := v_cuerpo;
        begin
            v_c := replace(v_c, ':P19_ID_EMPRESA', 'null');
            v_c := replace(v_c, ':P19_MODO', '''VER''');
            v_c := replace(v_c, ':P19_ESTADO', '''ACTIVO''');
            v_c := replace(v_c, ':APP_USER', '''DIAG_P19_B''');
            begin
                execute immediate 'begin ' || v_c || ' end;';
                v_codigo := 0;
            exception
                when others then
                    v_codigo := sqlcode;
            end;
            if v_codigo <> 0 then
                insert into tmp_multi_fallas
                values (substrb('M26: la carga con un usuario de 1 empresa dio el codigo '
                                || v_codigo || ' (se esperaba 0)', 1, 300));
            end if;
        end;

        -- (c) Con el id que trae el listado: tampoco debe fallar.
        declare
            v_c clob := v_cuerpo;
        begin
            v_c := replace(v_c, ':P19_ID_EMPRESA', '3');
            v_c := replace(v_c, ':P19_MODO', '''VER''');
            v_c := replace(v_c, ':P19_ESTADO', '''ACTIVO''');
            v_c := replace(v_c, ':APP_USER', '''DIAG_P19_A''');
            begin
                execute immediate 'begin ' || v_c || ' end;';
                v_codigo := 0;
            exception
                when others then
                    v_codigo := sqlcode;
            end;
            if v_codigo <> 0 then
                insert into tmp_multi_fallas
                values (substrb('M26: la carga con el id del listado dio el codigo '
                                || v_codigo || ' (se esperaba 0)', 1, 300));
            end if;
        end;

        -- (d) Con el id de una empresa AJENA: la carga no debe fallar (el
        -- proceso sale con 'return' y no carga nada), pero tampoco puede
        -- dejar la empresa ajena en el formulario.
        declare
            v_c clob := v_cuerpo;
        begin
            v_c := replace(v_c, ':P19_ID_EMPRESA', '5');
            v_c := replace(v_c, ':P19_MODO', '''VER''');
            v_c := replace(v_c, ':P19_ESTADO', '''ACTIVO''');
            v_c := replace(v_c, ':APP_USER', '''DIAG_P19_A''');
            begin
                execute immediate 'begin ' || v_c || ' end;';
                v_codigo := 0;
            exception
                when others then
                    v_codigo := sqlcode;
            end;
            if v_codigo <> 0 then
                insert into tmp_multi_fallas
                values (substrb('M26: la carga con una empresa ajena dio el codigo '
                                || v_codigo || ' (se esperaba 0)', 1, 300));
            end if;
        end;

        apex_application.g_user := v_g_user_anterior;
    end if;
end;
/

-- -----------------------------------------------------------------------------
-- Limpieza de los datos de prueba de M23, M24 y M25. Va SIEMPRE, aunque la
-- medicion haya fallado: los datos de prueba no se quedan en la base.
-- -----------------------------------------------------------------------------
begin
    begin
        execute immediate q'[delete from usuario_empresa
                            where usuario_id in (900020, 900021)
                               or id_empresa in (900020,
                                   (select min(id_empresa) from empresas where nombre_empresa = 'DIAG P19 ALTA'))]';
        commit;
    exception when others then null;
    end;
    begin
        execute immediate q'[delete from empresas where nombre_empresa = 'DIAG P19 ALTA']';
        commit;
    exception when others then null;
    end;
    begin
        execute immediate q'[delete from usuario_empresa where usuario_id in (900020, 900021)]';
        commit;
    exception when others then null;
    end;
    begin
        execute immediate q'[delete from usuario where usuario_id in (900020, 900021)]';
        commit;
    exception when others then null;
    end;
end;
/

-- =============================================================================
-- TAREA 4: filtros, defectos y condiciones por empresa (27 sitios del export).
--
-- Los 27 sitios se cambiaron para que lean la vista V_EMPRESAS_USUARIO (la
-- tabla de asociacion USUARIO_EMPRESA) en vez de la columna unica
-- USUARIO.ID_EMPRESA. Esta seccion lo COMPRUEBA:
--
--   M14 (AMPLIADO) Ninguna consulta guardada por APEX -regiones, p_query_where
--       de las regiones de formulario, items, LOVs de la app y TAMBIEN los
--       procesos de pagina, ya incluida la pagina 19- sigue leyendo la columna
--       unica del usuario. Ademas, cada pagina de la tabla del brief tiene que
--       leer la vista V_EMPRESAS_USUARIO (y la pagina 3, USUARIO_EMPRESA).
--       El escaneo de procesos es COMPLETO: no excluye ninguna pagina.
--   M14b LA EXCEPCION DE LA PAGINA 4, AFIRMADA CON LISTA CERRADA. Los cuatro
--       procesos de escritura de la pagina 4 ('Crear Usuario', 'update
--       usuario', 'Eliminar Usuario' y 'Desbloquear usuario') fuerzan
--       'id_empresa = v_mia' (la empresa PRINCIPAL del administrador): es la
--       limitacion viva de la FASE 3 del spec, que este plan NO hace (ver el
--       brief de la tarea 7, seccion 'Lo que este plan NO hace'). El M14 los
--       escanea TODOS, pero el M14b AFIRMA que el conjunto de procesos de la
--       pagina 4 que leen la columna unica es EXACTAMENTE esa lista cerrada:
--       si aparece un quinto, el caso falla. Lo que la cierra: la fase 3.
--   M15 Las listas Ã‚Â«Lista de PresupuestosÃ‚Â» (5) y Ã‚Â«Lista de FacturasÃ‚Â» (8),
--       ejecutadas con el TEXTO GUARDADO por APEX como un usuario de DOS
--       empresas: devuelven documentos de las DOS y NINGUNO de una tercera.
--   M16 Lo mismo con un usuario de UNA empresa: solo los suyos (regresion: un
--       usuario de una sola empresa no debe perder nada).
--   M17 Los defectos de empresa de P13_ID_EMPRESA, P7_ID_EMPRESA y
--       P17_ID_EMPRESA: con un usuario de DOS empresas devuelven NULL (la app
--       NO elige por su cuenta) y con uno de UNA devuelven esa empresa.
--   M18 La tarjeta Ã‚Â«Errores registrados hoyÃ‚Â» del Panel con :P13_ID_EMPRESA de
--       una empresa AJENA no cuenta los errores de otra empresa.
--   M19 La lista de usuarios de la pagina 3, ejecutada como el administrador
--       A: INCLUYE a un usuario que solo comparte empresa con A, EXCLUYE a uno
--       de una empresa con la que A no comparte, e INCLUYE al PENDIENTE sin
--       empresas.
--   M20 No hay fuga: ninguna consulta guardada devuelve documentos de una
--       empresa no asociada. Se comprueba POR ID (no solo por conteo de
--       filas), en los dos escenarios (usuario de DOS empresas y de UNA), y
--       en las DOS tablas: el presupuesto y la factura de la empresa ajena
--       (id 900032) no pueden salir en ninguna de las dos listas.
--
-- PATRON DE SIEMBRA (el mismo de las tareas anteriores):
--   - Rango reservado 900000+. Empresas de prueba: 900030 (compartida),
--     900031 (compartida), 900032 (ajena). Usuarios: 900030 (pares en
--     900030 y 900031), 900031 (par solo en 900030), 900032 (par solo en
--     900032, el ajeno), 900033 (PENDIENTE, sin empresas), 900034 (el
--     administrador A: par en 900030 y en 900031).
--   - Documentos: un presupuesto y una factura en cada empresa de prueba
--     (900030, 900031, 900032), con su cliente.
--   - Todo se borra al final, con 'commit' entre bloques (trampa ORA-12839:
--     varias DML sobre tablas con identity en la misma transaccion).
--   - Las empresas de prueba son ACTIVO y de pais VE: el caso tiene que medir
--     el filtro de EMPRESA, no el de estado.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- M14 (ampliado): ninguna consulta guardada por APEX sigue leyendo la columna
-- unica USUARIO.ID_EMPRESA.
--
-- Se buscan dos patrones, en minusculas, en:
--   - apex_application_page_regions.region_source   (la consulta de las regiones)
--   - apex_application_page_regions.where_clause    (el p_query_where de las
--                            regiones de formulario: paginas 6, 7, 8, 9, 10 y 16)
--   - apex_application_page_items                   (LOV, defecto y condiciones)
--   - apex_application_lovs.list_of_values_query    (las LOVs de la app)
--   - apex_application_page_proc.process_source     (los procesos de pagina)
-- Los patrones son:
--   'id_empresa from usuario'   -> el subselect viejo (F1)
--   'min(u.id_empresa)'          -> el defecto viejo (F2/F3/F4)
--
-- El caso avisa POR CATEGORIA y con el numero de sitios que quedan, no uno por
-- sitio: si no, una fila por cada uno de los 27 sitios pendientes taparia el
-- mensaje 'RESULTADO: FALLAS=n' (limitado a 2000 bytes) y no dejaria ver los
-- demas casos de la verificacion.
--
-- EXCEPCION DOCUMENTADA - LA PAGINA 4: sus cuatro procesos ('Crear Usuario',
-- 'update usuario', 'Eliminar Usuario' y 'Desbloquear usuario') fuerzan
-- 'id_empresa = v_mia', donde 'v_mia' es la empresa PRINCIPAL del
-- administrador. Eso es la limitacion VIVA de la FASE 3 del spec (la pagina 4
-- con seleccion multiple de empresas), que este plan NO hace: ver
-- '.superpowers/sdd/2026-11-10-multiempresa-usuario-empresa/task-7-brief.md',
-- seccion 'Lo que este plan NO hace'. No es un defecto de la tarea 4 y no
-- puede hacer fallar la verificacion; pero se avisa aparte como DEUDA (en
-- tmp_multi_notas, que NO se cuenta) para que no se pierda de vista.
-- -----------------------------------------------------------------------------
declare
    v_error   varchar2(300);
    v_detalle clob;
    v_n       number;
    v_lista   varchar2(1000);
    v_i       number;
    v_pagina  number;
    v_esperado number;
    v_n_p4     number;
    v_lista_p4 varchar2(300);

    procedure avisar(p_categoria varchar2, p_n number, p_lista varchar2) is
    begin
        if p_n > 0 then
            insert into tmp_multi_fallas
            values (substrb('M14: ' || p_categoria || ': ' || p_n
                            || ' sitio(s) siguen leyendo la columna unica del usuario'
                            || ' -> ' || coalesce(p_lista, ''), 1, 300));
        end if;
    end;
begin
    -- 1) Regiones: la consulta guardada (REGION_SOURCE).
    v_n := 0; v_lista := null;
    for r in (select region_id, region_name, region_source
                from apex_application_page_regions
               where application_id = 100
                 and region_source is not null) loop
        v_detalle := lower(r.region_source);
        if dbms_lob.instr(v_detalle, 'id_empresa from usuario') > 0
           or dbms_lob.instr(v_detalle, 'min(u.id_empresa)') > 0 then
            v_n := v_n + 1;
            v_lista := substrb(coalesce(v_lista, '') || r.region_name || '(reg ' || r.region_id || ') ', 1, 200);
        end if;
    end loop;
    avisar('regiones', v_n, v_lista);

    -- 2) Regiones de formulario: el p_query_where (WHERE_CLAUSE).
    v_n := 0; v_lista := null;
    for r in (select region_id, region_name, where_clause
                from apex_application_page_regions
               where application_id = 100
                 and where_clause is not null) loop
        v_detalle := lower(r.where_clause);
        if dbms_lob.instr(v_detalle, 'id_empresa from usuario') > 0
           or dbms_lob.instr(v_detalle, 'min(u.id_empresa)') > 0 then
            v_n := v_n + 1;
            v_lista := substrb(coalesce(v_lista, '') || r.region_name || '(reg ' || r.region_id || ') ', 1, 200);
        end if;
    end loop;
    avisar('regiones de formulario (where_clause)', v_n, v_lista);

    -- 3) Los items: LOV de item, defecto y condiciones.
    v_n := 0; v_lista := null;
    for it in (select item_id, item_name, lov_definition, item_default,
                      condition_expression1, condition_expression2,
                      read_only_condition_exp1, read_only_condition_exp2
                 from apex_application_page_items
                where application_id = 100) loop
        v_detalle := lower(coalesce(it.lov_definition, '') || ' '
                           || coalesce(it.item_default, '') || ' '
                           || coalesce(it.condition_expression1, '') || ' '
                           || coalesce(it.condition_expression2, '') || ' '
                           || coalesce(it.read_only_condition_exp1, '') || ' '
                           || coalesce(it.read_only_condition_exp2, ''));
        if dbms_lob.instr(v_detalle, 'id_empresa from usuario') > 0
           or dbms_lob.instr(v_detalle, 'min(u.id_empresa)') > 0 then
            v_n := v_n + 1;
            v_lista := substrb(coalesce(v_lista, '') || it.item_name || '(item ' || it.item_id || ') ', 1, 200);
        end if;
    end loop;
    avisar('items', v_n, v_lista);

    -- 4) Las LOVs de la app.
    v_n := 0; v_lista := null;
    for l in (select list_of_values_name, list_of_values_query
                from apex_application_lovs
               where application_id = 100
                 and list_of_values_query is not null) loop
        v_detalle := lower(l.list_of_values_query);
        if dbms_lob.instr(v_detalle, 'id_empresa from usuario') > 0
           or dbms_lob.instr(v_detalle, 'min(u.id_empresa)') > 0 then
            v_n := v_n + 1;
            v_lista := substrb(coalesce(v_lista, '') || l.list_of_values_name || ' ', 1, 200);
        end if;
    end loop;
    avisar('LOVs', v_n, v_lista);

    -- 5) La EXCEPCION DE LA PAGINA 4, contada ANTES del escaneo general.
    --
    -- FIX ROUND 2 (2026-11-10): aqui estaba el fallo. El descuento
    -- 'v_n := v_n - v_n_p4' estaba ANTES de que 'v_n_p4' tuviera valor: en
    -- PL/SQL una variable NUMBER sin inicializar es NULL, asi que
    -- 'v_n - v_n_p4' daba NULL, 'avisar' recibia NULL y su 'if p_n > 0' no
    -- se cumplia NUNCA: la categoria 'procesos de pagina' no reportaba NADA
    -- (ni cuando quedaban procesos fuera de la pagina 4). Ahora el conteo de
    -- la pagina 4 se calcula PRIMERO y el descuento se hace despues, con un
    -- NUMBER de verdad.
    --
    -- El escaneo general (abajo) sigue cubriendo TODAS las paginas: la
    -- excepcion de la pagina 4 la AFIRMA el caso propio M14b, con una lista
    -- cerrada (mas abajo), y aqui solo se descuenta del conteo para que el
    -- mensaje hable de los sitios REALMENTE pendientes de esta tarea.
    v_n_p4 := 0; v_lista_p4 := null;
    for pr in (select page_id, process_name, process_source
                  from apex_application_page_proc
                 where application_id = 100
                   and page_id = 4
                   and process_source is not null) loop
        v_detalle := lower(pr.process_source);
        if dbms_lob.instr(v_detalle, 'id_empresa from usuario') > 0
           or dbms_lob.instr(v_detalle, 'min(u.id_empresa)') > 0 then
            v_n_p4 := v_n_p4 + 1;
            v_lista_p4 := substrb(coalesce(v_lista_p4, '') || pr.process_name || ' ', 1, 200);
        end if;
    end loop;

    -- 6) Los procesos de pagina. Se escanean TODOS (ninguna exclusion).
    --
    -- FIX ROUND 1 (2026-11-10): esta categoria excluia en SILENCIO la
    -- pagina 4, y el brief de la tarea 4 solo permite excluir la pagina 19.
    -- Ahora el escaneo es completo, y la excepcion de la pagina 4 la
    -- AFIRMA el caso propio M14b, con una lista cerrada (mas abajo).
    v_n := 0; v_lista := null;
    for pr in (select page_id, process_id, process_name, process_source
                  from apex_application_page_proc
                 where application_id = 100
                   and process_source is not null) loop
        v_detalle := lower(pr.process_source);
        if dbms_lob.instr(v_detalle, 'id_empresa from usuario') > 0
           or dbms_lob.instr(v_detalle, 'min(u.id_empresa)') > 0 then
            v_n := v_n + 1;
            v_lista := substrb(coalesce(v_lista, '') || 'p' || pr.page_id || ':' || pr.process_name || ' ', 1, 200);
        end if;
    end loop;
    -- Los procesos de la pagina 4 son la excepcion CONOCIDA (FASE 3 del
    -- spec): los cuenta aparte el caso M14b, con su lista cerrada. Aqui se
    -- descuentan para que el conteo sea el de los sitios REALMENTE
    -- pendientes de esta tarea. 'v_n_p4' ya tiene valor (se conto antes).
    v_n := v_n - nvl(v_n_p4, 0);
    -- Red de seguridad: 'avisar' NUNCA debe recibir NULL (una categoria con
    -- conteo NULL no reportaria nada, que es justo el fallo que se corrige
    -- aqui). Si por lo que sea el conteo fuera NULL, se trata como 0 y se
    -- avisa igualmente, para que no se pueda volver a silenciar la categoria.
    if v_n is null then
        v_n := 0;
    end if;
    avisar('procesos de pagina', v_n, v_lista);

    -- 7) Cada pagina de la tabla del brief tiene que leer la VISTA. Se cuentan
    --    los sitios que la leen (region_source + where_clause + items + LOVs +
    --    procesos) y se compara con el numero esperado.
    --
    --    El numero esperado se calculo MEDIDO sobre la app ya cambiada (ver el
    --    informe de la tarea 4):
    --      p3  -> 0 sitios de la vista: su filtro (F5) lee USUARIO_EMPRESA
    --              directamente, porque necesita saber con quien COMPARTE
    --              empresa el administrador (no solo las suyas).
    --      p5  -> 2 (las dos listas)
    --      p6  -> 2 (el p_query_where y la LOV de impuestos)
    --      p7  -> 3 (el p_query_where, el defecto de empresa y el de moneda)
    --      p8  -> 2 (la lista y el p_query_where del detalle)
    --      p9  -> 5 (el p_query_where, dos LOVs y dos condiciones de pais)
    --      p10 -> 2 (el p_query_where y la LOV de impuestos)
    --      p13 -> 2 (los dos defectos)
    --      p16 -> 4 (la lista, el p_query_where, la LOV y el proceso)
    --      p17 -> 1 (el defecto)
    --      p18 -> 1 (el proceso)
    --      p19 -> 2 (la lista y el proceso; los cambio la tarea 6)
    --
    --    MEDIDO (2026-11-10): un 'for ... in (select ... union all ... from dual)'
    --    NO compila en PL/SQL (ORA-00928: SELECT keyword missing). Por eso la
    --    tabla de (pagina, esperado) va como un CASE y se recorre con un indice.
    v_lista := null;
    for v_i in 1 .. 12 loop
        v_pagina := case v_i when 1 then 3  when 2 then 5  when 3 then 6
                           when 4 then 7  when 5 then 8  when 6 then 9
                           when 7 then 10 when 8 then 13 when 9 then 16
                           when 10 then 17 when 11 then 18 when 12 then 19 end;
        v_esperado := case v_i when 1 then 0 when 2 then 2 when 3 then 2
                             when 4 then 3 when 5 then 2 when 6 then 5
                             when 7 then 2 when 8 then 2 when 9 then 4
                             when 10 then 1 when 11 then 1 when 12 then 2 end;
        v_n := 0;
        for r in (select region_source, where_clause
                    from apex_application_page_regions
                   where application_id = 100 and page_id = v_pagina) loop
            if r.region_source is not null then
                v_detalle := lower(r.region_source);
                v_n := v_n + regexp_count(v_detalle, 'v_empresas_usuario');
            end if;
            if r.where_clause is not null then
                v_detalle := lower(r.where_clause);
                v_n := v_n + regexp_count(v_detalle, 'v_empresas_usuario');
            end if;
        end loop;
        for it in (select lov_definition, item_default, condition_expression1,
                          condition_expression2, read_only_condition_exp1,
                          read_only_condition_exp2
                     from apex_application_page_items
                    where application_id = 100 and page_id = v_pagina) loop
            v_detalle := lower(coalesce(it.lov_definition, '') || ' '
                               || coalesce(it.item_default, '') || ' '
                               || coalesce(it.condition_expression1, '') || ' '
                               || coalesce(it.condition_expression2, '') || ' '
                               || coalesce(it.read_only_condition_exp1, '') || ' '
                               || coalesce(it.read_only_condition_exp2, ''));
            v_n := v_n + regexp_count(v_detalle, 'v_empresas_usuario');
        end loop;
        for pr in (select process_source from apex_application_page_proc
                    where application_id = 100 and page_id = v_pagina
                      and process_source is not null) loop
            v_detalle := lower(pr.process_source);
            v_n := v_n + regexp_count(v_detalle, 'v_empresas_usuario');
        end loop;
        if v_n <> v_esperado then
            v_lista := substrb(coalesce(v_lista, '') || 'p' || v_pagina || '(' || v_n
                               || '/' || v_esperado || ') ', 1, 200);
        end if;
    end loop;
    if v_lista is not null then
        insert into tmp_multi_fallas
        values (substrb('M14: paginas que NO leen V_EMPRESAS_USUARIO como deben (menciones/esperado): '
                        || v_lista, 1, 300));
    end if;

    -- 8) La pagina 3 (F5) tiene que leer USUARIO_EMPRESA: su filtro es
    --    've los que comparten alguna empresa conmigo, mas los que no tienen
    --    ninguna'. Si no lo lee, la lista de usuarios se vacia en silencio.
    --    Se busca por REGION_ID (10564941614198500) y no por el static_id, que
    --    lleva acento y depende de como el export codifique el unistr.
    v_n := 0;
    for r in (select region_source from apex_application_page_regions
                where application_id = 100 and region_id = 10564941614198500) loop
        v_detalle := lower(r.region_source);
        v_n := v_n + regexp_count(v_detalle, 'usuario_empresa');
    end loop;
    if v_n = 0 then
        insert into tmp_multi_fallas
        values (substrb('M14: la lista de usuarios de la pagina 3 no lee USUARIO_EMPRESA (F5)', 1, 300));
    end if;
exception
    when others then
        v_error := sqlerrm;
        insert into tmp_multi_fallas
        values (substrb('M14: error al medir: ' || v_error, 1, 300));
end;
/

-- -----------------------------------------------------------------------------
-- M14b: LA EXCEPCION DE LA PAGINA 4, AFIRMADA CON LISTA CERRADA.
--
-- Por que la pagina 4 es la excepcion:
--   Sus cuatro procesos de escritura ('Crear Usuario', 'update usuario',
--   'Eliminar Usuario' y 'Desbloquear usuario') fuerzan
--   'id_empresa = v_mia', donde 'v_mia' es la empresa PRINCIPAL del
--   administrador. Eso es la limitacion VIVA de la FASE 3 del spec (la pagina 4
--   con seleccion multiple de empresas), que este plan NO hace: ver
--   '.superpowers/sdd/2026-11-10-multiempresa-usuario-empresa/task-7-brief.md',
--   seccion 'Lo que este plan NO hace':
--     Ã‚Â«los procesos de la pagina 4 fuerzan id_empresa = v_mia, donde v_mia es
--       la empresa PRINCIPAL del administrador; un administrador con dos
--       empresas solo podra asignar esa principal. Es el comportamiento de hoy
--       y no empeora.Ã‚Â»
--   Lo que la cierra: la FASE 3 del spec (pagina 4 con asignacion multiple).
--   Cuando se implemente, este caso tiene que cambiar.
--
-- QUE COMPRUEBA (FIX ROUND 1, 2026-11-10): este caso AFIRMA el conjunto
-- EXACTO de procesos de la pagina 4 que leen la columna unica del usuario.
-- No es 'cualquiera que lea la columna': es una lista CERRADA, de modo que si
-- manana aparece un QUINTO proceso de la pagina 4 que lea la columna unica,
-- el caso FALLA (y no se avisa en silencio). Y si alguno de los cuatro deja
-- de leerla (porque ya se haya arreglado), el caso tambien falla, porque la
-- lista cerrada ya no cuadra.
--
-- La lista cerrada (MEDIDA el 2026-11-10 sobre la app importada):
--   Crear Usuario | Eliminar Usuario | update usuario | Desbloquear usuario
-- Los otros dos procesos de la pagina 4 ('Close Dialog' y 'Valida rol
-- administrador') NO leen la columna unica y no se listan.
-- -----------------------------------------------------------------------------
declare
    v_error   varchar2(300);
    v_detalle clob;
    v_n       number;
    v_lista   varchar2(300);
    v_esperada constant varchar2(300) := '|';
begin
    -- Los procesos de la pagina 4 que leen la columna unica del usuario.
    v_n := 0; v_lista := null;
    for pr in (select process_name, process_source
                  from apex_application_page_proc
                 where application_id = 100
                   and page_id = 4
                   and process_source is not null) loop
        v_detalle := lower(pr.process_source);
        if dbms_lob.instr(v_detalle, 'id_empresa from usuario') > 0
           or dbms_lob.instr(v_detalle, 'min(u.id_empresa)') > 0 then
            v_n := v_n + 1;
            -- Se ordena el nombre para que la comparacion sea estable.
            v_lista := v_lista || pr.process_name || '|';
        end if;
    end loop;

    -- La lista se ordena: se recoge en una cadena y se ordena con un
    -- listagg sobre los nombres sueltos.
    declare
        v_ordenada varchar2(300);
    begin
        select listagg(t.nombre, '|') within group (order by t.nombre)
          into v_ordenada
          from (select distinct pr.process_name as nombre
                  from apex_application_page_proc pr
                 where pr.application_id = 100
                   and pr.page_id = 4
                   and pr.process_source is not null
                   and (dbms_lob.instr(lower(pr.process_source), 'id_empresa from usuario') > 0
                     or dbms_lob.instr(lower(pr.process_source), 'min(u.id_empresa)') > 0)) t;

        if v_ordenada is null then
            v_ordenada := '';
        end if;
        v_ordenada := v_ordenada || '|';

        if v_ordenada <> v_esperada then
            insert into tmp_multi_fallas
            values (substrb('M14b: la pagina 4 sigue leyendo la columna unica del usuario. '
                            || 'Desde la fase 3 la guarda es fn_usuario_administrable y las '
                            || 'empresas salen de USUARIO_EMPRESA. Procesos que la leen: ['
                            || v_ordenada || ']', 1, 300));
        end if;
    exception
        when others then
            v_error := sqlerrm;
            insert into tmp_multi_fallas
            values (substrb('M14b: error al medir: ' || v_error, 1, 300));
    end;
end;
/

-- -----------------------------------------------------------------------------
-- Siembra de los datos de prueba de M15, M16, M17, M18, M19 y M20.
--
--   Empresas:  900030 (compartida por DIAG_M2 y DIAG_M1)
--              900031 (compartida por DIAG_M2)
--              900032 (AJENA: solo DIAG_M3)
--   Usuarios:  900030 DIAG_M2   -> pares en 900030 y 900031 (DOS empresas)
--              900031 DIAG_M1   -> par solo en 900030 (UNA empresa)
--              900032 DIAG_M3   -> par solo en 900032 (la ajena)
--              900033 DIAG_M0   -> PENDIENTE, SIN empresas
--              900034 DIAG_ADM -> pares en 900030 y 900031 (el administrador A)
--
--   Documentos: un presupuesto y una factura por cada empresa de prueba
--   (900030, 900031, 900032), con su cliente. Los ids se dan EXPLICITOS (las
--   identities son BY DEFAULT, medido el 2026-11-10) para que el M20 pueda
--   comprobar por id que el documento de la empresa ajena NO sale.
--
--   MEDIDO (2026-11-10): los INSERT con 'union all ... from dual' los manda
--   el servidor en PARALELO y en esta base el error de la FK sale enmascarado
--   como ORA-12801 ('error signaled in parallel query server P002'). Ademas,
--   cada rama del UNION es un bind distinto: con un solo ':h' sale
--   ORA-01008. Por eso aqui cada fila es un INSERT propio.
-- -----------------------------------------------------------------------------
declare
    v_error varchar2(300);
    v_hash  varchar2(512);
begin
    select sypex_hash_password('Diag#2026') into v_hash from dual;

    -- Barrido de restos de una corrida anterior. Un 'commit' despues de
    -- cada DELETE: en esta base, dos DML sobre tablas con identity en la
    -- misma transaccion dan ORA-12839 (medido).
    begin
        execute immediate q'[delete from usuario_empresa
                            where usuario_id in (900030, 900031, 900032, 900033, 900034)
                               or id_empresa in (900030, 900031, 900032)]';
        commit;
    exception when others then null;
    end;
    begin
        execute immediate q'[delete from usuario where usuario_id in (900030, 900031, 900032, 900033, 900034)]';
        commit;
    exception when others then null;
    end;
    begin
        execute immediate q'[delete from gastos_real where id_presupuesto in
                            (select id_presupuesto from presupuestos where id_empresa in (900030, 900031, 900032))]';
        commit;
    exception when others then null;
    end;
    begin
        execute immediate q'[delete from facturas where id_empresa in (900030, 900031, 900032)]';
        commit;
    exception when others then null;
    end;
    begin
        execute immediate q'[delete from presupuestos where id_empresa in (900030, 900031, 900032)]';
        commit;
    exception when others then null;
    end;
    begin
        execute immediate q'[delete from clientes where id_empresa in (900030, 900031, 900032)]';
        commit;
    exception when others then null;
    end;
    begin
        execute immediate q'[delete from empresas where id_empresa in (900030, 900031, 900032)]';
        commit;
    exception when others then null;
    end;

    -- Las tres empresas de prueba. ACTIVO y de pais VE: el caso tiene que
    -- medir el filtro de EMPRESA, no el de estado.
    begin
        execute immediate
            q'[insert into empresas (id_empresa, nombre_empresa, estado, cod_pais, tipo_ident_fiscal, rfc)
               values (900030, 'DIAG EMP A', 'ACTIVO', 'VE', 'RIF', 'DIAG-A')]';
        execute immediate
            q'[insert into empresas (id_empresa, nombre_empresa, estado, cod_pais, tipo_ident_fiscal, rfc)
               values (900031, 'DIAG EMP B', 'ACTIVO', 'VE', 'RIF', 'DIAG-B')]';
        execute immediate
            q'[insert into empresas (id_empresa, nombre_empresa, estado, cod_pais, tipo_ident_fiscal, rfc)
               values (900032, 'DIAG EMP AJENA', 'ACTIVO', 'VE', 'RIF', 'DIAG-X')]';
        commit;
    exception
        when others then
            v_error := sqlerrm;
            insert into tmp_multi_fallas
            values (substrb('M15-M20: no se pudieron crear las empresas de prueba: ' || v_error, 1, 300));
    end;

    -- Los cinco usuarios de prueba.
    begin
        execute immediate
            q'[insert into usuario (usuario_id, username, email, password_hash, estado,
                                    rol_id, id_empresa, debe_cambiar_clave)
               values (900030, 'DIAG_M2', 'diag.m2@synpex.local', :h, 'ACTIVO',
                      (select min(id_rol) from syn_roles where codigo_rol = 'ADMIN'), 900030, 'N')]'
            using v_hash;
        execute immediate
            q'[insert into usuario (usuario_id, username, email, password_hash, estado,
                                    rol_id, id_empresa, debe_cambiar_clave)
               values (900031, 'DIAG_M1', 'diag.m1@synpex.local', :h, 'ACTIVO',
                      (select min(id_rol) from syn_roles where codigo_rol = 'ADMIN'), 900030, 'N')]'
            using v_hash;
        execute immediate
            q'[insert into usuario (usuario_id, username, email, password_hash, estado,
                                    rol_id, id_empresa, debe_cambiar_clave)
               values (900032, 'DIAG_M3', 'diag.m3@synpex.local', :h, 'ACTIVO',
                      (select min(id_rol) from syn_roles where codigo_rol = 'ADMIN'), 900032, 'N')]'
            using v_hash;
        execute immediate
            q'[insert into usuario (usuario_id, username, email, password_hash, estado,
                                    rol_id, id_empresa, debe_cambiar_clave)
               values (900033, 'DIAG_M0', 'diag.m0@synpex.local', :h, 'PENDIENTE',
                      (select min(id_rol) from syn_roles where codigo_rol = 'ADMIN'), null, 'N')]'
            using v_hash;
        execute immediate
            q'[insert into usuario (usuario_id, username, email, password_hash, estado,
                                    rol_id, id_empresa, debe_cambiar_clave)
               values (900034, 'DIAG_ADM', 'diag.adm@synpex.local', :h, 'ACTIVO',
                      (select min(id_rol) from syn_roles where codigo_rol = 'ADMIN'), 900030, 'N')]'
            using v_hash;
        commit;
    exception
        when others then
            v_error := sqlerrm;
            insert into tmp_multi_fallas
            values (substrb('M15-M20: no se pudieron crear los usuarios de prueba: ' || v_error, 1, 300));
    end;

    -- Las asociaciones.
    begin
        execute immediate q'[insert into usuario_empresa (usuario_id, id_empresa) select 900030, 900030 from dual where not exists (select 1 from usuario_empresa x where x.usuario_id = 900030 and x.id_empresa = 900030)]';
        execute immediate q'[insert into usuario_empresa (usuario_id, id_empresa) select 900030, 900031 from dual where not exists (select 1 from usuario_empresa x where x.usuario_id = 900030 and x.id_empresa = 900031)]';
        execute immediate q'[insert into usuario_empresa (usuario_id, id_empresa) select 900031, 900030 from dual where not exists (select 1 from usuario_empresa x where x.usuario_id = 900031 and x.id_empresa = 900030)]';
        execute immediate q'[insert into usuario_empresa (usuario_id, id_empresa) select 900032, 900032 from dual where not exists (select 1 from usuario_empresa x where x.usuario_id = 900032 and x.id_empresa = 900032)]';
        execute immediate q'[insert into usuario_empresa (usuario_id, id_empresa) select 900034, 900030 from dual where not exists (select 1 from usuario_empresa x where x.usuario_id = 900034 and x.id_empresa = 900030)]';
        execute immediate q'[insert into usuario_empresa (usuario_id, id_empresa) select 900034, 900031 from dual where not exists (select 1 from usuario_empresa x where x.usuario_id = 900034 and x.id_empresa = 900031)]';
        commit;
    exception
        when others then
            v_error := sqlerrm;
            insert into tmp_multi_fallas
            values (substrb('M15-M20: no se pudieron crear las asociaciones de prueba: ' || v_error, 1, 300));
    end;

    -- Los clientes de prueba (uno por empresa).
    begin
        execute immediate
            q'[insert into clientes (id_empresa, rif, razon_social, estado, cod_pais)
               values (900030, 'DIAG-CLI-A', 'DIAG CLIENTE A', 'ACTIVO', 'VE')]';
        execute immediate
            q'[insert into clientes (id_empresa, rif, razon_social, estado, cod_pais)
               values (900031, 'DIAG-CLI-B', 'DIAG CLIENTE B', 'ACTIVO', 'VE')]';
        execute immediate
            q'[insert into clientes (id_empresa, rif, razon_social, estado, cod_pais)
               values (900032, 'DIAG-CLI-X', 'DIAG CLIENTE AJENO', 'ACTIVO', 'VE')]';
        commit;
    exception
        when others then
            v_error := sqlerrm;
            insert into tmp_multi_fallas
            values (substrb('M15-M20: no se pudieron crear los clientes de prueba: ' || v_error, 1, 300));
    end;

    -- Un presupuesto y una factura por cada empresa de prueba.
    begin
        execute immediate
            q'[insert into presupuestos (id_presupuesto, id_empresa, folio, id_cliente, fecha_emision, estado,
                                       subtotal, impuesto_iva, total, cod_moneda, tipo_cambio, creado_por)
               values (900030, 900030, 900030,
                      (select min(id_cliente) from clientes where id_empresa = 900030),
                      sysdate, 'PENDIENTE', 100, 16, 116, 'USD', 1, 'DIAG_M2')]';
        execute immediate
            q'[insert into presupuestos (id_presupuesto, id_empresa, folio, id_cliente, fecha_emision, estado,
                                       subtotal, impuesto_iva, total, cod_moneda, tipo_cambio, creado_por)
               values (900031, 900031, 900031,
                      (select min(id_cliente) from clientes where id_empresa = 900031),
                      sysdate, 'PENDIENTE', 200, 32, 232, 'USD', 1, 'DIAG_M2')]';
        execute immediate
            q'[insert into presupuestos (id_presupuesto, id_empresa, folio, id_cliente, fecha_emision, estado,
                                       subtotal, impuesto_iva, total, cod_moneda, tipo_cambio, creado_por)
               values (900032, 900032, 900032,
                      (select min(id_cliente) from clientes where id_empresa = 900032),
                      sysdate, 'PENDIENTE', 300, 48, 348, 'USD', 1, 'DIAG_M3')]';
        commit;
    exception
        when others then
            v_error := sqlerrm;
            insert into tmp_multi_fallas
            values (substrb('M15-M20: no se pudieron crear los presupuestos de prueba: ' || v_error, 1, 300));
    end;

    begin
        execute immediate
            q'[insert into facturas (id_factura, id_empresa, id_cliente, tipo_documento, folio_factura,
                                     cod_moneda, tipo_cambio, fecha_emision, subtotal,
                                     monto_impuesto, monto_total, estado, creado_por)
               values (900030, 900030,
                      (select min(id_cliente) from clientes where id_empresa = 900030),
                      'FAC', 'F-900030', 'USD', 1, sysdate, 100, 16, 116, 'PENDIENTE', 'DIAG_M2')]';
        execute immediate
            q'[insert into facturas (id_factura, id_empresa, id_cliente, tipo_documento, folio_factura,
                                     cod_moneda, tipo_cambio, fecha_emision, subtotal,
                                     monto_impuesto, monto_total, estado, creado_por)
               values (900031, 900031,
                      (select min(id_cliente) from clientes where id_empresa = 900031),
                      'FAC', 'F-900031', 'USD', 1, sysdate, 200, 32, 232, 'PENDIENTE', 'DIAG_M2')]';
        execute immediate
            q'[insert into facturas (id_factura, id_empresa, id_cliente, tipo_documento, folio_factura,
                                     cod_moneda, tipo_cambio, fecha_emision, subtotal,
                                     monto_impuesto, monto_total, estado, creado_por)
               values (900032, 900032,
                      (select min(id_cliente) from clientes where id_empresa = 900032),
                      'FAC', 'F-900032', 'USD', 1, sysdate, 300, 48, 348, 'PENDIENTE', 'DIAG_M3')]';
        commit;
    exception
        when others then
            v_error := sqlerrm;
            insert into tmp_multi_fallas
            values (substrb('M15-M20: no se pudieron crear las facturas de prueba: ' || v_error, 1, 300));
    end;
end;
/

-- -----------------------------------------------------------------------------
-- M15, M16 y M20: se ejecutan los TEXTOS GUARDADOS de las listas de las
-- paginas 5 y 8 con cada usuario de prueba y se cuentan los documentos que
-- devuelven.
--
-- Se mide el texto guardado (APEX_APPLICATION_PAGE_REGIONS.REGION_SOURCE), no
-- una copia a mano: si el texto guardado y el que se espera divergen, el
-- caso tiene que fallar. La consulta se envuelve en 'select count(*) from
-- (...)' para poder contarla, y se ejecuta con ':APP_USER' sustituido.
--
--   DIAG_M2 (2 empresas: 900030 y 900031)  -> 2 presupuestos y 2 facturas
--                                              (los de 900030 y 900031), y
--                                              NINGUNO de 900032.
--   DIAG_M1 (1 empresa: 900030)             -> 1 presupuesto y 1 factura.
--   DIAG_M3 (1 empresa: 900032)             -> 1 presupuesto y 1 factura.
-- -----------------------------------------------------------------------------
declare
    v_error  varchar2(300);
    v_cuenta number;
    v_ids    varchar2(2000);

    -- Cuenta las filas que devuelve el texto guardado de la region indicada
    -- para un usuario dado. Si la consulta no se puede ejecutar, devuelve -1
    -- para que el caso lo reporte como fallo.
    function contar_region(p_region_id number, p_usuario varchar2) return number is
        v_txt varchar2(32000);
        v_cnt number;
    begin
        select region_source into v_txt
          from apex_application_page_regions
         where application_id = 100 and region_id = p_region_id;
        v_txt := rtrim(rtrim(v_txt), ';');
        execute immediate 'select count(*) from (' || v_txt || ')' into v_cnt using p_usuario;
        return v_cnt;
    exception
        when others then
            return -1;
    end contar_region;

    -- Devuelve la lista de ids que devuelve el texto guardado. Se usa para
    -- el M20 (comprobar que no sale el documento de la empresa ajena).
    --
    -- FIX ROUND 1 (2026-11-10): la columna de id depende de la region: la
    -- lista de presupuestos la trae como 'id_presupuesto' y la de facturas
    -- como 'id_factura'. Se pasa el nombre de la columna.
    function ids_region(p_region_id number, p_usuario varchar2,
                        p_columna varchar2) return varchar2 is
        v_txt varchar2(32000);
        v_lis varchar2(2000);
        v_sql varchar2(32000);
    begin
        select region_source into v_txt
          from apex_application_page_regions
         where application_id = 100 and region_id = p_region_id;
        v_txt := rtrim(rtrim(v_txt), ';');
        -- MEDIDO (2026-11-10): con la concatenacion directa el literal
        -- PL/SQL queda ambiguo (la comilla de despues de '|| p_columna ||'
        -- abre un literal que no se cierra) y python-oracledb lo rechaza con
        -- 'DPY-2041: missing ending quote'. Por eso el SQL se arma en una
        -- variable y el trozo con la comilla del separador '|' va en q'{...}',
        -- que no hay que doblar.
        v_sql := 'select listagg(to_char(t.' || p_columna || q'{), '|'}) within group (order by t.}'
                  || p_columna || ')'
                  || ' from (' || v_txt || ') t';
        execute immediate v_sql into v_lis using p_usuario;
        return v_lis;
    exception
        when others then
            return 'ERROR';
    end ids_region;
begin
    -- M15: el usuario de DOS empresas ve las DOS.
    v_cuenta := contar_region(11950647600514906, 'DIAG_M2');   -- Lista de Presupuestos
    if v_cuenta <> 2 then
        insert into tmp_multi_fallas
        values (substrb('M15: Ã‚Â«Lista de PresupuestosÃ‚Â» devolvio ' || v_cuenta
                        || ' presupuestos para un usuario de 2 empresas (se esperaba 2)', 1, 300));
    end if;
    v_cuenta := contar_region(29963866505095675, 'DIAG_M2');   -- Lista de Facturas
    if v_cuenta <> 2 then
        insert into tmp_multi_fallas
        values (substrb('M15: Ã‚Â«Lista de FacturasÃ‚Â» devolvio ' || v_cuenta
                        || ' facturas para un usuario de 2 empresas (se esperaba 2)', 1, 300));
    end if;

    -- M16: el usuario de UNA empresa ve SOLO la suya (regresion).
    v_cuenta := contar_region(11950647600514906, 'DIAG_M1');
    if v_cuenta <> 1 then
        insert into tmp_multi_fallas
        values (substrb('M16: Ã‚Â«Lista de PresupuestosÃ‚Â» devolvio ' || v_cuenta
                        || ' presupuestos para un usuario de 1 empresa (se esperaba 1)', 1, 300));
    end if;
    v_cuenta := contar_region(29963866505095675, 'DIAG_M1');
    if v_cuenta <> 1 then
        insert into tmp_multi_fallas
        values (substrb('M16: Ã‚Â«Lista de FacturasÃ‚Â» devolvio ' || v_cuenta
                        || ' facturas para un usuario de 1 empresa (se esperaba 1)', 1, 300));
    end if;

    -- El usuario de la empresa ajena ve SOLO la suya (no la de los demas).
    v_cuenta := contar_region(11950647600514906, 'DIAG_M3');
    if v_cuenta <> 1 then
        insert into tmp_multi_fallas
        values (substrb('M20: Ã‚Â«Lista de PresupuestosÃ‚Â» devolvio ' || v_cuenta
                        || ' presupuestos para un usuario de la empresa ajena (se esperaba 1)', 1, 300));
    end if;
    v_cuenta := contar_region(29963866505095675, 'DIAG_M3');
    if v_cuenta <> 1 then
        insert into tmp_multi_fallas
        values (substrb('M20: Ã‚Â«Lista de FacturasÃ‚Â» devolvio ' || v_cuenta
                        || ' facturas para un usuario de la empresa ajena (se esperaba 1)', 1, 300));
    end if;

    -- M20: el documento de la empresa ajena (id 900032 en las dos tablas)
    -- NO puede salir en la lista del usuario de dos empresas, NI en la del
    -- usuario de una.
    --
    -- Se comprueba POR ID, no solo por conteo de filas: un conteo de 2
    -- podria pasar devolviendo las dos facturas equivocadas.
    --
    -- (a) El PRESUPUESTO de la empresa ajena (id 900032).
    v_ids := ids_region(11950647600514906, 'DIAG_M2', 'id_presupuesto');
    if v_ids like '%900032%' then
        insert into tmp_multi_fallas
        values (substrb('M20: Ã‚Â«Lista de PresupuestosÃ‚Â» devolvio el presupuesto de la empresa ajena: '
                        || v_ids, 1, 300));
    end if;

    -- (b) Y la lista de DIAG_M1 (una sola empresa) tampoco puede traerlo.
    v_ids := ids_region(11950647600514906, 'DIAG_M1', 'id_presupuesto');
    if v_ids like '%900032%' then
        insert into tmp_multi_fallas
        values (substrb('M20: Ã‚Â«Lista de PresupuestosÃ‚Â» de un usuario de 1 empresa devolvio '
                        || 'el presupuesto de la empresa ajena: ' || v_ids, 1, 300));
    end if;

    -- (c) La FACTURA de la empresa ajena (id 900032), para el usuario de
    -- DOS empresas. FIX ROUND 1: antes solo se comprobaba el presupuesto, y
    -- el conteo de filas del M15 (de facturas) podia pasar devolviendo las
    -- dos facturas equivocadas.
    v_ids := ids_region(29963866505095675, 'DIAG_M2', 'id_factura');
    if v_ids like '%900032%' then
        insert into tmp_multi_fallas
        values (substrb('M20: Ã‚Â«Lista de FacturasÃ‚Â» devolvio la factura de la empresa ajena: '
                        || v_ids, 1, 300));
    end if;

    -- (d) Y para el usuario de UNA empresa.
    v_ids := ids_region(29963866505095675, 'DIAG_M1', 'id_factura');
    if v_ids like '%900032%' then
        insert into tmp_multi_fallas
        values (substrb('M20: Ã‚Â«Lista de FacturasÃ‚Â» de un usuario de 1 empresa devolvio '
                        || 'la factura de la empresa ajena: ' || v_ids, 1, 300));
    end if;
end;
/

-- -----------------------------------------------------------------------------
-- M17: los defectos de empresa de P13_ID_EMPRESA, P7_ID_EMPRESA y
-- P17_ID_EMPRESA.
--
-- Se mide el TEXTO GUARDADO (APEX_APPLICATION_PAGE_ITEMS.ITEM_DEFAULT), no una
-- copia a mano. Con un usuario de DOS empresas el defecto tiene que devolver
-- NULL (la app NO elige por su cuenta: review focus 4 del plan) y con uno de
-- UNA empresa tiene que devolver esa empresa.
--
-- OJO: el defecto es un 'select min(...) ... having count(*) = 1'. Con dos
-- empresas NO DEVOLVE FILAS, asi que un 'execute immediate ... into' da
-- NO_DATA_FOUND: eso es exactamente el resultado que se espera para el caso
-- de dos empresas (el defecto es NULL), y lo que NO se espera para el caso de
-- una empresa.
-- -----------------------------------------------------------------------------
declare
    v_error  varchar2(300);
    v_codigo number;

    procedure medir_defecto(p_item varchar2, p_usuario varchar2,
                            p_esperado number, p_caso varchar2) is
        v_txt varchar2(32000);
        v_val number;
        v_cod number;
    begin
        v_txt := null;
        select item_default into v_txt
          from apex_application_page_items
         where application_id = 100 and item_name = p_item;
        v_cod := 0;
        v_val := null;
        begin
            execute immediate v_txt into v_val using p_usuario;
        exception
            when no_data_found then
                v_cod := 1;   -- sin filas: el defecto es NULL
            when others then
                v_cod := sqlcode;
        end;
        if p_esperado is null then
            -- Se espera NULL: con dos empresas el defecto no devuelve filas.
            if v_cod = 0 and v_val is not null then
                insert into tmp_multi_fallas
                values (substrb(p_caso || ': el defecto de ' || p_item
                                || ' devolvio ' || v_val
                                || ' para un usuario de 2 empresas (se esperaba NULL)', 1, 300));
            elsif v_cod not in (0, 1) then
                insert into tmp_multi_fallas
                values (substrb(p_caso || ': el defecto de ' || p_item
                                || ' dio el codigo ' || v_cod, 1, 300));
            end if;
        else
            if v_cod <> 0 then
                insert into tmp_multi_fallas
                values (substrb(p_caso || ': el defecto de ' || p_item
                                || ' dio el codigo ' || v_cod
                                || ' para un usuario de 1 empresa (se esperaba 900030)', 1, 300));
            elsif v_val <> p_esperado then
                insert into tmp_multi_fallas
                values (substrb(p_caso || ': el defecto de ' || p_item
                                || ' devolvio ' || v_val
                                || ' para un usuario de 1 empresa (se esperaba ' || p_esperado || ')', 1, 300));
            end if;
        end if;
    exception
        when others then
            v_error := sqlerrm;
            insert into tmp_multi_fallas
            values (substrb(p_caso || ': error al medir el defecto de ' || p_item
                            || ': ' || v_error, 1, 300));
    end medir_defecto;
begin
    -- Con DOS empresas: NULL en los tres.
    medir_defecto('P13_ID_EMPRESA', 'DIAG_M2', null, 'M17');
    medir_defecto('P7_ID_EMPRESA',  'DIAG_M2', null, 'M17');
    medir_defecto('P17_ID_EMPRESA', 'DIAG_M2', null, 'M17');

    -- Con UNA empresa: esa empresa (900030).
    medir_defecto('P13_ID_EMPRESA', 'DIAG_M1', 900030, 'M17');
    medir_defecto('P7_ID_EMPRESA',  'DIAG_M1', 900030, 'M17');
    medir_defecto('P17_ID_EMPRESA', 'DIAG_M1', 900030, 'M17');
end;
/

-- -----------------------------------------------------------------------------
-- M18: la tarjeta Ã‚Â«Errores registrados hoyÃ‚Â» del Panel (region Ã‚Â«IndicadoresÃ‚Â»)
-- NO cuenta los errores de una empresa ajena.
--
-- Se mide el TEXTO GUARDADO de la region Ã‚Â«IndicadoresÃ‚Â»
-- (APEX_APPLICATION_PAGE_REGIONS.REGION_SOURCE, region 23600000000000010) con
-- ':P13_ID_EMPRESA' sustituido por la empresa ELEGIDA y ':APP_USER' por el
-- usuario de prueba.
--
-- Se siembran DOS errores en SYN_ERROR_LOG: uno a nombre de DIAG_M3 (que
-- pertenece a la empresa ajena 900032) y otro a nombre de DIAG_M2 (que
-- pertenece a las empresas 900030 y 900031). Con ':P13_ID_EMPRESA' = 900030
-- (la empresa ELEGIDA, que el usuario de dos empresas tiene) la tarjeta NO
-- puede contar el error de DIAG_M3.
--
-- Los errores se siembran con la FECHA de hoy (la tarjeta filtra por
-- 'TRUNC(e.fecha) = TRUNC(SYSDATE)') y se borran al final.
-- -----------------------------------------------------------------------------
declare
    v_error  varchar2(300);
    v_texto  clob;
    v_cuenta number;

    -- Cuenta los errores que ve la tarjeta Ã‚Â«Errores registrados hoyÃ‚Â» con una
    -- empresa y un usuario dados.
    function contar_errores(p_texto clob, p_empresa number, p_usuario varchar2) return number is
        v_txt  varchar2(32000);
        v_cnt  number;
        v_cod  number;
    begin
        v_txt := dbms_lob.substr(p_texto, 32000, 1);
        v_txt := replace(v_txt, ':P13_ID_EMPRESA', to_char(p_empresa));
        v_txt := replace(v_txt, ':APP_USER', '''' || p_usuario || '''');
        v_txt := replace(v_txt, ':P13_MONEDA', '''USD''');
        v_cod := 0;
        v_cnt := -1;
        begin
            -- Se cuenta el NUMERO DE ERRORES, no las FILAS: la tarjeta sale
            -- siempre (con 0 errores), asi que contar filas daria 1 siempre.
            -- El numero va en el prefijo del 'valor'.
            execute immediate
                'select nvl(to_number(regexp_substr(valor, ''^[0-9]+'')), 0)
                  from (' || v_txt || ')
                 where titulo = ''Errores registrados hoy'''
                into v_cnt;
        exception
            when others then
                v_cod := sqlcode;
        end;
        if v_cod <> 0 then
            return -1;
        end if;
        return v_cnt;
    end contar_errores;
begin
    -- Siembra de los dos errores de prueba.
    begin
        execute immediate
            q'[insert into syn_error_log (fecha, usuario, mensaje, id_pagina)
               values (sysdate, 'DIAG_M3', 'DIAG error empresa ajena', 13)]';
        execute immediate
            q'[insert into syn_error_log (fecha, usuario, mensaje, id_pagina)
               values (sysdate, 'DIAG_M2', 'DIAG error empresa propia', 13)]';
        commit;
    exception
        when others then
            v_error := sqlerrm;
            insert into tmp_multi_fallas
            values (substrb('M18: no se pudieron sembrar los errores de prueba: ' || v_error, 1, 300));
    end;

    begin
        select region_source into v_texto
          from apex_application_page_regions
         where application_id = 100 and region_id = 23600000000000010;

        -- MEDIDO (2026-11-10): la tarjeta NO usa ':APP_USER'. Su filtro es
        -- 'EXISTS (... UPPER(u.username) = UPPER(e.usuario) AND
        -- ue.id_empresa = :P13_ID_EMPRESA)', o sea cuenta los errores cuyo
        -- AUTOR tiene un par con la empresa ELEGIDA.
        --
        -- Con la empresa ELEGIDA (900030): solo el error de DIAG_M2 (1). El
        -- error de DIAG_M3 (empresa 900032) NO se cuela.
        v_cuenta := contar_errores(v_texto, 900030, 'DIAG_M2');
        if v_cuenta <> 1 then
            insert into tmp_multi_fallas
            values (substrb('M18: la tarjeta conto ' || v_cuenta
                            || ' errores para la empresa 900030 (se esperaba 1: solo el propio)', 1, 300));
        end if;

        -- Con la OTRA empresa (900032): solo el error de DIAG_M3 (1). El error
        -- de DIAG_M2 NO se cuela: asi se comprueba que el filtro por empresa
        -- funciona en los dos sentidos.
        v_cuenta := contar_errores(v_texto, 900032, 'DIAG_M2');
        if v_cuenta <> 1 then
            insert into tmp_multi_fallas
            values (substrb('M18: la tarjeta conto ' || v_cuenta
                            || ' errores para la empresa 900032 (se esperaba 1: solo el de esa empresa)', 1, 300));
        end if;

        -- Y con una empresa que NADIE tiene (999999): 0 errores.
        v_cuenta := contar_errores(v_texto, 999999, 'DIAG_M2');
        if v_cuenta <> 0 then
            insert into tmp_multi_fallas
            values (substrb('M18: la tarjeta conto ' || v_cuenta
                            || ' errores para una empresa que nadie tiene (se esperaba 0)', 1, 300));
        end if;
    exception
        when others then
            v_error := sqlerrm;
            insert into tmp_multi_fallas
            values (substrb('M18: error al medir: ' || v_error, 1, 300));
    end;

    -- Limpieza de los errores de prueba.
    begin
        execute immediate q'[delete from syn_error_log where usuario in ('DIAG_M2','DIAG_M3','DIAG_M1','DIAG_ADM')]';
        commit;
    exception when others then null;
    end;
end;
/

-- -----------------------------------------------------------------------------
-- M19: la lista de usuarios de la pagina 3.
--
-- Se mide el TEXTO GUARDADO de la region Ã‚Â«Gestion de UsuariosÃ‚Â»
-- (APEX_APPLICATION_PAGE_REGIONS.REGION_SOURCE, region 10564941614198500) con
-- ':APP_USER' sustituido por el administrador A (DIAG_ADM).
--
-- DIAG_ADM tiene pares en 900030 y 900031.
--   DIAG_M2  -> par en 900030 y 900031  -> COMPARTE empresa: se INCLUYE.
--   DIAG_M1  -> par en 900030          -> COMPARTE empresa: se INCLUYE.
--   DIAG_M3  -> par en 900032          -> NO COMPARTE:          se EXCLUYE.
--   DIAG_M0  -> PENDIENTE, sin empresas-> se INCLUYE (para que el
--                 administrador lo pueda activar).
--   DIAG_ADM -> el propio administrador  -> se INCLUYE.
-- -----------------------------------------------------------------------------
declare
    v_error  varchar2(300);
    v_texto  clob;
    v_lista  varchar2(2000);
    v_codigo number;
begin
    begin
        select region_source into v_texto
          from apex_application_page_regions
         where application_id = 100 and region_id = 10564941614198500;

        -- La lista de usuarios de DIAG_ADM: tiene que salir en la columna
        -- USERNAME. La consulta se envuelve y se cuenta por nombre.
        --
        -- OJO (tarea 5, 2026-11-10): la consulta guardada tiene DOS
        -- apariciones de ':APP_USER' (el filtro F5 y el subselect de la
        -- columna EMPRESAS). En SQL dinamico hay que pasar el valor UNA VEZ
        -- POR APARICION: con un solo 'using' falla con ORA-01008 ('value for
        -- bind variable placeholder 1 was not provided').
        v_codigo := 0;
        begin
            execute immediate
                q'[select listagg(t.username, '|') within group (order by t.username)
                      from (]'
                || v_texto
                || q'[) t]'
                into v_lista using 'DIAG_ADM', 'DIAG_ADM';
        exception
            when others then
                v_codigo := sqlcode;
                v_lista := null;
        end;

        if v_codigo <> 0 then
            insert into tmp_multi_fallas
            values (substrb('M19: no se pudo ejecutar la lista de usuarios: codigo ' || v_codigo, 1, 300));
        else
            -- INCLUYE a quien comparte empresa.
            if v_lista not like '%DIAG_M2%' then
                insert into tmp_multi_fallas
                values (substrb('M19: la lista NO incluye a DIAG_M2 (comparte empresa): ' || v_lista, 1, 300));
            end if;
            if v_lista not like '%DIAG_M1%' then
                insert into tmp_multi_fallas
                values (substrb('M19: la lista NO incluye a DIAG_M1 (comparte empresa): ' || v_lista, 1, 300));
            end if;
            -- EXCLUYE a quien no comparte empresa.
            if v_lista like '%DIAG_M3%' then
                insert into tmp_multi_fallas
                values (substrb('M19: la lista INCLUYE a DIAG_M3 (empresa ajena): ' || v_lista, 1, 300));
            end if;
            -- INCLUYE al PENDIENTE sin empresas.
            if v_lista not like '%DIAG_M0%' then
                insert into tmp_multi_fallas
                values (substrb('M19: la lista NO incluye a DIAG_M0 (PENDIENTE sin empresas): ' || v_lista, 1, 300));
            end if;
            -- El propio administrador tambien sale.
            if v_lista not like '%DIAG_ADM%' then
                insert into tmp_multi_fallas
                values (substrb('M19: la lista NO incluye al propio administrador: ' || v_lista, 1, 300));
            end if;
        end if;
    exception
        when others then
            v_error := sqlerrm;
            insert into tmp_multi_fallas
            values (substrb('M19: error al medir: ' || v_error, 1, 300));
    end;
end;
/

-- -----------------------------------------------------------------------------
-- Limpieza de los datos de prueba de M15 a M20. Va SIEMPRE, aunque la
-- medicion haya fallado: los datos de prueba no se quedan en la base.
-- -----------------------------------------------------------------------------
begin
    begin
        execute immediate q'[delete from syn_error_log where usuario in ('DIAG_M2','DIAG_M3','DIAG_M1','DIAG_ADM')]';
        commit;
    exception when others then null;
    end;
    begin
        execute immediate q'[delete from usuario_empresa
                            where usuario_id in (900030, 900031, 900032, 900033, 900034)
                               or id_empresa in (900030, 900031, 900032)]';
        commit;
    exception when others then null;
    end;
    begin
        execute immediate q'[delete from usuario where usuario_id in (900030, 900031, 900032, 900033, 900034)]';
        commit;
    exception when others then null;
    end;
    begin
        execute immediate q'[delete from gastos_real where id_presupuesto in
                            (select id_presupuesto from presupuestos where id_empresa in (900030, 900031, 900032))]';
        commit;
    exception when others then null;
    end;
    begin
        execute immediate q'[delete from facturas where id_empresa in (900030, 900031, 900032)]';
        commit;
    exception when others then null;
    end;
    begin
        execute immediate q'[delete from presupuestos where id_empresa in (900030, 900031, 900032)]';
        commit;
    exception when others then null;
    end;
    begin
        execute immediate q'[delete from clientes where id_empresa in (900030, 900031, 900032)]';
        commit;
    exception when others then null;
    end;
    begin
        execute immediate q'[delete from empresas where id_empresa in (900030, 900031, 900032)]';
        commit;
    exception when others then null;
    end;
end;
/

-- =============================================================================
-- TAREA 5: pagina 3 Ã‚Â«Gestion de UsuariosÃ‚Â» Ã¢â‚¬â€ columna Ã‚Â«EmpresasÃ‚Â».
--
--   M21 La consulta GUARDADA de la region (APEX_APPLICATION_PAGE_REGIONS.
--       REGION_SOURCE de la region 10564941614198500) trae una columna EMPRESAS
--       con las empresas del usuario COMPARTIDAS con el administrador que
--       mira, separadas por ', ' y ordenadas por nombre. Ademas la columna
--       EMPRESAS esta declarada en la region y sale en el informe por defecto.
--   M22 Para un usuario que ademas tiene una empresa que el administrador NO
--       tiene, esa tercera NO aparece en EMPRESAS.
--
-- PATRON (R3 del ledger): se mide el TEXTO GUARDADO por APEX, no una copia
-- escrita a mano: si el texto guardado y el que se espera divergen, el caso
-- tiene que fallar. La consulta se envuelve en 'select ... from (<texto>) t'
-- y se ejecuta con ':APP_USER' sustituido por el administrador de prueba.
--
-- SEMILLA (rango reservado 900000+):
--   Empresas:  900040 'DIAG EMP P'   (compartida)
--              900041 'DIAG EMP Q'   (compartida)
--              900042 'DIAG EMP R'   (AJENA: solo del usuario, no del admin)
--   Usuarios:  900040 DIAG_ADM3 -> pares en 900040 y 900041 (el administrador)
--              900041 DIAG_U3   -> pares en 900040, 900041 y 900042
--
-- Por que 900040/900041 y no las empresas reales (1, 2, 3): los datos de
-- prueba tienen que ser REPRODUCIBLES y no depender del estado de la base.
-- Los nombres empiezan por 'DIAG EMP ' para que el orden alfabetico de
-- M21 sea P, Q (y no dependa de acentos: 'Empresa Mexico' lleva 'M', que en
-- la colacion del servidor puede ir antes o despues de 'Empresa Principal').
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Siembra de los datos de prueba de M21 y M22.
-- -----------------------------------------------------------------------------
declare
    v_error varchar2(300);
    v_hash  varchar2(512);
begin
    select sypex_hash_password('Diag#2026') into v_hash from dual;

    -- Barrido de restos de una corrida anterior. Fila por fila (el DELETE
    -- con 'in (...)' lo manda el servidor en paralelo y en esta base el
    -- error de la FK sale enmascarado como ORA-12801 con un ORA-02292
    -- FALSO: medido el 2026-11-11).
    begin
        execute immediate q'[delete from usuario_empresa where usuario_id = 900040]';
        commit;
    exception when others then null;
    end;
    begin
        execute immediate q'[delete from usuario_empresa where usuario_id = 900041]';
        commit;
    exception when others then null;
    end;
    begin
        execute immediate q'[delete from usuario_empresa where id_empresa = 900040]';
        commit;
    exception when others then null;
    end;
    begin
        execute immediate q'[delete from usuario_empresa where id_empresa = 900041]';
        commit;
    exception when others then null;
    end;
    begin
        execute immediate q'[delete from usuario_empresa where id_empresa = 900042]';
        commit;
    exception when others then null;
    end;
    begin
        execute immediate q'[delete from usuario where usuario_id = 900040]';
        commit;
    exception when others then null;
    end;
    begin
        execute immediate q'[delete from usuario where usuario_id = 900041]';
        commit;
    exception when others then null;
    end;
    begin
        execute immediate q'[delete from empresas where id_empresa = 900040]';
        commit;
    exception when others then null;
    end;
    begin
        execute immediate q'[delete from empresas where id_empresa = 900041]';
        commit;
    exception when others then null;
    end;
    begin
        execute immediate q'[delete from empresas where id_empresa = 900042]';
        commit;
    exception when others then null;
    end;

    begin
        execute immediate
            q'[insert into empresas (id_empresa, nombre_empresa, estado, cod_pais, tipo_ident_fiscal, rfc)
               values (900040, 'DIAG EMP P', 'ACTIVO', 'VE', 'RIF', 'DIAG-P')]';
        execute immediate
            q'[insert into empresas (id_empresa, nombre_empresa, estado, cod_pais, tipo_ident_fiscal, rfc)
               values (900041, 'DIAG EMP Q', 'ACTIVO', 'VE', 'RIF', 'DIAG-Q')]';
        execute immediate
            q'[insert into empresas (id_empresa, nombre_empresa, estado, cod_pais, tipo_ident_fiscal, rfc)
               values (900042, 'DIAG EMP R', 'ACTIVO', 'VE', 'RIF', 'DIAG-R')]';
        commit;
    exception
        when others then
            v_error := sqlerrm;
            insert into tmp_multi_fallas
            values (substrb('M21-M22: no se pudieron crear las empresas de prueba: ' || v_error, 1, 300));
    end;

    begin
        execute immediate
            q'[insert into usuario (usuario_id, username, email, password_hash, estado,
                                    rol_id, id_empresa, debe_cambiar_clave)
               values (900040, 'DIAG_ADM3', 'diag.adm3@synpex.local', :h, 'ACTIVO',
                       (select min(id_rol) from syn_roles where codigo_rol = 'ADMIN'), 900040, 'N')]'
            using v_hash;
        execute immediate
            q'[insert into usuario (usuario_id, username, email, password_hash, estado,
                                    rol_id, id_empresa, debe_cambiar_clave)
               values (900041, 'DIAG_U3', 'diag.u3@synpex.local', :h, 'ACTIVO',
                       (select min(id_rol) from syn_roles where codigo_rol = 'ADMIN'), 900040, 'N')]'
            using v_hash;
        commit;
    exception
        when others then
            v_error := sqlerrm;
            insert into tmp_multi_fallas
            values (substrb('M21-M22: no se pudieron crear los usuarios de prueba: ' || v_error, 1, 300));
    end;

    begin
        execute immediate q'[insert into usuario_empresa (usuario_id, id_empresa) select 900040, 900040 from dual where not exists (select 1 from usuario_empresa x where x.usuario_id = 900040 and x.id_empresa = 900040)]';
        execute immediate q'[insert into usuario_empresa (usuario_id, id_empresa) select 900040, 900041 from dual where not exists (select 1 from usuario_empresa x where x.usuario_id = 900040 and x.id_empresa = 900041)]';
        execute immediate q'[insert into usuario_empresa (usuario_id, id_empresa) select 900041, 900040 from dual where not exists (select 1 from usuario_empresa x where x.usuario_id = 900041 and x.id_empresa = 900040)]';
        execute immediate q'[insert into usuario_empresa (usuario_id, id_empresa) select 900041, 900041 from dual where not exists (select 1 from usuario_empresa x where x.usuario_id = 900041 and x.id_empresa = 900041)]';
        execute immediate q'[insert into usuario_empresa (usuario_id, id_empresa) select 900041, 900042 from dual where not exists (select 1 from usuario_empresa x where x.usuario_id = 900041 and x.id_empresa = 900042)]';
        commit;
    exception
        when others then
            v_error := sqlerrm;
            insert into tmp_multi_fallas
            values (substrb('M21-M22: no se pudieron crear las asociaciones de prueba: ' || v_error, 1, 300));
    end;
end;
/

-- -----------------------------------------------------------------------------
-- M21 y M22: la columna Ã‚Â«EmpresasÃ‚Â» de la lista de usuarios de la pagina 3.
--
-- Se ejecuta el TEXTO GUARDADO de la region con ':APP_USER' sustituido por
-- el administrador de prueba (DIAG_ADM3, que tiene pares en 900040 y 900041)
-- y se lee la columna EMPRESAS de la fila del usuario DIAG_U3 (que tiene
-- pares en 900040, 900041 y 900042: la tercera es AJENA al administrador).
--
-- M21: EMPRESAS = 'DIAG EMP P, DIAG EMP Q' (las dos compartidas, por nombre).
-- M22: 'DIAG EMP R' (la ajena) NO aparece.
--
-- Ademas se comprueba que la columna EMPRESAS esta DECLARADA en la region
-- (apex_application_page_ir_col) y que sale en el INFORME POR DEFECTO
-- (apex_application_page_ir_rpt.report_columns): sin declararla, la columna
-- no se pinta aunque el SELECT la traiga.
-- -----------------------------------------------------------------------------
declare
    v_error   varchar2(300);
    v_texto   clob;
    v_empresas varchar2(2000);
    v_codigo  number;
    v_columnas varchar2(300);
    v_cuenta   number;
begin
    -- (a) La columna EMPRESAS esta declarada en la region.
    begin
        select count(*) into v_cuenta
          from apex_application_page_ir_col
         where application_id = 100
           and region_id = 10564941614198500
           and column_alias = 'EMPRESAS';
        if v_cuenta <> 1 then
            insert into tmp_multi_fallas
            values (substrb('M21: la region Ã‚Â«Gestion de UsuariosÃ‚Â» no declara la columna EMPRESAS', 1, 300));
        end if;
    exception
        when others then
            v_error := sqlerrm;
            insert into tmp_multi_fallas
            values (substrb('M21: error al leer las columnas de la region: ' || v_error, 1, 300));
    end;

    -- (b) Y sale en el informe por defecto.
    --
    -- OJO: 'split' no existe en PL/SQL (medido: ORA-00904), asi que el token
    -- se busca con una regex que exige los DOS separadores. La columna
    -- existente 'EMPRESA' (singular) no puede dar un falso positivo con
    -- ':EMPRESAS:' porque la 'S' final es distinta.
    begin
        select report_columns into v_columnas
          from apex_application_page_ir_rpt
         where application_id = 100 and page_id = 3 and report_alias = 'primary';
        if v_columnas is null or not regexp_like(v_columnas, '(^|:)EMPRESAS(:|$)') then
            insert into tmp_multi_fallas
            values (substrb('M21: EMPRESAS no esta en el informe por defecto: ' || v_columnas, 1, 300));
        end if;
    exception
        when others then
            v_error := sqlerrm;
            insert into tmp_multi_fallas
            values (substrb('M21: error al leer el informe por defecto: ' || v_error, 1, 300));
    end;

    -- (c) Y el TEXTO GUARDADO devuelve las empresas compartidas.
    begin
        select region_source into v_texto
          from apex_application_page_regions
         where application_id = 100 and region_id = 10564941614198500;

        v_codigo := 0;
        v_empresas := null;
        begin
            -- OJO: la consulta guardada tiene DOS apariciones de ':APP_USER'
            -- (el filtro F5 y el subselect de la columna EMPRESAS), asi que
            -- el valor se pasa una vez POR APARICION (con uno solo falla con
            -- ORA-01008).
            execute immediate
                q'[select t.empresas from (]'
                || v_texto
                || q'[) t where upper(t.username) = 'DIAG_U3']'
                into v_empresas using 'DIAG_ADM3', 'DIAG_ADM3';
        exception
            when no_data_found then
                v_codigo := 1;
                v_empresas := null;
            when others then
                v_codigo := sqlcode;
                v_empresas := null;
        end;

        if v_codigo <> 0 then
            insert into tmp_multi_fallas
            values (substrb('M21: no se pudo leer la columna EMPRESAS de la consulta guardada'
                            || ' (codigo ' || v_codigo || ')', 1, 300));
        else
            -- M21: las dos empresas COMPARTIDAS, separadas por ', ' y por nombre.
            if v_empresas <> 'DIAG EMP P, DIAG EMP Q' then
                insert into tmp_multi_fallas
                values (substrb('M21: EMPRESAS devolvio Ã‚Â«' || v_empresas
                                || 'Ã‚Â» (se esperaba Ã‚Â«DIAG EMP P, DIAG EMP QÃ‚Â»)', 1, 300));
            end if;

            -- M22: la empresa AJENA al administrador NO aparece.
            if v_empresas like '%DIAG EMP R%' then
                insert into tmp_multi_fallas
                values (substrb('M22: EMPRESAS incluye la empresa ajena al administrador: Ã‚Â«'
                                || v_empresas || 'Ã‚Â»', 1, 300));
            end if;
        end if;
    exception
        when others then
            v_error := sqlerrm;
            insert into tmp_multi_fallas
            values (substrb('M21-M22: error al medir: ' || v_error, 1, 300));
    end;
end;
/

-- -----------------------------------------------------------------------------
-- Limpieza de los datos de prueba de M21 y M22. Va SIEMPRE, aunque la
-- medicion haya fallado: los datos de prueba no se quedan en la base.
--
-- MEDIDO (2026-11-11): los DELETE con 'in (...)' los manda el servidor en
-- PARALELO, y en esta base el error de la FK sale enmascarado como
-- ORA-12801 ('error signaled in parallel query server') con un ORA-02292
-- ('child record found') que es FALSO: no hay ninguna fila hija. Por eso se
-- borra fila por fila, que va en serie y no da el falso error.
--
-- OJO EL ORDEN: 'USUARIO.ID_EMPRESA' tiene su PROPIA FK a EMPRESAS
-- (FK_USUARIO_EMPRESA), aparte de la de USUARIO_EMPRESA. Por eso los
-- USUARIOS se borran ANTES que las EMPRESAS.
-- -----------------------------------------------------------------------------
begin
    begin
        execute immediate q'[delete from usuario_empresa where usuario_id = 900040]';
        commit;
    exception when others then null;
    end;
    begin
        execute immediate q'[delete from usuario_empresa where usuario_id = 900041]';
        commit;
    exception when others then null;
    end;
    begin
        execute immediate q'[delete from usuario_empresa where id_empresa = 900040]';
        commit;
    exception when others then null;
    end;
    begin
        execute immediate q'[delete from usuario_empresa where id_empresa = 900041]';
        commit;
    exception when others then null;
    end;
    begin
        execute immediate q'[delete from usuario_empresa where id_empresa = 900042]';
        commit;
    exception when others then null;
    end;
    begin
        execute immediate q'[delete from usuario where usuario_id = 900040]';
        commit;
    exception when others then null;
    end;
    begin
        execute immediate q'[delete from usuario where usuario_id = 900041]';
        commit;
    exception when others then null;
    end;
    begin
        execute immediate q'[delete from empresas where id_empresa = 900040]';
        commit;
    exception when others then null;
    end;
    begin
        execute immediate q'[delete from empresas where id_empresa = 900041]';
        commit;
    exception when others then null;
    end;
    begin
        execute immediate q'[delete from empresas where id_empresa = 900042]';
        commit;
    exception when others then null;
    end;
end;
/

-- -----------------------------------------------------------------------------
-- M27-M29: el filtro por empresa tiene que estar EN EL SERVIDOR, no solo en la
-- LOV. Medido en la revision final del 2026-11-11: el Panel (13) filtraba solo
-- por el item P13_ID_EMPRESA (sin comprobar que sea del usuario) y las cargas
-- de las paginas 17 y 18 leian la empresa del item sin la guarda; con un POST
-- manipulado se veian la facturacion y los datos fiscales de otro cliente.
-- Se comprueba el TEXTO GUARDADO por APEX (como M14), no una copia a mano.
-- -----------------------------------------------------------------------------
insert into tmp_multi_fallas
select substrb('M27: el Panel (13) no valida que P13_ID_EMPRESA sea del usuario', 1, 300)
  from dual
 where not exists (select 1
                     from apex_application_page_proc p
                    where p.application_id = 100
                      and p.page_id = 13
                      and p.process_point_code = 'BEFORE_HEADER'
                      and instr(upper(p.process_source), 'FN_USUARIO_EMPRESA_VALIDA') > 0
                      and instr(upper(p.process_source), 'P13_ID_EMPRESA') > 0);
/

insert into tmp_multi_fallas
select substrb('M28: la carga de Datos Fiscales (18) no valida la empresa del item', 1, 300)
  from dual
 where not exists (select 1
                     from apex_application_page_proc p
                    where p.application_id = 100
                      and p.page_id = 18
                      and p.process_point_code = 'BEFORE_HEADER'
                      and instr(upper(p.process_source), 'FN_USUARIO_EMPRESA_VALIDA') > 0);
/

insert into tmp_multi_fallas
select substrb('M29: el logo (17) pinta el de una empresa que no es del usuario', 1, 300)
  from dual
 where not exists (select 1
                     from apex_application_page_regions r
                    where r.application_id = 100
                      and r.page_id = 17
                      and r.region_static_id = 'logo-actual'
                      and instr(upper(r.region_source), 'FN_USUARIO_EMPRESA_VALIDA') > 0);
/

-- M30-M34: la pagina 4 asigna varias empresas (fase 3).
-- Datos propios en el rango 900000+. Cuatro usuarios:
--   900050 admin con las empresas A y B
--   900051 usuario con pares en A, B y en la 1 (la 1 es de OTRO admin)
--   900052 usuario sin pares (es el caso del alta desde la pagina 2)
--   900053 usuario con par solo en la 2 (no comparte nada con el admin)
declare
    v_emp_a constant number := 900060;
    v_emp_b constant number := 900061;
    v_adm   constant number := 900050;
    v_usr   constant number := 900051;
    v_sin   constant number := 900052;
    v_ajeno constant number := 900053;
    v_estado varchar2(20);
    v_msg    varchar2(400);
    v_cod    number;
    v_error  varchar2(400);
    v_paso   varchar2(40) := 'inicio';
    v_n      number;

    procedure alta_usuario (p_id number, p_nombre varchar2) is
    begin
        insert into usuario (usuario_id, username, email, password_hash, estado, rol_id,
                             id_empresa, debe_cambiar_clave)
        values (p_id, p_nombre, lower(p_nombre) || '@synpex.local', 'x', 'ACTIVO',
                (select min(id_rol) from syn_roles where codigo_rol = 'ADMIN'), null, 'N');
        commit;
    end;

    procedure alta_par (p_usuario number, p_empresa number) is
    begin
        insert into usuario_empresa (usuario_id, id_empresa)
        select p_usuario, p_empresa from dual
         where not exists (select 1 from usuario_empresa
                            where usuario_id = p_usuario and id_empresa = p_empresa);
        commit;
    end;
begin
    insert into empresas (id_empresa, nombre_empresa, cod_pais, tipo_ident_fiscal, estado, fecha_creacion)
    values (v_emp_a, 'DIAG P4 A', 'VE', 'RIF', 'ACTIVO', systimestamp);
    commit;
    insert into empresas (id_empresa, nombre_empresa, cod_pais, tipo_ident_fiscal, estado, fecha_creacion)
    values (v_emp_b, 'DIAG P4 B', 'VE', 'RIF', 'ACTIVO', systimestamp);
    commit;
    alta_usuario(v_adm, 'DIAG_P4_ADMIN');
    alta_par(v_adm, v_emp_a);
    alta_par(v_adm, v_emp_b);
    alta_usuario(v_usr, 'DIAG_P4_USER');
    alta_par(v_usr, v_emp_a);
    alta_par(v_usr, v_emp_b);
    alta_par(v_usr, 1);
    alta_usuario(v_sin, 'DIAG_P4_SIN');
    alta_usuario(v_ajeno, 'DIAG_P4_AJENO');
    alta_par(v_ajeno, 2);

    -- M34a: un usuario SIN pares es administrable (es el alta desde la pagina 2)
    if not fn_usuario_administrable('DIAG_P4_ADMIN', v_sin) then
        insert into tmp_multi_fallas
        values (substrb('M34: no deja administrar un usuario sin empresas', 1, 300));
    end if;

    -- M30: alta con dos empresas -> dos pares y la menor como principal
    v_paso := 'M30';
    prc_empresas_usuario(v_sin, v_emp_a || ':' || v_emp_b, 'DIAG_P4_ADMIN', v_estado, v_msg);
    select count(*) into v_n from usuario_empresa
     where usuario_id = v_sin and id_empresa in (v_emp_a, v_emp_b);
    if v_n <> 2 then
        insert into tmp_multi_fallas
        values (substrb('M30: dos empresas no dejaron dos pares (' || v_n || ')', 1, 300));
    end if;
    select id_empresa into v_n from usuario where usuario_id = v_sin;
    if v_n <> v_emp_a then
        insert into tmp_multi_fallas
        values (substrb('M30: id_empresa no es la menor (' || v_n || ')', 1, 300));
    end if;

    -- M31: quitar una empresa borra SU par y conserva el de la empresa que el admin no ve
    v_paso := 'M31';
    prc_empresas_usuario(v_usr, to_char(v_emp_a), 'DIAG_P4_ADMIN', v_estado, v_msg);
    select count(*) into v_n from usuario_empresa
     where usuario_id = v_usr and id_empresa in (v_emp_a, 1);
    if v_n <> 2 then
        insert into tmp_multi_fallas
        values (substrb('M31: conservo los pares equivocados (' || v_n || ')', 1, 300));
    end if;
    select count(*) into v_n from usuario_empresa
     where usuario_id = v_usr and id_empresa = v_emp_b;
    if v_n <> 0 then
        insert into tmp_multi_fallas
        values (substrb('M31: el par de la empresa quitada sigue', 1, 300));
    end if;
    select count(*) into v_n from usuario_empresa
     where usuario_id = v_usr and id_empresa = 1;
    if v_n <> 1 then
        insert into tmp_multi_fallas
        values (substrb('M31: borro un par de una empresa que el admin no ve', 1, 300));
    end if;

    -- M32: seleccion vacia con el usuario ACTIVO -> INACTIVO y pares intactos
    update usuario set estado = 'ACTIVO' where usuario_id = v_usr;
    commit;
    v_paso := 'M32';
    prc_empresas_usuario(v_usr, null, 'DIAG_P4_ADMIN', v_estado, v_msg);
    select count(*) into v_n from usuario where usuario_id = v_usr and estado = 'INACTIVO';
    if v_n <> 1 then
        insert into tmp_multi_fallas
        values (substrb('M32: no quedo INACTIVO sin empresas', 1, 300));
    end if;
    select count(*) into v_n from usuario_empresa where usuario_id = v_usr;
    if v_n <> 2 then
        insert into tmp_multi_fallas
        values (substrb('M32: la desactivacion toco los pares (' || v_n || ')', 1, 300));
    end if;
    if v_msg is null then
        insert into tmp_multi_fallas
        values (substrb('M32: no devolvio el aviso de desactivacion', 1, 300));
    end if;

    -- M33: una empresa que no es del admin -> -20003
    begin
    v_paso := 'M33';
        prc_empresas_usuario(v_usr, '2', 'DIAG_P4_ADMIN', v_estado, v_msg);
        insert into tmp_multi_fallas
        values (substrb('M33: acepto una empresa que no es del admin', 1, 300));
    exception
        when others then
            v_cod := sqlcode;
            if v_cod <> -20003 then
                insert into tmp_multi_fallas
                values (substrb('M33: devolvio ' || v_cod || ' y no -20003', 1, 300));
            end if;
    end;

    -- M33b: basura en la seleccion ('abc') -> -20003, no una excepcion sin control
    begin
    v_paso := 'M33b';
        prc_empresas_usuario(v_usr, 'abc', 'DIAG_P4_ADMIN', v_estado, v_msg);
        insert into tmp_multi_fallas
        values (substrb('M33b: acepto una empresa que no es un numero', 1, 300));
    exception
        when others then
            v_cod := sqlcode;
            if v_cod <> -20003 then
                insert into tmp_multi_fallas
                values (substrb('M33b: devolvio ' || v_cod || ' y no -20003', 1, 300));
            end if;
    end;

    -- M34b: administrable = comparte empresa; el ajeno no
    if not fn_usuario_administrable('DIAG_P4_ADMIN', v_usr) then
        insert into tmp_multi_fallas
        values (substrb('M34: no ve un usuario con empresa compartida', 1, 300));
    end if;
    if fn_usuario_administrable('DIAG_P4_ADMIN', v_ajeno) then
        insert into tmp_multi_fallas
        values (substrb('M34: ve un usuario sin empresa compartida', 1, 300));
    end if;

    v_paso := 'limpieza';
    delete from usuario_empresa where usuario_id in (v_adm, v_usr, v_sin, v_ajeno);
    commit;
    delete from usuario where usuario_id in (v_adm, v_usr, v_sin, v_ajeno);
    commit;
    delete from empresas where id_empresa in (v_emp_a, v_emp_b);
    commit;
exception
    when others then
        begin
            delete from usuario_empresa where usuario_id in (900050, 900051, 900052, 900053);
            commit;
            delete from usuario where usuario_id in (900050, 900051, 900052, 900053);
            commit;
            delete from empresas where id_empresa in (900060, 900061);
            commit;
        exception when others then null;
        end;
        v_error := sqlerrm;
        insert into tmp_multi_fallas
        values (substrb('M30-M34: fallo en [' || v_paso || ']: ' || v_error, 1, 300));
        commit;
end;
/

-- M37: ninguna validacion de la pagina 4 puede exigir empresa: la decision
-- del dueno (2026-11-11) es que sin seleccion la cuenta quede INACTIVA.
insert into tmp_multi_fallas
select substrb('M37: una validacion de la pagina 4 bloquea guardar sin empresas', 1, 300) from dual
 where exists (select 1 from apex_application_page_val v
                where v.application_id = 100 and v.page_id = 4
                  and v.validation_expression1 is not null
                  and instr(upper(v.validation_expression1), 'P4_ID_EMPRESA') > 0);
/

-- M38: el item tiene que ser "Always Null". Si queda como columna del
-- formulario, el fetch lo pisa con USUARIO.ID_EMPRESA y el guardado borraria
-- los demas pares del usuario (el bug de la pagina 13, 2026-11-06).
insert into tmp_multi_fallas
select substrb('M38: P4_ID_EMPRESA sigue siendo columna del formulario ('
               || nvl((select item_source_type from apex_application_page_items
                        where application_id = 100 and page_id = 4
                          and item_name = 'P4_ID_EMPRESA'), '?') || ')', 1, 300)
  from dual
 where nvl((select item_source_type from apex_application_page_items
             where application_id = 100 and page_id = 4
               and item_name = 'P4_ID_EMPRESA'), '#') <> 'Always Null';
/

-- M39: la carga de casillas solo puede correr al abrir, no en el render que
-- sigue a un submit: si corre, borra lo que el admin acaba de marcar.
insert into tmp_multi_fallas
select substrb('M39: la carga de casillas pisa lo marcado (no mira :REQUEST)', 1, 300) from dual
 where not exists (select 1 from apex_application_page_proc p
                    where p.application_id = 100 and p.page_id = 4
                      and p.static_id = 'carga-empresas-usuario'
                      and p.process_source is not null
                      and instr(upper(p.process_source), 'REQUEST') > 0);
/

-- M40: los CUATRO procesos de escritura llevan guarda, y crear y update
-- llaman al procedimiento que sincroniza.
insert into tmp_multi_fallas
select substrb('M40: el proceso ' || p.process_name || ' no lleva guarda de empresas', 1, 300)
  from apex_application_page_proc p
 where p.application_id = 100 and p.page_id = 4
   and p.process_name in ('Crear Usuario', 'update usuario', 'Desbloquear usuario', 'Eliminar Usuario')
   and p.process_source is not null
   and instr(upper(p.process_source), 'FN_USUARIO_ADMINISTRABLE') = 0
   and instr(upper(p.process_source), 'PRC_EMPRESAS_USUARIO') = 0;
/

insert into tmp_multi_fallas
select substrb('M40: ' || p.process_name || ' no llama a prc_empresas_usuario', 1, 300)
  from apex_application_page_proc p
 where p.application_id = 100 and p.page_id = 4
   and p.process_name in ('Crear Usuario', 'update usuario')
   and p.process_source is not null
   and instr(upper(p.process_source), 'PRC_EMPRESAS_USUARIO') = 0;
/

insert into tmp_multi_fallas
select substrb('M35: el item P4_ID_EMPRESA no es un grupo de casillas', 1, 300) from dual
 where not exists (select 1 from apex_application_page_items i
                    where i.application_id = 100 and i.page_id = 4
                      and i.item_name = 'P4_ID_EMPRESA'
                      and i.display_as_code = 'NATIVE_CHECKBOX');
/

insert into tmp_multi_fallas
select substrb('M36: la pagina 4 no sincroniza las empresas con el procedimiento', 1, 300) from dual
 where not exists (select 1 from apex_application_page_proc p
                    where p.application_id = 100 and p.page_id = 4
                      and p.process_name in ('Crear Usuario', 'update usuario')
                      and p.process_source is not null
                      and instr(upper(p.process_source), 'PRC_EMPRESAS_USUARIO') > 0);
/

declare
    v_fallas number;
    v_lista  varchar2(2000);
begin
    select count(*) into v_fallas from tmp_multi_fallas;
    -- 'on overflow truncate' es obligatorio: sin el, un listagg largo revienta con
    -- ORA-01489 ANTES de llegar al substr, y se pierde el "FALLAS=n".
    --
    -- El 'substr' por FUERA tambien es obligatorio, y no es redundante: en esta
    -- version 'on overflow truncate' recorta al maximo de la propia lista
    -- (medido: 5857 caracteres con 20 elementos de 290), no al tamano de la
    -- variable destino, asi que el 'INTO' de un VARCHAR2(2000) revienta con
    -- ORA-06502 y se pierde el 'RESULTADO: FALLAS=n'. Con el substr de fuera,
    -- el valor entra en la variable y el raise_application_error (que admite
    -- 2048 bytes) ya recorta a 2000.
    select substrb(listagg(caso, ' | ' on overflow truncate) within group (order by caso), 1, 2000)
      into v_lista
      from tmp_multi_fallas;
    execute immediate 'drop table tmp_multi_fallas purge';
    raise_application_error(-20100, substrb('RESULTADO: FALLAS=' || v_fallas || ' | ' || v_lista, 1, 2000));
end;
/

