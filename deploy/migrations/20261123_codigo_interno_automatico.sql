-- =============================================================================
-- 20261123_codigo_interno_automatico.sql
--
-- El codigo interno del catalogo deja de teclearse (2026-11-23):
--   * dos series nuevas en FOLIO_CONTADOR: PROD -> 'PROD-00001' y
--     SERV -> 'SERV-00001', por empresa y con contador atomico;
--   * fn_asignar_folio / fn_siguiente_folio las formatean (y la vista previa de
--     ARTICULO pasa a devolver los 8 digitos, que antes devolvia el numero);
--   * el trigger TRG_PRODUCTO_SERVICIO_CODIGO asigna el codigo al insertar
--     cuando llega nulo y lo protege: no se cambia.
--
-- Los articulos que ya existen conservan su codigo (SERV-001, REP-002...).
-- Idempotente: se puede volver a correr.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

begin
    execute immediate 'alter table folio_contador drop constraint ck_folio_contador_tipo';
exception
    when others then
        if sqlcode <> -2443 then raise; end if;   -- ORA-02443: no existe
end;
/

alter table folio_contador add constraint ck_folio_contador_tipo
    check (tipo in ('PRESUPUESTO', 'FAC', 'NC', 'ND', 'CONTROL',
                    'FAC_PROV', 'CONTROL_PROV', 'ARTICULO',
                    'PROD', 'SERV')) enable
/

-- funciones/fn_asignar_folio.sql
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
/

-- funciones/fn_siguiente_folio.sql
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
             when 'ARTICULO'     then lpad(to_char(10000000 + v_num), 8, '0')
             when 'PROD'         then 'PROD-' || lpad(to_char(v_num), 5, '0')
             when 'SERV'         then 'SERV-' || lpad(to_char(v_num), 5, '0')
             else to_char(v_num)
           end;
end fn_siguiente_folio;
/
/

-- trigger/trg_producto_servicio_codigo.sql
-- =============================================================================
-- TRG_PRODUCTO_SERVICIO_CODIGO
--
-- El codigo interno del catalogo (2026-11-23):
--   * lo asigna el sistema al insertar, con la serie PROD o SERV de
--     FOLIO_CONTADOR segun el tipo (PROD-00001, SERV-00001...), asi que un
--     articulo no puede quedar sin codigo ni depende de que el usuario lleve
--     la numeracion a mano;
--   * es permanente: no se puede cambiar (las etiquetas ya impresas y los
--     documentos que lo citan dejarian de cuadrar);
--   * el contador es atomico (fn_asignar_folio hace UPDATE ... RETURNING), asi
--     que dos altas a la vez reciben numeros distintos.
--
-- Los articulos que ya existian conservan su codigo (SERV-001, REP-002...): el
-- trigger solo actua cuando el codigo llega nulo.
-- =============================================================================

create or replace trigger trg_producto_servicio_codigo
before insert or update of codigo on producto_servicio
for each row
begin
    if updating and :old.codigo is not null
       and (:new.codigo is null or :new.codigo <> :old.codigo) then
        raise_application_error(-20132,
            'El codigo interno es permanente: no se puede cambiar.');
    end if;

    if inserting and :new.codigo is null then
        :new.codigo := fn_asignar_folio(:new.id_empresa,
            case when upper(nvl(:new.tipo, 'SERVICIO')) = 'PRODUCTO'
                 then 'PROD' else 'SERV' end);
    end if;
end;
/
/

begin
    dbms_utility.compile_schema('WKSP_SYPEXWS', false);
end;
/

declare
    v_n number;
begin
    select count(*) into v_n
      from all_objects
     where owner = 'WKSP_SYPEXWS' and status <> 'VALID';
    if v_n > 0 then
        raise_application_error(-20100, 'RESULTADO: FALLAS=1 objetos invalidos: ' || v_n);
    end if;

    select count(*) into v_n
      from all_constraints
     where owner = 'WKSP_SYPEXWS'
       and constraint_name = 'CK_FOLIO_CONTADOR_TIPO'
       and search_condition_vc like '%PROD%';
    if v_n = 0 then
        raise_application_error(-20100, 'RESULTADO: FALLAS=1 el check no admite PROD');
    end if;

    if fn_siguiente_folio(1, 'PROD') not like 'PROD-%' then
        raise_application_error(-20100, 'RESULTADO: FALLAS=1 formato PROD');
    end if;
    if fn_siguiente_folio(1, 'ARTICULO') is null
       or length(fn_siguiente_folio(1, 'ARTICULO')) <> 8 then
        raise_application_error(-20100, 'RESULTADO: FALLAS=1 vista previa de ARTICULO');
    end if;

    raise_application_error(-20100, 'RESULTADO: FALLAS=0');
end;
/
