-- =============================================================================
-- deploy/install_datos.sql
--
-- Datos MINIMOS sin los que la app no arranca:
--   1. los roles de SYN_ROLES
--   2. una empresa (si no hay ninguna)
--   3. un administrador inicial (si no hay ningun usuario)
--
-- Por que existe: medido el 2026-11-07, install.sql no sembraba SYN_ROLES y una
-- instalacion limpia quedaba con la tabla vacia. fn_autenticar_usuario exige un
-- rol y las guardas comparan por codigo_rol, asi que NADIE podia entrar.
-- Y aunque hubiera roles, sin EMPRESA ni USUARIO tampoco se puede entrar: la
-- autenticacion exige empresa y rol. (Los datos vivian solo en
-- instalacion y migracion/datos_demo.sql, que es el dataset de ejemplo y no se
-- debe cargar en produccion.)
--
-- Idempotente: MERGE por codigo_rol, y las filas de empresa/usuario solo se
-- crean si las tablas estan vacias. No fija id_rol (la identidad asigna).
--
-- OJO: el nombre va con unistr() donde lleva acento, porque el runner corrompe
-- los literales acentuados. Y cada sentencia lleva su linea '/' porque
-- importar_export.py corta por ahi (sin ellas, ORA-03405).
--
-- Uso:
--   python deploy/conexion/importar_export.py deploy/install_datos.sql
-- =============================================================================

merge into syn_roles t
using (
    select 'ADMIN' as codigo_rol, 'Administrador' as nombre_rol,
           'Acceso total al sistema' as descripcion from dual
    union all
    select 'GERENCIA', 'Gerencia', to_char(unistr('Consulta y aprobaci\00F3n')) from dual
    union all
    select 'VENTAS', 'Ventas', to_char(unistr('Presupuestos y facturaci\00F3n')) from dual
    union all
    select 'CONTABILIDAD', 'Contabilidad', 'Cobros y tasas' from dual
    union all
    select 'ALMACEN', to_char(unistr('Almac\00E9n')), 'Productos y servicios' from dual
    union all
    select 'CONSULTA', 'Consulta', 'Solo lectura' from dual
    union all
    select 'FACTURACION', to_char(unistr('Facturaci\00F3n')), 'Emite y gestiona facturas' from dual
) s
on (t.codigo_rol = s.codigo_rol)
when not matched then
    insert (codigo_rol, nombre_rol, descripcion)
    values (s.codigo_rol, s.nombre_rol, s.descripcion);
/

commit;
/

-- -----------------------------------------------------------------------------
-- Empresa inicial: sin empresa no hay LOV, ni clientes, ni documentos. Solo se
-- crea si EMPRESAS esta vacia (en una base ya en uso no toca nada).
-- -----------------------------------------------------------------------------
insert into empresas (nombre_empresa, cod_pais, tipo_ident_fiscal, estado)
select 'Empresa Principal', 'VE', 'RIF', 'ACTIVO'
  from dual
 where not exists (select 1 from empresas);
/
commit;
/

-- -----------------------------------------------------------------------------
-- Administrador inicial: sin usuario NADIE puede entrar. Clave temporal y
-- DEBE_CAMBIAR_CLAVE='S' (el primer login obliga a cambiarla en la pagina 14).
-- -----------------------------------------------------------------------------
insert into usuario (username, email, password_hash, estado, id_empresa, rol_id, debe_cambiar_clave)
select 'admin',
       'admin@synpex.local',
       sypex_hash_password('Sypex#2026'),
       'ACTIVO',
       (select min(id_empresa) from empresas),
       (select id_rol from syn_roles where codigo_rol = 'ADMIN'),
       'S'
  from dual
 where not exists (select 1 from usuario);
/

commit;
/

-- -----------------------------------------------------------------------------
-- Asociacion del administrador inicial con su empresa. Desde el 2026-11-10 el
-- permiso sale de USUARIO_EMPRESA, no de USUARIO.ID_EMPRESA: sin este par el
-- usuario no tendria ninguna empresa y no podria entrar.
-- -----------------------------------------------------------------------------
insert into usuario_empresa (usuario_id, id_empresa)
select u.usuario_id, u.id_empresa
  from usuario u
  join empresas e on e.id_empresa = u.id_empresa
 where upper(u.username) = 'ADMIN'
   and u.id_empresa is not null
   and not exists (select 1 from usuario_empresa ue
                    where ue.usuario_id = u.usuario_id
                      and ue.id_empresa  = u.id_empresa);
/

commit;
/

-- Tipos de documento de la pagina 9. Sin estas filas la combo "Tipo Documento" sale vacia
-- en una instalacion limpia (install.sql solo hace el DDL de TIPO_DOCUMENTO).
-- Los codigos tienen que ser exactamente los del CHECK FACTURAS.CHK_FACTURA_TIPO.
merge into tipo_documento d
using (
    select 'FAC' as codigo, 'Factura de Venta' as descripcion from dual
    union all
    select 'NC', to_char(unistr('Nota de Cr\00E9dito')) from dual
    union all
    select 'ND', to_char(unistr('Nota de D\00E9bito')) from dual
) s
on (d.codigo = s.codigo)
when not matched then insert (codigo, descripcion, activo)
                      values (s.codigo, s.descripcion, 'Y')
when matched then update set descripcion = s.descripcion, activo = 'Y'
/

commit;
/

-- Constancia: los siete roles, la empresa y el usuario inicial.
select codigo_rol, nombre_rol from syn_roles order by codigo_rol;
/

select id_empresa, nombre_empresa, cod_pais, tipo_ident_fiscal from empresas order by id_empresa;
/

select username, id_empresa, estado, debe_cambiar_clave from usuario order by usuario_id;
/
