-- =============================================================================
-- sypex_hash_password.sql
--
-- Hash de contrasena: PBKDF2-HMAC-SHA256 con sal aleatoria por usuario.
-- Formato guardado en USUARIO.PASSWORD_HASH (VARCHAR2(512)):
--
--   PBKDF2-SHA256$<iteraciones>$<sal_hex>$<hash_hex>
--
-- La firma no cambia a proposito: las paginas 2, 4 y 14 la llaman dentro de
-- INSERT/UPDATE y siguen funcionando sin tocarse.
--
-- Requiere: grant execute on sys.dbms_crypto to WKSP_SYPEXWS
-- =============================================================================

create or replace function sypex_hash_password (
    p_password in varchar2
) return varchar2 is
    c_iteraciones constant number := 100000;
    c_bloque      constant raw(4) := hextoraw('00000001');
    v_sal  raw(16);
    v_u    raw(32);
    v_xor  raw(32);
    v_key  raw(2000);
begin
    if p_password is null then
        return null;
    end if;

    v_sal := dbms_crypto.randombytes(16);
    v_key := utl_raw.cast_to_raw(p_password);

    -- PBKDF2, un solo bloque de salida (dkLen = 32 bytes)
    v_u   := dbms_crypto.mac(v_sal || c_bloque, dbms_crypto.hmac_sh256, v_key);
    v_xor := v_u;
    for i in 2 .. c_iteraciones loop
        v_u   := dbms_crypto.mac(v_u, dbms_crypto.hmac_sh256, v_key);
        v_xor := utl_raw.bit_xor(v_xor, v_u);
    end loop;

    return 'PBKDF2-SHA256$' || c_iteraciones || '$' || rawtohex(v_sal) || '$' || rawtohex(v_xor);
end sypex_hash_password;
/
