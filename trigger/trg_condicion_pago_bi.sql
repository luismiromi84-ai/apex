create or replace TRIGGER trg_condicion_pago_bi
BEFORE INSERT ON condicion_pago
FOR EACH ROW
BEGIN
    IF :NEW.id_condicion_pago IS NULL THEN
        :NEW.id_condicion_pago := seq_condicion_pago.NEXTVAL;
    END IF;
    :NEW.codigo := UPPER(TRIM(:NEW.codigo));
END;
/