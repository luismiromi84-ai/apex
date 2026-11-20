-- =============================================================================
-- 20261119_islr_conceptos_seed.sql
--
-- Siembra el catalogo de conceptos de retencion de ISLR.
--
-- QUE HABIA: ISLR_CONCEPTOS vacia (la creo 20261119_retenciones_iva_islr.sql).
-- Sin catalogo no se puede calcular el ISLR: el comprobante exige el codigo de
-- concepto del SENIAT, la actividad, la tarifa y el sustraendo en unidades
-- tributarias, y una tarifa o un sustraendo mal puestos son dinero mal retenido
-- en cada compra.
--
-- QUE HACE ESTA MIGRACION: siembra las 16 filas de la tabla oficial (Decreto
-- 1.808, G.O. 43.140, UT = 43 Bs):
--   - los 13 conceptos de TARIFA PLANA de uso habitual, ACTIVO = 'S':
--     002 y 003 honorarios profesionales, 018 y 019 comisiones mercantiles,
--     053/054/055 servicios, 057/058/059 arrendamiento de inmuebles y
--     061/062/063 arrendamiento de muebles;
--   - los 3 que NO son un porcentaje plano, ACTIVO = 'N' para que se vean pero
--     no se puedan elegir: 040 (primas de seguro, 30 % del ingreso neto) y 065 y
--     067 (tarjetas de credito, base por formula de tramos de UT).
--
-- POR QUE SOLO ESTOS: el dueno aprobo sembrar primero los 13 confirmados. El
-- resto de conceptos de tarifa plana del PDF (fletes, publicidad, regalias,
-- asistencia tecnica, intereses, premios...) NO se siembra aqui: espera su
-- revision de la lista completa. Cuando la apruebe se agregan a este mismo
-- MERGE, sin tocar el modelo.
--
-- VALORES: base %, tarifa y sustraendo salen del PDF
-- (libreria/tabla-de-retenciones-del-islr-ut-43-2025.pdf). El sustraendo va en
-- UT con 4 decimales porque la tabla lo imprime en bolivares y hay que poder
-- volver a la UT exacta: 107,50 / 43 = 2,5 y 35,83 / 43 = 0,8333 (guardar 0,83
-- daria 35,69 Bs en vez de 35,83).
--
-- TIPO_PERSONA / DOMICILIADO son informativos y salen de la variante de cada
-- codigo en la tabla (natural o juridica, domiciliada o no): 053 es la variante
-- de persona juridica domiciliada (J/S) y 054 la de natural domiciliada (N/S).
-- Los tres inactivos van con NULL: la tabla no trae variante para ellos.
--
-- ACTIVIDAD repite la descripcion: el comprobante imprime la actividad y el
-- origen no trae una lista de actividades aparte.
--
-- Las descripciones van en mayusculas y sin acentos a proposito (la base no es
-- AL32UTF8).
--
-- Idempotente: MERGE por CODIGO. Re-ejecutarla no duplica y vuelve a dejar los
-- valores de la tabla (si alguien los toco por SQL, los corrige).
--
-- Se valida sola: antes de compilar contrasta las 16 filas contra la tabla
-- oficial con sus cuatro numeros (base %, tarifa, sustraendo en UT y bandera) y
-- cuenta los 13 activos SOLO entre esas 16, para que sumar mas conceptos en otra
-- migracion no la haga abortar. Despues de compilar solo vigila que no queden
-- objetos invalidos.
--
-- Requiere: 20261119_retenciones_iva_islr.sql (crea ISLR_CONCEPTOS).
--
-- Reversa (primero se sueltan las referencias: las dos FK al catalogo bloquean
-- el delete con ORA-02292 si alguna compra o proveedor ya lo usa):
--   update compras set id_concepto_islr = null
--    where id_concepto_islr in (select id_concepto from islr_conceptos
--                                where codigo in ('002','003','018','019','040',
--                                                 '053','054','055','057','058',
--                                                 '059','061','062','063','065','067'));
--   update proveedores set id_concepto_islr = null
--    where id_concepto_islr in (select id_concepto from islr_conceptos
--                                where codigo in ('002','003','018','019','040',
--                                                 '053','054','055','057','058',
--                                                 '059','061','062','063','065','067'));
--   delete from islr_conceptos
--    where codigo in ('002','003','018','019','040','053','054','055','057',
--                     '058','059','061','062','063','065','067');
--
-- Verificacion: deploy/diagnostico/20261119_retenciones_verificacion.sql (R1b)
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

merge into islr_conceptos t
using (
    -- Honorarios profesionales (9.1)
    select '002' as codigo, '9.1.b' as numeral,
           'HONORARIOS PROFESIONALES' as descripcion,
           100 as base_pct, 3 as tarifa, 2.5 as sustraendo_ut,
           'J' as tipo_persona, 'S' as domiciliado, 'S' as activo
      from dual
    union all
    select '003', '9.1.a', 'HONORARIOS PROFESIONALES',
           90, 34, 0, 'N', 'S', 'S' from dual
    -- Comisiones mercantiles y otras (9.2.b)
    union all
    select '018', '9.2.b', 'COMISIONES MERCANTILES Y OTRAS',
           100, 3, 2.5, 'J', 'S', 'S' from dual
    union all
    select '019', '9.2.b', 'COMISIONES MERCANTILES Y OTRAS',
           100, 34, 0, 'N', 'S', 'S' from dual
    -- Servicios (9.11)
    union all
    select '053', '9.11', 'SERVICIOS',
           100, 1, 0.8333, 'J', 'S', 'S' from dual
    union all
    select '054', '9.11', 'SERVICIOS',
           100, 34, 0, 'N', 'S', 'S' from dual
    union all
    select '055', '9.11', 'SERVICIOS',
           100, 2, 0, 'J', 'N', 'S' from dual
    -- Arrendamiento de bienes inmuebles (9.12)
    union all
    select '057', '9.12', 'ARRENDAMIENTO BIENES INMUEBLES',
           100, 3, 2.5, 'J', 'S', 'S' from dual
    union all
    select '058', '9.12', 'ARRENDAMIENTO BIENES INMUEBLES',
           100, 34, 0, 'N', 'S', 'S' from dual
    union all
    select '059', '9.12', 'ARRENDAMIENTO BIENES INMUEBLES',
           100, 5, 0, 'J', 'N', 'S' from dual
    -- Arrendamiento de bienes muebles (9.13)
    union all
    select '061', '9.13', 'ARRENDAMIENTO BIENES MUEBLES',
           100, 3, 2.5, 'J', 'S', 'S' from dual
    union all
    select '062', '9.13', 'ARRENDAMIENTO BIENES MUEBLES',
           100, 34, 0, 'N', 'S', 'S' from dual
    union all
    select '063', '9.13', 'ARRENDAMIENTO BIENES MUEBLES',
           100, 5, 0, 'J', 'N', 'S' from dual
    -- Formula especial: se siembran inactivos (no se pueden elegir)
    union all
    select '040', '9.8', 'PRIMAS DE SEGURO (requiere captura manual)',
           30, 10, 0, null, null, 'N' from dual
    union all
    select '065', '9.14', 'TARJETAS DE CREDITO (requiere captura manual)',
           100, 3, 0, null, null, 'N' from dual
    union all
    select '067', '9.14', 'TARJETAS DE CREDITO (requiere captura manual)',
           100, 5, 0, null, null, 'N' from dual
) s
on (t.codigo = s.codigo)
-- OJO: el SET va en la misma linea del UPDATE. importar_export.py descarta toda
-- linea que empiece por "set " y el MERGE se quedaria sin el SET (ORA-00971).
when matched then update set
    t.numeral       = s.numeral,
    t.descripcion   = s.descripcion,
    t.actividad     = s.descripcion,
    t.base_pct      = s.base_pct,
    t.tarifa        = s.tarifa,
    t.sustraendo_ut = s.sustraendo_ut,
    t.tipo_persona  = s.tipo_persona,
    t.domiciliado   = s.domiciliado,
    t.activo        = s.activo
when not matched then
    insert (codigo, numeral, descripcion, actividad, base_pct, tarifa,
            sustraendo_ut, tipo_persona, domiciliado, activo)
    values (s.codigo, s.numeral, s.descripcion, s.descripcion, s.base_pct,
            s.tarifa, s.sustraendo_ut, s.tipo_persona, s.domiciliado, s.activo)
/

-- Comprobacion de los DATOS, ANTES de compilar: si alguna fila no quedo como la
-- tabla oficial, el script corta aqui y el MERGE no llega a persistirse (el
-- runner solo commitea si todas las sentencias pasan; al abortar, la conexion se
-- cierra y el MERGE se descarta). Ojo con lo que esto NO es: no es una garantia
-- de rollback en general. La proteccion de fondo es que el seed es idempotente
-- (si una corrida falla, se corrige y se vuelve a ejecutar, y el MERGE deja los
-- valores de la tabla) y que esta validacion es una red contra un valor mal
-- puesto, no un sustituto del commit.
declare
    v_n number;
begin
    -- Las 16 filas de la tabla oficial, ninguna de mas ni de menos
    select count(*) into v_n from islr_conceptos
     where codigo in ('002','003','018','019','040','053','054','055','057',
                      '058','059','061','062','063','065','067');
    if v_n <> 16 then
        raise_application_error(-20112, 'el catalogo tiene ' || v_n || ' de 16 conceptos');
    end if;

    -- LA RED: las 16 filas contrastadas contra la tabla oficial, una por una, con
    -- sus cuatro numeros (base %, tarifa, sustraendo en UT y bandera). Un typo en
    -- BASE_PCT multiplica TODA la retencion de esa compra y no lo caza ninguna
    -- otra prueba: los dos unicos valores distintos de 100 son el 90 del 003 y el
    -- 30 del 040. Lo mismo con las tarifas que no se usan a diario (34 % del 003,
    -- 019, 054, 058 y 062; 2 % del 055; 5 % del 059, 063 y 067).
    --
    -- Va por codigo y no por "cuantas filas hay": si manana otra migracion suma
    -- mas conceptos al catalogo, esta comparacion sigue midiendo solo las 16 de
    -- este seed.
    select count(*) into v_n
      from (
            select '002' as codigo, 100 as base_pct,  3 as tarifa, 2.5    as sustraendo_ut, 'S' as activo from dual
            union all select '003',  90, 34, 0,     'S' from dual
            union all select '018', 100,  3, 2.5,   'S' from dual
            union all select '019', 100, 34, 0,     'S' from dual
            union all select '040',  30, 10, 0,     'N' from dual
            union all select '053', 100,  1, 0.8333,'S' from dual
            union all select '054', 100, 34, 0,     'S' from dual
            union all select '055', 100,  2, 0,     'S' from dual
            union all select '057', 100,  3, 2.5,   'S' from dual
            union all select '058', 100, 34, 0,     'S' from dual
            union all select '059', 100,  5, 0,     'S' from dual
            union all select '061', 100,  3, 2.5,   'S' from dual
            union all select '062', 100, 34, 0,     'S' from dual
            union all select '063', 100,  5, 0,     'S' from dual
            union all select '065', 100,  3, 0,     'N' from dual
            union all select '067', 100,  5, 0,     'N' from dual
           ) e
      join islr_conceptos c on c.codigo = e.codigo
     where c.base_pct      = e.base_pct
       and c.tarifa        = e.tarifa
       and c.sustraendo_ut = e.sustraendo_ut
       and c.activo        = e.activo;
    if v_n <> 16 then
        raise_application_error(-20112, 'solo ' || v_n
            || ' de 16 conceptos coinciden con la tabla oficial (base, tarifa, sustraendo o activo)');
    end if;

    -- Los 13 activos, contados SOLO entre los 16 de este seed. Sin el filtro por
    -- codigo, el dia que otra migracion agregue los conceptos que faltan esta
    -- validacion abortaria con "hay N conceptos activos" aunque el catalogo este
    -- bien.
    select count(*) into v_n from islr_conceptos
     where codigo in ('002','003','018','019','040','053','054','055','057',
                      '058','059','061','062','063','065','067')
       and activo = 'S';
    if v_n <> 13 then
        raise_application_error(-20112, 'hay ' || v_n || ' de 16 conceptos activos (esperado 13)');
    end if;

    select count(*) into v_n from islr_conceptos
     where codigo in ('040','065','067') and activo = 'N';
    if v_n <> 3 then
        raise_application_error(-20112, 'los conceptos con formula no quedaron inactivos');
    end if;

    -- El sustraendo es lo que mas caro sale si se redondea: 0,83 UT en vez de
    -- 0,8333 son 35,69 Bs en vez de 35,83 en cada compra al 1 %.
    select count(*) into v_n from islr_conceptos
     where codigo = '053' and tarifa = 1 and abs(sustraendo_ut - 0.8333) < 0.0001;
    if v_n <> 1 then
        raise_application_error(-20112, 'el concepto 053 no quedo con 1 % y 0,8333 UT');
    end if;

    select count(*) into v_n from islr_conceptos
     where codigo in ('002','018','057','061') and tarifa = 3 and sustraendo_ut = 2.5;
    if v_n <> 4 then
        raise_application_error(-20112, 'los conceptos al 3 % no quedaron con 2,5 UT de sustraendo');
    end if;
end;
/

-- Compilar es DDL y commitea por su cuenta, asi que va DESPUES de la validacion
-- de los datos (si fuera antes, un dato malo se reportaria con las 16 filas ya
-- persistidas). Aqui solo se vigila que la compilacion no haya dejado nada
-- invalido.
begin
    dbms_utility.compile_schema('WKSP_SYPEXWS', false);
end;
/

declare
    v_in number;
begin
    select count(*) into v_in from all_objects
     where owner = 'WKSP_SYPEXWS' and status = 'INVALID';
    if v_in > 0 then
        raise_application_error(-20112, 'quedaron ' || v_in || ' objetos invalidos');
    end if;
end;
/

commit;
/
