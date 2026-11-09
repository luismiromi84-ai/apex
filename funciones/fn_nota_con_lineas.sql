create or replace function fn_nota_con_lineas (p_id_factura in number) return boolean is
    -- Para la pagina 9: una vez la nota tiene lineas no se puede cambiar la
    -- factura que acredita, la moneda ni la tasa (las lineas son de esa factura).
    v_lineas number;
begin
    if p_id_factura is null then
        return false;
    end if;

    select count(*) into v_lineas
      from facturas_det d
     where d.id_factura = p_id_factura;

    return v_lineas > 0;
end fn_nota_con_lineas;
/
