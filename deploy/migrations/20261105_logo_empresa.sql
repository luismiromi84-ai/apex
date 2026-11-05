-- =============================================================================
-- 20261105_logo_empresa.sql
--
-- Objetivo: que cada empresa cliente pueda tener su logo y que salga en el
--           impreso de presupuesto y factura. EMPRESAS.LOGO_FILENAME estaba
--           declarado y muerto (ninguna pagina lo leia ni lo escribia).
--
-- Que hace:
--   1. Crea EMPRESA_LOGO (una fila por empresa, BLOB + tipo + tamano).
--   2. Crea PKG_EMPRESA_LOGO: alta/reemplazo con validaciones (PNG o JPG, maximo
--      2 MB), baja, y fn_logo_img que devuelve <img src="data:...;base64,...">.
--   3. Deja EMPRESAS.LOGO_FILENAME como el nombre del archivo cargado.
--
-- Afecta a: una tabla nueva y un paquete nuevo. No toca datos existentes.
--
-- Por que data URI: el impreso se genera desde un CLOB y se manda al navegador;
--           si el logo fuera una URL habria que servirla desde APEX con permisos
--           y no funcionaria al imprimir o exportar el HTML fuera de la app.
--
-- Idempotente: la tabla y el paquete se comprueban antes de crear.
--
-- Ejecutar:
--   python deploy/conexion/importar_export.py deploy/migrations/20261105_logo_empresa.sql
--
-- REVERSA:
--   drop package pkg_empresa_logo;
--   drop table empresa_logo;
--   update empresas set logo_filename = null;
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;
/

declare
    v_n number;
begin
    select count(*) into v_n from all_tables
     where owner='WKSP_SYPEXWS' and table_name='EMPRESA_LOGO';

    if v_n = 0 then
        execute immediate q'~
create table empresa_logo (
    id_empresa      number        not null enable,
    nombre_archivo  varchar2(255),
    mime_type       varchar2(100) not null enable,
    tamano          number        not null enable,
    imagen          blob          not null enable,
    fecha_carga     date          default sysdate,
    subido_por      varchar2(100),
    constraint pk_empresa_logo primary key (id_empresa) using index enable,
    constraint fk_empresa_logo foreign key (id_empresa)
        references empresas (id_empresa) enable,
    constraint ck_empresa_logo_mime check (mime_type in ('image/png', 'image/jpeg')) enable
)~';
    end if;
end;
/

-- -----------------------------------------------------------------------------
-- Validaciones: las tres deben devolver cero filas
-- -----------------------------------------------------------------------------
select 'FALLA: falta la tabla EMPRESA_LOGO' as caso from dual
 where not exists (select 1 from all_tables
                    where owner='WKSP_SYPEXWS' and table_name='EMPRESA_LOGO');
/

select 'FALLA: falta la FK a EMPRESAS' as caso from dual
 where not exists (select 1 from all_constraints
                    where owner='WKSP_SYPEXWS' and table_name='EMPRESA_LOGO'
                      and constraint_name='FK_EMPRESA_LOGO' and status='ENABLED');
/

select 'FALLA: hay objetos invalidos' as caso
  from all_objects
 where owner='WKSP_SYPEXWS' and status <> 'VALID'
   and object_type in ('FUNCTION','PROCEDURE','PACKAGE','PACKAGE BODY','TRIGGER','VIEW');
/
