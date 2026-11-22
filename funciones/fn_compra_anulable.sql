-- =============================================================================
-- fn_compra_anulable.sql
--
-- 'S' si la compra se puede anular hoy (2026-11-21): no esta ya ANULADA y no
-- tiene pagos ACTIVOS aplicados. Las compras con pagos no se anulan a ciegas
-- (pkg_compras lanza -20118): primero se anulan los pagos, que las liberan.
--
-- Existe como funcion porque la condicion de un boton es una expresion PL/SQL y
-- NO admite subconsultas.
-- =============================================================================

create or replace function fn_compra_anulable (
    p_id_compra in number
) return varchar2 is
    v_estado varchar2(20);
    v_pagos  number;
begin
    if p_id_compra is null then
        return 'N';
    end if;

    begin
        select c.estado into v_estado
          from compras c
         where c.id_compra = p_id_compra;
    exception
        when no_data_found then
            return 'N';
    end;

    if v_estado = 'ANULADA' then
        return 'N';
    end if;

    select count(*) into v_pagos
      from pagos_detalle d
      join pagos p on p.id_pago = d.id_pago
     where d.id_compra = p_id_compra
       and p.estado = 'ACTIVO';

    return case when v_pagos > 0 then 'N' else 'S' end;
end fn_compra_anulable;
/
