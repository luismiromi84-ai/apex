-- =============================================================================
-- fn_clean_num.sql
--
-- Convierte texto en numero aceptando formato latino (1.234,56) y estandar
-- (1234.56).
--
-- Cambio del 2026-11-05: antes borraba los caracteres que no eran numero con un
-- REGEXP_REPLACE, asi que "12,5x" se convertia en 12,5 y el error desaparecia.
-- Ahora se valida la cadena completa: si no es un numero, devuelve NULL. Un NULL
-- revienta en una columna obligatoria y se ve; un 12,5 silencioso no.
--
-- Reglas:
--   * NULL o cadena vacia -> 0 (una casilla vacia significa cero, no error).
--   * Numero valido -> su valor.
--   * Cualquier otra cosa -> NULL. NO se recorta ni se convierte a 0.
--
-- Cambio del 2026-11-06: la mascara de TO_NUMBER tenia 4 decimales y las tasas
-- de cambio tienen 6 (MXN->VES 47,910741). Una tasa de 6 decimales devolvia
-- NULL, y en `prc_guardar_factura` eso terminaba en ORA-01400 al insertar
-- `TIPO_CAMBIO`. Ahora la mascara admite 10 decimales.
--
-- Ojo: los llamadores que hacian nvl(fn_clean_num(x), 0) siguen dando cero; los
-- que no, ahora reciben NULL y fallan de forma visible.
-- =============================================================================

create or replace FUNCTION fn_clean_num (p_val IN VARCHAR2)
RETURN NUMBER IS
    l_limpio VARCHAR2(100);
BEGIN
    IF p_val IS NULL OR TRIM(p_val) IS NULL THEN
        RETURN 0;
    END IF;

    l_limpio := TRIM(p_val);

    -- Solo digitos, separadores y signo. Si aparece cualquier otra cosa
    -- (letras, simbolos de moneda, basura), no es un numero.
    IF NOT REGEXP_LIKE(l_limpio, '^[-+]?[0-9]+([.,][0-9]+)*$')
       AND NOT REGEXP_LIKE(l_limpio, '^[-+]?[.,][0-9]+$') THEN
        RETURN NULL;
    END IF;

    -- Formato latino: si tiene coma y punto, el que este mas a la derecha es el
    -- decimal y el otro el separador de miles.
    IF INSTR(l_limpio, ',') > 0 AND INSTR(l_limpio, '.') > 0 THEN
        IF INSTR(l_limpio, ',') > INSTR(l_limpio, '.') THEN
            l_limpio := REPLACE(l_limpio, '.', '');
            l_limpio := REPLACE(l_limpio, ',', '.');
        ELSE
            l_limpio := REPLACE(l_limpio, ',', '');
        END IF;
    ELSIF INSTR(l_limpio, ',') > 0 THEN
        l_limpio := REPLACE(l_limpio, ',', '.');
    END IF;

    IF l_limpio IN ('.', '-', '+', '-.', '+.') THEN
        RETURN NULL;
    END IF;

    -- El signo + no lo acepta la mascara de TO_NUMBER.
    IF SUBSTR(l_limpio, 1, 1) = '+' THEN
        l_limpio := SUBSTR(l_limpio, 2);
    END IF;

    RETURN TO_NUMBER(l_limpio, 'FM999999999999999999.9999999999', 'NLS_NUMERIC_CHARACTERS=''.,''');

EXCEPTION
    WHEN OTHERS THEN
        -- Cadena con pinta de numero pero que no convierte: es invalida, no cero.
        RETURN NULL;
END fn_clean_num;
/
