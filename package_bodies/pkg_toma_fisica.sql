-- =============================================================================
-- pkg_toma_fisica (body) - toma fisica de inventario (2026-11-25)
-- =============================================================================

create or replace package body pkg_toma_fisica as

    -- La toma, validada contra la empresa del usuario. Bloquea la fila.
    function lee_toma(p_id_toma in number, p_usuario in varchar2) return tomas_fisicas%rowtype is
        r tomas_fisicas%rowtype;
    begin
        begin
            select * into r from tomas_fisicas where id_toma = p_id_toma for update;
        exception
            when no_data_found then
                raise_application_error(-20163, 'La toma fisica no existe.');
        end;
        if not fn_usuario_empresa_valida(p_usuario, r.id_empresa) then
            raise_application_error(-20163, 'La toma fisica es de otra empresa.');
        end if;
        return r;
    end lee_toma;

    function fn_crear(p_id_empresa in number, p_fecha in date, p_usuario in varchar2) return number is
        v_n  number;
        v_id number;
    begin
        if not fn_usuario_empresa_valida(p_usuario, p_id_empresa) then
            raise_application_error(-20163, 'No tiene acceso a la empresa indicada.');
        end if;
        select count(*) into v_n from tomas_fisicas
         where id_empresa = p_id_empresa and estado = 'BORRADOR';
        if v_n > 0 then
            raise_application_error(-20160,
                'Ya hay una toma fisica abierta: aplicala o anulala antes de crear otra.');
        end if;

        insert into tomas_fisicas (id_empresa, fecha, estado, creado_por)
        values (p_id_empresa, nvl(trunc(p_fecha), trunc(sysdate)), 'BORRADOR', p_usuario)
        returning id_toma into v_id;

        insert into tomas_fisicas_det (id_toma, id_producto_servicio, existencia_sistema)
        select v_id, a.id_producto_servicio, nvl(pkg_inventario.fn_disponible(p_id_empresa, a.id_producto_servicio), 0)
          from producto_servicio a
         where a.id_empresa = p_id_empresa
           and a.tipo = 'PRODUCTO'
           and nvl(a.estado, 'ACTIVO') = 'ACTIVO';
        return v_id;
    end fn_crear;

    procedure prc_guardar_conteo(p_id_toma in number, p_json in clob, p_usuario in varchar2) is
        r tomas_fisicas%rowtype;
    begin
        r := lee_toma(p_id_toma, p_usuario);
        if r.estado <> 'BORRADOR' then
            raise_application_error(-20161, 'La toma fisica ya esta ' || r.estado || ': no se puede cambiar.');
        end if;
        for c in (select jt.id, jt.conteo
                    from json_table(nvl(p_json, '[]'), '$[*]'
                         columns (id number path '$.id', conteo number path '$.conteo')) jt) loop
            if c.conteo is not null and c.conteo < 0 then
                raise_application_error(-20162, 'Un conteo no puede ser negativo.');
            end if;
            update tomas_fisicas_det d set d.conteo = c.conteo
             where d.id_toma = p_id_toma and d.id_producto_servicio = c.id;
        end loop;
    end prc_guardar_conteo;

    procedure prc_aplicar(p_id_toma in number, p_usuario in varchar2, p_ajustes out number) is
        r      tomas_fisicas%rowtype;
        v_act  number;
        v_dif  number;
        v_mot  varchar2(200);
    begin
        p_ajustes := 0;
        r := lee_toma(p_id_toma, p_usuario);
        if r.estado <> 'BORRADOR' then
            raise_application_error(-20161, 'La toma fisica ya esta ' || r.estado || '.');
        end if;
        v_mot := 'Toma fisica N. ' || r.id_toma || ' del ' || to_char(r.fecha, 'DD/MM/YYYY');

        -- Ordenado por articulo: dos procesos sobre los mismos articulos no se cruzan.
        for d in (select id_producto_servicio, conteo
                    from tomas_fisicas_det
                   where id_toma = p_id_toma and conteo is not null
                   order by id_producto_servicio) loop
            v_act := nvl(pkg_inventario.fn_disponible(r.id_empresa, d.id_producto_servicio), 0);
            v_dif := d.conteo - v_act;
            update tomas_fisicas_det x set x.diferencia = v_dif
             where x.id_toma = p_id_toma and x.id_producto_servicio = d.id_producto_servicio;
            if abs(v_dif) > 0.00001 then
                pkg_inventario.prc_ajuste(
                    p_id_empresa    => r.id_empresa,
                    p_id_producto   => d.id_producto_servicio,
                    p_fecha         => r.fecha,
                    p_tipo          => case when v_dif > 0 then 'AJUSTE_ENTRADA' else 'AJUSTE_SALIDA' end,
                    p_cantidad      => abs(v_dif),
                    p_costo_unit_bs => null,
                    p_moneda        => 'VES',
                    p_tasa          => 1,
                    p_motivo        => v_mot,
                    p_usuario       => p_usuario);
                p_ajustes := p_ajustes + 1;
            end if;
        end loop;

        update tomas_fisicas t set t.estado = 'APLICADA', t.aplicado_por = p_usuario,
               t.fecha_aplicacion = sysdate
         where t.id_toma = p_id_toma;
    end prc_aplicar;

    procedure prc_anular(p_id_toma in number, p_usuario in varchar2) is
        r tomas_fisicas%rowtype;
    begin
        r := lee_toma(p_id_toma, p_usuario);
        if r.estado <> 'BORRADOR' then
            raise_application_error(-20161, 'Solo se anula una toma en borrador (esta ' || r.estado || ').');
        end if;
        update tomas_fisicas t set t.estado = 'ANULADA' where t.id_toma = p_id_toma;
    end prc_anular;

end pkg_toma_fisica;
/
