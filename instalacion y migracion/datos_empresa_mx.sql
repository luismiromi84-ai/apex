-- =============================================================================
-- datos_empresa_mx.sql
--
-- Segunda empresa (México) con clientes y un usuario demo ligado a ella.
-- Sirve para comprobar que la cascada empresa -> cliente filtra de verdad:
-- con `mx.demo` la LOV de empresa debe traer solo la empresa 2 y la de
-- clientes solo sus 3 clientes.
--
-- Idempotente: no duplica si ya existen (busca por nombre/usuario).
-- Ids fuera de los rangos que purgan datos_demo.sql (1000-1999) y validar_carga.sql (9000+).
-- =============================================================================

set define off
alter session set current_schema = WKSP_SYPEXWS;

-- Empresa 2 (México)
merge into empresas t
using (select 2 id_empresa from dual) s
   on (t.id_empresa = s.id_empresa)
when not matched then
    insert (id_empresa, nombre_empresa, cod_pais, rfc, tipo_ident_fiscal, estado, fecha_creacion)
    values (2, 'Empresa México', 'MX', 'MXE010101AAA', 'RFC', 'ACTIVO', sysdate);

-- Tres clientes de la empresa 2 (ids 201-203)
merge into clientes t
using (
    select 201 id_cliente, 'MXE850101AB1' rif, 'Distribuidora Azteca S.A. de C.V.' razon_social,
           'contacto@azteca.mx' email, '+52 55 5555 0101' telefono,
           'Av. Reforma 100, Ciudad de México' direccion from dual union all
    select 202, 'MXE900202CD3', 'Comercializadora Maya S.A.', 'ventas@maya.mx',
           '+52 998 555 0202', 'Blvd. Kukulcán 20, Cancún' from dual union all
    select 203, 'MXE920303EF5', 'Servicios del Norte S. de R.L.', 'info@delnorte.mx',
           '+52 81 5555 0303', 'Av. Constitución 300, Monterrey' from dual
) s
   on (t.id_cliente = s.id_cliente)
when not matched then
    insert (id_cliente, id_empresa, rif, razon_social, email, telefono, direccion, estado, fecha_creacion)
    values (s.id_cliente, 2, s.rif, s.razon_social, s.email, s.telefono, s.direccion, 'ACTIVO', sysdate);

-- Usuario demo ligado a la empresa 2
merge into usuario t
using (select 9010 usuario_id, 'mx.demo' username from dual) s
   on (t.usuario_id = s.usuario_id or upper(t.username) = upper(s.username))
when not matched then
    insert (usuario_id, username, email, password_hash, estado, fecha_creacion, id_empresa, rol_id)
    values (9010, 'mx.demo', 'mx.demo@sypex.local', sypex_hash_password('Demo#2026'), 'ACTIVO',
            sysdate, 2, (select id_rol from syn_roles where codigo_rol = 'ADMIN'));

commit;

select id_empresa, nombre_empresa, cod_pais, estado from empresas order by id_empresa;

select id_empresa, count(*) clientes from clientes group by id_empresa order by id_empresa;

select usuario_id, username, id_empresa from usuario where usuario_id = 9010;

-- Limpieza:
--   delete from usuario  where usuario_id = 9010;
--   delete from clientes where id_cliente between 201 and 203;
--   delete from empresas where id_empresa = 2;
--   commit;
