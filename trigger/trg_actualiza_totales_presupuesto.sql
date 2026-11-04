create or replace TRIGGER "TRG_ACTUALIZA_TOTALES_PRESUPUESTO"
FOR INSERT OR UPDATE OR DELETE ON PRESUPUESTOS_DET
COMPOUND TRIGGER

    TYPE t_presupuestos IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
    g_presupuestos t_presupuestos;

    AFTER EACH ROW IS
    BEGIN
        IF DELETING THEN
            g_presupuestos(:OLD.id_presupuesto) := :OLD.id_presupuesto;
        ELSE
            g_presupuestos(:NEW.id_presupuesto) := :NEW.id_presupuesto;
        END IF;
    END AFTER EACH ROW;

    AFTER STATEMENT IS
        v_id NUMBER;
    BEGIN
        v_id := g_presupuestos.FIRST;
        WHILE v_id IS NOT NULL LOOP
            UPDATE presupuestos p
               SET p.subtotal     = (SELECT NVL(SUM(subtotal_linea), 0) FROM presupuestos_det WHERE id_presupuesto = v_id),
                   p.impuesto_iva = (SELECT NVL(SUM(monto_impuesto), 0) FROM presupuestos_det WHERE id_presupuesto = v_id),
                   p.total        = (SELECT NVL(SUM(monto_total_linea), 0) FROM presupuestos_det WHERE id_presupuesto = v_id)
             WHERE p.id_presupuesto = v_id;

            v_id := g_presupuestos.NEXT(v_id);
        END LOOP;
    END AFTER STATEMENT;
END trg_actualiza_totales_presupuesto;
/