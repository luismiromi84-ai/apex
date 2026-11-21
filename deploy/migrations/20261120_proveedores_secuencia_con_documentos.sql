-- =============================================================================
-- 20261120_proveedores_secuencia_con_documentos.sql
--
-- La numeracion de PROVEEDORES volvio a quedar con huecos: las pruebas de
-- navegador dan de alta un proveedor y lo borran, y la identidad (global) no se
-- devuelve. Medido el 2026-11-20: 3 filas con id 1, 2 y 391.
--
-- Diferencia con 20261118_proveedores_secuencia.sql: aquella aborta si existe
-- CUALQUIER compra, porque renumerar cambiaria documentos ya emitidos. Aqui:
--   * solo se mueven los proveedores cuyo id no coincide con su posicion
--     (los que estan en su sitio NO se tocan, asi la FK de COMPRAS y
--     RETENCIONES no se rompe);
--   * y se aborta solo si alguno de los que se mueven tiene documentos.
--
-- Pasos: (1) ver si hay algo que hacer y si es seguro; (2) los que se mueven a
-- negativo, en una transaccion; (3) a su posicion 1..n, en otra; (4) reiniciar
-- la identidad; (5) validar; (6) recompilar (el ALTER de la identidad deja
-- INVALIDOS pkg_compras y pkg_retenciones).
--
-- Idempotente: si max(id) = count(*) y min = 1, no hace nada.
-- OJO: el SET va en la misma linea del UPDATE (el runner descarta las lineas que
--      empiezan por "set ") y los dos UPDATE van con commit en medio (ORA-12860).
-- Reversa: no aplica (los id viejos no se recuperan).
-- Verificacion: deploy/diagnostico/20261118_correlativos_verificacion.sql (P1, P2)
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

-- Paso 1: que hay que hacer y si es seguro
declare
    v_cnt     number;
    v_max     number;
    v_min     number;
    v_neg     number;
    v_mueven  number;
    v_docs    number;
begin
    select count(*), nvl(max(id_proveedor), 0), nvl(min(id_proveedor), 0),
           count(case when id_proveedor < 0 then 1 end)
      into v_cnt, v_max, v_min, v_neg from proveedores;

    if v_cnt = 0 or (v_max = v_cnt and v_min = 1 and v_neg = 0) then
        dbms_output.put_line('proveedores ya en secuencia: nada que hacer');
        return;
    end if;

    -- proveedores cuyo id no coincide con su posicion en el orden actual
    select count(*) into v_mueven
      from (select id_proveedor, row_number() over (order by id_proveedor) rn
              from proveedores)
     where id_proveedor <> rn;

    if v_mueven > 0 and v_neg = 0 then
        select count(*) into v_docs
          from compras co
         where co.id_proveedor in (select id_proveedor
                                     from (select id_proveedor,
                                                  row_number() over (order by id_proveedor) rn
                                             from proveedores)
                                    where id_proveedor <> rn);
        select v_docs + count(*) into v_docs
          from retenciones r
         where r.id_proveedor in (select id_proveedor
                                    from (select id_proveedor,
                                                 row_number() over (order by id_proveedor) rn
                                            from proveedores)
                                   where id_proveedor <> rn);
        if v_docs > 0 then
            raise_application_error(-20107,
                'Hay ' || v_docs || ' documento(s) de proveedores que habria que renumerar: '
                || 'renumerar cambiaria documentos ya emitidos. Revisar a mano.');
        end if;
    end if;
end;
/

-- Paso 2: SOLO los que se mueven, a negativo (transaccion aparte).
-- Los que ya estan en su sitio no se tocan: sus compras y retenciones siguen
-- apuntando a un id que existe en todo momento.
declare
    v_movidos number;
    v_neg     number;
begin
    select count(case when id_proveedor < 0 then 1 end) into v_neg from proveedores;
    if v_neg > 0 then
        dbms_output.put_line('ya hay ids negativos: se salta este paso');
        return;
    end if;
    update proveedores p set id_proveedor = -p.id_proveedor
     where p.id_proveedor > 0
       and p.id_proveedor <> (select q.rn
                                from (select id_proveedor,
                                             row_number() over (order by id_proveedor) rn
                                        from proveedores) q
                               where q.id_proveedor = p.id_proveedor);
    v_movidos := sql%rowcount;
    commit;
    dbms_output.put_line('proveedores movidos a negativo: ' || v_movidos);
end;
/

-- Paso 3: cada negativo toma su posicion 1..n (transaccion aparte).
-- Fila a fila y sin subconsulta en el SET: con el UPDATE de una sola sentencia
-- esta ADB lo manda a un servidor paralelo y la comprobacion de la FK de
-- COMPRAS revienta con ORA-12801/ORA-02292 (medido el 2026-11-20).
declare
    v_pend number;
    v_rn   number;
begin
    select count(*) into v_pend from proveedores where id_proveedor < 0;
    if v_pend = 0 then
        dbms_output.put_line('no hay ids negativos: se salta este paso');
        return;
    end if;
    for r in (select id_proveedor from proveedores
               where id_proveedor < 0 order by abs(id_proveedor)) loop
        select count(*) into v_rn
          from proveedores
         where abs(id_proveedor) <= abs(r.id_proveedor);
        update proveedores set id_proveedor = v_rn
         where id_proveedor = r.id_proveedor;
    end loop;
    commit;
end;
/

-- Paso 4: la identidad continua en el maximo actual + 1
alter table proveedores modify id_proveedor generated by default on null as identity
    (start with limit value)
/

-- Paso 5: validacion
declare
    v_cnt number;
    v_max number;
    v_min number;
begin
    select count(*), max(id_proveedor), min(id_proveedor)
      into v_cnt, v_max, v_min from proveedores;
    if v_cnt > 0 and (v_max <> v_cnt or v_min <> 1) then
        raise_application_error(-20108,
            'los proveedores quedaron de ' || v_min || ' a ' || v_max || ' con ' || v_cnt || ' filas');
    end if;
end;
/

-- Paso 6: recompilar y comprobar 0 invalidos
declare
    v_n number;
begin
    dbms_utility.compile_schema('WKSP_SYPEXWS', false);
    select count(*) into v_n from all_objects
     where owner = 'WKSP_SYPEXWS' and status = 'INVALID';
    if v_n > 0 then
        raise_application_error(-20109, 'quedaron ' || v_n || ' objeto(s) INVALID');
    end if;
end;
/
