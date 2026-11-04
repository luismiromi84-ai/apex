create or replace TRIGGER trg_forma_pago_bi
BEFORE INSERT ON forma_pago
FOR EACH ROW
BEGIN
    IF :NEW.id_forma_pago IS NULL THEN
        :NEW.id_forma_pago := seq_forma_pago.NEXTVAL;
    END IF;
    :NEW.codigo := UPPER(TRIM(:NEW.codigo));
END;
/