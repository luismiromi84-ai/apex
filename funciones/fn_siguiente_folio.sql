-- =============================================================================
-- fn_siguiente_folio
--
-- El numero que se le muestra al usuario ANTES de guardar. Es solo una vista
-- previa: NO incrementa el contador y no bloquea nada, asi que si otro usuario
-- guarda primero el folio real sera distinto. El que manda es el que devuelve
-- fn_asignar_folio() al insertar.
--
-- Tambien sirve para las series del PROVEEDOR en las compras (2026-11-18):
-- FAC_PROV -> '45' y CONTROL_PROV -> '00-000045'. Esas series son internas del
-- sistema para no teclearlas a mano; el papel del proveedor sigue mandando.
--
-- Y para las series del catalogo (2026-11-23): ARTICULO -> '10000009' (codigo
-- de barras) y PROD / SERV -> 'PROD-00001' / 'SERV-00001' (codigo interno).
--
-- 2026-11-24: KARDEX -> 'K-000001' (movimientos de inventario) y RETENCION ->
-- 'AAAAMM00000001' (comprobante de retencion de IVA e ISLR). La retencion es la
-- unica serie que NO vive en FOLIO_CONTADOR: su contador es RETENCION_CONTADOR
-- y se reinicia cada periodo, asi que la vista previa se calcula ahi.
-- =============================================================================

create or replace function fn_siguiente_folio (
    p_id_empresa in number,
    p_tipo       in varchar2
) return varchar2 is
    v_tipo  varchar2(20) := upper(trim(p_tipo));
    v_num   number;
    v_desde empresa_fiscal.control_desde%type;
    v_ancho pls_integer;
    v_pref  varchar2(30);
begin
    select nvl(max(ultimo), 0) + 1
      into v_num
      from folio_contador
     where id_empresa = p_id_empresa
       and tipo       = v_tipo;

    -- CONTROL (2026-11-23): la vista previa del numero de control sale del rango
    -- de la providencia, igual que fn_asignar_control, pero SIN consumirlo.
    if v_tipo = 'CONTROL' then
        begin
            select control_desde
              into v_desde
              from empresa_fiscal
             where id_empresa = p_id_empresa;
        exception
            when no_data_found then
                return null;
        end;
        if v_desde is null then
            return null;
        end if;
        v_ancho := length(regexp_substr(v_desde, '[0-9]+$'));
        v_pref  := substr(v_desde, 1, length(v_desde) - v_ancho);
        return v_pref || lpad(to_char(v_num), v_ancho, '0');
    end if;

    -- RETENCION (2026-11-24): AAAAMM + 8 digitos, con su propio contador por
    -- periodo. Es solo vista previa; el numero real lo toma pkg_retenciones al
    -- emitir el comprobante.
    if v_tipo = 'RETENCION' then
        select nvl(max(ultimo), 0) + 1
          into v_num
          from retencion_contador
         where id_empresa = p_id_empresa
           and periodo     = to_char(sysdate, 'YYYYMM');
        return to_char(sysdate, 'YYYYMM') || lpad(to_char(v_num), 8, '0');
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
             when 'KARDEX'       then 'K-' || lpad(to_char(v_num), 6, '0')
             else to_char(v_num)
           end;
end fn_siguiente_folio;
/
