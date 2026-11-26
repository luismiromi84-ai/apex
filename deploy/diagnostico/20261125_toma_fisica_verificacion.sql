-- =============================================================================
-- 20261125_toma_fisica_verificacion.sql
--
-- Toma fisica de inventario (pkg_toma_fisica):
--   T1 crear la toma copia la existencia del sistema de cada producto activo
--   T2 no se puede crear otra mientras haya una abierta (-20160)
--   T3 un conteo negativo se rechaza (-20162)
--   T4 aplicar: el articulo con mas unidades contadas entra (AJUSTE_ENTRADA) y el que
--      tiene menos sale (AJUSTE_SALIDA); la existencia queda igual al conteo
--   T5 el articulo sin contar no se toca
--   T6 una toma aplicada ya no se cambia ni se aplica otra vez (-20161)
--   T7 anular una toma en borrador no toca el kardex
--
-- Empresa temporal 900270 con dos articulos y un usuario temporal; se limpia al final.
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261125_toma_fisica_verificacion.sql
-- FALLAS=0 = EXITO (el runner sale con codigo 1 aunque sea verde: se lee el mensaje).
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

begin
    begin execute immediate 'drop table tmp_tf_fallas purge'; exception when others then null; end;
end;
/

create table tmp_tf_fallas (caso varchar2(400))
/

begin
    for r in (select usuario_id from usuario where upper(username) = 'DIAG.TOMA') loop
        delete from usuario_empresa where usuario_id = r.usuario_id; commit;
        delete from usuario where usuario_id = r.usuario_id; commit;
    end loop;
    begin delete from tomas_fisicas_det where id_toma in (select id_toma from tomas_fisicas where id_empresa = 900270); commit; exception when others then null; end;
    begin delete from tomas_fisicas where id_empresa = 900270; commit; exception when others then null; end;
    begin delete from kardex_saldo where id_empresa = 900270; commit; exception when others then null; end;
    begin delete from kardex_mov where id_empresa = 900270; commit; exception when others then null; end;
    begin delete from producto_servicio where id_empresa = 900270; commit; exception when others then null; end;
    begin delete from folio_contador where id_empresa = 900270; commit; exception when others then null; end;
    begin delete from usuario_empresa where id_empresa = 900270; commit; exception when others then null; end;
    begin delete from empresas where id_empresa = 900270; commit; exception when others then null; end;
end;
/

insert into empresas (id_empresa, nombre_empresa, cod_pais, tipo_ident_fiscal, rfc, estado)
values (900270, 'DIAG TOMA', 'VE', 'RIF', 'J-90027000-1', 'ACTIVO')
/

commit
/

insert into usuario (username, email, password_hash, estado, id_empresa, rol_id, debe_cambiar_clave, reintentos_fallidos)
values ('diag.toma', 'diag.toma@synpex.local', 'x', 'ACTIVO', 900270,
        (select id_rol from syn_roles where codigo_rol = 'ADMIN'), 'N', 0)
/

commit
/

insert into producto_servicio (id_empresa, nombre, descripcion, tipo, precio_sugerido, estado)
values (900270, 'Articulo A', 'Articulo A', 'PRODUCTO', 10, 'ACTIVO')
/

commit
/

insert into producto_servicio (id_empresa, nombre, descripcion, tipo, precio_sugerido, estado)
values (900270, 'Articulo B', 'Articulo B', 'PRODUCTO', 10, 'ACTIVO')
/

commit
/

insert into producto_servicio (id_empresa, nombre, descripcion, tipo, precio_sugerido, estado)
values (900270, 'Articulo C', 'Articulo C', 'PRODUCTO', 10, 'ACTIVO')
/

commit
/

declare
    v_a    number;
    v_b    number;
    v_c    number;
    v_toma number;
    v_toma2 number;
    v_n    number;
    v_aj   number;

    procedure falla(p varchar2) is
    begin
        insert into tmp_tf_fallas values (substrb(p, 1, 400));
        commit;
    end;

    function existencia(p number) return number is
    begin
        return nvl(pkg_inventario.fn_disponible(900270, p), 0);
    end;
begin
    select id_producto_servicio into v_a from producto_servicio where id_empresa = 900270 and nombre = 'Articulo A';
    select id_producto_servicio into v_b from producto_servicio where id_empresa = 900270 and nombre = 'Articulo B';
    select id_producto_servicio into v_c from producto_servicio where id_empresa = 900270 and nombre = 'Articulo C';

    -- carga inicial: A 10, B 10, C 5
    pkg_inventario.prc_ajuste(900270, v_a, trunc(sysdate), 'SALDO_INICIAL', 10, 50, 'VES', 1, 'carga diag', 'diag.toma');
    pkg_inventario.prc_ajuste(900270, v_b, trunc(sysdate), 'SALDO_INICIAL', 10, 50, 'VES', 1, 'carga diag', 'diag.toma');
    pkg_inventario.prc_ajuste(900270, v_c, trunc(sysdate), 'SALDO_INICIAL', 5, 50, 'VES', 1, 'carga diag', 'diag.toma');
    commit;

    -- T1
    v_toma := pkg_toma_fisica.fn_crear(900270, trunc(sysdate), 'diag.toma');
    commit;
    select count(*) into v_n from tomas_fisicas_det where id_toma = v_toma;
    if v_n <> 3 then falla('T1: la toma tiene ' || v_n || ' articulos (esperaba 3)'); end if;
    select count(*) into v_n from tomas_fisicas_det
     where id_toma = v_toma and id_producto_servicio = v_a and existencia_sistema = 10;
    if v_n <> 1 then falla('T1: la existencia del sistema de A no quedo en 10'); end if;

    -- T2
    begin
        v_toma2 := pkg_toma_fisica.fn_crear(900270, trunc(sysdate), 'diag.toma');
        falla('T2: se creo una segunda toma abierta');
        rollback;
    exception when others then
        if sqlcode <> -20160 then falla('T2: codigo ' || sqlcode); end if;
        rollback;
    end;

    -- T3
    begin
        pkg_toma_fisica.prc_guardar_conteo(v_toma, '[{"id":' || v_a || ',"conteo":-1}]', 'diag.toma');
        falla('T3: se acepto un conteo negativo');
        rollback;
    exception when others then
        if sqlcode <> -20162 then falla('T3: codigo ' || sqlcode); end if;
        rollback;
    end;

    -- T4/T5: A se cuentan 12 (+2), B 7 (-3), C sin contar
    pkg_toma_fisica.prc_guardar_conteo(v_toma,
        '[{"id":' || v_a || ',"conteo":12},{"id":' || v_b || ',"conteo":7}]', 'diag.toma');
    pkg_toma_fisica.prc_aplicar(v_toma, 'diag.toma', v_aj);
    commit;
    if v_aj <> 2 then falla('T4: hizo ' || v_aj || ' ajustes (esperaba 2)'); end if;
    if existencia(v_a) <> 12 then falla('T4: A quedo en ' || existencia(v_a) || ' (esperaba 12)'); end if;
    if existencia(v_b) <> 7 then falla('T4: B quedo en ' || existencia(v_b) || ' (esperaba 7)'); end if;
    select count(*) into v_n from kardex_mov
     where id_empresa = 900270 and id_producto_servicio = v_a and tipo_movimiento = 'AJUSTE_ENTRADA' and cantidad = 2;
    if v_n <> 1 then falla('T4: A no tiene su AJUSTE_ENTRADA de 2'); end if;
    select count(*) into v_n from kardex_mov
     where id_empresa = 900270 and id_producto_servicio = v_b and tipo_movimiento = 'AJUSTE_SALIDA' and cantidad = 3;
    if v_n <> 1 then falla('T4: B no tiene su AJUSTE_SALIDA de 3'); end if;
    if existencia(v_c) <> 5 then falla('T5: C (sin contar) cambio a ' || existencia(v_c)); end if;

    -- T6
    begin
        pkg_toma_fisica.prc_aplicar(v_toma, 'diag.toma', v_aj);
        falla('T6: se aplico dos veces');
        rollback;
    exception when others then
        if sqlcode <> -20161 then falla('T6: codigo ' || sqlcode); end if;
        rollback;
    end;

    -- T7
    v_toma2 := pkg_toma_fisica.fn_crear(900270, trunc(sysdate), 'diag.toma');
    pkg_toma_fisica.prc_guardar_conteo(v_toma2, '[{"id":' || v_c || ',"conteo":0}]', 'diag.toma');
    pkg_toma_fisica.prc_anular(v_toma2, 'diag.toma');
    commit;
    if existencia(v_c) <> 5 then falla('T7: anular movio el kardex (C=' || existencia(v_c) || ')'); end if;
end;
/

begin
    for r in (select usuario_id from usuario where upper(username) = 'DIAG.TOMA') loop
        delete from usuario_empresa where usuario_id = r.usuario_id; commit;
        delete from usuario where usuario_id = r.usuario_id; commit;
    end loop;
    begin delete from tomas_fisicas_det where id_toma in (select id_toma from tomas_fisicas where id_empresa = 900270); commit; exception when others then null; end;
    begin delete from tomas_fisicas where id_empresa = 900270; commit; exception when others then null; end;
    begin delete from kardex_saldo where id_empresa = 900270; commit; exception when others then null; end;
    begin delete from kardex_mov where id_empresa = 900270; commit; exception when others then null; end;
    begin delete from producto_servicio where id_empresa = 900270; commit; exception when others then null; end;
    begin delete from folio_contador where id_empresa = 900270; commit; exception when others then null; end;
    begin delete from usuario_empresa where id_empresa = 900270; commit; exception when others then null; end;
    begin delete from empresas where id_empresa = 900270; commit; exception when others then null; end;
end;
/

declare
    v_fallas number;
    v_lista  varchar2(2000);
begin
    select count(*) into v_fallas from tmp_tf_fallas;
    select substrb(listagg(caso, ' | ' on overflow truncate) within group (order by caso), 1, 2000)
      into v_lista from tmp_tf_fallas;
    execute immediate 'drop table tmp_tf_fallas purge';
    raise_application_error(-20100, substrb('RESULTADO: FALLAS=' || v_fallas || ' | ' || v_lista, 1, 2000));
end;
/
