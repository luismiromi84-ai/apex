-- Usuarios de prueba para validar la autorizacion por rol.
--
-- Estado medido el 2026-11-04: los usuarios demo ya existen con estos ids
--   admin.demo 1001 ADMIN | gerencia.demo 1002 GERENCIA | ventas1.demo 1003 VENTAS
--   ventas2.demo 1004 VENTAS | contabilidad.demo 1005 CONTABILIDAD
--   almacen.demo 1006 ALMACEN | consulta.demo 1007 CONSULTA | auditor.demo 1008 CONSULTA
-- Por eso aqui solo se crea el que falta:  facturacion.demo / Demo#2026 / rol FACTURACION.
-- Id 9003 (rango 9000+ que validar_carga.sql excluye). No pisa usuarios existentes.
--
-- OJO: datos_demo.sql purga ids 1000-1999, asi que recargar el dataset borra los
-- usuarios demo 1001-1008. Este script los puede recrear solo si se amplia; hoy
-- garantiza unicamente facturacion.demo (9003) porque no cae en ese rango.

set define off
alter session set current_schema = WKSP_SYPEXWS;

merge into usuario t
using (
    select 9003                 usuario_id,
           'facturacion.demo'   username,
           'facturacion.demo@sypex.local' email
      from dual
) s
on (t.usuario_id = s.usuario_id or upper(t.username) = upper(s.username))
when not matched then
    insert (usuario_id, username, email, password_hash, estado,
            fecha_creacion, id_empresa, rol_id)
    values (s.usuario_id, s.username, s.email,
            sypex_hash_password('Demo#2026'), 'ACTIVO',
            sysdate, 1,
            (select id_rol from syn_roles where codigo_rol = 'FACTURACION'));

commit;

select u.usuario_id, u.username, r.codigo_rol, u.estado, u.id_empresa
  from usuario u left join syn_roles r on r.id_rol = u.rol_id
 where u.usuario_id >= 9000
 order by u.usuario_id;

-- Limpieza (solo el usuario creado aqui):
--   delete from usuario_empresa where usuario_id = 9003;
--   delete from usuario where usuario_id = 9003;
--   commit;
