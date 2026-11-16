-- =============================================================================
-- datos_demo.sql — dataset de ejemplo del panel (ids 1000–1999)
--
-- Ejecutar en SQLcl sobre Sypex_SQL:
--   sql -name SYPEX_SQL_MCP @instalacion y migracion/datos_demo.sql
--
-- Es idempotente: empieza borrando su propio rango, así que se puede repetir.
-- NO usa ids 9000+: ese rango es del usuario de prueba (usuario_prueba.sql).
--
-- Las cabeceras de presupuestos y facturas se insertan con montos en 0 y el
-- detalle después: los triggers compound calculan los totales, como en
-- producción.
-- =============================================================================

set define off
set feedback on
set verify off
set serveroutput on

alter session set current_schema = WKSP_SYPEXWS;

-- -----------------------------------------------------------------------------
-- 0. Purga del dataset anterior (orden inverso a las FK, rango explícito)
-- -----------------------------------------------------------------------------
delete from facturas_det      where id_detalle           between 1000 and 1999;
delete from facturas          where id_factura           between 1000 and 1999;
delete from presupuestos_det  where id_detalle           between 1000 and 1999;
delete from presupuestos      where id_presupuesto       between 1000 and 1999;
delete from tipo_cambio       where id_tipo_cambio       between 1000 and 1999;
delete from producto_servicio where id_producto_servicio between 1000 and 1999;
delete from clientes          where id_cliente           between 1000 and 1999;
delete from usuario_empresa   where usuario_id           between 1000 and 1999;
commit;
delete from usuario           where usuario_id           between 1000 and 1999;
delete from syn_roles         where id_rol               between 1000 and 1999;
delete from emp               where empno between 7369 and 7934;
delete from dept              where deptno in (10,20,30,40);
commit;

-- -----------------------------------------------------------------------------
-- 1. DEPT y EMP (juego clásico). Los jefes van antes que sus subordinados
--    porque EMP.MGR es FK a EMP.EMPNO.
-- -----------------------------------------------------------------------------
insert into dept (deptno, dname, loc) values (10, 'ACCOUNTING', 'NEW YORK');
insert into dept (deptno, dname, loc) values (20, 'RESEARCH',   'DALLAS');
insert into dept (deptno, dname, loc) values (30, 'SALES',      'CHICAGO');
insert into dept (deptno, dname, loc) values (40, 'OPERATIONS', 'BOSTON');

insert into emp (empno, ename, job, mgr, hiredate, sal, comm, deptno) values (7839, 'KING',   'PRESIDENT', null, date '1981-11-17', 5000, null, 10);
insert into emp (empno, ename, job, mgr, hiredate, sal, comm, deptno) values (7566, 'JONES',  'MANAGER',   7839, date '1981-04-02', 2975, null, 20);
insert into emp (empno, ename, job, mgr, hiredate, sal, comm, deptno) values (7698, 'BLAKE',  'MANAGER',   7839, date '1981-05-01', 2850, null, 30);
insert into emp (empno, ename, job, mgr, hiredate, sal, comm, deptno) values (7782, 'CLARK',  'MANAGER',   7839, date '1981-06-09', 2450, null, 10);
insert into emp (empno, ename, job, mgr, hiredate, sal, comm, deptno) values (7499, 'ALLEN',  'SALESMAN',  7698, date '1981-02-20', 1600, 300,  30);
insert into emp (empno, ename, job, mgr, hiredate, sal, comm, deptno) values (7521, 'WARD',   'SALESMAN',  7698, date '1981-02-22', 1250, 500,  30);
insert into emp (empno, ename, job, mgr, hiredate, sal, comm, deptno) values (7654, 'MARTIN', 'SALESMAN',  7698, date '1981-09-28', 1250, 1400, 30);
insert into emp (empno, ename, job, mgr, hiredate, sal, comm, deptno) values (7788, 'SCOTT',  'ANALYST',   7566, date '1987-04-19', 3000, null, 20);
insert into emp (empno, ename, job, mgr, hiredate, sal, comm, deptno) values (7844, 'TURNER', 'SALESMAN',  7698, date '1981-09-08', 1500, 0,    30);
insert into emp (empno, ename, job, mgr, hiredate, sal, comm, deptno) values (7876, 'ADAMS',  'CLERK',     7788, date '1987-05-23', 1100, null, 20);
insert into emp (empno, ename, job, mgr, hiredate, sal, comm, deptno) values (7900, 'JAMES',  'CLERK',     7698, date '1981-12-03', 950,  null, 30);
insert into emp (empno, ename, job, mgr, hiredate, sal, comm, deptno) values (7902, 'FORD',   'ANALYST',   7566, date '1981-12-03', 3000, null, 20);
insert into emp (empno, ename, job, mgr, hiredate, sal, comm, deptno) values (7369, 'SMITH',  'CLERK',     7902, date '1980-12-17', 800,  null, 20);
insert into emp (empno, ename, job, mgr, hiredate, sal, comm, deptno) values (7934, 'MILLER', 'CLERK',     7782, date '1982-01-23', 1300, null, 10);

-- -----------------------------------------------------------------------------
-- 2. Roles
-- -----------------------------------------------------------------------------
insert into syn_roles (id_rol, codigo_rol, nombre_rol, descripcion) values (1001, 'ADMIN',        'Administrador', 'Acceso total al sistema');
insert into syn_roles (id_rol, codigo_rol, nombre_rol, descripcion) values (1002, 'GERENCIA',     'Gerencia',      'Consulta y aprobación');
insert into syn_roles (id_rol, codigo_rol, nombre_rol, descripcion) values (1003, 'VENTAS',       'Ventas',        'Presupuestos y facturación');
insert into syn_roles (id_rol, codigo_rol, nombre_rol, descripcion) values (1004, 'CONTABILIDAD', 'Contabilidad',  'Cobros y tasas');
insert into syn_roles (id_rol, codigo_rol, nombre_rol, descripcion) values (1005, 'ALMACEN',      'Almacén',       'Productos y servicios');
insert into syn_roles (id_rol, codigo_rol, nombre_rol, descripcion) values (1006, 'CONSULTA',     'Consulta',      'Solo lectura');

-- -----------------------------------------------------------------------------
-- 3. Usuarios: todos ACTIVO, todos con la clave Prueba#2026
--    (hash = SYPEX_HASH_PASSWORD('Prueba#2026'))
-- -----------------------------------------------------------------------------
insert into usuario (usuario_id, username, email, password_hash, estado, fecha_creacion, id_empresa, rol_id)
values (1001, 'admin.demo', 'admin.demo@sypex.demo',
        '79bf79f838f4e215a561b2fc82201df0b09789543b7bb8ee1002016fce0ea805', 'ACTIVO', sysdate, 1, 1001);
insert into usuario (usuario_id, username, email, password_hash, estado, fecha_creacion, id_empresa, rol_id)
values (1002, 'gerencia.demo', 'gerencia.demo@sypex.demo',
        '79bf79f838f4e215a561b2fc82201df0b09789543b7bb8ee1002016fce0ea805', 'ACTIVO', sysdate, 1, 1002);
insert into usuario (usuario_id, username, email, password_hash, estado, fecha_creacion, id_empresa, rol_id)
values (1003, 'ventas1.demo', 'ventas1.demo@sypex.demo',
        '79bf79f838f4e215a561b2fc82201df0b09789543b7bb8ee1002016fce0ea805', 'ACTIVO', sysdate, 1, 1003);
insert into usuario (usuario_id, username, email, password_hash, estado, fecha_creacion, id_empresa, rol_id)
values (1004, 'ventas2.demo', 'ventas2.demo@sypex.demo',
        '79bf79f838f4e215a561b2fc82201df0b09789543b7bb8ee1002016fce0ea805', 'ACTIVO', sysdate, 1, 1003);
insert into usuario (usuario_id, username, email, password_hash, estado, fecha_creacion, id_empresa, rol_id)
values (1005, 'contabilidad.demo', 'contabilidad.demo@sypex.demo',
        '79bf79f838f4e215a561b2fc82201df0b09789543b7bb8ee1002016fce0ea805', 'ACTIVO', sysdate, 1, 1004);
insert into usuario (usuario_id, username, email, password_hash, estado, fecha_creacion, id_empresa, rol_id)
values (1006, 'almacen.demo', 'almacen.demo@sypex.demo',
        '79bf79f838f4e215a561b2fc82201df0b09789543b7bb8ee1002016fce0ea805', 'ACTIVO', sysdate, 1, 1005);
insert into usuario (usuario_id, username, email, password_hash, estado, fecha_creacion, id_empresa, rol_id)
values (1007, 'consulta.demo', 'consulta.demo@sypex.demo',
        '79bf79f838f4e215a561b2fc82201df0b09789543b7bb8ee1002016fce0ea805', 'ACTIVO', sysdate, 1, 1006);
insert into usuario (usuario_id, username, email, password_hash, estado, fecha_creacion, id_empresa, rol_id)
values (1008, 'auditor.demo', 'auditor.demo@sypex.demo',
        '79bf79f838f4e215a561b2fc82201df0b09789543b7bb8ee1002016fce0ea805', 'ACTIVO', sysdate, 1, 1006);

-- -----------------------------------------------------------------------------
-- 4. Clientes: 8 venezolanos (RIF) y 4 mexicanos (RFC)
-- -----------------------------------------------------------------------------
insert into clientes (id_cliente, id_empresa, rif, razon_social, email, telefono, direccion, estado, fecha_creacion)
values (1001, 1, 'J-30123456-7', 'Distribuidora Andina C.A.',    'contacto@andina.demo',    '+58 212 5550101', 'Av. Libertador, Caracas',      'ACTIVO', sysdate);
insert into clientes (id_cliente, id_empresa, rif, razon_social, email, telefono, direccion, estado, fecha_creacion)
values (1002, 1, 'J-30234567-8', 'Servicios Caracas C.A.',       'contacto@scaracas.demo',  '+58 212 5550102', 'Torre Este, Caracas',          'ACTIVO', sysdate);
insert into clientes (id_cliente, id_empresa, rif, razon_social, email, telefono, direccion, estado, fecha_creacion)
values (1003, 1, 'J-30345678-9', 'Comercial Maracaibo C.A.',     'contacto@maracaibo.demo', '+58 261 5550103', 'Av. Bella Vista, Maracaibo',   'ACTIVO', sysdate);
insert into clientes (id_cliente, id_empresa, rif, razon_social, email, telefono, direccion, estado, fecha_creacion)
values (1004, 1, 'J-30456789-0', 'Inversiones Valencia C.A.',    'contacto@valencia.demo',  '+58 241 5550104', 'Av. Bolívar, Valencia',        'ACTIVO', sysdate);
insert into clientes (id_cliente, id_empresa, rif, razon_social, email, telefono, direccion, estado, fecha_creacion)
values (1005, 1, 'J-30567890-1', 'Grupo Oriente C.A.',           'contacto@oriente.demo',   '+58 281 5550105', 'Av. Intercomunal, Puerto La Cruz', 'ACTIVO', sysdate);
insert into clientes (id_cliente, id_empresa, rif, razon_social, email, telefono, direccion, estado, fecha_creacion)
values (1006, 1, 'J-30678901-2', 'Talleres Barquisimeto C.A.',   'contacto@talleres.demo',  '+58 251 5550106', 'Calle 20, Barquisimeto',       'ACTIVO', sysdate);
insert into clientes (id_cliente, id_empresa, rif, razon_social, email, telefono, direccion, estado, fecha_creacion)
values (1007, 1, 'J-30789012-3', 'Suministros Aragua C.A.',      'contacto@aragua.demo',    '+58 243 5550107', 'Av. Aragua, Maracay',          'ACTIVO', sysdate);
insert into clientes (id_cliente, id_empresa, rif, razon_social, email, telefono, direccion, estado, fecha_creacion)
values (1008, 1, 'J-30890123-4', 'Logística Bolívar C.A.',       'contacto@bolivar.demo',   '+58 285 5550108', 'Zona Industrial, Ciudad Bolívar', 'ACTIVO', sysdate);

insert into clientes (id_cliente, id_empresa, rif, razon_social, email, telefono, direccion, estado, fecha_creacion)
values (1009, 1, 'DAN850101AB1', 'Distribuidora Azteca SA de CV', 'contacto@azteca.demo',  '+52 55 55510109', 'Av. Reforma 100, CDMX',        'ACTIVO', sysdate);
insert into clientes (id_cliente, id_empresa, rif, razon_social, email, telefono, direccion, estado, fecha_creacion)
values (1010, 1, 'SCM900202CD2', 'Servicios Monterrey SA de CV',  'contacto@monterrey.demo','+52 81 55510110', 'Av. Constitución 200, Monterrey', 'ACTIVO', sysdate);
insert into clientes (id_cliente, id_empresa, rif, razon_social, email, telefono, direccion, estado, fecha_creacion)
values (1011, 1, 'CMZ010303EF3', 'Comercial Jalisco SA de CV',    'contacto@jalisco.demo', '+52 33 55510111', 'Av. Vallarta 300, Guadalajara', 'ACTIVO', sysdate);
insert into clientes (id_cliente, id_empresa, rif, razon_social, email, telefono, direccion, estado, fecha_creacion)
values (1012, 1, 'IVM020404GH4', 'Inversiones Puebla SA de CV',   'contacto@puebla.demo',  '+52 22 55510112', 'Av. Juárez 400, Puebla',        'ACTIVO', sysdate);

-- -----------------------------------------------------------------------------
-- 5. Productos y servicios
-- -----------------------------------------------------------------------------
insert into producto_servicio (id_producto_servicio, codigo, nombre, descripcion, tipo, precio_sugerido, impuesto_aplicable, estado, fecha_creacion)
values (1001, 'SRV-CON', 'Consultoría',      'Hora de consultoría funcional',        'SERVICIO',  80.00, 16.00, 'ACTIVO', sysdate);
insert into producto_servicio (id_producto_servicio, codigo, nombre, descripcion, tipo, precio_sugerido, impuesto_aplicable, estado, fecha_creacion)
values (1002, 'SRV-SOP', 'Soporte',          'Hora de soporte técnico',              'SERVICIO',  60.00, 16.00, 'ACTIVO', sysdate);
insert into producto_servicio (id_producto_servicio, codigo, nombre, descripcion, tipo, precio_sugerido, impuesto_aplicable, estado, fecha_creacion)
values (1003, 'SRV-CAP', 'Capacitación',     'Hora de capacitación',                 'SERVICIO',  50.00, 16.00, 'ACTIVO', sysdate);
insert into producto_servicio (id_producto_servicio, codigo, nombre, descripcion, tipo, precio_sugerido, impuesto_aplicable, estado, fecha_creacion)
values (1004, 'SRV-IMP', 'Implementación',   'Jornada de implementación',            'SERVICIO', 120.00, 16.00, 'ACTIVO', sysdate);
insert into producto_servicio (id_producto_servicio, codigo, nombre, descripcion, tipo, precio_sugerido, impuesto_aplicable, estado, fecha_creacion)
values (1005, 'SRV-AUD', 'Auditoría',        'Revisión de procesos',                 'SERVICIO',  90.00, 16.00, 'ACTIVO', sysdate);
insert into producto_servicio (id_producto_servicio, codigo, nombre, descripcion, tipo, precio_sugerido, impuesto_aplicable, estado, fecha_creacion)
values (1006, 'PRD-LIC', 'Licencia anual',   'Licencia de uso por usuario',          'PRODUCTO', 450.00, 16.00, 'ACTIVO', sysdate);
insert into producto_servicio (id_producto_servicio, codigo, nombre, descripcion, tipo, precio_sugerido, impuesto_aplicable, estado, fecha_creacion)
values (1007, 'PRD-MOD', 'Módulo contable',  'Módulo adicional de contabilidad',     'PRODUCTO', 900.00, 16.00, 'ACTIVO', sysdate);
insert into producto_servicio (id_producto_servicio, codigo, nombre, descripcion, tipo, precio_sugerido, impuesto_aplicable, estado, fecha_creacion)
values (1008, 'PRD-HW1', 'Lector de código','Lector USB de códigos de barra',       'PRODUCTO', 150.00, 16.00, 'ACTIVO', sysdate);
insert into producto_servicio (id_producto_servicio, codigo, nombre, descripcion, tipo, precio_sugerido, impuesto_aplicable, estado, fecha_creacion)
values (1009, 'PRD-CON', 'Consumible',       'Rollo térmico para impresora',        'PRODUCTO',  20.00, 16.00, 'ACTIVO', sysdate);
insert into producto_servicio (id_producto_servicio, codigo, nombre, descripcion, tipo, precio_sugerido, impuesto_aplicable, estado, fecha_creacion)
values (1010, 'PRD-REP', 'Repuesto',         'Kit de repuestos de impresora',       'PRODUCTO', 250.00, 16.00, 'ACTIVO', sysdate);

-- -----------------------------------------------------------------------------
-- 6. Tipos de cambio: 12 fechas (cada 15 días hacia atrás) × 2 combinaciones.
--    La app busca X→VES, así que MXN usa MXN→VES.
--
--    OJO: TIPO_CAMBIO.TIPO_TASA es VARCHAR2(10) y el CHECK permite
--    ('PRESUPUESTO','REAL'), pero 'PRESUPUESTO' mide 11 caracteres: no cabe y
--    el INSERT falla con ORA-12899. Es un defecto del esquema, no del demo;
--    hasta que se migre la columna a VARCHAR2(12) solo se cargan tasas 'REAL'.
--    Toda la app usa únicamente 'REAL'.
-- -----------------------------------------------------------------------------
declare
    v_id    number := 1000;
    v_fecha date;
    v_ves   number;
begin
    for k in 0 .. 11 loop
        v_fecha := trunc(sysdate) - k * 15;
        v_ves   := round(55 - k * 2.27, 4);

        v_id := v_id + 1;
        insert into tipo_cambio (id_tipo_cambio, moneda_origen, moneda_destino, tipo_tasa, tasa_cambio, fecha_vigencia)
        values (v_id, 'USD', 'VES', 'REAL', v_ves, v_fecha);

        v_id := v_id + 1;
        insert into tipo_cambio (id_tipo_cambio, moneda_origen, moneda_destino, tipo_tasa, tasa_cambio, fecha_vigencia)
        values (v_id, 'MXN', 'VES', 'REAL', round(2.8 - k * 0.05, 4), v_fecha);
    end loop;
end;
/

-- -----------------------------------------------------------------------------
-- 7. Presupuestos (45) y su detalle
--    Cabeceras con montos en 0: los calcula el trigger compound desde el detalle.
-- -----------------------------------------------------------------------------
declare
    v_estados sys.odcivarchar2list := sys.odcivarchar2list(
        'PENDIENTE','ENVIADO','APROBADO','RECHAZADO','CANCELADO','FACTURADO');
    v_id_pre  number;
    v_cliente number;
    v_fecha   date;
    v_estado  varchar2(20);
    v_moneda  varchar2(5);
    v_prod    number;
    v_precio  number;
    v_cant    number;
    v_imp     number;
    v_bruto   number;
    v_iva     number;
begin
    for i in 1 .. 45 loop
        v_id_pre  := 1000 + i;
        v_cliente := 1000 + mod(i, 12) + 1;
        v_fecha   := add_months(trunc(sysdate,'MM'), -mod(i,6)) + mod(i,27);
        v_estado  := v_estados(mod(i,6) + 1);
        v_moneda  := case when mod(i,10) < 6 then 'USD'
                          when mod(i,10) < 9 then 'VES'
                          else 'MXN' end;

        insert into presupuestos (id_presupuesto, id_empresa, folio, id_cliente, fecha_emision,
                                  estado, cod_moneda, tipo_cambio, subtotal, impuesto_iva, total,
                                  observaciones, creado_por)
        values (v_id_pre, 1, 1000 + i, v_cliente, v_fecha, v_estado, v_moneda, 1, 0, 0, 0,
                'Presupuesto de ejemplo', 'ADMIN_SYPEX');

        for j in 1 .. 1 + mod(i,3) loop
            v_prod   := 1000 + mod(i + j, 10) + 1;
            v_cant   := 1 + mod(i + j, 4);
            select precio_sugerido into v_precio
              from producto_servicio where id_producto_servicio = v_prod;
            v_imp    := case when mod(v_cliente,2) = 0 then 1 else 4 end;  -- VE : MX, ambos 16 %
            v_bruto  := v_cant * v_precio;
            v_iva    := round(v_bruto * 16 / 100, 2);

            insert into presupuestos_det (id_detalle, id_presupuesto, id_producto_servicio,
                                          descripcion, cantidad, precio_unitario, subtotal_linea,
                                          porcentage_descuento, monto_descuento,
                                          id_impuesto, porcentage_impuesto, monto_impuesto,
                                          monto_total_linea)
            values (1000 + i*10 + j, v_id_pre, v_prod,
                    'Línea ' || j || ' del presupuesto ' || (1000 + i),
                    v_cant, v_precio, v_bruto,
                    0, 0, v_imp, 16, v_iva, v_bruto + v_iva);
        end loop;
    end loop;
end;
/

-- -----------------------------------------------------------------------------
-- 8. Facturas (40) y su detalle: 32 FAC, 5 NC (restan) y 3 ND (suman)
-- -----------------------------------------------------------------------------
declare
    v_id_fac  number;
    v_cliente number;
    v_fecha   date;
    v_estado  varchar2(20);
    v_moneda  varchar2(5);
    v_tipo    varchar2(3);
    v_prod    number;
    v_codigo  varchar2(20);
    v_precio  number;
    v_cant    number;
    v_imp     number;
    v_bruto   number;
    v_iva     number;
begin
    for i in 1 .. 40 loop
        v_id_fac  := 1000 + i;
        v_cliente := 1000 + mod(i, 12) + 1;
        v_fecha   := add_months(trunc(sysdate,'MM'), -mod(i,6)) + mod(i,20);
        v_moneda  := case when i <= 24 then 'USD'
                          when i <= 36 then 'VES'
                          else 'MXN' end;
        v_tipo    := case when i <= 32 then 'FAC' when i <= 37 then 'NC' else 'ND' end;
        v_estado  := case mod(i,4) when 0 then 'ANULADA' when 1 then 'PENDIENTE'
                                    when 2 then 'TIMBRADA' else 'PAGADA' end;

        insert into facturas (id_factura, id_empresa, id_cliente, id_presupuesto, tipo_documento,
                              folio_factura, cod_moneda, tipo_cambio, fecha_emision, estado,
                              subtotal, monto_impuesto, monto_total, observaciones, creado_por)
        values (v_id_fac, 1, v_cliente, 1000 + i, v_tipo,
                'F-' || to_char(1000 + i), v_moneda, 1, v_fecha, v_estado, 0, 0, 0,
                'Documento de ejemplo', 'ADMIN_SYPEX');

        for j in 1 .. 1 + mod(i,3) loop
            v_prod   := 1000 + mod(i + j, 10) + 1;
            v_cant   := 1 + mod(i + j, 3);
            select precio_sugerido, codigo into v_precio, v_codigo
              from producto_servicio where id_producto_servicio = v_prod;
            v_imp    := case when mod(v_cliente,2) = 0 then 1 else 4 end;
            v_bruto  := v_cant * v_precio;
            v_iva    := round(v_bruto * 16 / 100, 2);

            insert into facturas_det (id_detalle, id_factura, num_linea, id_producto, codigo_producto,
                                      descripcion, cantidad, precio_unitario,
                                      porcentaje_descuento, monto_descuento, id_impuesto,
                                      porcentaje_impuesto, monto_impuesto,
                                      subtotal_linea, monto_total_linea,
                                      tasa_cambio_aplicada, subtotal_bs, total_bs,
                                      porcentage_impuesto, porcentage_descuento, creado_por)
            values (1500 + i*10 + j, v_id_fac, j, v_prod, v_codigo,
                    'Línea ' || j || ' del documento ' || (1000 + i),
                    v_cant, v_precio,
                    0, 0, v_imp,
                    16, v_iva,
                    v_bruto, v_bruto + v_iva,
                    1, v_bruto, v_bruto + v_iva,
                    16, 0, 'ADMIN_SYPEX');
        end loop;
    end loop;
end;
/

commit;

-- -----------------------------------------------------------------------------
-- 9. Realineo de secuencias: los INSERT traen ids explícitos, que no avanzan
--    las secuencias. Las identity se ajustan con START WITH LIMIT VALUE; las
--    explícitas, con el truco de incremento.
-- -----------------------------------------------------------------------------
declare
    v_want number;
    v_cur  number;
    v_diff number;

    procedure realinear_secuencia(p_seq varchar2, p_tabla varchar2, p_columna varchar2) is
    begin
        execute immediate 'select nvl(max("' || p_columna || '"),0)+1 from "WKSP_SYPEXWS"."' || p_tabla || '"'
            into v_want;
        execute immediate 'select "WKSP_SYPEXWS"."' || p_seq || '".nextval from dual' into v_cur;
        if v_want > v_cur then
            v_diff := v_want - v_cur;
            execute immediate 'alter sequence "WKSP_SYPEXWS"."' || p_seq || '" increment by ' || v_diff;
            execute immediate 'select "WKSP_SYPEXWS"."' || p_seq || '".nextval from dual' into v_cur;
        end if;
        execute immediate 'alter sequence "WKSP_SYPEXWS"."' || p_seq || '" increment by 1';
    end;
begin
    for r in (select table_name, column_name, generation_type
                from all_tab_identity_cols where owner = 'WKSP_SYPEXWS')
    loop
        execute immediate 'alter table "WKSP_SYPEXWS"."' || r.table_name || '" modify ("' || r.column_name
                       || '" GENERATED ' || r.generation_type || ' AS IDENTITY (START WITH LIMIT VALUE))';
    end loop;

    realinear_secuencia('SEQ_PRODUCTO_SERVICIO', 'PRODUCTO_SERVICIO', 'ID_PRODUCTO_SERVICIO');
    realinear_secuencia('SEQ_CONDICION_PAGO',    'CONDICION_PAGO',    'ID_CONDICION_PAGO');
    realinear_secuencia('SEQ_FORMA_PAGO',        'FORMA_PAGO',        'ID_FORMA_PAGO');
    realinear_secuencia('DEPT_SEQ',              'DEPT',              'DEPTNO');
    realinear_secuencia('EMP_SEQ',               'EMP',               'EMPNO');
end;
/

commit;

prompt
prompt Dataset de ejemplo cargado: catalogos, 45 presupuestos, 40 facturas.
prompt Verificar con: @instalacion y migracion/validar_demo.sql
prompt
