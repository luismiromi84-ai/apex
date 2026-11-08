-- =============================================================================
-- 20261108_productos_iniciales.sql
--
-- Catalogo inicial de productos y servicios.
--
-- Por que: la purga del demo (2026-11-08) dejo `producto_servicio` en 0 filas, y
-- la LOV "Producto / Servicio" de la pagina 6 solo muestra los que estan
-- ACTIVO. Sin catalogo no se puede ni crear una linea de presupuesto.
--
-- Son datos de ARRANQUE para poder probar: reemplazalos por el catalogo real.
-- `impuesto_aplicable` es el PORCENTAJE (16 = IVA general), no el id de IMPUESTOS.
--
-- Idempotente: MERGE por CODIGO (la tabla tiene UNIQUE(CODIGO)). Los acentos van
-- con unistr() porque el runner corrompe los literales acentuados.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

merge into producto_servicio d
using (select 'SERV-001' as codigo from dual) s
on (d.codigo = s.codigo)
when not matched then insert (codigo, nombre, descripcion, tipo, precio_sugerido,
                              impuesto_aplicable, estado, fecha_creacion)
values ('SERV-001', 'Mantenimiento preventivo',
        unistr('Revisi\00F3n general de 10 puntos'), 'SERVICIO', 45.00, 16.00, 'ACTIVO', sysdate)
when matched then update set nombre = 'Mantenimiento preventivo',
                              descripcion = unistr('Revisi\00F3n general de 10 puntos'),
                              tipo = 'SERVICIO', precio_sugerido = 45.00,
                              impuesto_aplicable = 16.00, estado = 'ACTIVO'
/

merge into producto_servicio d
using (select 'SERV-002' as codigo from dual) s
on (d.codigo = s.codigo)
when not matched then insert (codigo, nombre, descripcion, tipo, precio_sugerido,
                              impuesto_aplicable, estado, fecha_creacion)
values ('SERV-002', 'Cambio de aceite y filtro',
        'Aceite sintetico y filtro incluido', 'SERVICIO', 38.00, 16.00, 'ACTIVO', sysdate)
when matched then update set nombre = 'Cambio de aceite y filtro',
                              descripcion = 'Aceite sintetico y filtro incluido',
                              tipo = 'SERVICIO', precio_sugerido = 38.00,
                              impuesto_aplicable = 16.00, estado = 'ACTIVO'
/

merge into producto_servicio d
using (select 'SERV-003' as codigo from dual) s
on (d.codigo = s.codigo)
when not matched then insert (codigo, nombre, descripcion, tipo, precio_sugerido,
                              impuesto_aplicable, estado, fecha_creacion)
values ('SERV-003', unistr('Diagn\00F3stico computarizado'),
        'Escaneo OBD-II con reporte impreso', 'SERVICIO', 25.00, 16.00, 'ACTIVO', sysdate)
when matched then update set nombre = unistr('Diagn\00F3stico computarizado'),
                              descripcion = 'Escaneo OBD-II con reporte impreso',
                              tipo = 'SERVICIO', precio_sugerido = 25.00,
                              impuesto_aplicable = 16.00, estado = 'ACTIVO'
/

merge into producto_servicio d
using (select 'SERV-004' as codigo from dual) s
on (d.codigo = s.codigo)
when not matched then insert (codigo, nombre, descripcion, tipo, precio_sugerido,
                              impuesto_aplicable, estado, fecha_creacion)
values ('SERV-004', unistr('Reparaci\00F3n de frenos'),
        'Cambio de pastillas y purga del sistema', 'SERVICIO', 60.00, 16.00, 'ACTIVO', sysdate)
when matched then update set nombre = unistr('Reparaci\00F3n de frenos'),
                              descripcion = 'Cambio de pastillas y purga del sistema',
                              tipo = 'SERVICIO', precio_sugerido = 60.00,
                              impuesto_aplicable = 16.00, estado = 'ACTIVO'
/

merge into producto_servicio d
using (select 'SERV-005' as codigo from dual) s
on (d.codigo = s.codigo)
when not matched then insert (codigo, nombre, descripcion, tipo, precio_sugerido,
                              impuesto_aplicable, estado, fecha_creacion)
values ('SERV-005', unistr('Alineaci\00F3n y balanceo'), 'Las cuatro ruedas',
        'SERVICIO', 30.00, 16.00, 'ACTIVO', sysdate)
when matched then update set nombre = unistr('Alineaci\00F3n y balanceo'),
                              descripcion = 'Las cuatro ruedas',
                              tipo = 'SERVICIO', precio_sugerido = 30.00,
                              impuesto_aplicable = 16.00, estado = 'ACTIVO'
/

merge into producto_servicio d
using (select 'REP-001' as codigo from dual) s
on (d.codigo = s.codigo)
when not matched then insert (codigo, nombre, descripcion, tipo, precio_sugerido,
                              impuesto_aplicable, estado, fecha_creacion)
values ('REP-001', 'Pastillas de freno', 'Juego delantero',
        'PRODUCTO', 28.00, 16.00, 'ACTIVO', sysdate)
when matched then update set nombre = 'Pastillas de freno', descripcion = 'Juego delantero',
                              tipo = 'PRODUCTO', precio_sugerido = 28.00,
                              impuesto_aplicable = 16.00, estado = 'ACTIVO'
/

merge into producto_servicio d
using (select 'REP-002' as codigo from dual) s
on (d.codigo = s.codigo)
when not matched then insert (codigo, nombre, descripcion, tipo, precio_sugerido,
                              impuesto_aplicable, estado, fecha_creacion)
values ('REP-002', 'Filtro de aceite', 'Filtro original',
        'PRODUCTO', 8.50, 16.00, 'ACTIVO', sysdate)
when matched then update set nombre = 'Filtro de aceite', descripcion = 'Filtro original',
                              tipo = 'PRODUCTO', precio_sugerido = 8.50,
                              impuesto_aplicable = 16.00, estado = 'ACTIVO'
/

merge into producto_servicio d
using (select 'REP-003' as codigo from dual) s
on (d.codigo = s.codigo)
when not matched then insert (codigo, nombre, descripcion, tipo, precio_sugerido,
                              impuesto_aplicable, estado, fecha_creacion)
values ('REP-003', unistr('Bater\00EDa 12V 60Ah'), 'Con garantia de 12 meses',
        'PRODUCTO', 85.00, 16.00, 'ACTIVO', sysdate)
when matched then update set nombre = unistr('Bater\00EDa 12V 60Ah'),
                              descripcion = 'Con garantia de 12 meses',
                              tipo = 'PRODUCTO', precio_sugerido = 85.00,
                              impuesto_aplicable = 16.00, estado = 'ACTIVO'
/

commit
/
