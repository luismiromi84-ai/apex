-- =============================================================================
-- fn_verificar_password.sql
--
-- Comprueba una contrasena contra el hash guardado en USUARIO.PASSWORD_HASH.
-- Acepta dos formatos:
--   * PBKDF2-SHA256$<iter>$<sal_hex>$<hash_hex>  (actual)
--   * hex de 64 caracteres = sha256(password || 'SYPEX_SALT_2026')  (legado)
--
-- Devuelve FALSE ante cualquier entrada invalida en vez de lanzar error: la
-- llama fn_autenticar_usuario en el camino del login.
-- =============================================================================

create or replace function fn_verificar_password (
    p_password in varchar2,
    p_hash     in varchar2
) return boolean is
    v_iter number;
    v_sal  raw(2000);
    v_hash raw(2000);
    v_u    raw(32);
    v_xor  raw(32);
    v_key  raw(2000);
    v_leg  varchar2(64);
    v_p1   pls_integer;
    v_p2   pls_integer;
    v_p3   pls_integer;
begin
    if p_password is null or p_hash is null then
        return false;
    end if;

    if p_hash not like 'PBKDF2-SHA256$%' then
        -- formato legado
        execute immediate 'select lower(rawtohex(standard_hash(:1,''SHA256''))) from dual'
            into v_leg using p_password || 'SYPEX_SALT_2026';
        return lower(p_hash) = v_leg;
    end if;

    v_p1 := instr(p_hash, '$', 1, 1);
    v_p2 := instr(p_hash, '$', 1, 2);
    v_p3 := instr(p_hash, '$', 1, 3);

    v_iter := to_number(substr(p_hash, v_p1 + 1, v_p2 - v_p1 - 1));
    v_sal  := hextoraw(substr(p_hash, v_p2 + 1, v_p3 - v_p2 - 1));
    v_hash := hextoraw(substr(p_hash, v_p3 + 1));

    if v_iter is null or v_iter < 1 or v_iter > 1000000 or v_sal is null or v_hash is null then
        return false;
    end if;

    v_key := utl_raw.cast_to_raw(p_password);
    v_u   := dbms_crypto.mac(v_sal || hextoraw('00000001'), dbms_crypto.hmac_sh256, v_key);
    v_xor := v_u;
    for i in 2 .. v_iter loop
        v_u   := dbms_crypto.mac(v_u, dbms_crypto.hmac_sh256, v_key);
        v_xor := utl_raw.bit_xor(v_xor, v_u);
    end loop;

    return v_xor = v_hash;
exception
    when others then
        return false;
end fn_verificar_password;
/
