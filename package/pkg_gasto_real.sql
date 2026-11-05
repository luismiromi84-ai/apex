create or replace PACKAGE pkg_gasto_real AS
    -- Gasto real por presupuesto: lo que costo ejecutarlo, para compararlo con
    -- lo que se cotizo. Todo se guarda ademas en USD (MONTO_BASE_USD) para que
    -- el panel pueda sumar documentos de paises distintos.

    PROCEDURE prc_guardar_gasto (
        p_id_gasto        IN OUT NUMBER,
        p_id_presupuesto  IN  NUMBER,
        p_fecha_gasto     IN  DATE,
        p_monto_origen    IN  NUMBER,
        p_moneda_origen   IN  VARCHAR2,
        p_tasa_real       IN  NUMBER   DEFAULT NULL,
        p_usuario         IN  VARCHAR2 DEFAULT NULL);

    PROCEDURE prc_eliminar_gasto (
        p_id_gasto IN NUMBER,
        p_usuario  IN VARCHAR2 DEFAULT NULL);

    FUNCTION fn_total_gasto_usd (p_id_presupuesto IN NUMBER) RETURN NUMBER;
END pkg_gasto_real;
/
