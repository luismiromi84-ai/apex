-- =============================================================================
-- 20261126_factura_desde_presupuesto_redondeo_verificacion.sql
--
-- Facturar un presupuesto en OTRA moneda (pkg_factura_detalle.reemplazar_desde_presupuesto con un
-- factor de conversion): el precio de la linea se guarda con 2 decimales y el subtotal sale de ese
-- precio, para que el impreso (cantidad x precio) cuadre con la linea. Antes se guardaba
-- precio x factor sin redondear (la F-6 de la empresa 6 quedo con 40,046 / 60,069).
--
--   D1 con factor 1/894,8876 (USD -> VES al reves, a proposito para que salgan muchos decimales)
--      el precio queda con 2 decimales y subtotal + descuento = round(cantidad x precio, 2)
--   D2 impuesto = round(subtotal x %, 2) y total = subtotal + impuesto
--   D3 con factor 1 (misma moneda) la linea queda igual que la del presupuesto (200 + 32 = 232)
--
-- Usa el fixture (presupuesto 900001, factura PENDIENTE 900011) dentro de un rollback.
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261108_fixture_prueba.sql
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261126_factura_desde_presupuesto_redondeo_verificacion.sql
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000);
    v_n      number;
    r        facturas_det%rowtype;

    procedure falla(p varchar2) is
    begin
        v_fallas := v_fallas + 1;
        v_lista := substr(v_lista || ' | ' || p, 1, 2800);
    end falla;
begin
    select count(*) into v_n from presupuestos where id_presupuesto = 900001;
    if v_n = 0 then
        raise_application_error(-20100, 'RESULTADO: FALLAS=1 | falta el fixture (20261108_fixture_prueba.sql)');
    end if;
    savepoint sp;

    -- D1 / D2
    pkg_factura_detalle.reemplazar_desde_presupuesto(900011, 900001, 1 / 894.8876, 1, 'DIAG');
    select count(*) into v_n from facturas_det where id_factura = 900011;
    if v_n = 0 then
        falla('D1 no se copio ninguna linea');
    end if;
    for d in (select * from facturas_det where id_factura = 900011) loop
        if d.precio_unitario <> round(d.precio_unitario, 2) then
            falla('D1 precio con mas de 2 decimales: ' || d.precio_unitario);
        end if;
        if d.subtotal_linea + nvl(d.monto_descuento, 0) <> round(d.cantidad * d.precio_unitario, 2) then
            falla('D1 la linea no cuadra: ' || d.cantidad || ' x ' || d.precio_unitario || ' <> '
                  || (d.subtotal_linea + nvl(d.monto_descuento, 0)));
        end if;
        if d.monto_impuesto <> round(d.subtotal_linea * d.porcentaje_impuesto / 100, 2)
           or d.monto_total_linea <> d.subtotal_linea + d.monto_impuesto then
            falla('D2 impuesto o total de la linea mal calculados');
        end if;
    end loop;

    -- D3 misma moneda
    pkg_factura_detalle.reemplazar_desde_presupuesto(900011, 900001, 1, 1, 'DIAG');
    select * into r from facturas_det where id_factura = 900011 and rownum = 1;
    if r.precio_unitario <> 100 or r.subtotal_linea <> 200 or r.monto_impuesto <> 32 or r.monto_total_linea <> 232 then
        falla('D3 con factor 1 la linea cambio: ' || r.precio_unitario || ' / ' || r.subtotal_linea
              || ' / ' || r.monto_impuesto || ' / ' || r.monto_total_linea);
    end if;

    rollback to sp;
    raise_application_error(-20100, 'RESULTADO: FALLAS=' || v_fallas || v_lista);
exception
    when others then
        if sqlcode = -20100 then
            raise;
        end if;
        rollback to sp;
        raise_application_error(-20100, 'RESULTADO: FALLAS=1 | error inesperado: ' || substr(sqlerrm, 1, 300));
end;
/
