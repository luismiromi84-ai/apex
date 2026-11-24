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
