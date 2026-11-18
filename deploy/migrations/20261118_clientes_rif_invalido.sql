-- =============================================================================
-- 20261118_clientes_rif_invalido.sql
--
-- Un RIF/RFC mal formado no lo rechaza el SENIAT al emitir: lo rechaza el cliente y,
-- si la factura ya salio, hay que anularla. Desde el 2026-11-17 la regla es
--     Venezuela: J (juridica) / V o E (natural) + 9 digitos
--     Mexico:    3 letras + 6 digitos + 3 (moral) o 4 letras + 6 digitos + 3 (fisica)
-- y la aplica fn_rif_cliente_valido, pero los clientes cargados ANTES de esa regla
-- se quedaron con RIF invalidos en la base (p. ej. J-6454545, con 7 digitos).
--
-- No se inventa el RIF que falta: se dejan INACTIVOS para que no se les pueda
-- facturar (la lista de clientes de la pagina 9 solo ofrece los ACTIVO) y el duenio
-- los corrige y reactiva cuando tenga el numero real.
--
-- Reversa:  update clientes set estado = 'ACTIVO' where id_cliente in (...);
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

-- Informe: qué clientes siguen con un RIF que hoy no pasa la regla.
-- OJO: el tipo de persona sale de CLIENTES.TIPO_PERSONA, NO de la letra del RIF (los RFC
-- mexicanos empiezan por la letra de la razón social y se colarían como «natural»).
select c.id_cliente, c.id_empresa, c.razon_social, c.rif, c.estado
  from clientes c
 where c.estado = 'ACTIVO'
   and not fn_rif_cliente_valido(
           c.rif,
           nvl(c.cod_pais, (select e.cod_pais from empresas e where e.id_empresa = c.id_empresa)),
           nvl(c.tipo_persona, 'J'))
 order by c.id_empresa, c.id_cliente
/

-- Y se desactivan (idempotente: solo los ACTIVO con RIF invalido).
-- OJO: el runner descarta las lineas que empiezan por «set », asi que el SET va en la
-- misma linea que el UPDATE.
update clientes set estado = 'INACTIVO'
 where estado = 'ACTIVO'
   and not fn_rif_cliente_valido(
           rif,
           nvl(cod_pais, (select e.cod_pais from empresas e where e.id_empresa = clientes.id_empresa)),
           nvl(tipo_persona, 'J'))
/

commit
/

-- Validación: no queda ningún cliente ACTIVO con RIF inválido.
declare
    v_n number;
begin
    select count(*) into v_n
      from clientes c
     where c.estado = 'ACTIVO'
       and not fn_rif_cliente_valido(
               c.rif,
               nvl(c.cod_pais, (select e.cod_pais from empresas e where e.id_empresa = c.id_empresa)),
               nvl(c.tipo_persona, 'J'));
    if v_n > 0 then
        raise_application_error(-20101, 'quedan ' || v_n || ' clientes ACTIVO con RIF invalido');
    end if;
end;
/
