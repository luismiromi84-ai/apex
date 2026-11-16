-- =============================================================================
-- deploy/migrations/20261110_multiempresa_usuario_empresa.sql
--
-- Migracion del modelo multiempresa: crea la tabla de asociacion
-- USUARIO_EMPRESA y la vista V_EMPRESAS_USUARIO, y siembra los datos para que
-- NADA de lo que hoy funciona se rompa.
--
-- Es la fase 1 del diseno (docs/superpowers/specs/2026-11-10-multiempresa-
-- usuario-empresa-design.md). Esta migracion NO toca pantallas: la LOV
-- EMPRESA, fn_usuario_empresa_valida y los ~30 filtros del export los
-- reescriben las tareas siguientes.
--
-- IDEMPOTENTE: se puede ejecutar mas de una vez sin romper nada.
--
-- OJO con el runner: cada sentencia necesita su linea '/' porque
-- importar_export.py corta por ahi (sin ellas, ORA-03405). Y hay un 'commit'
-- entre bloques: en esta base, varias DML seguidas sobre tablas con identity
-- dan ORA-12839.
--
-- Uso:
--   python deploy/conexion/importar_export.py deploy/migrations/20261110_multiempresa_usuario_empresa.sql
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;
/

-- -----------------------------------------------------------------------------
-- 1. La tabla, si no existe. El bloque PL/SQL con 'all_tables' la deja
--    idempotente; los indices y las FK se crean dentro del mismo bloque para
--    que no queden a medias si la tabla ya estaba.
-- -----------------------------------------------------------------------------
declare
    v_ya_existe number;
begin
    select count(*) into v_ya_existe from all_tables
     where owner = 'WKSP_SYPEXWS' and table_name = 'USUARIO_EMPRESA';
    if v_ya_existe = 0 then
        execute immediate q'[create table usuario_empresa (
            usuario_id     number       not null enable,
            id_empresa     number       not null enable,
            fecha_creacion timestamp    default systimestamp not null enable,
            constraint pk_usuario_empresa primary key (usuario_id, id_empresa)
                using index enable,
            constraint fk_ue_usuario foreign key (usuario_id)
                references usuario (usuario_id) enable,
            constraint fk_ue_empresa foreign key (id_empresa)
                references empresas (id_empresa) enable
        )]';
    end if;
end;
/

-- El indice por ID_EMPRESA se crea aparte y tambien con guarda: asi la
-- migracion tambien lo deja bien si la tabla ya existia sin el.
begin
    execute immediate 'create index ix_ue_empresa on usuario_empresa (id_empresa)';
exception
    when others then
        if sqlcode != -955 then raise; end if;   -- ORA-00955: el indice ya existe
end;
/
commit;
/

-- -----------------------------------------------------------------------------
-- 2. La vista. Si la tabla se acaba de crear, ya se puede compilar.
-- -----------------------------------------------------------------------------
create or replace view v_empresas_usuario as
select u.username,
       u.usuario_id,
       e.id_empresa,
       e.nombre_empresa,
       e.cod_pais,
       e.tipo_ident_fiscal,
       e.rfc,
       e.estado,
       p.moneda_local
  from usuario u
  join usuario_empresa ue on ue.usuario_id = u.usuario_id
  join empresas e        on e.id_empresa   = ue.id_empresa
  left join paises p     on p.cod_pais     = e.cod_pais
 where upper(u.estado) in ('ACTIVO', 'A', '1');
/
commit;
/

-- -----------------------------------------------------------------------------
-- 3. Siembra: cada usuario con ID_EMPRESA no nulo conserva su empresa. Con
--    esto, la vista devuelve exactamente lo mismo que devolvia el filtro
--    viejo y todas las listas siguen mostrando lo mismo.
-- -----------------------------------------------------------------------------
insert into usuario_empresa (usuario_id, id_empresa)
select u.usuario_id, u.id_empresa
  from usuario u
 where u.id_empresa is not null
   and not exists (select 1 from usuario_empresa ue
                    where ue.usuario_id = u.usuario_id
                      and ue.id_empresa  = u.id_empresa);
/
commit;
/

-- -----------------------------------------------------------------------------
-- 4. Empresas huerfanas: las creadas desde la pagina 19 que todavia no
--    tienen a nadie (hoy 3, 4 y 5, las tres «dotech») se asocian a 'admin',
--    para que dejen de ser invisibles y el dueño pueda decidir cual conserva.
--    Solo si de verdad no tienen ningun usuario asociado.
-- -----------------------------------------------------------------------------
insert into usuario_empresa (usuario_id, id_empresa)
select (select min(u.usuario_id) from usuario u where upper(u.username) = 'ADMIN'),
       e.id_empresa
  from empresas e
 where not exists (select 1 from usuario_empresa ue where ue.id_empresa = e.id_empresa)
   and exists (select 1 from usuario u where upper(u.username) = 'ADMIN');
/
commit;
/

-- -----------------------------------------------------------------------------
-- 5. Recompilar el esquema y comprobar que no queda nada INVALID (el
--    'alter table' y el 'create table' dejan objetos invalidos si no se
--    recompila).
-- -----------------------------------------------------------------------------
begin
    dbms_utility.compile_schema('WKSP_SYPEXWS', false);
end;
/
commit;
/

-- Constancia: como quedo la asociacion.
select u.username, ue.id_empresa, e.nombre_empresa
  from usuario_empresa ue
  join usuario u on u.usuario_id = ue.usuario_id
  join empresas e on e.id_empresa  = ue.id_empresa
 order by u.username, ue.id_empresa;
/

select object_name, object_type, status
  from all_objects
 where owner = 'WKSP_SYPEXWS' and status <> 'VALID'
   and object_type in ('FUNCTION','PROCEDURE','PACKAGE','PACKAGE BODY','TRIGGER','VIEW','TABLE');
/

-- =============================================================================
-- REVERSA (deshecha a mano, en este orden):
--
--   begin
--       execute immediate 'drop view v_empresas_usuario';
--       execute immediate 'drop table usuario_empresa purge';
--   end;
--   /
--   begin
--       dbms_utility.compile_schema('WKSP_SYPEXWS', false);
--   end;
--   /
--
-- La columna USUARIO.ID_EMPRESA NO se toca: sigue ahi y las pantallas viejas
-- siguen funcionando con ella. Lo unico que se pierde son las asociaciones
-- adicionales (las empresas «dotech» volverian a quedar huerfanas).
-- =============================================================================
