-- =============================================================================
-- 20261117_rif_empresa.sql
--
-- Funcion de validacion del RIF/RFC de la empresa emisora (2026-11-17).
-- Idempotente: create or replace.
--
-- El proceso «Guardar empresa» de la pagina 19 la llama; esta migracion solo
-- compila la funcion para que el proceso la encuentre.
--
-- Verificacion: deploy/diagnostico/20261117_rif_empresa_verificacion.sql
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
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
--     P (pasaporte) o C (consejo comunal) y despues solo digitos. Los guiones y
--     espacios dan igual: 'J-12345678-9' y 'J123456789' valen lo mismo.
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
        return regexp_like(v_rif, '^[JVEGPC][0-9]{6,12}$');
    elsif v_pais = 'MX' then
        return regexp_like(v_rif, '^[A-Z&Ñ0-9]{12,13}$');
    end if;

    return length(v_rif) between 5 and 30;
end fn_rif_empresa_valido;
/
