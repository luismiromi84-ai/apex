-- =============================================================================
-- prc_resincronizar_secuencia
--
-- Deja el contador de una serie EXACTAMENTE en el maximo real de la empresa
-- (2026-11-23). Es la migracion 20261118_resincronizar_folios.sql, ahora con
-- boton: sirve cuando las pruebas o una carga dejaron el contador por delante y
-- el proximo folio saldria con un hueco.
--
-- No toca documentos: solo mueve el contador. Las series que numera el
-- PROVEEDOR (FAC_PROV y CONTROL_PROV) no se resincronizan: su maximo no se puede
-- deducir de nuestras tablas.
-- =============================================================================

create or replace procedure prc_resincronizar_secuencia (
    p_id_empresa in number,
    p_tipo       in varchar2,
    p_usuario    in varchar2
) is
    v_tipo   varchar2(20) := upper(trim(p_tipo));
    v_max    number;
    v_es_adm number;
begin
    if p_id_empresa is null then
        raise_application_error(-20023, 'Elige una empresa antes de resincronizar.');
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

    v_max := fn_maximo_real(p_id_empresa, v_tipo);
    if v_max is null then
        raise_application_error(-20142,
            'Esa serie no se puede resincronizar: el numero lo pone el proveedor.');
    end if;

    merge into folio_contador f
    using (select p_id_empresa as id_empresa, v_tipo as tipo from dual) s
       on (f.id_empresa = s.id_empresa and f.tipo = s.tipo)
    when matched then
        update set f.ultimo = v_max
    when not matched then
        insert (id_empresa, tipo, ultimo) values (s.id_empresa, s.tipo, v_max);
end prc_resincronizar_secuencia;
/
