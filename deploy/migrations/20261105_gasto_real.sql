-- =============================================================================
-- 20261105_gasto_real.sql
--
-- **OJO (2026-11-23): este archivo es HISTORICO y ya NO se puede ejecutar tal
-- cual.** Usa `fn_tasa_cambio`, que se elimino ese dia; la version vigente del
-- paquete, que convierte con `fn_tasa_ves` (bolivares por unidad), esta en
-- `deploy/migrations/20261106_gasto_real_factor_usd.sql` y en
-- `package_bodies/pkg_gasto_real.sql`. Se conserva como evidencia del 2026-11-05.
-- Para crear el paquete hoy: `deploy/install_bodies.sql`.
--
-- Objetivo: poner en marcha la tabla GASTO_REAL, que estaba declarada y muerta
--           (0 filas, 0 referencias en todo el codigo).
--
-- Que hace:
--   1. PAQUETE PKG_GASTO_REAL: alta/edicion con validaciones, baja, y total
--      gastado por presupuesto en USD. La conversion usa FN_TASA_CAMBIO y se
--      puede forzar la tasa desde fuera (p_tasa_real).
--   2. GASTO_REAL.ID_PRESUPUESTO pasa a NOT NULL y gana FK a PRESUPUESTOS.
--   3. VISTA V_PRESUPUESTO_REAL: presupuestado, gastado, desviacion y porcentaje
--      ejecutado, por presupuesto.
--
-- Afecta a: GASTO_REAL (dos restricciones) y tres objetos nuevos. No toca datos
--           (la tabla esta vacia).
--
-- Idempotente: el paquete y la vista se recrean; las restricciones se comprueban.
--
-- Ejecutar:
--   python deploy/conexion/importar_export.py deploy/migrations/20261105_gasto_real.sql
--
-- REVERSA:
--   drop view v_presupuesto_real;
--   alter table gasto_real drop constraint fk_gasto_presupuesto;
--   alter table gasto_real modify (id_presupuesto null);
--   drop package pkg_gasto_real;
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;
/

create or replace PACKAGE pkg_gasto_real AS
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

create or replace PACKAGE BODY pkg_gasto_real AS

    PROCEDURE prc_guardar_gasto (
        p_id_gasto        IN OUT NUMBER,
        p_id_presupuesto  IN  NUMBER,
        p_fecha_gasto     IN  DATE,
        p_monto_origen    IN  NUMBER,
        p_moneda_origen   IN  VARCHAR2,
        p_tasa_real       IN  NUMBER   DEFAULT NULL,
        p_usuario         IN  VARCHAR2 DEFAULT NULL
    ) IS
        v_moneda varchar2(5);
        v_tasa   number;
        v_usd    number;
        v_existe number;
    begin
        if p_id_presupuesto is null then
            raise_application_error(-20040, 'El gasto necesita un presupuesto.');
        end if;

        if p_monto_origen is null or p_monto_origen <= 0 then
            raise_application_error(-20041, 'El monto del gasto debe ser mayor que cero.');
        end if;

        select count(*) into v_existe
          from presupuestos where id_presupuesto = p_id_presupuesto;

        if v_existe = 0 then
            raise_application_error(-20042, 'El presupuesto no existe.');
        end if;

        if p_usuario is not null and not fn_presupuesto_propio(p_id_presupuesto, p_usuario) then
            raise_application_error(-20003, 'No tiene permisos sobre este documento.');
        end if;

        v_moneda := upper(nvl(p_moneda_origen, 'USD'));

        if v_moneda = 'USD' then
            v_tasa := 1;
        else
            v_tasa := nvl(p_tasa_real,
                          fn_tasa_cambio(nvl(p_fecha_gasto, sysdate), v_moneda));
        end if;

        v_usd := round(p_monto_origen * nvl(v_tasa, 1), 2);

        if p_id_gasto is null then
            insert into gasto_real (id_presupuesto, fecha_gasto, monto_origen,
                                    moneda_origen, tasa_real, monto_base_usd)
            values (p_id_presupuesto, nvl(p_fecha_gasto, sysdate), p_monto_origen,
                    v_moneda, nvl(v_tasa, 1), v_usd)
            returning id_gasto into p_id_gasto;
        else
            update gasto_real set
                   id_presupuesto = p_id_presupuesto,
                   fecha_gasto    = nvl(p_fecha_gasto, sysdate),
                   monto_origen   = p_monto_origen,
                   moneda_origen  = v_moneda,
                   tasa_real      = nvl(v_tasa, 1),
                   monto_base_usd = v_usd
             where id_gasto = p_id_gasto;

            if sql%rowcount = 0 then
                raise_application_error(-20043, 'El gasto no existe.');
            end if;
        end if;
    end prc_guardar_gasto;

    PROCEDURE prc_eliminar_gasto (
        p_id_gasto IN NUMBER,
        p_usuario  IN VARCHAR2 DEFAULT NULL
    ) IS
        v_presupuesto number;
    begin
        select id_presupuesto into v_presupuesto
          from gasto_real where id_gasto = p_id_gasto;

        if p_usuario is not null and not fn_presupuesto_propio(v_presupuesto, p_usuario) then
            raise_application_error(-20003, 'No tiene permisos sobre este documento.');
        end if;

        delete from gasto_real where id_gasto = p_id_gasto;

    exception
        when no_data_found then
            raise_application_error(-20043, 'El gasto no existe.');
    end prc_eliminar_gasto;

    FUNCTION fn_total_gasto_usd (p_id_presupuesto IN NUMBER) RETURN NUMBER IS
        v_total number;
    begin
        select nvl(sum(monto_base_usd), 0) into v_total
          from gasto_real
         where id_presupuesto = p_id_presupuesto;

        return v_total;
    end fn_total_gasto_usd;

END pkg_gasto_real;
/

create or replace view v_presupuesto_real as
select p.id_presupuesto,
       p.id_empresa,
       p.folio,
       p.estado,
       p.cod_moneda,
       nvl(p.total, 0)                                   as presupuestado_usd,
       nvl(g.gasto_usd, 0)                               as gasto_real_usd,
       nvl(p.total, 0) - nvl(g.gasto_usd, 0)             as desviacion_usd,
       case when nvl(p.total, 0) > 0
            then round(nvl(g.gasto_usd, 0) / p.total * 100, 2)
       end                                               as pct_ejecutado
  from presupuestos p
  left join (select id_presupuesto, sum(monto_base_usd) as gasto_usd
               from gasto_real
              group by id_presupuesto) g
    on g.id_presupuesto = p.id_presupuesto;
/

declare
    v_existe number;
begin
    select count(*) into v_existe from all_tab_cols
     where owner='WKSP_SYPEXWS' and table_name='GASTO_REAL'
       and column_name='ID_PRESUPUESTO' and nullable='Y';
    if v_existe = 1 then
        execute immediate 'alter table gasto_real modify (id_presupuesto not null)';
    end if;

    select count(*) into v_existe from all_constraints
     where owner='WKSP_SYPEXWS' and table_name='GASTO_REAL'
       and constraint_name='FK_GASTO_PRESUPUESTO';
    if v_existe = 0 then
        execute immediate 'alter table gasto_real add constraint fk_gasto_presupuesto '
                       || 'foreign key (id_presupuesto) references presupuestos (id_presupuesto)';
    end if;

    dbms_utility.compile_schema(schema => 'WKSP_SYPEXWS', compile_all => false);
end;
/

-- -----------------------------------------------------------------------------
-- Validaciones: todo debe devolver cero filas o los valores esperados
-- -----------------------------------------------------------------------------
select 'FALLA: PKG_GASTO_REAL invalido' as caso from dual
 where not exists (select 1 from all_objects
                    where owner='WKSP_SYPEXWS' and object_name='PKG_GASTO_REAL'
                      and object_type='PACKAGE BODY' and status='VALID');
/

select 'FALLA: falta la vista V_PRESUPUESTO_REAL' as caso from dual
 where not exists (select 1 from all_objects
                    where owner='WKSP_SYPEXWS' and object_name='V_PRESUPUESTO_REAL'
                      and status='VALID');
/

select 'FALLA: falta FK_GASTO_PRESUPUESTO' as caso from dual
 where not exists (select 1 from all_constraints
                    where owner='WKSP_SYPEXWS' and table_name='GASTO_REAL'
                      and constraint_name='FK_GASTO_PRESUPUESTO' and status='ENABLED');
/

select 'FALLA: hay objetos invalidos' as caso
  from all_objects
 where owner='WKSP_SYPEXWS' and status <> 'VALID'
   and object_type in ('FUNCTION','PROCEDURE','PACKAGE','PACKAGE BODY','TRIGGER','VIEW');
/
