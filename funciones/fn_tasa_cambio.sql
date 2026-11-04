create or replace FUNCTION fn_tasa_cambio (
    p_fecha         IN DATE,
    p_moneda_origen IN VARCHAR2 DEFAULT 'USD'
) RETURN NUMBER IS
    v_tasa NUMBER(12,6);
BEGIN
    -- Si la moneda es Bolívares (VES o BS), la tasa siempre es 1 por ley y normativa
    IF p_moneda_origen IN ('VES', 'BS') THEN
        RETURN 1.0000;
    END IF;

    -- Si la fecha es nula, retorna nulo directamente
    IF p_fecha IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT MAX(TASA_CAMBIO) KEEP (DENSE_RANK LAST ORDER BY FECHA_VIGENCIA ASC)
      INTO v_tasa
      FROM TIPO_CAMBIO
     WHERE MONEDA_ORIGEN = p_moneda_origen
       AND FECHA_VIGENCIA <= TRUNC(p_fecha);

    RETURN NVL(v_tasa, 1); -- Si no encuentra tasa para la divisa, por seguridad retorna 1 o puedes dejarlo en NULL
EXCEPTION
    WHEN OTHERS THEN
        RETURN 1;
END;
/