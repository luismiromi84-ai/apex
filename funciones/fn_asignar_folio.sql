-- =============================================================================
-- fn_asignar_folio
--
-- Devuelve el siguiente folio de la empresa para el tipo indicado y deja el
-- contador incrementado, todo dentro de la transaccion del llamador (no hace
-- COMMIT).
--
-- Por que un UPDATE y no max(folio)+1: el UPDATE bloquea la fila del contador
-- hasta el COMMIT, asi que dos sesiones que guardan a la vez se serializan y la
-- segunda recibe el numero siguiente en vez de chocar con el UNIQUE y acabar en
-- ORA-20021.
--
-- Si la fila no existe todavia (primera factura de una empresa) se inserta con
-- 1; si dos sesiones lo intentan a la vez, la segunda recibe DUP_VAL_ON_INDEX y
-- reintenta el UPDATE.
--
-- Formatos: PRESUPUESTO -> '1047', FAC -> 'F-1041', NC -> 'NC-1', ND -> 'ND-1',
-- FAC_PROV -> '45' (numeracion del proveedor), CONTROL_PROV -> '00-000045',
-- ARTICULO -> '10000001' (codigo de barras del catalogo, 8 digitos; la base
-- 10000000 vive aqui para que una empresa nueva tambien empiece en 10000001),
-- PROD -> 'PROD-00001' y SERV -> 'SERV-00001' (codigo interno del catalogo,
-- 2026-11-23: lo asigna la base y no se teclea).
--
-- Ojo al editar: el SET del UPDATE va en la misma linea que el UPDATE. El
-- runner de despliegue descarta toda linea que empiece por "set " y partiria
-- la sentencia (ORA-00971).
-- =============================================================================

create or replace function fn_asignar_folio (
    p_id_empresa in number,
    p_tipo       in varchar2
) return varchar2 is
    v_tipo varchar2(20) := upper(trim(p_tipo));
    v_num  number;
begin
    if p_id_empresa is null or v_tipo is null then
        raise_application_error(-20062,
            'No se puede asignar un folio sin empresa y tipo de documento.');
    end if;

    begin
        update folio_contador set ultimo = ultimo + 1
         where id_empresa = p_id_empresa
           and tipo       = v_tipo
        returning ultimo into v_num;
    exception
        when no_data_found then
            v_num := null;
    end;

    if v_num is null then
        begin
            insert into folio_contador (id_empresa, tipo, ultimo)
            values (p_id_empresa, v_tipo, 1)
            returning ultimo into v_num;
        exception
            when dup_val_on_index then
                update folio_contador set ultimo = ultimo + 1
                 where id_empresa = p_id_empresa
                   and tipo       = v_tipo
                returning ultimo into v_num;
        end;
    end if;

    return case v_tipo
             when 'PRESUPUESTO'  then to_char(v_num)
             when 'FAC'          then 'F-'  || v_num
             when 'NC'           then 'NC-' || v_num
             when 'ND'           then 'ND-' || v_num
             when 'FAC_PROV'     then to_char(v_num)
             when 'CONTROL_PROV' then '00-' || lpad(to_char(v_num), 6, '0')
             when 'ARTICULO'     then lpad(to_char(10000000 + v_num), 8, '0')
             when 'PROD'         then 'PROD-' || lpad(to_char(v_num), 5, '0')
             when 'SERV'         then 'SERV-' || lpad(to_char(v_num), 5, '0')
             else to_char(v_num)
           end;
end fn_asignar_folio;
/
