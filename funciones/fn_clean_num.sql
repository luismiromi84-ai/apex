create or replace FUNCTION fn_clean_num (p_val IN VARCHAR2) 
RETURN NUMBER IS
    l_limpio VARCHAR2(100);
BEGIN
    IF p_val IS NULL OR TRIM(p_val) = '' THEN  
        RETURN 0;  
    END IF;

    -- 1. Eliminar cualquier carácter que no sea número, punto, coma o signo menos
    l_limpio := REGEXP_REPLACE(p_val, '[^0-9\.,-]', '');

    -- 2. Si usa la coma como decimal (formato venezolano/latino), 
    -- reemplazamos los puntos de miles por nada y la coma por punto para que TO_NUMBER lo entienda universalmente.
    -- O si viene con formato estándar con punto, lo adaptamos.
    -- Ejemplo seguro: si contiene coma, asumimos coma decimal y punto de mil.
    IF INSTR(l_limpio, ',') > 0 AND INSTR(l_limpio, '.') > 0 THEN
        -- Si tiene ambos, el que esté más a la derecha suele ser el decimal
        IF INSTR(l_limpio, ',') > INSTR(l_limpio, '.') THEN
            l_limpio := REPLACE(l_limpio, '.', ''); -- Quitar puntos de miles
            l_limpio := REPLACE(l_limpio, ',', '.'); -- Cambiar coma decimal por punto
        ELSE
            l_limpio := REPLACE(l_limpio, ',', ''); -- Quitar comas de miles
        END IF;
    ELSIF INSTR(l_limpio, ',') > 0 THEN
        -- Solo tiene coma, la convertimos a punto decimal
        l_limpio := REPLACE(l_limpio, ',', '.');
    END IF;

    -- 3. Conversión directa y limpia
    RETURN TO_NUMBER(l_limpio);
    
EXCEPTION
    WHEN OTHERS THEN
        -- Opcional: puedes registrar el error con RAISE_APPLICATION_ERROR si vuelve a fallar para depurar
        RETURN 0;
END fn_clean_num;
/