-- =============================================================================
-- 20261116_control_factura_rango.sql
--
-- El N° de Control de las facturas sale del rango de la providencia SENIAT que
-- la empresa tiene en EMPRESA_FISCAL (CONTROL_DESDE .. CONTROL_HASTA), como pidio
-- el dueño: al guardar una factura sin control se asigna el siguiente y no se
-- puede pasar del «hasta».
--
--   1. FOLIO_CONTADOR admite el tipo 'CONTROL' (contador atomico, como los folios).
--   2. fn_asignar_control(id_empresa): siguiente control formateado y consumido.
--   3. fn_control_en_rango(id_empresa, control): valida/normaliza el tecleado.
--   4. Siembra del contador con lo ya emitido (para no repetir numeros).
--
-- Reversa: alter table folio_contador drop constraint el check viejo y volver a
-- crearlo sin 'CONTROL'; drop function de las dos funciones; borrar la fila
-- CONTROL de folio_contador.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

alter table folio_contador drop constraint CK_FOLIO_CONTADOR_TIPO
/

alter table folio_contador add constraint CK_FOLIO_CONTADOR_TIPO
    check (tipo in ('PRESUPUESTO', 'FAC', 'NC', 'ND', 'CONTROL')) enable
/

create or replace function fn_control_en_rango (
    p_id_empresa in number,
    p_control    in varchar2
) return varchar2 is
    v_desde empresa_fiscal.control_desde%type;
    v_hasta empresa_fiscal.control_hasta%type;
    v_pref  varchar2(30);
    v_num   number;
    v_d     number;
    v_h     number;
    v_txt   varchar2(60) := trim(p_control);
begin
    begin
        select control_desde, control_hasta
          into v_desde, v_hasta
          from empresa_fiscal
         where id_empresa = p_id_empresa;
    exception
        when no_data_found then
            return v_txt;
    end;

    if v_desde is null or v_hasta is null or v_txt is null then
        return v_txt;
    end if;

    v_pref := substr(v_desde, 1, length(v_desde) - length(regexp_substr(v_desde, '[0-9]+$')));
    v_d    := to_number(regexp_substr(v_desde, '[0-9]+$'));
    v_h    := to_number(regexp_substr(v_hasta, '[0-9]+$'));

    if nvl(length(v_pref), 0) > 0
       and substr(v_txt, 1, length(v_pref)) <> v_pref then
        raise_application_error(-20063,
            'El numero de control debe empezar por ' || v_pref ||
            ' (rango de la providencia: ' || v_desde || ' a ' || v_hasta || ').');
    end if;

    if not regexp_like(substr(v_txt, nvl(length(v_pref), 0) + 1), '^[0-9]+$') then
        raise_application_error(-20063,
            'El numero de control debe tener la forma ' || v_desde || '.');
    end if;

    v_num := to_number(substr(v_txt, nvl(length(v_pref), 0) + 1));

    if v_num < v_d or v_num > v_h then
        raise_application_error(-20063,
            'El numero de control ' || v_txt || ' esta fuera del rango de la providencia ('
            || v_desde || ' a ' || v_hasta || ').');
    end if;

    return v_txt;
end;
/

create or replace function fn_asignar_control (
    p_id_empresa in number
) return varchar2 is
    v_desde empresa_fiscal.control_desde%type;
    v_hasta empresa_fiscal.control_hasta%type;
    v_pref  varchar2(30);
    v_ancho pls_integer;
    v_d     number;
    v_h     number;
    v_n     number;
begin
    begin
        select control_desde, control_hasta
          into v_desde, v_hasta
          from empresa_fiscal
         where id_empresa = p_id_empresa;
    exception
        when no_data_found then
            return null;
    end;

    if v_desde is null or v_hasta is null then
        return null;
    end if;

    v_ancho := length(regexp_substr(v_desde, '[0-9]+$'));
    v_pref  := substr(v_desde, 1, length(v_desde) - v_ancho);
    v_d     := to_number(regexp_substr(v_desde, '[0-9]+$'));
    v_h     := to_number(regexp_substr(v_hasta, '[0-9]+$'));

    begin
        insert into folio_contador (id_empresa, tipo, ultimo)
        select p_id_empresa, 'CONTROL', v_d - 1
          from dual
         where not exists (select 1 from folio_contador
                            where id_empresa = p_id_empresa and tipo = 'CONTROL');
    exception
        when dup_val_on_index then
            null;
    end;

    update folio_contador set ultimo = ultimo + 1
     where id_empresa = p_id_empresa
       and tipo = 'CONTROL'
     returning ultimo into v_n;

    if v_n > v_h then
        raise_application_error(-20062,
            'El rango de control de la empresa esta agotado: llega hasta ' || v_hasta ||
            '. Actualiza la providencia en Datos fiscales.');
    end if;

    return v_pref || lpad(to_char(v_n), v_ancho, '0');
end;
/

-- Siembra: el contador arranca por delante de lo ya emitido CON LA MISMA FORMA
-- (mismo prefijo y ancho que «Control desde»). Los valores tecleados a mano sin
-- esa forma (por ejemplo '876') no empujan el contador.
merge into folio_contador f
using (
    with rango as (
        select id_empresa, control_desde, control_hasta,
               regexp_substr(control_desde, '[0-9]+$') as cola
          from empresa_fiscal
         where control_desde is not null
           and control_hasta is not null
    ), calc as (
        select id_empresa,
               substr(control_desde, 1, length(control_desde) - length(cola)) as pref,
               length(cola) as ancho,
               to_number(cola) - 1 as base
          from rango
    )
    select c.id_empresa,
           c.base,
           (select max(to_number(substr(fc.nro_control, length(c.pref) + 1)
                                 default null on conversion error))
              from facturas fc
             where fc.id_empresa = c.id_empresa
               and fc.nro_control is not null
               and substr(fc.nro_control, 1, length(c.pref)) = c.pref
               and regexp_like(substr(fc.nro_control, length(c.pref) + 1), '^[0-9]+$')
               and length(substr(fc.nro_control, length(c.pref) + 1)) = c.ancho) as usados
      from calc c
) s
on (f.id_empresa = s.id_empresa and f.tipo = 'CONTROL')
when matched then
    update set f.ultimo = greatest(s.base, nvl(s.usados, 0))
when not matched then
    insert (id_empresa, tipo, ultimo)
    values (s.id_empresa, 'CONTROL', greatest(s.base, nvl(s.usados, 0)))
/

begin
    dbms_utility.compile_schema('WKSP_SYPEXWS', false);
end;
/
