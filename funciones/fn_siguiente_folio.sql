-- =============================================================================
-- fn_siguiente_folio
--
-- El numero que se le muestra al usuario ANTES de guardar. Es solo una vista
-- previa: NO incrementa el contador y no bloquea nada, asi que si otro usuario
-- guarda primero el folio real sera distinto. El que manda es el que devuelve
-- fn_asignar_folio() al insertar.
-- =============================================================================

create or replace function fn_siguiente_folio (
    p_id_empresa in number,
    p_tipo       in varchar2
) return varchar2 is
    v_tipo varchar2(20) := upper(trim(p_tipo));
    v_num  number;
begin
    select nvl(max(ultimo), 0) + 1
      into v_num
      from folio_contador
     where id_empresa = p_id_empresa
       and tipo       = v_tipo;

    return case v_tipo
             when 'PRESUPUESTO' then to_char(v_num)
             when 'FAC'         then 'F-'  || v_num
             when 'NC'          then 'NC-' || v_num
             when 'ND'          then 'ND-' || v_num
             else to_char(v_num)
           end;
end fn_siguiente_folio;
/
