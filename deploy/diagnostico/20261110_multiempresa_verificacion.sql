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
--      pasa de largo: 'substr(rpad(''x'',290,''x'')||rpad(''á'',10,''á''),1,300)'
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
    end if;
end;
/

create table tmp_multi_fallas (caso varchar2(300));
/

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
-- silencioso y este archivo dejaria de ser la reja de regresión.
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
               select 900003, 1 from dual
               union all select 900003, 2 from dual
               union all select 900004, 1 from dual
               union all select 900005, 1 from dual
               union all select 900005, 900010 from dual]';
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
