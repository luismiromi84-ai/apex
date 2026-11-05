-- =============================================================================
-- fn_password_es_legado.sql
--
-- TRUE si el hash guardado no es del formato actual. Sirve para convertir el
-- hash viejo (sha256 + sal literal) la primera vez que el usuario entra.
-- =============================================================================

create or replace function fn_password_es_legado (
    p_hash in varchar2
) return boolean is
begin
    return p_hash is not null and p_hash not like 'PBKDF2-SHA256$%';
end fn_password_es_legado;
/
