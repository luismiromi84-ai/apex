-- =============================================================================
-- 20261118_numeros_control_prueba.sql
--
-- Limpieza de los Números de Control de prueba que quedaron con formatos que la
-- regla de la providencia no admite (02, 876, 1, 3, 002) y que el libro muestra
-- como si fueran fiscales.
--
--   * Las FACTURAS (FAC) de una empresa con rango configurado que no tengan un
--     control con la forma del rango reciben el SIGUIENTE del contador
--     (fn_asignar_control), por fecha de emisión. Así el rango sigue correlativo.
--   * Las NOTAS (NC/ND) NO llevan número de control propio: se quedan en NULL y
--     el impreso toma el de la factura que acreditan. La app no las numera.
--
-- La validación al GUARDAR ya existe (fn_control_en_rango la aplica
-- pkg_facturacion); esto es solo el dato histórico.
--
-- Reversa: los valores viejos quedan en esta misma bitácora (abajo) por si hay
-- que volver a ponerlos.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

-- Bitácora antes de tocar nada.
select f.id_factura, f.id_empresa, f.folio_factura, f.tipo_documento, f.nro_control,
       ef.control_desde, ef.control_hasta
  from facturas f
  left join empresa_fiscal ef on ef.id_empresa = f.id_empresa
 where f.nro_control is not null
 order by f.id_empresa, f.fecha_emision, f.folio_factura
/

-- Las notas no llevan control propio.
update facturas set nro_control = null
 where tipo_documento in ('NC', 'ND')
   and nro_control is not null
/

commit
/

-- Las facturas con control que no encaja con el rango de su empresa reciben el
-- siguiente del contador. Se hace por fecha para que el rango quede correlativo.
declare
    v_pref  varchar2(30);
    v_ancho pls_integer;
begin
    for r in (select f.id_factura, f.id_empresa, f.nro_control,
                     ef.control_desde, ef.control_hasta
                from facturas f
                join empresa_fiscal ef on ef.id_empresa = f.id_empresa
               where f.tipo_documento = 'FAC'
                 and ef.control_desde is not null
                 and ef.control_hasta is not null
               order by f.id_empresa, f.fecha_emision, f.folio_factura) loop
        v_ancho := length(regexp_substr(r.control_desde, '[0-9]+$'));
        v_pref  := substr(r.control_desde, 1, length(r.control_desde) - v_ancho);
        -- Válido = mismo prefijo, misma anchura, todo dígitos
        if r.nro_control is null
           or not regexp_like(r.nro_control, '^' || v_pref || '[0-9]{' || v_ancho || '}$') then
            update facturas set nro_control = fn_asignar_control(r.id_empresa)
             where id_factura = r.id_factura;
            commit;
        end if;
    end loop;
end;
/

-- Validación: ninguna factura de una empresa con rango queda con un control que no encaje.
declare
    v_mal number := 0;
    v_pref varchar2(30);
    v_ancho pls_integer;
begin
    for r in (select f.id_factura, f.nro_control, ef.control_desde
                from facturas f
                join empresa_fiscal ef on ef.id_empresa = f.id_empresa
               where f.tipo_documento = 'FAC'
                 and ef.control_desde is not null) loop
        v_ancho := length(regexp_substr(r.control_desde, '[0-9]+$'));
        v_pref  := substr(r.control_desde, 1, length(r.control_desde) - v_ancho);
        if r.nro_control is null
           or not regexp_like(r.nro_control, '^' || v_pref || '[0-9]{' || v_ancho || '}$') then
            v_mal := v_mal + 1;
        end if;
    end loop;
    if v_mal > 0 then
        raise_application_error(-20102, 'quedan ' || v_mal || ' facturas con N de Control fuera de formato');
    end if;
end;
/

select f.id_empresa, f.folio_factura, f.tipo_documento, f.nro_control
  from facturas f
 order by f.id_empresa, f.fecha_emision, f.folio_factura
/
