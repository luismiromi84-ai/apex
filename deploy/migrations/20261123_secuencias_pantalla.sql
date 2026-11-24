-- =============================================================================
-- 20261123_secuencias_pantalla.sql
--
-- Pestana «Secuencias» de Administracion (19): ver y fijar el correlativo de
-- cada serie de la empresa (2026-11-23).
--
--   * fn_maximo_real(empresa, serie): el numero mas alto ya usado, que es el
--     tope duro de la pantalla (no se puede fijar por debajo);
--   * fn_siguiente_folio gana el caso CONTROL: la vista previa del numero de
--     control sale del rango de la providencia y NO lo consume;
--   * prc_fijar_secuencia / prc_resincronizar_secuencia: las reglas, en la base
--     (rol ADMIN, empresa del usuario, tope -20140, rango -20141, series del
--     proveedor -20142).
--
-- No toca ningun documento emitido: solo mueve el contador.
-- Idempotente: se puede volver a correr.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
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

-- funciones/fn_maximo_real.sql
-- =============================================================================
-- fn_maximo_real
--
-- El numero MAS ALTO que ya se uso en una serie de la empresa (2026-11-23).
-- Es el tope de la pantalla «Secuencias» (pestana de Administracion): el
-- contador de FOLIO_CONTADOR no se puede fijar por debajo de esto, o el sistema
-- volveria a entregar un numero ya emitido.
--
-- Por serie:
--   PRESUPUESTO  -> max(presupuestos.folio)
--   FAC / NC / ND -> maximo sufijo numerico de facturas.folio_factura con su prefijo
--   CONTROL      -> maximo control de NUESTRAS facturas con la forma de la providencia
--                   (00-000123); los valores tecleados a mano ('876', '002') no cuentan
--   ARTICULO     -> maximo codigo de barras MENOS la base 10000000 (el contador
--                   de FOLIO_CONTADOR guarda 11 para el codigo 10000011)
--   PROD / SERV  -> maximo sufijo de producto_servicio.codigo, solo con la forma
--                   nueva de 5 digitos (PROD-00001); los codigos viejos del
--                   catalogo (SERV-001, REP-002) NO son de esta serie
--   FAC_PROV / CONTROL_PROV -> NULL: ese numero lo pone el PROVEEDOR, no hay
--                   nada que comparar; el contador interno es la unica verdad.
--
-- Devuelve 0 cuando la serie no tiene nada emitido, y NULL cuando no aplica.
-- =============================================================================

create or replace function fn_maximo_real (
    p_id_empresa in number,
    p_tipo       in varchar2
) return number is
    v_tipo varchar2(20) := upper(trim(p_tipo));
    v_n    number;
begin
    if p_id_empresa is null or v_tipo is null then
        return null;
    end if;

    case v_tipo
        when 'PRESUPUESTO' then
            select nvl(max(folio), 0)
              into v_n
              from presupuestos
             where id_empresa = p_id_empresa
               and regexp_like(folio, '^[0-9]+$');

        when 'FAC' then
            select nvl(max(to_number(regexp_substr(folio_factura, '[0-9]+$'))), 0)
              into v_n
              from facturas
             where id_empresa = p_id_empresa
               and regexp_like(folio_factura, '^F-[0-9]+$');

        when 'NC' then
            select nvl(max(to_number(regexp_substr(folio_factura, '[0-9]+$'))), 0)
              into v_n
              from facturas
             where id_empresa = p_id_empresa
               and regexp_like(folio_factura, '^NC-[0-9]+$');

        when 'ND' then
            select nvl(max(to_number(regexp_substr(folio_factura, '[0-9]+$'))), 0)
              into v_n
              from facturas
             where id_empresa = p_id_empresa
               and regexp_like(folio_factura, '^ND-[0-9]+$');

        when 'CONTROL' then
            select nvl(max(to_number(regexp_substr(nro_control, '[0-9]+$'))), 0)
              into v_n
              from facturas
             where id_empresa = p_id_empresa
               and regexp_like(nro_control, '^[0-9]{2}-[0-9]{6}$');

        when 'ARTICULO' then
            -- El contador de la serie ARTICULO guarda n, y el codigo de barras
            -- es 10000000 + n: se devuelve en las unidades del contador.
            select nvl(max(to_number(codigo_barras)) - 10000000, 0)
              into v_n
              from producto_servicio
             where id_empresa = p_id_empresa
               and regexp_like(codigo_barras, '^[0-9]+$')
               and to_number(codigo_barras) > 10000000;

        when 'PROD' then
            select nvl(max(to_number(regexp_substr(codigo, '[0-9]+$'))), 0)
              into v_n
              from producto_servicio
             where id_empresa = p_id_empresa
               and regexp_like(codigo, '^PROD-[0-9]{5}$');

        when 'SERV' then
            select nvl(max(to_number(regexp_substr(codigo, '[0-9]+$'))), 0)
              into v_n
              from producto_servicio
             where id_empresa = p_id_empresa
               and regexp_like(codigo, '^SERV-[0-9]{5}$');

        else
            return null;
    end case;

    return v_n;
end fn_maximo_real;
/
/

-- procedimientos/prc_fijar_secuencia.sql
-- =============================================================================
-- prc_fijar_secuencia
--
-- Fija el correlativo de una serie de la empresa (2026-11-23), desde la pestana
-- «Secuencias» de Administracion (19). NO toca ningun documento emitido: solo
-- decide cual sera el proximo numero.
--
-- Reglas:
--   * solo un ADMIN de la empresa (o que comparta empresa con ella) puede;
--   * la serie tiene que ser una de las conocidas;
--   * el valor no puede ser negativo;
--   * no se puede fijar por debajo del maximo real de la serie (-20140), o se
--     reemitiria un folio ya usado;
--   * en CONTROL el siguiente numero tiene que caber en el rango de la
--     providencia (-20141).
--
-- El rol se comprueba contra la tabla y con el usuario que llega (no con
-- apex_application.g_user): asi la regla se puede probar por SQL. La pagina
-- vuelve a comprobar el rol con fn_tiene_rol antes de llamar.
-- =============================================================================

create or replace procedure prc_fijar_secuencia (
    p_id_empresa in number,
    p_tipo       in varchar2,
    p_ultimo     in number,
    p_usuario    in varchar2
) is
    v_tipo   varchar2(20) := upper(trim(p_tipo));
    v_max    number;
    v_es_adm number;
    v_desde  empresa_fiscal.control_desde%type;
    v_hasta  empresa_fiscal.control_hasta%type;
    v_ancho  pls_integer;
    v_pref   varchar2(30);
    v_h      number;
begin
    if p_id_empresa is null then
        raise_application_error(-20023, 'Elige una empresa antes de fijar la secuencia.');
    end if;
    if v_tipo not in ('PRESUPUESTO', 'FAC', 'NC', 'ND', 'CONTROL',
                      'FAC_PROV', 'CONTROL_PROV', 'ARTICULO', 'PROD', 'SERV') then
        raise_application_error(-20023, 'Esa serie no existe: ' || nvl(p_tipo, '(vacia)') || '.');
    end if;

    select count(*)
      into v_es_adm
      from usuario u
      join syn_roles r on r.id_rol = u.rol_id
     where upper(u.username) = upper(nvl(p_usuario, '#ninguno#'))
       and u.estado in ('ACTIVO', 'A', '1')
       and r.codigo_rol = 'ADMIN';
    if v_es_adm = 0 then
        raise_application_error(-20003, 'Solo un administrador cambia los correlativos.');
    end if;
    if not fn_usuario_empresa_valida(p_usuario, p_id_empresa) then
        raise_application_error(-20003, 'Solo puede cambiar los correlativos de su empresa.');
    end if;

    if p_ultimo is null or p_ultimo < 0 then
        raise_application_error(-20023, 'El ultimo numero no puede ser negativo.');
    end if;

    v_max := fn_maximo_real(p_id_empresa, v_tipo);
    if v_max is not null and p_ultimo < v_max then
        raise_application_error(-20140,
            'La serie ' || v_tipo || ' ya llego a ' || v_max ||
            ': no se puede fijar en ' || p_ultimo ||
            '. Deja el ultimo en ' || v_max || ' o mas.');
    end if;

    if v_tipo = 'CONTROL' then
        begin
            select control_desde, control_hasta
              into v_desde, v_hasta
              from empresa_fiscal
             where id_empresa = p_id_empresa;
        exception
            when no_data_found then
                v_desde := null;
                v_hasta := null;
        end;
        if v_desde is not null and v_hasta is not null then
            v_ancho := length(regexp_substr(v_desde, '[0-9]+$'));
            v_pref  := substr(v_desde, 1, length(v_desde) - v_ancho);
            v_h     := to_number(regexp_substr(v_hasta, '[0-9]+$'));
            if p_ultimo + 1 > v_h then
                raise_application_error(-20141,
                    'El rango de control de la empresa llega hasta ' || v_hasta ||
                    ': no caben mas numeros. Actualiza la providencia en Datos fiscales.');
            end if;
        end if;
    end if;

    merge into folio_contador f
    using (select p_id_empresa as id_empresa, v_tipo as tipo from dual) s
       on (f.id_empresa = s.id_empresa and f.tipo = s.tipo)
    when matched then
        update set f.ultimo = p_ultimo
    when not matched then
        insert (id_empresa, tipo, ultimo) values (s.id_empresa, s.tipo, p_ultimo);
end prc_fijar_secuencia;
/
/

-- procedimientos/prc_resincronizar_secuencia.sql
-- =============================================================================
-- prc_resincronizar_secuencia
--
-- Deja el contador de una serie EXACTAMENTE en el maximo real de la empresa
-- (2026-11-23). Es la migracion 20261118_resincronizar_folios.sql, ahora con
-- boton: sirve cuando las pruebas o una carga dejaron el contador por delante y
-- el proximo folio saldria con un hueco.
--
-- No toca documentos: solo mueve el contador. Las series que numera el
-- PROVEEDOR (FAC_PROV y CONTROL_PROV) no se resincronizan: su maximo no se puede
-- deducir de nuestras tablas.
-- =============================================================================

create or replace procedure prc_resincronizar_secuencia (
    p_id_empresa in number,
    p_tipo       in varchar2,
    p_usuario    in varchar2
) is
    v_tipo   varchar2(20) := upper(trim(p_tipo));
    v_max    number;
    v_es_adm number;
begin
    if p_id_empresa is null then
        raise_application_error(-20023, 'Elige una empresa antes de resincronizar.');
    end if;

    select count(*)
      into v_es_adm
      from usuario u
      join syn_roles r on r.id_rol = u.rol_id
     where upper(u.username) = upper(nvl(p_usuario, '#ninguno#'))
       and u.estado in ('ACTIVO', 'A', '1')
       and r.codigo_rol = 'ADMIN';
    if v_es_adm = 0 then
        raise_application_error(-20003, 'Solo un administrador cambia los correlativos.');
    end if;
    if not fn_usuario_empresa_valida(p_usuario, p_id_empresa) then
        raise_application_error(-20003, 'Solo puede cambiar los correlativos de su empresa.');
    end if;

    v_max := fn_maximo_real(p_id_empresa, v_tipo);
    if v_max is null then
        raise_application_error(-20142,
            'Esa serie no se puede resincronizar: el numero lo pone el proveedor.');
    end if;

    merge into folio_contador f
    using (select p_id_empresa as id_empresa, v_tipo as tipo from dual) s
       on (f.id_empresa = s.id_empresa and f.tipo = s.tipo)
    when matched then
        update set f.ultimo = v_max
    when not matched then
        insert (id_empresa, tipo, ultimo) values (s.id_empresa, s.tipo, v_max);
end prc_resincronizar_secuencia;
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

    if fn_maximo_real(1, 'PRESUPUESTO') is null then
        raise_application_error(-20100, 'RESULTADO: FALLAS=1 fn_maximo_real de PRESUPUESTO');
    end if;
    if fn_maximo_real(1, 'FAC_PROV') is not null then
        raise_application_error(-20100, 'RESULTADO: FALLAS=1 FAC_PROV deberia ser NULL');
    end if;

    raise_application_error(-20100, 'RESULTADO: FALLAS=0');
end;
/
