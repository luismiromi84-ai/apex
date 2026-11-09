create or replace function fn_nota_traible (p_id_factura in number) return boolean is
    v_existe number;
    v_lineas number;
begin
    if p_id_factura is null then
        return false;
    end if;

    select count(*) into v_existe
      from facturas f
     where f.id_factura = p_id_factura
       and f.tipo_documento in ('NC', 'ND')
       and f.id_factura_origen is not null;

    if v_existe = 0 then
        return false;
    end if;

    select count(*) into v_lineas
      from facturas_det d
     where d.id_factura = p_id_factura;

    return v_lineas = 0;
end fn_nota_traible;
/
