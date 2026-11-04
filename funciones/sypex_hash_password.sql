create or replace FUNCTION sypex_hash_password (
    p_password IN VARCHAR2
) RETURN VARCHAR2 IS
    v_hash VARCHAR2(255);
BEGIN
    IF p_password IS NULL THEN
        RETURN NULL;
    END IF;

    -- Usamos SQL dinámico para saltar la validación estática de PL/SQL
    EXECUTE IMMEDIATE 
        'SELECT LOWER(RAWTOHEX(STANDARD_HASH(:1, ''SHA256''))) FROM DUAL'
        INTO v_hash
        USING (p_password || 'SYPEX_SALT_2026');

    RETURN v_hash;
END sypex_hash_password;
/