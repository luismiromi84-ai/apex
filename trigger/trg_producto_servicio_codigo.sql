-- =============================================================================
-- TRG_PRODUCTO_SERVICIO_CODIGO
--
-- El codigo interno del catalogo (2026-11-23):
--   * lo asigna el sistema al insertar, con la serie PROD o SERV de
--     FOLIO_CONTADOR segun el tipo (PROD-00001, SERV-00001...), asi que un
--     articulo no puede quedar sin codigo ni depende de que el usuario lleve
--     la numeracion a mano;
--   * es permanente: no se puede cambiar (las etiquetas ya impresas y los
--     documentos que lo citan dejarian de cuadrar);
--   * el contador es atomico (fn_asignar_folio hace UPDATE ... RETURNING), asi
--     que dos altas a la vez reciben numeros distintos.
--
-- Los articulos que ya existian conservan su codigo (SERV-001, REP-002...): el
-- trigger solo actua cuando el codigo llega nulo.
-- =============================================================================

create or replace trigger trg_producto_servicio_codigo
before insert or update of codigo on producto_servicio
for each row
begin
    if updating and :old.codigo is not null
       and (:new.codigo is null or :new.codigo <> :old.codigo) then
        raise_application_error(-20132,
            'El codigo interno es permanente: no se puede cambiar.');
    end if;

    if inserting and :new.codigo is null then
        :new.codigo := fn_asignar_folio(:new.id_empresa,
            case when upper(nvl(:new.tipo, 'SERVICIO')) = 'PRODUCTO'
                 then 'PROD' else 'SERV' end);
    end if;
end;
/
