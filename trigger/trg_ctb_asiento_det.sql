-- =============================================================================
-- trg_ctb_asiento_det / trg_ctb_asientos_protege (contabilidad, 2026-11-25)
--
-- * Las lineas solo se tocan mientras el asiento esta en BORRADOR (-20182): un asiento
--   confirmado se corrige con un reverso, nunca editandolo.
-- * La cuenta de la linea es de la misma empresa, esta ACTIVA y acepta movimiento (-20183).
-- * Al final de la sentencia recalcula TOTAL_DEBE / TOTAL_HABER de la cabecera.
-- * La cabecera confirmada no cambia de fecha, empresa, concepto ni totales, y no se borra.
-- =============================================================================

create or replace trigger trg_ctb_asiento_det
for insert or update or delete on ctb_asiento_det
compound trigger

    type t_ids is table of number index by pls_integer;
    g_ids t_ids;

    procedure marca(p_id number) is
    begin
        if p_id is not null then
            g_ids(p_id) := p_id;
        end if;
    end marca;

    before each row is
        v_estado ctb_asientos.estado%type;
        v_emp    number;
        v_n      number;
        v_id     number := nvl(:new.id_asiento, :old.id_asiento);
    begin
        -- la purga de pruebas (pkg_contabilidad.prc_purgar_prueba) pasa sin controles
        if not pkg_contabilidad.fn_purgando then
            begin
                select estado, id_empresa into v_estado, v_emp from ctb_asientos where id_asiento = v_id;
            exception
                when no_data_found then
                    raise_application_error(-20190, 'El asiento no existe.');
            end;
            if v_estado <> 'BORRADOR' then
                raise_application_error(-20182,
                    'El asiento esta ' || v_estado || ': no se modifica, se corrige con un reverso.');
            end if;
            if inserting or updating then
                select count(*) into v_n from ctb_cuentas
                 where id_cuenta_ctb = :new.id_cuenta_ctb and id_empresa = v_emp
                   and estado = 'ACTIVO' and acepta_movimiento = 'S';
                if v_n = 0 then
                    raise_application_error(-20183,
                        'La cuenta de la linea ' || :new.linea || ' no es de la empresa, esta inactiva o es de grupo.');
                end if;
            end if;
        end if;
    end before each row;

    after each row is
    begin
        marca(:new.id_asiento);
        marca(:old.id_asiento);
    end after each row;

    after statement is
        v_i pls_integer := g_ids.first;
    begin
        while v_i is not null loop
            update ctb_asientos a set (total_debe, total_haber) =
                   (select nvl(sum(d.debe), 0), nvl(sum(d.haber), 0)
                      from ctb_asiento_det d where d.id_asiento = a.id_asiento)
             where a.id_asiento = g_ids(v_i);
            v_i := g_ids.next(v_i);
        end loop;
        g_ids.delete;
    end after statement;

end trg_ctb_asiento_det;
/

create or replace trigger trg_ctb_asientos_protege
before update or delete on ctb_asientos
for each row
begin
    if pkg_contabilidad.fn_purgando then
        return;
    end if;
    if deleting then
        if :old.estado <> 'BORRADOR' then
            raise_application_error(-20182, 'Un asiento ' || :old.estado || ' no se borra: se reversa.');
        end if;
    elsif :old.estado <> 'BORRADOR' then
        if :new.id_empresa <> :old.id_empresa or :new.fecha <> :old.fecha
           or :new.concepto <> :old.concepto
           or :new.total_debe <> :old.total_debe or :new.total_haber <> :old.total_haber then
            raise_application_error(-20182, 'El asiento esta ' || :old.estado || ': no se modifica.');
        end if;
    end if;
end trg_ctb_asientos_protege;
/
