-- =============================================================================
-- fn_factura_propio.sql
--
-- Propiedad de documento (semana 3 del cronograma de seguridad). Comprueba que
-- la factura pertenece a una empresa del usuario indicado.
--
-- Existe porque las paginas 8, 9 y 10 reciben el id de la factura desde el
-- navegador y lo pasan al package sin comprobar de quien es: sin esta guarda,
-- un usuario de la empresa 1 puede procesar, anular o tocar lineas de una
-- factura de la empresa 2.
--
-- Devuelve FALSE si el id o el usuario son nulos, si la factura no existe o si
-- su id_empresa no es una empresa del usuario. Se apoya en
-- fn_usuario_empresa_valida, que exige usuario ACTIVO/A/1.
--
-- No lanza excepcion por datos faltantes.
-- =============================================================================

create or replace function fn_factura_propio (
    p_id_factura in number,
    p_username   in varchar2
) return boolean is
    v_id_empresa number;
begin
    if p_id_factura is null or p_username is null then
        return false;
    end if;

    begin
        select f.id_empresa
          into v_id_empresa
          from facturas f
         where f.id_factura = p_id_factura;
    exception
        when no_data_found then
            return false;
    end;

    return fn_usuario_empresa_valida(p_username, v_id_empresa);
end fn_factura_propio;
/
