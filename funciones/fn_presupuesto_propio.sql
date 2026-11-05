-- =============================================================================
-- fn_presupuesto_propio.sql
--
-- Propiedad de documento (semana 3 del cronograma de seguridad). Comprueba que
-- el presupuesto pertenece a una empresa del usuario indicado.
--
-- Existe porque las paginas 5 y 6 reciben el id del presupuesto desde el
-- navegador y lo pasan al package sin comprobar de quien es: sin esta guarda,
-- un usuario de la empresa 1 puede procesar o tocar lineas de un presupuesto
-- de la empresa 2.
--
-- Devuelve FALSE si el id o el usuario son nulos, si el presupuesto no existe
-- o si su id_empresa no es una empresa del usuario. Se apoya en
-- fn_usuario_empresa_valida, que exige usuario ACTIVO/A/1.
--
-- No lanza excepcion por datos faltantes.
-- =============================================================================

create or replace function fn_presupuesto_propio (
    p_id_presupuesto in number,
    p_username       in varchar2
) return boolean is
    v_id_empresa number;
begin
    if p_id_presupuesto is null or p_username is null then
        return false;
    end if;

    begin
        select p.id_empresa
          into v_id_empresa
          from presupuestos p
         where p.id_presupuesto = p_id_presupuesto;
    exception
        when no_data_found then
            return false;
    end;

    return fn_usuario_empresa_valida(p_username, v_id_empresa);
end fn_presupuesto_propio;
/
