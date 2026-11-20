-- =============================================================================
-- 20261120_estado_compra_y_pantallas.sql
--
-- La etiqueta de estado de la factura de compra para las pantallas: la compra
-- REGISTRADA se LEE "Procesada" (en Venezuela la factura de compra no se timbra,
-- la procesa el receptor y se emiten sus comprobantes de retencion).
--
-- El valor guardado en COMPRAS.ESTADO NO se toca: de el dependen las condiciones
-- de servidor de la pagina 28, la emision y el libro. La funcion es solo para
-- mostrar; un estado que no conoce lo devuelve tal cual.
--
-- Solo crea la funcion: las pantallas (lista de compras 27 y cabecera de la 28)
-- ya la llaman desde el export, y la 31 recibe el tipo de comprobante.
--
-- Reversa: drop function fn_estado_compra.
-- Verificacion: deploy/diagnostico/20261119_retenciones_verificacion.sql (R12)
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

create or replace function fn_estado_compra (
    p_estado in varchar2
) return varchar2 is
begin
    return case upper(nvl(p_estado, '#'))
               when 'BORRADOR'   then 'Borrador'
               when 'REGISTRADA' then 'Procesada'
               when 'ANULADA'    then 'Anulada'
               else p_estado
           end;
end fn_estado_compra;
/

begin
    dbms_utility.compile_schema('WKSP_SYPEXWS', false);
end;
/

declare
    v_n   number;
    v_txt varchar2(30);
    v_mal varchar2(400);
begin
    select count(*) into v_n
      from all_objects
     where owner = 'WKSP_SYPEXWS' and object_name = 'FN_ESTADO_COMPRA'
       and status = 'VALID';
    if v_n < 1 then
        raise_application_error(-20112, 'FN_ESTADO_COMPRA quedo invalida');
    end if;

    select fn_estado_compra('REGISTRADA') into v_txt from dual;
    if v_txt <> 'Procesada' then
        raise_application_error(-20112, 'REGISTRADA no se lee Procesada: ' || v_txt);
    end if;

    select fn_estado_compra('OTRO') into v_txt from dual;
    if v_txt <> 'OTRO' then
        raise_application_error(-20112, 'un estado desconocido se devuelve tal cual: ' || v_txt);
    end if;

    -- El esquema entero, no solo esta funcion: una migracion que deja algo INVALID
    -- (el trigger de compras, un package que la llame) revienta la app y no se ve
    -- hasta que alguien abre la pantalla. Es la regla de las migraciones del repo.
    select count(*) into v_n
      from all_objects
     where owner = 'WKSP_SYPEXWS' and status = 'INVALID'
       and object_type in ('FUNCTION','PROCEDURE','PACKAGE','PACKAGE BODY','TRIGGER','VIEW');
    if v_n > 0 then
        for r in (select object_name, object_type
                    from all_objects
                   where owner = 'WKSP_SYPEXWS' and status = 'INVALID'
                     and object_type in ('FUNCTION','PROCEDURE','PACKAGE','PACKAGE BODY','TRIGGER','VIEW')
                   order by object_name) loop
            v_mal := substr(v_mal || r.object_type || ' ' || r.object_name || '; ', 1, 400);
        end loop;
        raise_application_error(-20112, v_n || ' objetos invalidos: ' || v_mal);
    end if;
end;
/
