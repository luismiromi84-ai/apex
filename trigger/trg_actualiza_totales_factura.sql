create or replace TRIGGER trg_actualiza_totales_factura
FOR INSERT OR UPDATE OR DELETE ON FACTURAS_DET
COMPOUND TRIGGER

    TYPE t_facturas IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
    g_facturas t_facturas;

    AFTER EACH ROW IS
    BEGIN
        IF DELETING THEN
            g_facturas(:OLD.id_factura) := :OLD.id_factura;
        ELSE
            g_facturas(:NEW.id_factura) := :NEW.id_factura;
        END IF;
    END AFTER EACH ROW;

    AFTER STATEMENT IS
        v_id NUMBER;
    BEGIN
        v_id := g_facturas.FIRST;
        WHILE v_id IS NOT NULL LOOP
            UPDATE facturas f
               SET f.subtotal        = (SELECT NVL(SUM(subtotal_linea), 0) FROM facturas_det WHERE id_factura = v_id),
                   f.monto_impuesto  = (SELECT NVL(SUM(monto_impuesto), 0) FROM facturas_det WHERE id_factura = v_id),
                   f.monto_total     = (SELECT NVL(SUM(monto_total_linea), 0) FROM facturas_det WHERE id_factura = v_id),
                   f.fecha_modificacion = SYSTIMESTAMP,
                   f.modificado_por     = USER
             WHERE f.id_factura = v_id;

            v_id := g_facturas.NEXT(v_id);
        END LOOP;
    END AFTER STATEMENT;

END trg_actualiza_totales_factura;
/