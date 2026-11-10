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
