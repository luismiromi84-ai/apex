-- =============================================================================
-- 20261118_folio_proveedor.sql
--
-- El N° de factura y el N° de control de una COMPRA los emite el proveedor, pero
-- el dueño pidio que el sistema los lleve en serie y los proponga solos
-- (2026-11-18). No hace falta otra tabla: se agregan dos series a FOLIO_CONTADOR.
--
--   FAC_PROV     -> '45'        (numeracion del proveedor)
--   CONTROL_PROV -> '00-000045' (control del proveedor)
--
-- Se consume la serie al dar de alta la compra SOLO si se dejo la propuesta; si
-- el usuario escribe otro numero (el que trae el papel), se respeta y la serie no
-- se mueve.
--
-- Reversa: volver al CHECK anterior (sin las dos series) y borrar sus filas.
-- Verificacion: deploy/diagnostico/20261118_folio_proveedor_verificacion.sql
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

-- 1) El CHECK tiene que admitir las dos series nuevas
declare
    v_n number;
begin
    select count(*) into v_n from all_constraints
     where owner = 'WKSP_SYPEXWS' and table_name = 'FOLIO_CONTADOR'
       and constraint_name = 'CK_FOLIO_CONTADOR_TIPO';
    if v_n = 1 then
        execute immediate 'alter table folio_contador drop constraint ck_folio_contador_tipo';
    end if;
end;
/

alter table folio_contador add constraint ck_folio_contador_tipo
    check (tipo in ('PRESUPUESTO', 'FAC', 'NC', 'ND', 'CONTROL', 'FAC_PROV', 'CONTROL_PROV')) enable
/

-- 2) Una fila por empresa para cada serie nueva (empieza en 0: el primero es 1)
merge into folio_contador f
using (select id_empresa from empresas) d
on (f.id_empresa = d.id_empresa and f.tipo = 'FAC_PROV')
when not matched then insert (id_empresa, tipo, ultimo)
     values (d.id_empresa, 'FAC_PROV', 0)
/

merge into folio_contador f
using (select id_empresa from empresas) d
on (f.id_empresa = d.id_empresa and f.tipo = 'CONTROL_PROV')
when not matched then insert (id_empresa, tipo, ultimo)
     values (d.id_empresa, 'CONTROL_PROV', 0)
/

-- 3) Las funciones de folio conocen las dos series (formato '45' y '00-000045')
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
-- FAC_PROV -> '45' (numeracion del proveedor), CONTROL_PROV -> '00-000045'.
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
             else to_char(v_num)
           end;
end fn_asignar_folio;
/
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
             when 'PRESUPUESTO'  then to_char(v_num)
             when 'FAC'          then 'F-'  || v_num
             when 'NC'           then 'NC-' || v_num
             when 'ND'           then 'ND-' || v_num
             when 'FAC_PROV'     then to_char(v_num)
             when 'CONTROL_PROV' then '00-' || lpad(to_char(v_num), 6, '0')
             else to_char(v_num)
           end;
end fn_siguiente_folio;
/

-- 4) El package que CONSUME las series al dar de alta la compra
-- (solo cambia el body; la spec no cambia)
-- =============================================================================
-- package_bodies/pkg_compras.sql
--
-- OJO con el runner: descarta las lineas que empiezan por "set ", asi que los
-- UPDATE llevan el SET en la misma linea.
-- =============================================================================

create or replace package body pkg_compras as

    procedure prc_guardar_compra(
        p_id_compra            in out number,
        p_id_empresa           in number,
        p_id_proveedor         in number,
        p_tipo_documento       in varchar2 default 'FAC',
        p_folio_factura        in varchar2,
        p_nro_control          in varchar2 default null,
        p_fecha_emision        in date,
        p_cod_moneda           in varchar2 default 'VES',
        p_tipo_cambio          in number default 1,
        p_porcentaje_retencion in number default null,
        p_id_compra_origen     in number default null,
        p_observaciones        in varchar2 default null,
        p_usuario              in varchar2) is
        v_estado    varchar2(20);
        v_prov_emp  number;
        v_tasa      number;
        v_pct       number;
        v_fecha     date;
        v_folio     varchar2(50);
        v_control   varchar2(50);
    begin
        if p_id_proveedor is null then
            raise_application_error(-20087, 'La compra necesita un proveedor.');
        end if;

        if not fn_usuario_empresa_valida(p_usuario, p_id_empresa) then
            raise_application_error(-20003, 'No tiene permisos sobre esta empresa.');
        end if;

        begin
            select id_empresa into v_prov_emp
              from proveedores where id_proveedor = p_id_proveedor;
        exception
            when no_data_found then
                raise_application_error(-20084, 'El proveedor no existe.');
        end;
        if v_prov_emp <> p_id_empresa then
            raise_application_error(-20084, 'El proveedor no es de la empresa del documento.');
        end if;

        if p_porcentaje_retencion is not null
           and (p_porcentaje_retencion < 0 or p_porcentaje_retencion > 100) then
            raise_application_error(-20082, 'El porcentaje de retencion debe estar entre 0 y 100.');
        end if;

        v_fecha := nvl(p_fecha_emision, sysdate);

        if upper(nvl(p_cod_moneda, 'VES')) in ('VES', 'BS') then
            v_tasa := 1;
        else
            v_tasa := fn_validar_tasa_documento(p_cod_moneda, v_fecha, p_tipo_cambio);
        end if;

        if p_porcentaje_retencion is null then
            v_pct := pkg_retenciones.fn_porcentaje(p_id_proveedor);
        else
            v_pct := p_porcentaje_retencion;
        end if;

        -- Numeracion del PROVEEDOR (2026-11-18): la serie vive en FOLIO_CONTADOR
        -- (FAC_PROV y CONTROL_PROV) para que la pantalla la proponga sola. Al dar de
        -- alta se CONSUME solo si se dejo la propuesta (o vacio); si el usuario
        -- escribio otro numero, se respeta el suyo y la serie no se mueve.
        v_folio := trim(p_folio_factura);
        v_control := trim(p_nro_control);

        if p_id_compra is null then
            if v_folio is null
               or upper(v_folio) = upper(fn_siguiente_folio(p_id_empresa, 'FAC_PROV')) then
                v_folio := fn_asignar_folio(p_id_empresa, 'FAC_PROV');
            end if;
            if v_control is null
               or upper(v_control) = upper(fn_siguiente_folio(p_id_empresa, 'CONTROL_PROV')) then
                v_control := fn_asignar_folio(p_id_empresa, 'CONTROL_PROV');
            end if;
        end if;

        if v_folio is null then
            raise_application_error(-20087,
                'El numero de factura del proveedor es obligatorio.');
        end if;
        if v_control is not null and length(v_control) < 3 then
            raise_application_error(-20089,
                'El numero de control del proveedor no puede ser un numero suelto de 1 o 2 digitos. '
                || 'Escribelo como aparece en la factura (por ejemplo 00-000045).');
        end if;

        if p_id_compra is null then
            begin
                insert into compras (id_empresa, id_proveedor, tipo_documento, folio_factura,
                                     nro_control, fecha_emision, cod_moneda, tipo_cambio,
                                     porcentaje_retencion, estado, observaciones,
                                     id_compra_origen, creado_por)
                values (p_id_empresa, p_id_proveedor, nvl(p_tipo_documento, 'FAC'),
                        v_folio, v_control, v_fecha, nvl(p_cod_moneda, 'VES'),
                        v_tasa, v_pct, 'BORRADOR', p_observaciones,
                        p_id_compra_origen, p_usuario)
                returning id_compra into p_id_compra;
            exception
                when dup_val_on_index then
                    raise_application_error(-20080,
                        'Ya existe la factura ' || v_folio || ' de este proveedor.');
            end;
        else
            begin
                select estado into v_estado from compras where id_compra = p_id_compra;
            exception
                when no_data_found then
                    raise_application_error(-20085, 'La compra ' || p_id_compra || ' no existe.');
            end;
            if v_estado <> 'BORRADOR' then
                raise_application_error(-20083,
                    'La compra esta ' || v_estado || ': no se puede modificar.');
            end if;
            begin
                update compras set id_proveedor = p_id_proveedor,
                       tipo_documento = nvl(p_tipo_documento, 'FAC'),
                       folio_factura = v_folio, nro_control = v_control,
                       fecha_emision = v_fecha, cod_moneda = nvl(p_cod_moneda, 'VES'),
                       tipo_cambio = v_tasa, porcentaje_retencion = v_pct,
                       observaciones = p_observaciones, id_compra_origen = p_id_compra_origen,
                       modificado_por = p_usuario, fecha_modificacion = systimestamp
                 where id_compra = p_id_compra;
            exception
                when dup_val_on_index then
                    raise_application_error(-20080,
                        'Ya existe la factura ' || v_folio || ' de este proveedor.');
            end;
        end if;
    end prc_guardar_compra;

    procedure prc_registrar_compra(p_id_compra in number, p_usuario in varchar2) is
        v_estado varchar2(20);
        v_lineas number;
        v_idret  number;
    begin
        select estado into v_estado
          from compras where id_compra = p_id_compra for update;

        if v_estado <> 'BORRADOR' then
            raise_application_error(-20083,
                'La compra esta ' || v_estado || ': no se puede registrar.');
        end if;

        select count(*) into v_lineas from compras_det where id_compra = p_id_compra;
        if v_lineas = 0 then
            raise_application_error(-20085,
                'La compra no tiene lineas: agrega al menos una antes de registrarla.');
        end if;

        update compras set estado = 'REGISTRADA', modificado_por = p_usuario,
               fecha_modificacion = systimestamp
         where id_compra = p_id_compra;

        pkg_retenciones.prc_emitir(p_id_compra, v_idret, p_usuario);
    exception
        when no_data_found then
            raise_application_error(-20085, 'La compra ' || p_id_compra || ' no existe.');
    end prc_registrar_compra;

    procedure prc_anular_compra(p_id_compra in number, p_usuario in varchar2) is
        v_estado varchar2(20);
    begin
        select estado into v_estado
          from compras where id_compra = p_id_compra for update;

        if v_estado = 'ANULADA' then
            return;
        end if;

        update compras set estado = 'ANULADA', modificado_por = p_usuario,
               fecha_modificacion = systimestamp
         where id_compra = p_id_compra;

        pkg_retenciones.prc_anular(p_id_compra, p_usuario);
    exception
        when no_data_found then
            raise_application_error(-20085, 'La compra ' || p_id_compra || ' no existe.');
    end prc_anular_compra;

end pkg_compras;
/


-- 5) Validacion: funciones y package VALID y la propuesta con la forma correcta
begin
    dbms_utility.compile_schema('WKSP_SYPEXWS', false);
end;
/

declare
    v_n   number;
    v_sig varchar2(30);
begin
    select count(*) into v_n from all_objects
     where owner = 'WKSP_SYPEXWS'
       and object_name in ('FN_ASIGNAR_FOLIO', 'FN_SIGUIENTE_FOLIO', 'PKG_COMPRAS')
       and status = 'VALID';
    if v_n < 4 then
        raise_application_error(-20112, 'quedaron funciones/packages invalidos (' || v_n || '/4)');
    end if;

    v_sig := fn_siguiente_folio(1, 'CONTROL_PROV');
    if not regexp_like(v_sig, '^[0-9]{2}-[0-9]{6}$') then
        raise_application_error(-20112, 'el siguiente control del proveedor no tiene la forma: ' || v_sig);
    end if;
end;
/
