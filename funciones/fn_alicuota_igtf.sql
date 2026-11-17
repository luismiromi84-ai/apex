-- =============================================================================
-- fn_alicuota_igtf.sql
--
-- Alicuota del IGTF que le toca a una empresa (2026-11-17).
--
-- No hay un 3 % escrito en el codigo: se lee de IMPUESTOS, la fila IGTF del pais
-- de la empresa, marcada con APLICA_EN='CABECERA' (los impuestos de linea son los
-- del detalle). Asi, si la ley cambia la alicuota o exime un caso, es un UPDATE.
--
-- Devuelve 0 si la empresa no existe, su pais no tiene IGTF o la fila esta
-- inactiva.
--
-- No mira si la empresa es SPE: eso lo decide quien cobra (pkg_cobros), porque
-- esta funcion tambien se usa para proponer en pantalla.
-- =============================================================================

create or replace function fn_alicuota_igtf (
    p_id_empresa in number
) return number is
    v_pct number;
begin
    if p_id_empresa is null then
        return 0;
    end if;

    select nvl(max(i.porcentage), 0)
      into v_pct
      from impuestos i
      join empresas e on e.cod_pais = i.cod_pais
     where e.id_empresa  = p_id_empresa
       and i.cod_impuesto = 'IGTF'
       and i.estado     = 'ACTIVO'
       and i.aplica_en  = 'CABECERA';

    return nvl(v_pct, 0);
end fn_alicuota_igtf;
/
