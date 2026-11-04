create or replace PACKAGE pkg_reportes_factura AS
    FUNCTION fn_imprimir_factura (p_id_factura IN NUMBER) RETURN CLOB;
END pkg_reportes_factura;
/