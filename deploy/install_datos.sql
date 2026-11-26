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

-- -----------------------------------------------------------------------------
-- Catalogo de conceptos de retencion de ISLR (tabla oficial del SENIAT,
-- Decreto 1.808, G.O. 43.140, UT = 43 Bs).
--
-- Por que existe aqui: sin catalogo no se puede calcular el ISLR ni imprimir su
-- comprobante, y una tarifa o un sustraendo mal puestos son dinero mal retenido
-- en cada compra. Hasta el 2026-11-19 el catalogo solo lo sembraba la migracion
-- deploy/migrations/20261119_islr_conceptos_seed.sql, asi que una INSTALACION
-- LIMPIA quedaba con ISLR_CONCEPTOS vacia y la compra no podia retener.
--
-- Es el MISMO merge que la migracion (alli esta el detalle de cada fila y la
-- validacion contra el PDF). Aqui va sin "alter session" porque install_datos
-- se ejecuta dentro del esquema.
--
-- Los 13 de tarifa plana van ACTIVO='S'; los 3 de formula especial (040 primas
-- de seguro, 065 y 067 tarjetas de credito) van ACTIVO='N': se ven en el
-- catalogo pero no se pueden elegir. El resto de conceptos de tarifa plana del
-- PDF (fletes, publicidad, regalias, asistencia tecnica, intereses, premios...)
-- NO se siembra: espera la revision del dueno.
--
-- OJO: el SET va en la misma linea del UPDATE. importar_export.py descarta toda
-- linea que empiece por "set " y el MERGE se quedaria sin el SET (ORA-00971).
--
-- Idempotente: MERGE por CODIGO.
-- -----------------------------------------------------------------------------
merge into islr_conceptos t
using (
    -- Honorarios profesionales (9.1)
    select '002' as codigo, '9.1.b' as numeral,
           'HONORARIOS PROFESIONALES' as descripcion,
           100 as base_pct, 3 as tarifa, 2.5 as sustraendo_ut,
           'J' as tipo_persona, 'S' as domiciliado, 'S' as activo
      from dual
    union all
    select '003', '9.1.a', 'HONORARIOS PROFESIONALES',
           90, 34, 0, 'N', 'S', 'S' from dual
    -- Comisiones mercantiles y otras (9.2.b)
    union all
    select '018', '9.2.b', 'COMISIONES MERCANTILES Y OTRAS',
           100, 3, 2.5, 'J', 'S', 'S' from dual
    union all
    select '019', '9.2.b', 'COMISIONES MERCANTILES Y OTRAS',
           100, 34, 0, 'N', 'S', 'S' from dual
    -- Servicios (9.11)
    union all
    select '053', '9.11', 'SERVICIOS',
           100, 1, 0.8333, 'J', 'S', 'S' from dual
    union all
    select '054', '9.11', 'SERVICIOS',
           100, 34, 0, 'N', 'S', 'S' from dual
    union all
    select '055', '9.11', 'SERVICIOS',
           100, 2, 0, 'J', 'N', 'S' from dual
    -- Arrendamiento de bienes inmuebles (9.12)
    union all
    select '057', '9.12', 'ARRENDAMIENTO BIENES INMUEBLES',
           100, 3, 2.5, 'J', 'S', 'S' from dual
    union all
    select '058', '9.12', 'ARRENDAMIENTO BIENES INMUEBLES',
           100, 34, 0, 'N', 'S', 'S' from dual
    union all
    select '059', '9.12', 'ARRENDAMIENTO BIENES INMUEBLES',
           100, 5, 0, 'J', 'N', 'S' from dual
    -- Arrendamiento de bienes muebles (9.13)
    union all
    select '061', '9.13', 'ARRENDAMIENTO BIENES MUEBLES',
           100, 3, 2.5, 'J', 'S', 'S' from dual
    union all
    select '062', '9.13', 'ARRENDAMIENTO BIENES MUEBLES',
           100, 34, 0, 'N', 'S', 'S' from dual
    union all
    select '063', '9.13', 'ARRENDAMIENTO BIENES MUEBLES',
           100, 5, 0, 'J', 'N', 'S' from dual
    -- Formula especial: se siembran inactivos (no se pueden elegir)
    union all
    select '040', '9.8', 'PRIMAS DE SEGURO (requiere captura manual)',
           30, 10, 0, null, null, 'N' from dual
    union all
    select '065', '9.14', 'TARJETAS DE CREDITO (requiere captura manual)',
           100, 3, 0, null, null, 'N' from dual
    union all
    select '067', '9.14', 'TARJETAS DE CREDITO (requiere captura manual)',
           100, 5, 0, null, null, 'N' from dual
) s
on (t.codigo = s.codigo)
when matched then update set
    t.numeral       = s.numeral,
    t.descripcion   = s.descripcion,
    t.actividad     = s.descripcion,
    t.base_pct      = s.base_pct,
    t.tarifa        = s.tarifa,
    t.sustraendo_ut = s.sustraendo_ut,
    t.tipo_persona  = s.tipo_persona,
    t.domiciliado   = s.domiciliado,
    t.activo        = s.activo
when not matched then
    insert (codigo, numeral, descripcion, actividad, base_pct, tarifa,
            sustraendo_ut, tipo_persona, domiciliado, activo)
    values (s.codigo, s.numeral, s.descripcion, s.descripcion, s.base_pct,
            s.tarifa, s.sustraendo_ut, s.tipo_persona, s.domiciliado, s.activo)
/

commit;
/

-- Comprobacion del catalogo: 16 conceptos sembrados y 13 elegibles. Se cuentan
-- SOLO los 16 codigos de esta siembra, para que agregar conceptos en otra
-- migracion no haga abortar una reinstalacion.
declare
    v_n number;
begin
    select count(*) into v_n from islr_conceptos
     where codigo in ('002','003','018','019','040','053','054','055','057',
                      '058','059','061','062','063','065','067');
    if v_n <> 16 then
        raise_application_error(-20112, 'el catalogo de ISLR tiene ' || v_n || ' de 16 conceptos');
    end if;

    select count(*) into v_n from islr_conceptos
     where codigo in ('002','003','018','019','040','053','054','055','057',
                      '058','059','061','062','063','065','067')
       and activo = 'S';
    if v_n <> 13 then
        raise_application_error(-20112, 'hay ' || v_n || ' de 16 conceptos de ISLR activos (esperado 13)');
    end if;

    -- El sustraendo es lo que mas caro sale si se redondea: 0,83 UT en vez de
    -- 0,8333 son 35,69 Bs en vez de 35,83 en cada compra al 1 %.
    select count(*) into v_n from islr_conceptos
     where codigo = '053' and tarifa = 1 and abs(sustraendo_ut - 0.8333) < 0.0001;
    if v_n <> 1 then
        raise_application_error(-20112, 'el concepto 053 no quedo con 1 % y 0,8333 UT');
    end if;
end;
/

-- Constancia: los siete roles, la empresa y el usuario inicial.
select codigo_rol, nombre_rol from syn_roles order by codigo_rol;
/

select id_empresa, nombre_empresa, cod_pais, tipo_ident_fiscal from empresas order by id_empresa;
/

select username, id_empresa, estado, debe_cambiar_clave from usuario order by usuario_id;
/

-- Inventario (2026-11-24): 1 permite dejar existencias en negativo (decision del
-- dueno: en Venezuela se despacha antes de que llegue la compra), 0 lo prohibe.
insert into syn_parametros (clave, valor, descripcion)
select 'INVENTARIO_PERMITE_NEGATIVO', 1,
       'Inventario: 1 permite dejar existencias en negativo, 0 lo prohibe' from dual
 where not exists (select 1 from syn_parametros where clave = 'INVENTARIO_PERMITE_NEGATIVO');
commit;

-- Formato de las cifras por pais (2026-11-25): 1 = una empresa venezolana ve 1.234,56;
-- 0 = toda la app con el formato de es-mx (1,234.56). Lo lee prc_nls_sesion.
insert into syn_parametros (clave, valor, descripcion)
select 'FORMATO_NUMERO_POR_PAIS', 1,
       'Formato de las cifras por pais de la empresa activa: 1 VE con 1.234,56; 0 todo como la app (1,234.56)' from dual
 where not exists (select 1 from syn_parametros where clave = 'FORMATO_NUMERO_POR_PAIS');
commit;

-- Cajas y bancos (2026-11-25): cada empresa nace con su «Caja principal» en su moneda local.
insert into cuentas_fondos (id_empresa, nombre, tipo, cod_moneda, es_principal, estado, creado_por)
select e.id_empresa, 'Caja principal', 'CAJA', nvl(pa.moneda_local, 'USD'), 'S', 'ACTIVO', 'INSTALACION'
  from empresas e left join paises pa on pa.cod_pais = e.cod_pais
 where not exists (select 1 from cuentas_fondos c where c.id_empresa = e.id_empresa and c.es_principal = 'S');
commit;

-- Contabilidad (2026-11-25): plantilla del plan de cuentas de Venezuela.
@@datos/ctb_plantilla_ve.sql
