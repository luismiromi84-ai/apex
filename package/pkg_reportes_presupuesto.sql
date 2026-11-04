create or replace PACKAGE pkg_reportes_presupuesto AS
    -- Función que genera el CLOB con el HTML estilizado del presupuesto para impresión/PDF
    FUNCTION fn_imprimir_presupuesto (p_id_presupuesto IN NUMBER) RETURN CLOB;
END pkg_reportes_presupuesto;
/