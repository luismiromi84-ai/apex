-- =============================================================================
-- 20261122_estado_compra_pendiente.sql
--
-- La etiqueta visible del estado BORRADOR de la compra pasa a "Pendiente"
-- (pedido del dueno, 2026-11-22). El VALOR guardado no cambia: de BORRADOR
-- dependen las condiciones de las paginas 28/29, los comprobantes de retencion,
-- el libro y los pagos. Solo cambia lo que se lee, igual que "Procesada" para
-- REGISTRADA (2026-11-21).
--
-- Idempotente: recrea la funcion y valida. Si ya estaba, no hace nada distinto.
--
-- Uso:
--   python deploy/conexion/importar_export.py deploy/migrations/20261122_estado_compra_pendiente.sql
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

create or replace function fn_estado_compra (
    p_estado in varchar2
) return varchar2 is
begin
    return case upper(nvl(p_estado, '#'))
               when 'BORRADOR'   then 'Pendiente'
               when 'REGISTRADA' then 'Procesada'
               when 'PARCIAL'    then 'Abonada'
               when 'PAGADA'     then 'Pagada'
               when 'ANULADA'    then 'Anulada'
               else p_estado
           end;
end fn_estado_compra;
/

declare
    v_n     number;
    v_etiq  varchar2(40);
    v_lista varchar2(500) := '';
begin
    v_etiq := fn_estado_compra('BORRADOR');
    if v_etiq <> 'Pendiente' then
        v_lista := v_lista || ' | BORRADOR se lee ' || v_etiq;
    end if;
    if fn_estado_compra('REGISTRADA') <> 'Procesada'
       or fn_estado_compra('PARCIAL') <> 'Abonada'
       or fn_estado_compra('PAGADA') <> 'Pagada'
       or fn_estado_compra('ANULADA') <> 'Anulada' then
        v_lista := v_lista || ' | se movieron otras etiquetas';
    end if;

    select count(*) into v_n from compras where upper(estado) = 'PENDIENTE';
    if v_n <> 0 then
        v_lista := v_lista || ' | ' || v_n || ' compras con el valor PENDIENTE';
    end if;

    select count(*) into v_n
      from all_constraints
     where owner = 'WKSP_SYPEXWS'
       and table_name = 'COMPRAS'
       and constraint_name = 'CHK_COMPRAS_ESTADO'
       and search_condition_vc like '%BORRADOR%';
    if v_n <> 1 then
        v_lista := v_lista || ' | el CHECK de COMPRAS ya no admite BORRADOR';
    end if;

    select count(*) into v_n
      from all_objects
     where owner = 'WKSP_SYPEXWS' and object_name = 'FN_ESTADO_COMPRA' and status <> 'VALID';
    if v_n <> 0 then
        v_lista := v_lista || ' | la funcion quedo invalida';
    end if;

    if v_lista is null then
        raise_application_error(-20100, 'RESULTADO: FALLAS=0');
    else
        raise_application_error(-20100, substrb('RESULTADO: FALLAS=1' || v_lista, 1, 500));
    end if;
end;
/
