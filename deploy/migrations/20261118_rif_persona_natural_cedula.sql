-- =============================================================================
-- 20261118_rif_persona_natural_cedula.sql
--
-- El RIF de una persona natural venezolana no tiene 9 digitos fijos (2026-11-19).
--
-- Sintoma reportado: en Proveedores (pagina 23) el RIF «V-4666778-9» se
-- rechazaba con «El RIF/RFC no tiene la forma esperada para VE». La causa no era
-- la pantalla: el 2026-11-17 se exigieron EXACTAMENTE 9 digitos despues de la
-- letra para todos los tipos, para que no colara «J-6454545» (7 digitos). Eso es
-- correcto en una juridica (8 de la empresa + verificador), pero el RIF de una
-- persona natural es la CEDULA (6 a 8 digitos) mas el verificador, asi que
-- despues de la V o la E puede haber 7, 8 o 9 digitos. Ya el 2026-11-15 se habia
-- reportado el mismo caso con «V-9877766».
--
-- Regla que queda:
--   * VE juridica (J)  -> J + 9 digitos            (J-12345678-9)
--   * VE natural (V,E) -> V/E + 7 a 9 digitos      (V-4666778-9, V-12345678-9)
--   * VE emisor: J, G y C siguen con 9; V y E de 7 a 9.
--   * Mexico y «otro pais», sin cambios.
--
-- No cambia ninguna pantalla ni proceso: las paginas 21 (Cliente), 23 (Proveedor)
-- y 19 (pestana Empresa) ya llaman a estas funciones.
--
-- Reversa: volver a `{9}` en la rama natural de las dos funciones.
--
-- Verificacion: deploy/diagnostico/20261111_clientes_verificacion.sql (C21-C24)
--               deploy/diagnostico/20261117_rif_empresa_verificacion.sql (F7)
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

-- =============================================================================
-- fn_rif_cliente_valido.sql
--
-- ¿El RIF/RFC de un cliente tiene la forma que le toca? (2026-11-11)
--
-- Decisiones del dueño (2026-11-11, tras probar el alta con V76554445677):
--   * Venezuela: manda la LETRA y la CANTIDAD DE DIGITOS de ese tipo. Juridica ->
--     J y **9 digitos** (8 de la empresa + verificador; rechaza «J-6454545»).
--     Natural -> V (venezolano) o E (extranjero) y **7 a 9 digitos**: el RIF de
--     una persona natural es la cedula (6 a 8 digitos) mas el verificador, asi
--     que 9 fijos rechazaban cedulas de 7 digitos (V-4666778-9, 2026-11-19).
--     Los guiones y espacios dan igual: 'V-12345678-9' y 'V123456789' valen igual.
--   * Mexico: RFC de 12 (moral) o 13 (fisica), alfanumerico.
--   * El digito verificador NO se comprueba.
--   * Cualquier otro pais: no vacio y de 5 a 30 caracteres.
--
-- Devuelve boolean para usarla tambien en una validacion PL/SQL de APEX.
-- =============================================================================

create or replace function fn_rif_cliente_valido (
    p_rif          in varchar2,
    p_cod_pais     in varchar2,
    p_tipo_persona in varchar2
) return boolean is
    v_rif   varchar2(40);
    v_letra varchar2(1);
    v_resto varchar2(30);
    v_pais  varchar2(2) := upper(trim(p_cod_pais));
    v_tipo  varchar2(1) := upper(trim(p_tipo_persona));
begin
    -- Los separadores no cuentan: se quitan antes de mirar la forma.
    v_rif := replace(replace(upper(trim(p_rif)), '-', ''), ' ', '');

    if v_rif is null or v_tipo is null then
        return false;
    end if;

    if v_pais = 'VE' then
        v_letra := substr(v_rif, 1, 1);
        v_resto := substr(v_rif, 2);
        if v_tipo = 'J' then
            return v_letra = 'J' and regexp_like(v_resto, '^[0-9]{9}$');
        elsif v_tipo = 'N' then
            return v_letra in ('V', 'E') and regexp_like(v_resto, '^[0-9]{7,9}$');
        end if;
        return false;
    end if;

    if v_pais = 'MX' then
        if v_tipo = 'J' then
            return regexp_like(v_rif, '^[A-Z&]{3}[0-9]{6}[A-Z0-9]{3}$');
        elsif v_tipo = 'N' then
            return regexp_like(v_rif, '^[A-Z&]{4}[0-9]{6}[A-Z0-9]{3}$');
        end if;
        return false;
    end if;

    return length(v_rif) between 5 and 30;
end fn_rif_cliente_valido;
/

-- =============================================================================
-- fn_rif_empresa_valido.sql
--
-- El RIF/RFC de la empresa emisora tiene la forma de su pais? (2026-11-17)
--
-- Hasta hoy la pestana «Empresa» aceptaba cualquier texto en el RIF (en la base
-- de trabajo quedaba «EMP123456789», que es el relleno del PDF de ejemplo). Con
-- un RIF asi el SENIAT rechaza facturas, retenciones y libros, y en la fase de
-- cobros no se puede cruzar con el comprobante del cliente.
--
-- Reglas (las mismas que fn_rif_cliente_valido, adaptadas al emisor):
--   * Venezuela: una letra J (juridica), V o E (persona natural), G (gobierno),
--     P (pasaporte) o C (consejo comunal) y despues solo digitos. J, G y C llevan
--     9 digitos; V y E de 7 a 9, porque su RIF es la cedula (6 a 8 digitos) mas
--     el verificador (2026-11-19: exigir 9 rechazaba «V-4666778-9»). Los guiones
--     y espacios dan igual: 'J-12345678-9' y 'J123456789' valen lo mismo.
--   * Mexico: RFC de 12 (moral) o 13 (fisica), alfanumerico.
--   * Otro pais: de 5 a 30 caracteres.
--
-- El digito verificador NO se comprueba (misma decision que en los clientes:
-- puede haber RIF antiguos o especiales).
-- =============================================================================

create or replace function fn_rif_empresa_valido (
    p_rif      in varchar2,
    p_cod_pais in varchar2
) return boolean is
    v_rif  varchar2(40);
    v_pais varchar2(2) := upper(trim(p_cod_pais));
begin
    if p_rif is null then
        return false;
    end if;

    -- Los separadores no cuentan: se quitan antes de mirar la forma.
    v_rif := replace(replace(upper(trim(p_rif)), '-', ''), ' ', '');

    if v_rif is null then
        return false;
    end if;

    if v_pais = 'VE' then
        return regexp_like(v_rif, '^[JGCP][0-9]{9}$')
            or regexp_like(v_rif, '^[VE][0-9]{7,9}$');
    elsif v_pais = 'MX' then
        return regexp_like(v_rif, '^[A-Z&Ñ0-9]{12,13}$');
    end if;

    return length(v_rif) between 5 and 30;
end fn_rif_empresa_valido;
/


-- =============================================================================
-- Validacion de la migracion
-- =============================================================================
declare
    v_n number;
begin
    if not fn_rif_cliente_valido('V-4666778-9', 'VE', 'N') then
        raise_application_error(-20105, 'fn_rif_cliente_valido sigue rechazando V-4666778-9');
    end if;
    if not fn_rif_cliente_valido('V-9877766', 'VE', 'N') then
        raise_application_error(-20105, 'fn_rif_cliente_valido rechaza una cedula de 7 digitos');
    end if;
    if not fn_rif_cliente_valido('V-12345678-9', 'VE', 'N') then
        raise_application_error(-20105, 'fn_rif_cliente_valido rechaza V-12345678-9');
    end if;
    if fn_rif_cliente_valido('J-6454545', 'VE', 'J') then
        raise_application_error(-20105, 'fn_rif_cliente_valido acepta J-6454545');
    end if;
    if fn_rif_cliente_valido('J-1234567-8', 'VE', 'J') then
        raise_application_error(-20105, 'fn_rif_cliente_valido acepta una juridica de 8 digitos');
    end if;

    if not fn_rif_empresa_valido('V-4666778-9', 'VE') then
        raise_application_error(-20105, 'fn_rif_empresa_valido rechaza V-4666778-9');
    end if;
    if fn_rif_empresa_valido('J-6454545', 'VE') then
        raise_application_error(-20105, 'fn_rif_empresa_valido acepta J-6454545');
    end if;

    select count(*) into v_n from all_objects
     where owner = 'WKSP_SYPEXWS'
       and object_name in ('FN_RIF_CLIENTE_VALIDO', 'FN_RIF_EMPRESA_VALIDO')
       and object_type = 'FUNCTION'
       and status = 'VALID';
    if v_n <> 2 then
        raise_application_error(-20105, 'las dos funciones no quedaron VALID (' || v_n || ')');
    end if;
end;
/
