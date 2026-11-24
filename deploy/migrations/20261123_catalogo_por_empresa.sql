-- =============================================================================
-- 20261123_catalogo_por_empresa.sql
--
-- El catalogo PRODUCTO_SERVICIO pasa a ser POR EMPRESA y gana el codigo de
-- barras (decision del dueño, 2026-11-23):
--   * ID_EMPRESA: cada empresa lleva sus propios articulos y servicios. Dos
--     empresas pueden tener el mismo codigo (SERV-001) sin chocar.
--   * CODIGO_BARRAS: numero interno de 8 digitos (10000001, 10000002...),
--     unico por empresa, permanente y que no se reutiliza. Lo asigna el trigger
--     TRG_PRODUCTO_SERVICIO_BARRAS con fn_asignar_folio (serie ARTICULO).
--
-- Los registros existentes se reparten asi:
--   1. todos quedan de la empresa 1 (es la que los usa hoy);
--   2. si un documento de OTRA empresa usa un articulo, se crea una copia en esa
--      empresa (mismo codigo y datos) y se repuntan sus lineas, para que nunca
--      quede una linea de factura con un articulo de otra empresa;
--   3. cada articulo recibe su codigo de barras.
--
-- Reversa: alter table producto_servicio drop column codigo_barras;
--          alter table producto_servicio drop column id_empresa;  (perderia las
--          copias por empresa: sacar copia antes)
-- Verificacion: deploy/diagnostico/20261123_catalogo_verificacion.sql
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

-- 1. Las dos columnas nuevas (idempotente: all_tab_columns, no user_tab_columns)
declare
    v_n number;
begin
    select count(*) into v_n from all_tab_columns
     where owner = 'WKSP_SYPEXWS' and table_name = 'PRODUCTO_SERVICIO'
       and column_name = 'ID_EMPRESA';
    if v_n = 0 then
        execute immediate 'alter table producto_servicio add (id_empresa number)';
    end if;

    select count(*) into v_n from all_tab_columns
     where owner = 'WKSP_SYPEXWS' and table_name = 'PRODUCTO_SERVICIO'
       and column_name = 'CODIGO_BARRAS';
    if v_n = 0 then
        execute immediate 'alter table producto_servicio add (codigo_barras varchar2(20))';
    end if;
end;
/

-- 2. Fuera el UNIQUE global de CODIGO: ahora es unico por empresa.
--    Solo si es de UNA columna (si ya existe el compuesto, no se toca).
declare
    v_c varchar2(30);
begin
    select c.constraint_name into v_c
      from all_constraints c
     where c.owner = 'WKSP_SYPEXWS' and c.table_name = 'PRODUCTO_SERVICIO'
       and c.constraint_type = 'U'
       and (select count(*) from all_cons_columns cc
             where cc.owner = c.owner and cc.constraint_name = c.constraint_name) = 1
       and exists (select 1 from all_cons_columns cc
                    where cc.owner = c.owner and cc.constraint_name = c.constraint_name
                      and cc.column_name = 'CODIGO');
    execute immediate 'alter table producto_servicio drop constraint ' || v_c;
exception
    when no_data_found then
        null;
end;
/

-- 3. Los existentes, de la empresa 1
update producto_servicio set id_empresa = 1 where id_empresa is null
/

-- ORA-12839: en esta ADB, dos DML sobre la misma tabla en la misma transaccion
-- se pelean ("cannot modify an object in parallel after modifying it"). Se
-- confirma cada paso: la migracion es idempotente.
commit
/

-- 4. Copia por empresa a la que le facturan / le compran, y repunte de lineas.
--    Idempotente: si la copia ya existe (misma empresa + mismo codigo) la reusa.
declare
    v_codigo   varchar2(20);
    v_nombre   varchar2(150);
    v_desc     varchar2(500);
    v_tipo     varchar2(20);
    v_precio   number;
    v_imp      number;
    v_estado   varchar2(10);
    v_old      number;
    v_new      number;
begin
    for r in (
        select distinct x.empresa, x.id_prod
          from (select p.id_empresa empresa, d.id_producto_servicio id_prod
                  from presupuestos_det d
                  join presupuestos p on p.id_presupuesto = d.id_presupuesto
                 where d.id_producto_servicio is not null
                 union
                select f.id_empresa, d.id_producto
                  from facturas_det d
                  join facturas f on f.id_factura = d.id_factura
                 where d.id_producto is not null
                 union
                select c.id_empresa, d.id_producto_servicio
                  from compras_det d
                  join compras c on c.id_compra = d.id_compra
                 where d.id_producto_servicio is not null) x
          join producto_servicio ps on ps.id_producto_servicio = x.id_prod
         where x.empresa <> ps.id_empresa
    ) loop
        select codigo, nombre, descripcion, tipo, precio_sugerido, impuesto_aplicable, estado
          into v_codigo, v_nombre, v_desc, v_tipo, v_precio, v_imp, v_estado
          from producto_servicio
         where id_producto_servicio = r.id_prod;
        v_old := r.id_prod;

        begin
            select id_producto_servicio into v_new
              from producto_servicio
             where id_empresa = r.empresa and codigo = v_codigo;
        exception
            when no_data_found then
                insert into producto_servicio
                       (id_empresa, codigo, nombre, descripcion, tipo,
                        precio_sugerido, impuesto_aplicable, estado)
                values (r.empresa, v_codigo, v_nombre, v_desc, v_tipo,
                        v_precio, v_imp, v_estado)
                returning id_producto_servicio into v_new;
        end;
        commit;

        update presupuestos_det d set d.id_producto_servicio = v_new
         where d.id_producto_servicio = v_old
           and exists (select 1 from presupuestos p
                        where p.id_presupuesto = d.id_presupuesto
                          and p.id_empresa = r.empresa);

        update facturas_det d set d.id_producto = v_new
         where d.id_producto = v_old
           and exists (select 1 from facturas f
                        where f.id_factura = d.id_factura
                          and f.id_empresa = r.empresa);

        update compras_det d set d.id_producto_servicio = v_new
         where d.id_producto_servicio = v_old
           and exists (select 1 from compras c
                        where c.id_compra = d.id_compra
                          and c.id_empresa = r.empresa);
    end loop;
    commit;
end;
/

-- 5. Restricciones: empresa obligatoria, y el codigo unico DENTRO de la empresa
--    (ORA-01442 en esta version si se repite el NOT NULL: se comprueba antes)
declare
    v_n number;
begin
    select count(*) into v_n from all_tab_columns
     where owner = 'WKSP_SYPEXWS' and table_name = 'PRODUCTO_SERVICIO'
       and column_name = 'ID_EMPRESA' and nullable = 'Y';
    if v_n > 0 then
        execute immediate 'alter table producto_servicio modify (id_empresa number not null)';
    end if;
end;
/

declare
    v_n number;
begin
    select count(*) into v_n from all_constraints
     where owner = 'WKSP_SYPEXWS' and table_name = 'PRODUCTO_SERVICIO'
       and constraint_name = 'FK_PRODUCTO_EMPRESA';
    if v_n = 0 then
        execute immediate 'alter table producto_servicio add constraint fk_producto_empresa
            foreign key (id_empresa) references empresas (id_empresa)';
    end if;

    select count(*) into v_n from all_constraints
     where owner = 'WKSP_SYPEXWS' and table_name = 'PRODUCTO_SERVICIO'
       and constraint_name = 'UQ_PRODUCTO_CODIGO';
    if v_n = 0 then
        execute immediate 'alter table producto_servicio add constraint uq_producto_codigo
            unique (id_empresa, codigo)';
    end if;

    select count(*) into v_n from all_indexes
     where owner = 'WKSP_SYPEXWS' and index_name = 'IX_PRODUCTO_EMPRESA';
    if v_n = 0 then
        execute immediate 'create index ix_producto_empresa on producto_servicio (id_empresa, estado)';
    end if;
end;
/

-- 6. La serie ARTICULO en FOLIO_CONTADOR
declare
    v_n number;
begin
    select count(*) into v_n from all_constraints
     where owner = 'WKSP_SYPEXWS' and constraint_name = 'CK_FOLIO_CONTADOR_TIPO';
    if v_n > 0 then
        execute immediate 'alter table folio_contador drop constraint ck_folio_contador_tipo';
    end if;
    execute immediate 'alter table folio_contador add constraint ck_folio_contador_tipo
        check (tipo in (''PRESUPUESTO'', ''FAC'', ''NC'', ''ND'', ''CONTROL'',
                        ''FAC_PROV'', ''CONTROL_PROV'', ''ARTICULO''))';
end;
/

-- 7. fn_asignar_folio: la serie ARTICULO devuelve el codigo de barras de 8
--    digitos. El contador arranca en 1 y la base (10000000) vive aqui, no en la
--    tabla, para que un articulo nuevo de una empresa nueva tambien empiece en
--    10000001.
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
             else to_char(v_num)
           end;
end fn_asignar_folio;
/

-- 8. Codigo de barras a los articulos existentes, en orden de id por empresa
declare
    v_nuevo varchar2(20);
begin
    for r in (select id_producto_servicio id, id_empresa emp
                from producto_servicio
               where codigo_barras is null
               order by id_empresa, id_producto_servicio) loop
        v_nuevo := fn_asignar_folio(r.emp, 'ARTICULO');
        update producto_servicio set codigo_barras = v_nuevo
         where id_producto_servicio = r.id;
        commit;
    end loop;
    commit;
end;
/

-- 9. Ahora que todos tienen codigo, el codigo de barras es obligatorio y
--    unico dentro de la empresa. (No antes: en un UNIQUE compuesto,
--    (empresa, NULL) SI cuenta como clave repetida.)
declare
    v_n number;
begin
    select count(*) into v_n from all_tab_columns
     where owner = 'WKSP_SYPEXWS' and table_name = 'PRODUCTO_SERVICIO'
       and column_name = 'CODIGO_BARRAS' and nullable = 'Y';
    if v_n > 0 then
        execute immediate 'alter table producto_servicio modify (codigo_barras varchar2(20) not null)';
    end if;
end;
/

declare
    v_n number;
begin
    select count(*) into v_n from all_constraints
     where owner = 'WKSP_SYPEXWS' and table_name = 'PRODUCTO_SERVICIO'
       and constraint_name = 'UQ_PRODUCTO_BARRAS';
    if v_n = 0 then
        execute immediate 'alter table producto_servicio add constraint uq_producto_barras
            unique (id_empresa, codigo_barras)';
    end if;
end;
/

-- 10. El trigger que asigna el codigo al guardar (y lo hace permanente)
create or replace trigger trg_producto_servicio_barras
before insert or update of id_empresa, codigo_barras on producto_servicio
for each row
begin
    if :new.id_empresa is null then
        raise_application_error(-20130,
            'El articulo necesita empresa: el catalogo es por empresa.');
    end if;

    if updating and :old.codigo_barras is not null
       and (:new.codigo_barras is null or :new.codigo_barras <> :old.codigo_barras) then
        raise_application_error(-20131,
            'El codigo de barras es permanente: no se puede cambiar ni reutilizar.');
    end if;

    if :new.codigo_barras is null then
        :new.codigo_barras := fn_asignar_folio(:new.id_empresa, 'ARTICULO');
    end if;
end;
/

-- 10. Compilar y validar: un ALTER sobre PRODUCTO_SERVICIO deja INVALIDOS los
--     bodies que lo tocan (pkg_compra_detalle, pkg_gastos, etc.)
declare
    v_n       number;
    v_sin_emp number;
    v_sin_cb  number;
    v_cruce   number;
begin
    dbms_utility.compile_schema('WKSP_SYPEXWS', false);

    select count(*) into v_n from all_objects
     where owner = 'WKSP_SYPEXWS' and status = 'INVALID';
    if v_n > 0 then
        raise_application_error(-20132, 'quedaron ' || v_n || ' objeto(s) INVALID');
    end if;

    select count(*) into v_sin_emp from producto_servicio where id_empresa is null;
    select count(*) into v_sin_cb  from producto_servicio where codigo_barras is null;
    if v_sin_emp > 0 or v_sin_cb > 0 then
        raise_application_error(-20133,
            'articulos sin empresa: ' || v_sin_emp || ', sin codigo de barras: ' || v_sin_cb);
    end if;

    select count(*) into v_cruce
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
    if v_cruce > 0 then
        raise_application_error(-20134,
            v_cruce || ' linea(s) de documento usan un articulo de otra empresa');
    end if;
end;
/
