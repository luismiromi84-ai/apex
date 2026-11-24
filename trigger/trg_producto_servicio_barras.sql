-- =============================================================================
-- TRG_PRODUCTO_SERVICIO_BARRAS
--
-- El codigo de barras del catalogo (2026-11-23):
--   * lo asigna el sistema al guardar, con la serie ARTICULO de FOLIO_CONTADOR
--     (10000001, 10000002...), asi que un articulo no puede quedar sin codigo;
--   * es permanente: no se puede cambiar (para reimprimir etiquetas viejas) ni
--     reutilizar en otro articulo;
--   * la empresa es obligatoria: el catalogo es por empresa.
--
-- Si alguna vez hay que corregir un codigo a mano (una carga masiva mal hecha),
-- se hace con el trigger deshabilitado y se documenta; la app no ofrece esa via.
-- =============================================================================

create or replace trigger trg_producto_servicio_barras
before insert or update of id_empresa, codigo_barras on producto_servicio
for each row
begin
    if :new.id_empresa is null then
        raise_application_error(-20130,
            'El articulo necesita empresa: el catalogo es por empresa.');
    end if;

    if updating and :old.codigo_barras is not null
       and (:new.codigo_barras is null or :new.codigo_barras <> :old.codigo_barras) then
        raise_application_error(-20131,
            'El codigo de barras es permanente: no se puede cambiar ni reutilizar.');
    end if;

    if :new.codigo_barras is null then
        :new.codigo_barras := fn_asignar_folio(:new.id_empresa, 'ARTICULO');
    end if;
end;
/
