-- =============================================================================
-- deploy/install_datos.sql
--
-- Datos MINIMOS sin los que la app no arranca: los roles de SYN_ROLES.
--
-- Por que existe: medido el 2026-11-07, install.sql no sembraba SYN_ROLES y una
-- instalacion limpia quedaba con la tabla vacia. fn_autenticar_usuario exige un
-- rol y las guardas comparan por codigo_rol, asi que NADIE podia entrar.
-- (Los roles vivian solo en instalacion y migracion/datos_demo.sql, que es el
-- dataset de ejemplo y no se debe cargar en produccion.)
--
-- Idempotente: MERGE por codigo_rol. No fija id_rol a proposito (la identidad
-- asigna el numero); el codigo es la clave real y es lo que usan las guardas.
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

-- Constancia: los siete roles que deben quedar (no es una validacion).
select codigo_rol, nombre_rol from syn_roles order by codigo_rol;
/
