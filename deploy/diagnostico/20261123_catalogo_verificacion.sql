-- =============================================================================
-- 20261123_catalogo_verificacion.sql
--
-- El catalogo de articulos y servicios, POR EMPRESA y con codigo de barras
-- (2026-11-23). Comprueba el modelo, no la pantalla:
--
--   C1  todo articulo tiene empresa y codigo de barras de 8 digitos, y no se
--       repite el codigo de barras dentro de la misma empresa
--   C2  ninguna linea de presupuesto, factura o compra usa un articulo de otra
--       empresa (es lo que la migracion tenia que dejar limpio)
--   C3  el trigger asigna el siguiente codigo al insertar (1000000N)
--   C4  el codigo es permanente: cambiarlo lanza -20131
--   C5  un articulo sin empresa no se puede guardar (-20130)
--   C6  el mismo codigo interno SI puede existir en dos empresas distintas
--   C7  el codigo de barras no se puede repetir dentro de la empresa
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261123_catalogo_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000) := '';
    v_n      number;
    v_txt    varchar2(400);

    procedure falla(p_caso varchar2, p_detalle varchar2) is
    begin
        v_fallas := v_fallas + 1;
        v_lista  := v_lista || ' | ' || p_caso || ': ' || substrb(p_detalle, 1, 170);
    end;

    procedure espera_num(p_caso varchar2, p_valor number, p_esperado number) is
    begin
        if p_valor is null or p_valor <> p_esperado then
            falla(p_caso, 'esperaba ' || p_esperado || ' y hay ' || nvl(to_char(p_valor), 'NULL'));
        end if;
    end;
begin
    ------------------------------------------------------------------ C1
    select count(*) into v_n
      from producto_servicio
     where id_empresa is null
        or codigo_barras is null
        or not regexp_like(codigo_barras, '^[0-9]{8}$');
    espera_num('C1 articulos sin empresa o sin codigo de 8 digitos', v_n, 0);

    select count(*) into v_n
      from (select id_empresa, codigo_barras
              from producto_servicio
             group by id_empresa, codigo_barras
            having count(*) > 1);
    espera_num('C1 codigo de barras repetido en una empresa', v_n, 0);

    ------------------------------------------------------------------ C2
    select count(*) into v_n
      from (select p.id_empresa empresa, d.id_producto_servicio id_prod
              from presupuestos_det d
              join presupuestos p on p.id_presupuesto = d.id_presupuesto
             where d.id_producto_servicio is not null
             union all
            select f.id_empresa, d.id_producto
              from facturas_det d
              join facturas f on f.id_factura = d.id_factura
             where d.id_producto is not null
             union all
            select c.id_empresa, d.id_producto_servicio
              from compras_det d
              join compras c on c.id_compra = d.id_compra
             where d.id_producto_servicio is not null) x
      join producto_servicio ps on ps.id_producto_servicio = x.id_prod
     where ps.id_empresa <> x.empresa;
    espera_num('C2 lineas con articulo de otra empresa', v_n, 0);

    ------------------------------------------------------------------ C3 / C4 / C5 / C6 / C7
    -- Todo dentro de un savepoint: no queda ningun articulo de prueba.
    savepoint sp_catalogo;
    declare
        v_comun   number;
        v_ultimo  number;
        v_new     number;
        v_cb      varchar2(20);
        v_cb2     varchar2(20);
        v_otro    number;
    begin
        select ultimo into v_ultimo from folio_contador
         where id_empresa = 1 and tipo = 'ARTICULO';

        insert into producto_servicio (id_empresa, codigo, nombre, tipo, precio_sugerido,
                                       impuesto_aplicable, estado)
        values (1, 'TEST-C3', 'Articulo de verificacion', 'PRODUCTO', 10, 16, 'ACTIVO')
        returning id_producto_servicio, codigo_barras into v_new, v_cb;

        -- C3: el siguiente de la serie
        if v_cb <> lpad(to_char(10000000 + v_ultimo + 1), 8, '0') then
            falla('C3 codigo asignado', 'esperaba ' || lpad(to_char(10000000 + v_ultimo + 1), 8, '0')
                                       || ' y hay ' || v_cb);
        end if;

        begin
            update producto_servicio set codigo_barras = '99999999'
             where id_producto_servicio = v_new;
            falla('C4 codigo permanente', 'dejo cambiarlo');
        exception
            when others then
                if sqlcode <> -20131 then
                    falla('C4 codigo permanente', 'codigo ' || sqlcode || ': ' || sqlerrm);
                end if;
        end;

        begin
            insert into producto_servicio (id_empresa, codigo, nombre, tipo, precio_sugerido,
                                           impuesto_aplicable, estado)
            values (null, 'TEST-C5', 'Sin empresa', 'PRODUCTO', 1, 16, 'ACTIVO');
            falla('C5 empresa obligatoria', 'dejo insertar sin empresa');
        exception
            when others then
                if sqlcode <> -20130 then
                    falla('C5 empresa obligatoria', 'codigo ' || sqlcode || ': ' || sqlerrm);
                end if;
        end;

        -- C6: el mismo codigo interno en otra empresa si vale
        begin
            insert into producto_servicio (id_empresa, codigo, nombre, tipo, precio_sugerido,
                                           impuesto_aplicable, estado)
            values (2, 'TEST-C3', 'El mismo codigo en otra empresa', 'PRODUCTO', 10, 16, 'ACTIVO')
            returning id_producto_servicio into v_otro;
        exception
            when others then
                falla('C6 codigo por empresa', 'no dejo repetir el codigo en otra empresa: ' || sqlerrm);
        end;

        -- C7: el codigo de barras no se repite dentro de la empresa
        begin
            select codigo_barras into v_cb2
              from producto_servicio
             where id_empresa = 2 and id_producto_servicio <> v_otro
               and rownum = 1;
            insert into producto_servicio (id_empresa, codigo, nombre, tipo, precio_sugerido,
                                           impuesto_aplicable, estado, codigo_barras)
            values (2, 'TEST-C7', 'Barras repetidas', 'PRODUCTO', 1, 16, 'ACTIVO', v_cb2);
            falla('C7 barras unicas por empresa', 'dejo repetir el codigo de barras ' || v_cb2);
        exception
            when dup_val_on_index then
                null;
            when others then
                falla('C7 barras unicas por empresa', 'codigo ' || sqlcode || ': ' || sqlerrm);
        end;

        rollback to sp_catalogo;
    end;

    ------------------------------------------------------------- resultado
    if v_fallas = 0 then
        raise_application_error(-20100, 'RESULTADO: FALLAS=0');
    else
        raise_application_error(-20101, 'RESULTADO: FALLAS=' || v_fallas || v_lista);
    end if;
exception
    when others then
        if sqlcode in (-20100, -20101) then
            raise;
        end if;
        raise_application_error(-20102, 'RESULTADO: FALLAS=1 excepcion: ' || sqlerrm);
end;
/
