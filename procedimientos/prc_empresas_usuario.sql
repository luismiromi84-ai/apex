-- =============================================================================
-- prc_empresas_usuario.sql
--
-- Sincroniza las empresas de un usuario desde la pagina 4 (fase 3 de
-- multiempresa, 2026-11-11).
--
-- Entrada:  p_usuario_id  el usuario a tocar
--           p_empresas    la seleccion como la manda APEX: '1:3:4' (puede ser nulo)
--           p_admin       APP_USER que esta guardando
-- Salida:   p_estado      estado final del usuario
--           p_mensaje     aviso para la pantalla, o nulo
--
-- Reglas (spec 2026-11-11, seccion 5):
--   * El administrador solo toca usuarios que compartan alguna empresa con el,
--     o que no tengan ninguna (los PENDIENTE del registro). Si no: -20003.
--   * Solo puede asignar empresas SUYAS. Si no: -20003.
--   * Con seleccion: se borran los pares de las empresas del admin que ya no
--     estan marcados (los de empresas que el admin NO ve no se tocan), se
--     insertan los que faltan y USUARIO.ID_EMPRESA pasa a ser la MENOR de la
--     seleccion.
--   * Sin seleccion: NO se toca ningun par. Si el usuario estaba activo se
--     deja INACTIVO, conservando sus empresas para auditoria (decision del
--     dueño, 2026-11-11).
--
-- Ojo: dentro del procedimiento solo se BORRAN pares; el usuario se ACTUALIZA.
-- Borrar pares y su usuario en la misma transaccion da ORA-12860 en esta ADB.
-- =============================================================================

create or replace procedure prc_empresas_usuario (
    p_usuario_id in number,
    p_empresas   in varchar2,
    p_admin      in varchar2,
    p_estado     out varchar2,
    p_mensaje    out varchar2
) is
    type t_numeros is table of number;
    v_nums      t_numeros := t_numeros();
    v_ids       varchar2(4000) := ',';
    v_empresa   number;
    v_suyas     number;
    v_min       number;
    v_estado    usuario.estado%type;
begin
    p_estado  := null;
    p_mensaje := null;

    if not fn_usuario_administrable(p_admin, p_usuario_id) then
        raise_application_error(-20003, 'Solo puede administrar usuarios de su empresa.');
    end if;

    -- 1. Validar la seleccion: cada valor tiene que ser una empresa del admin.
    for r in (select trim(column_value) as valor
                from table(apex_string.split(nvl(p_empresas, ':'), ':'))) loop
        if r.valor is not null then
            v_empresa := fn_clean_num(r.valor);
            select count(*) into v_suyas
              from v_empresas_usuario
             where upper(username) = upper(p_admin)
               and id_empresa = v_empresa;
            if v_suyas = 0 then
                raise_application_error(-20003, 'Solo puede asignar empresas suyas.');
            end if;
            v_nums.extend;
            v_nums(v_nums.count) := v_empresa;
            v_ids := v_ids || v_empresa || ',';
            v_min := least(nvl(v_min, v_empresa), v_empresa);
        end if;
    end loop;

    -- 2. Sin seleccion: no se tocan los pares; si estaba activo, se desactiva.
    if v_nums.count = 0 then
        select estado into v_estado from usuario where usuario_id = p_usuario_id;
        if nvl(upper(v_estado), '#') in ('ACTIVO', 'A', '1') then
            update usuario set estado = 'INACTIVO' where usuario_id = p_usuario_id;
            p_estado  := 'INACTIVO';
            p_mensaje := 'El usuario quedo INACTIVO porque no tiene ninguna empresa asignada. '
                      || 'Sus empresas se conservan para auditoria.';
        else
            p_estado := v_estado;
        end if;
        return;
    end if;

    -- 3. Quitar los pares que el admin ve y ya no estan marcados.
    delete from usuario_empresa
     where usuario_id = p_usuario_id
       and instr(v_ids, ',' || id_empresa || ',') = 0
       and id_empresa in (select id_empresa from v_empresas_usuario
                           where upper(username) = upper(p_admin));

    -- 4. Anadir los que falten (el trigger de la empresa principal puede haber
    --    creado ya alguno: 'where not exists' evita chocar con la PK).
    for i in 1 .. v_nums.count loop
        insert into usuario_empresa (usuario_id, id_empresa)
        select p_usuario_id, v_nums(i) from dual
         where not exists (select 1
                             from usuario_empresa
                            where usuario_id = p_usuario_id
                              and id_empresa  = v_nums(i));
    end loop;

    -- 5. La principal es la menor de la seleccion (spec, decision 13.3).
    update usuario set id_empresa = v_min where usuario_id = p_usuario_id;

    select estado into v_estado from usuario where usuario_id = p_usuario_id;
    p_estado := v_estado;
end prc_empresas_usuario;
/
