-- =============================================================================
-- fn_cuenta_fondos
--
-- La caja o cuenta bancaria de un cobro o de un pago (2026-11-25).
--   * Si llega una cuenta: tiene que ser de la empresa y estar ACTIVA.
--   * Si no llega ninguna: la PRINCIPAL de la empresa («Caja principal»).
--   * Si no hay ninguna valida: -20125 con el motivo.
-- La usan pkg_cobros.prc_registrar_cobro y pkg_pagos.prc_registrar_pago.
-- =============================================================================

create or replace function fn_cuenta_fondos (
    p_id_empresa in number,
    p_id_cuenta  in number default null
) return number is
    v_id number;
begin
    if nvl(p_id_cuenta, 0) > 0 then
        select max(id_cuenta) into v_id
          from cuentas_fondos
         where id_cuenta = p_id_cuenta
           and id_empresa = p_id_empresa
           and estado = 'ACTIVO';
        if v_id is null then
            raise_application_error(-20125,
                'La caja o cuenta elegida no es de esta empresa o esta INACTIVA.');
        end if;
        return v_id;
    end if;

    select max(id_cuenta) into v_id
      from cuentas_fondos
     where id_empresa = p_id_empresa
       and es_principal = 'S'
       and estado = 'ACTIVO';
    if v_id is null then
        raise_application_error(-20125,
            'La empresa no tiene una caja principal activa. Creala en Cajas y bancos.');
    end if;
    return v_id;
end fn_cuenta_fondos;
/
