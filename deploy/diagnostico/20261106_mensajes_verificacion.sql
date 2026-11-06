-- =============================================================================
-- 20261106_mensajes_verificacion.sql
--
-- Verifica que los mensajes al usuario no lleven jerga tecnica ni errores
-- duplicados, y que la escotilla de correccion siga funcionando.
--
-- Se ejecuta de arriba a abajo:
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261106_mensajes_verificacion.sql
--
-- Un solo bloque PL/SQL (el runner de python no imprime los SELECT) que termina
-- con -20100 ('RESULTADO: FALLAS=0'). Codigo de salida 1 con FALLAS=0 = EXITO.
--
-- Casos:
--   C1  Ningun body de package arma un mensaje con SQLERRM.
--   C2  Ningun trigger de estados menciona CLIENT_INFO en el mensaje.
--   C3  Cancelar un presupuesto FACTURADO da -20070 limpio (sin 'pkg_', sin
--       'CLIENT_INFO', con un solo 'ORA-').
--   C4  Borrar una linea de una factura PAGADA da -20002 limpio, no duplicado.
--   C5  La escotilla SYPEX_FORZAR_ESTADO sigue permitiendo la correccion.
--   C6  Los cuatro bodies dejan el detalle tecnico en el log (llaman a
--       prc_log_error).
--   C7  No queda ningun objeto INVALID.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000) := '';
    v_cnt    number;

    procedure falla (p_caso in varchar2, p_detalle in varchar2) is
    begin
        v_fallas := v_fallas + 1;
        v_lista  := v_lista || ' | ' || p_caso || ': ' || p_detalle;
    end falla;

    procedure cierra is
    begin
        raise_application_error(-20100, substr('RESULTADO: FALLAS=' || v_fallas
            || v_lista, 1, 1900));
    end cierra;
begin
    -- C1: SQLERRM solo puede aparecer como detalle del log, nunca dentro de un
    -- mensaje al usuario.
    select count(*) into v_cnt
      from all_source
     where owner = 'WKSP_SYPEXWS' and type = 'PACKAGE BODY'
       and upper(text) like '%SQLERRM%'
       and lower(text) not like '%p_detalle%';
    if v_cnt > 0 then
        falla('C1', v_cnt || ' lineas de body usan SQLERRM fuera del log');
    end if;

    -- C2
    select count(*) into v_cnt
      from all_source
     where owner = 'WKSP_SYPEXWS' and type = 'TRIGGER'
       and upper(text) like '%CLIENT_INFO%';
    if v_cnt > 0 then
        falla('C2', v_cnt || ' lineas de trigger mencionan CLIENT_INFO');
    end if;

    -- C3
    declare
        v_id   number;
        v_est  varchar2(50);
        v_obs  varchar2(4000);
    begin
        select min(id_presupuesto) into v_id from presupuestos where estado = 'FACTURADO';
        if v_id is null then
            falla('C3', 'no hay presupuestos FACTURADOS para probar');
        else
            begin
                pkg_presupuestos.prc_cancelar_presupuesto(
                    p_id_presupuesto => v_id, p_usuario => 'zz_test',
                    p_nuevo_estado => v_est, p_nuevas_obs => v_obs);
                falla('C3', 'cancelar un FACTURADO no dio error');
            exception
                when others then
                    if sqlcode <> -20070 then
                        falla('C3', 'se esperaba -20070 y llego ' || sqlcode);
                    end if;
                    if instr(lower(sqlerrm), 'pkg_') > 0
                       or instr(upper(sqlerrm), 'CLIENT_INFO') > 0 then
                        falla('C3', 'el mensaje tiene jerga: ' || sqlerrm);
                    end if;
                    if instr(sqlerrm, 'ORA-', 6) > 0 then
                        falla('C3', 'el mensaje viene duplicado: ' || sqlerrm);
                    end if;
            end;
        end if;
    end;

    rollback;

    -- C4
    declare
        v_fact number;
        v_det  number;
    begin
        select min(f.id_factura), min(d.id_detalle)
          into v_fact, v_det
          from facturas f
          join facturas_det d on d.id_factura = f.id_factura
         where f.estado = 'PAGADA';
        if v_fact is null then
            falla('C4', 'no hay facturas PAGADAS con detalle');
        else
            begin
                pkg_factura_detalle.eliminar_detalle(v_fact, v_det);
                falla('C4', 'borrar una linea de una PAGADA no dio error');
            exception
                when others then
                    if sqlcode <> -20002 then
                        falla('C4', 'se esperaba -20002 y llego ' || sqlcode);
                    end if;
                    if instr(sqlerrm, 'ORA-', 6) > 0 then
                        falla('C4', 'el mensaje viene duplicado: ' || sqlerrm);
                    end if;
                    if instr(lower(sqlerrm), 'documento cerrado') = 0 then
                        falla('C4', 'el mensaje no explica que es un documento cerrado: ' || sqlerrm);
                    end if;
            end;
        end if;
    end;

    rollback;

    -- C5: la escotilla sigue viva.
    declare
        v_id number;
    begin
        select min(id_presupuesto) into v_id from presupuestos where estado = 'FACTURADO';
        if v_id is not null then
            dbms_application_info.set_client_info('SYPEX_FORZAR_ESTADO');
            begin
                update presupuestos set estado = 'CANCELADO' where id_presupuesto = v_id;
                if sql%rowcount <> 1 then
                    falla('C5', 'la escotilla no dejo actualizar');
                end if;
            exception
                when others then
                    falla('C5', 'la escotilla ya no funciona: ' || sqlerrm);
            end;
            dbms_application_info.set_client_info(null);
            rollback;
        end if;
    end;

    -- C6
    select count(distinct name) into v_cnt
      from all_source
     where owner = 'WKSP_SYPEXWS' and type = 'PACKAGE BODY'
       and name in ('PKG_FACTURACION', 'PKG_PRESUPUESTOS',
                    'PKG_PRESUPUESTO_DETALLE', 'PKG_FACTURA_DETALLE')
       and lower(text) like '%prc_log_error%';
    if v_cnt <> 4 then
        falla('C6', 'solo ' || v_cnt || ' de 4 bodies dejan el detalle en el log');
    end if;

    -- C7
    select count(*) into v_cnt
      from all_objects
     where owner = 'WKSP_SYPEXWS' and status <> 'VALID'
       and object_type in ('FUNCTION', 'PROCEDURE', 'PACKAGE', 'PACKAGE BODY',
                           'TRIGGER', 'VIEW');
    if v_cnt > 0 then
        falla('C7', v_cnt || ' objetos INVALID en el esquema');
    end if;

    cierra;
end;
/
