-- =============================================================================
-- trigger/trg_actualiza_totales_compra.sql
--
-- Mantiene los totales de COMPRAS a partir de COMPRAS_DET, igual que
-- TRG_ACTUALIZA_TOTALES_FACTURA hace con facturas. La cabecera nunca se escribe
-- a mano.
--
-- OJO con el runner de importacion: descarta toda linea que empiece por "set ",
-- asi que el SET del UPDATE va en la misma linea que el UPDATE.
-- =============================================================================

create or replace trigger trg_actualiza_totales_compra
for insert or update or delete on compras_det
compound trigger

    type t_compras is table of number index by pls_integer;
    g_compras t_compras;

    after each row is
    begin
        if deleting then
            g_compras(:old.id_compra) := :old.id_compra;
        else
            g_compras(:new.id_compra) := :new.id_compra;
        end if;
    end after each row;

    after statement is
        v_id number;
    begin
        v_id := g_compras.first;
        while v_id is not null loop
            update compras c set c.subtotal          = (select nvl(sum(subtotal_linea), 0) from compras_det where id_compra = v_id),
                                 c.monto_impuesto    = (select nvl(sum(monto_impuesto), 0) from compras_det where id_compra = v_id),
                                 c.monto_total       = (select nvl(sum(total_linea), 0) from compras_det where id_compra = v_id),
                                 c.fecha_modificacion = systimestamp,
                                 c.modificado_por     = user
             where c.id_compra = v_id;

            v_id := g_compras.next(v_id);
        end loop;
    end after statement;

end trg_actualiza_totales_compra;
/

alter trigger trg_actualiza_totales_compra enable
/
