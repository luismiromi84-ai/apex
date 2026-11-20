-- =============================================================================
-- 20261119_retenciones_verificacion.sql
--
-- Comprobantes de retencion de IVA e ISLR: modelo cabecera/detalle.
--
-- El comprobante de IVA vivia en una tabla plana (RETENCIONES_IVA, 1:1 con la
-- compra) y no habia nada de ISLR. El modelo nuevo es una cabecera
-- (RETENCIONES) con lineas (RETENCIONES_DET), sirve a los dos tipos y guarda en
-- la LINEA la foto del calculo (base %, tarifa, sustraendo en UT, valor de la UT
-- y sustraendo en bolivares): asi el papel reimpreso no se mueve si manana
-- cambia la UT o se corrige un concepto.
--
-- Casos (se van agregando por tarea):
--   R1   las tres tablas existen, con sus dos unicos, las columnas en
--        compras/proveedores, la UT parametrizada en 43 y la precision de los
--        importes del detalle
--   R1a  las columnas del contrato, la identidad de las PK y las FK al catalogo
--   R1b  el catalogo de conceptos esta sembrado con la tabla oficial: los 13 de
--        tarifa plana activos, los 3 de formula especial inactivos y la tarifa y
--        el sustraendo en UT de tres conceptos contrastados uno a uno (un
--        sustraendo mal puesto es dinero mal retenido)
--   R2   el comprobante de IVA historico (RETENCIONES_IVA) se copio a RETENCIONES
--        con el mismo numero y las mismas cifras (base, IVA y retenido), y tiene
--        al menos una linea de la compra que respalda
--   R2b  la cabecera y las lineas conservan ademas fecha, periodo, estado, autor, el
--        total con IVA del documento y los datos de la factura del proveedor; cada
--        linea lleva una alicuota que existe de verdad en compras_det de esa compra
--        (no un promedio inventado) y las lineas suman la base y el IVA de la
--        cabecera
--   R3   la migracion no consumio numeracion: el contador de RETENCION_CONTADOR
--        sigue cuadrando con el ultimo numero emitido y con el valor que tenia al
--        empezar el script (no se compara contra 202611/1: esa constante deja de
--        ser cierta en cuanto se emite otro comprobante)
--   R4   una factura al 16 % con retencion del 75 % retiene 120,00 sobre 1.000 de
--        base, y el comprobante de IVA queda en RETENCIONES (no en la tabla vieja)
--   R4b  una compra en DIVISA deja la base y el impuesto del comprobante en
--        bolivares con la tasa del documento (100 + 16 USD al 900 = 90.000,00 y
--        14.400,00; el 75 % retiene 10.800,00)
--   R5   el motor de ISLR con el caso del cliente: 100 % de base y 5 % de tarifa
--        sin sustraendo sobre 1.067.106,36 Bs da 53.355,32 (el papel dice eso)
--   R5b  una compra en DIVISA: la base y el retenido van en bolivares, con la
--        tasa del documento (1.000 USD al 900 = 900.000,00 Bs -> 45.000,00).
--        Sin la tasa, cada compra en moneda extranjera retiene de menos
--   R6   la UT es parametrizable de verdad (se cambia SYN_PARAMETROS y la funcion
--        la sigue), el sustraendo en bolivares es 107,50 y el 3 % con sustraendo
--        de 2,5 UT da 31.905,69 (32.013,19 - 107,50), no un 3 % pelado
--   R6b  un concepto con base_pct distinto de 100: 003 (honorarios, 90 % y 34 %)
--        sobre la misma base da 960.395,72 y 326.534,54. Si el BASE_PCT se
--        ignorara saldria 362.816,16
--   R7   una base por debajo del sustraendo da 0, nunca un importe negativo
--        (un negativo en el comprobante es un abono al proveedor que nadie pidio)
--   R8   el concepto de ISLR se HEREDA del proveedor al dar de alta la compra, se
--        puede cambiar en la actualizacion, 0 lo borra, un concepto explicito gana
--        al del proveedor y **no pasar el parametro NO lo borra** (guardar un
--        borrador desde la pantalla vieja conserva el concepto). Sin la herencia,
--        cada factura de un proveedor con concepto nace sin ISLR; sin el centinela,
--        cada guardado la dejaba sin ISLR: el papel que falta solo se nota al
--        declarar
--   R9   registrar una factura con retencion de IVA y concepto de ISLR emite los
--        DOS comprobantes y consume DOS numeros consecutivos de la serie unica
--   R9b  la linea del comprobante de ISLR guarda la foto completa del calculo
--        (base %, tarifa, sustraendo en UT, valor de la UT y sustraendo en Bs)
--   R10  anular la compra deja los dos comprobantes ANULADO y les conserva el numero
--   R13  una factura con dos alicuotas (16 % y 8 %) deja DOS lineas, cada una con
--        su base y su IVA, y la cabecera suma las dos
--   R13b el redondeo por alicuota no descuadra la cabecera: la cabecera es el 75 %
--        del IVA total (dos lineas con IVA de 0,02: 0,03) y las lineas lo reparten
--        (0,01 + 0,02), asi que suman exactamente el papel
--   R14  registrar una nota de credito NO crea comprobante y NO mueve el contador
--   R15  una linea con IGTF no entra en la base ni en el IVA retenido
--   R16  ISLR por debajo del umbral (1.000 Bs con el concepto 057): no emite
--        comprobante de ISLR y NO consume numero (el contador sube 1, el del IVA)
--   R17  ninguna compra SIN concepto de ISLR tiene comprobante de ISLR (se mira el
--        bloque entero) y esas compras si tienen el suyo de IVA
--   R11  los dos papeles traen los campos de su formato, el de IVA es el que
--        imprime la Providencia SNAT/2025/000054 y devuelven NULL si no hay
--        comprobante de ese tipo (nunca un papel en blanco)
--   R11b la reimpresion NO recalcula: se cambia la UT y la tarifa del concepto en
--        el catalogo y el papel sigue mostrando las cifras con las que se emitio
--   R12  las pantallas del final: la 31 imprime el tipo que se le pide (los dos
--        comprobantes), la 28 deja elegir el concepto de ISLR y ofrece el segundo
--        boton, la etiqueta del estado dice Procesada SIN tocar el valor guardado
--        (de el dependen las condiciones de servidor, la emision y el libro) y el
--        guardado de la 28 manda el concepto con 0, nunca con nullif
--   R18  registrar o anular una compra de OTRA empresa lanza -20003 y no toca su
--        numeracion (C1 de la revision final); el usuario de la empresa duena si la
--        registra, asi que la guarda no es un "siempre falso"
--   R19  el resumen del BORRADOR (fn_retencion_bs) y el comprobante emitido dan el
--        MISMO retenido en una compra en DIVISA con dos alicuotas (I2), las lineas
--        suman la cabecera y ninguna linea con base queda en 0,00
--   R20  sin papel emitido (compra al 0 %) el boton «Imprimir comprobante» no sale:
--        depende de fn_compra_tiene_iva, no del estado (I3)
--   R21  el concepto de ISLR por defecto del proveedor se fija en la pagina 23
--        (item, carga, guardado con 0 -> null y lista de activos con tarifa) y la
--        compra lo hereda (I1)
--   R22  cambiar la tasa de un BORRADOR reprecia sus lineas (tasa, subtotal_bs y
--        total_bs): los dos comprobantes salen en la misma moneda (I4)
--
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261119_retenciones_verificacion.sql
-- FALLAS=0 = EXITO.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS
/

declare
    v_fallas number := 0;
    v_lista  varchar2(3000) := '';
    v_n      number;
    v_tar    number;
    v_sus    number;
    v_periodo     char(6);
    v_ultimo_ini  number;
    v_viejo       number;
    v_max         number;

    -- R5/R6/R7: compras de prueba y valores del motor de ISLR
    v_prov        number;
    v_usuario     varchar2(100);
    v_compra_gra  number;
    v_compra_chi  number;
    v_compra_usd  number;
    v_det         number;
    v_con_003     number;
    v_con_057     number;
    v_con_063     number;
    v_calc        number;
    v_ut          number;

    -- R4/R4b/R9/R10/R13/R14/R15: la emision y la anulacion
    v_e_id_iva    number;
    v_e_id_usd    number;
    v_e_id_islr   number;
    v_e_id_dos    number;
    v_e_id_igtf   number;
    v_e_id_cent   number;
    v_e_id_bajo   number;
    v_e_id_fac    number;
    v_e_id_nc     number;
    v_e_id_r11    number;
    v_r11_iva     varchar2(14);
    v_r11_islr    varchar2(14);
    v_r11_rif_pro varchar2(30);
    v_r11_rif_emp varchar2(30);
    v_html        clob;
    v_e_ret       number;
    v_e_ret2      number;
    v_e_num1      varchar2(14);
    v_e_num2      varchar2(14);
    v_e_cont      number;
    v_e_cont2     number;
    v_e_periodo   char(6);
    -- Caso en curso: si el bloque de la emision revienta, el fallo tiene que decir
    -- DONDE revento y no etiquetarlo todo como R4.
    v_caso_emi    varchar2(10) := 'R4';

    procedure falla(p_caso varchar2, p_detalle varchar2) is
    begin
        v_fallas := v_fallas + 1;
        v_lista  := v_lista || ' | ' || p_caso || ': ' || substrb(p_detalle, 1, 150);
    end;

    -- Alta de una compra de prueba de la emision. Folio y control explicitos para
    -- no consumir las series FAC_PROV / CONTROL_PROV del proveedor.
    -- p_concepto: se pasa TAL CUAL al parametro del package, para que el caso que mide
    -- el concepto (R9/R16) lo ejercite por el mismo camino que la pantalla y no con un
    -- UPDATE a mano por detras. El defecto -1 es "no lo mando".
    procedure crea_compra(p_folio    varchar2,
                          p_control  varchar2,
                          p_moneda   varchar2,
                          p_tasa     number,
                          p_pct      number,
                          p_id       out number,
                          p_concepto number default -1) is
    begin
        pkg_compras.prc_guardar_compra(
            p_id_compra            => p_id,
            p_id_empresa           => 1,
            p_id_proveedor         => v_prov,
            p_tipo_documento       => 'FAC',
            p_folio_factura        => p_folio,
            p_nro_control          => p_control,
            p_fecha_emision        => trunc(sysdate),
            p_cod_moneda           => p_moneda,
            p_tipo_cambio          => p_tasa,
            p_porcentaje_retencion => p_pct,
            p_id_concepto_islr     => p_concepto,
            p_usuario              => v_usuario);
    end;

    procedure crea_linea(p_compra number,
                         p_num    number,
                         p_desc   varchar2,
                         p_precio number,
                         p_imp    number,
                         p_pct    number) is
        v_det number;
    begin
        pkg_compra_detalle.guardar_detalle(
            p_id_detalle           => v_det,
            p_id_compra            => p_compra,
            p_num_linea            => p_num,
            p_id_producto_servicio => null,
            p_descripcion          => p_desc,
            p_cantidad             => 1,
            p_precio_unitario      => p_precio,
            p_porcentaje_descuento => 0,
            p_monto_descuento      => 0,
            p_id_impuesto          => p_imp,
            p_porcentaje_impuesto  => p_pct,
            p_usuario              => v_usuario);
    end;

    -- Un NULL concatenado deja el mensaje vacio justo cuando mas falta hace (el
    -- caso R5b/R6b que mide esto es precisamente el que puede devolver NULL).
    function num(p_valor number) return varchar2 is
    begin
        return nvl(to_char(p_valor), 'NULL');
    end;
begin
    -- Autolimpieza de las compras de prueba. Si una corrida anterior murio entre
    -- el borrado de las lineas y el de la compra, la compra se queda y el alta de
    -- esta corrida muere con -20080 (folio repetido): la suite se curaria sola y
    -- no bloquearia el resto para siempre. Hijo primero y con commit en medio
    -- (ORA-12860: hijo y padre no se borran en la misma transaccion en esta ADB).
    delete from compras_det
     where id_compra in (select id_compra from compras where folio_factura like 'ISLR-T4%');
    commit;
    delete from compras where folio_factura like 'ISLR-T4%';
    commit;

    -- Lo mismo con las compras de la emision (T5). Primero los comprobantes: la FK
    -- de RETENCIONES y RETENCIONES_DET a COMPRAS no deja borrar la compra mientras
    -- existan, y el borrado del hijo y del padre no va en la misma transaccion
    -- (ORA-12860). RETENCIONES_IVA solo se limpia por si una corrida anterior dejo
    -- ahi el comprobante que escribia el codigo viejo.
    delete from retenciones_det
     where id_compra in (select id_compra from compras where folio_factura like 'ISLR-T5%');
    commit;
    delete from retenciones
     where id_compra in (select id_compra from compras where folio_factura like 'ISLR-T5%');
    commit;
    delete from retenciones_iva
     where id_compra in (select id_compra from compras where folio_factura like 'ISLR-T5%');
    commit;
    delete from compras_det
     where id_compra in (select id_compra from compras where folio_factura like 'ISLR-T5%');
    commit;
    delete from compras where folio_factura like 'ISLR-T5%';
    commit;

    -- Las compras del cierre de la revision final (R18-R22), por el mismo motivo.
    delete from retenciones_det
     where id_compra in (select id_compra from compras where folio_factura like 'CIERRE-T8%');
    commit;
    delete from retenciones
     where id_compra in (select id_compra from compras where folio_factura like 'CIERRE-T8%');
    commit;
    delete from compras_det
     where id_compra in (select id_compra from compras where folio_factura like 'CIERRE-T8%');
    commit;
    delete from compras where folio_factura like 'CIERRE-T8%';
    commit;
    delete from proveedores where rif = 'CIERRE-T8-PROV';
    commit;

    -- R8 se lleva su propio proveedor y sus compras. Se limpia aqui porque ese bloque
    -- hace COMMIT (varias DML de identity en una transaccion dan ORA-12839): si una
    -- corrida anterior murio a medias, el RIF repetido tumbaria el alta de hoy y la
    -- suite no volveria a correr nunca. Las compras primero: la FK de compras a
    -- proveedores no deja borrar el proveedor mientras existan, y el borrado del hijo
    -- y del padre no va en la misma transaccion (ORA-12860). Los comprobantes van
    -- delante por si algun dia R8 registra una compra (hoy no lo hace).
    delete from retenciones_det
     where id_compra in (select id_compra from compras where folio_factura like 'ISLR-T6%');
    commit;
    delete from retenciones
     where id_compra in (select id_compra from compras where folio_factura like 'ISLR-T6%');
    commit;
    delete from compras_det
     where id_compra in (select id_compra from compras where folio_factura like 'ISLR-T6%');
    commit;
    delete from compras where folio_factura like 'ISLR-T6%';
    commit;
    delete from proveedores where id_empresa = 1 and rif = 'R8-ISLR-0001';
    commit;

    -- Proveedor de FIXTURE para todas las compras de prueba, con el concepto de ISLR
    -- NULO a proposito. Antes se tomaba el primer proveedor de la empresa 1, que es una
    -- fila REAL del cliente: desde que la compra hereda el concepto del proveedor, el
    -- dia que ese proveedor tenga uno, las compras de la emision emitirian un
    -- comprobante de ISLR que los casos no esperan y R16/R17 dejarian de medir lo que
    -- dicen medir (se pondrian rojos por datos del cliente, no por un defecto).
    delete from proveedores where id_empresa = 1 and rif = 'ISLR-T5-PROV';
    commit;
    insert into proveedores (id_empresa, rif, razon_social, tipo_persona, cod_pais,
                             estado, retener_iva, porcentaje_retencion, es_spe,
                             dias_credito, id_concepto_islr)
    values (1, 'ISLR-T5-PROV', 'Proveedor de prueba ISLR', 'J', 'VE',
            'ACTIVO', 'S', 75, 'N', 0, null)
    returning id_proveedor into v_prov;
    commit;

    -- El contador de retenciones tal como esta al empezar. R3 lo vuelve a leer al
    -- final: la migracion no puede consumir numeracion. Se lee de la tabla y no se
    -- escribe 202611/1 a proposito: ese es el estado de hoy y deja de ser cierto en
    -- cuanto se emite un comprobante mas.
    select nvl(max(periodo), to_char(sysdate, 'YYYYMM')) into v_periodo
      from retencion_contador;
    select nvl(max(ultimo), 0) into v_ultimo_ini
      from retencion_contador
     where periodo = v_periodo;

    -- R1: las tablas nuevas existen con sus unicos y las columnas en compras/proveedores
    select count(*) into v_n from all_tables
     where owner = 'WKSP_SYPEXWS' and table_name in ('ISLR_CONCEPTOS','RETENCIONES','RETENCIONES_DET');
    if v_n <> 3 then falla('R1', 'faltan tablas nuevas (' || v_n || ' de 3)'); end if;

    select count(*) into v_n from all_constraints
     where owner = 'WKSP_SYPEXWS' and table_name = 'RETENCIONES'
       and constraint_type = 'U'
       and constraint_name in ('UQ_RETENCIONES_NUMERO','UQ_RETENCIONES_COMPRA');
    if v_n <> 2 then falla('R1', 'faltan los unicos de RETENCIONES (' || v_n || ' de 2)'); end if;

    select count(*) into v_n from all_tab_columns
     where owner = 'WKSP_SYPEXWS' and column_name = 'ID_CONCEPTO_ISLR'
       and table_name in ('COMPRAS','PROVEEDORES');
    if v_n <> 2 then falla('R1', 'falta ID_CONCEPTO_ISLR en compras/proveedores'); end if;

    -- La UT no basta con que exista: con UT_ISLR = 1 el sustraendo de cada concepto
    -- se queda en 1 Bs y TODAS las retenciones de ISLR salen mal. El valor vigente
    -- lo fija el dueño (43,00 desde 2025, G.O. 43.140); si el SENIAT lo cambia se
    -- actualiza aqui y en tabla/syn_parametros.sql.
    select count(*) into v_n from syn_parametros where clave = 'UT_ISLR' and valor = 43;
    if v_n <> 1 then falla('R1', 'UT_ISLR no vale 43 en SYN_PARAMETROS'); end if;

    -- Precision de los importes del detalle: un number(10,2) o un (14,4) pasarian
    -- desapercibidos hoy y redondearian dinero al emitir.
    select count(*) into v_n from all_tab_columns
     where owner = 'WKSP_SYPEXWS' and table_name = 'RETENCIONES_DET' and data_type = 'NUMBER'
       and (   (column_name in ('TOTAL_CON_IVA_BS','BASE_IMPONIBLE_BS','RETENIDO_BS')
                and data_precision = 14 and data_scale = 2)
            or (column_name = 'SUSTRAENDO_UT' and data_scale = 4));
    if v_n <> 4 then
        falla('R1', 'precision de los importes del detalle (' || v_n || ' de 4 columnas)');
    end if;

    -- R1a: las columnas del contrato, la identidad de las PK y las FK al catalogo.
    -- Una tabla creada con las columnas cambiadas no revienta aqui: revienta en la
    -- tarea que la use, con un ORA-00904 lejos de la causa.
    select count(*) into v_n from all_tab_columns
     where owner = 'WKSP_SYPEXWS' and table_name = 'ISLR_CONCEPTOS'
       and column_name in ('ID_CONCEPTO','CODIGO','NUMERAL','DESCRIPCION','ACTIVIDAD',
                           'BASE_PCT','TARIFA','SUSTRAENDO_UT','TIPO_PERSONA','DOMICILIADO','ACTIVO');
    if v_n <> 11 then falla('R1a', 'ISLR_CONCEPTOS tiene ' || v_n || ' de 11 columnas'); end if;

    select count(*) into v_n from all_tab_columns
     where owner = 'WKSP_SYPEXWS' and table_name = 'RETENCIONES'
       and column_name in ('ID_RETENCION','ID_EMPRESA','ID_PROVEEDOR','TIPO','NUMERO_COMPROBANTE',
                           'FECHA_EMISION','PERIODO_ANIO','PERIODO_MES','ID_COMPRA','TOTAL_CON_IVA_BS',
                           'SIN_DERECHO_CREDITO_BS','BASE_IMPONIBLE_BS','IMPUESTO_BS','RETENIDO_BS',
                           'ID_CONCEPTO_ISLR','CODIGO_CONCEPTO','ACTIVIDAD','ESTADO','CREADO_POR',
                           'FECHA_CREACION');
    if v_n <> 20 then falla('R1a', 'RETENCIONES tiene ' || v_n || ' de 20 columnas'); end if;

    select count(*) into v_n from all_tab_columns
     where owner = 'WKSP_SYPEXWS' and table_name = 'RETENCIONES_DET'
       and column_name in ('ID_LINEA','ID_RETENCION','ID_COMPRA','FECHA_FACTURA','NRO_FACTURA',
                           'NRO_CONTROL','TIPO_DOCUMENTO','NRO_NOTA_DEBITO','NRO_NOTA_CREDITO',
                           'NRO_FACTURA_AFECTADA','TOTAL_CON_IVA_BS','SIN_DERECHO_CREDITO_BS',
                           'BASE_IMPONIBLE_BS','PORCENTAJE','IMPUESTO_BS','RETENIDO_BS','BASE_PCT',
                           'TARIFA','SUSTRAENDO_UT','VALOR_UT','SUSTRAENDO_BS');
    if v_n <> 21 then falla('R1a', 'RETENCIONES_DET tiene ' || v_n || ' de 21 columnas'); end if;

    -- la foto del calculo vive en la linea, no en la cabecera
    select count(*) into v_n from all_tab_columns
     where owner = 'WKSP_SYPEXWS' and table_name = 'RETENCIONES'
       and column_name in ('BASE_PCT','TARIFA','SUSTRAENDO_UT','VALOR_UT','SUSTRAENDO_BS');
    if v_n <> 0 then
        falla('R1a', 'la foto del calculo esta en la cabecera (' || v_n || ' columnas)');
    end if;

    select count(*) into v_n from all_tab_identity_cols
     where owner = 'WKSP_SYPEXWS' and table_name in ('ISLR_CONCEPTOS','RETENCIONES','RETENCIONES_DET');
    if v_n <> 3 then falla('R1a', 'las PK no son identity (' || v_n || ' de 3)'); end if;

    -- El detalle NO lleva unico: una factura con lineas al 16 % y al 8 % deja dos
    -- filas de la misma cabecera y de la misma compra (es el caso R13).
    select count(*) into v_n from all_constraints
     where owner = 'WKSP_SYPEXWS' and table_name = 'RETENCIONES_DET' and constraint_type = 'U';
    if v_n <> 0 then falla('R1a', 'RETENCIONES_DET no debe llevar unico (' || v_n || ')'); end if;

    -- La cabecera tiene que admitir ID_COMPRA nulo: es la puerta que deja consolidar
    -- varias facturas en un papel el dia que haga falta.
    select count(*) into v_n from all_tab_columns
     where owner = 'WKSP_SYPEXWS' and table_name = 'RETENCIONES'
       and column_name = 'ID_COMPRA' and nullable = 'Y';
    if v_n <> 1 then falla('R1a', 'RETENCIONES.ID_COMPRA tendria que admitir nulo'); end if;

    select count(*) into v_n
      from all_constraints c
     where c.owner = 'WKSP_SYPEXWS'
       and c.constraint_type = 'R'
       and c.table_name in ('COMPRAS','PROVEEDORES')
       and c.r_constraint_name = (select p.constraint_name
                                    from all_constraints p
                                   where p.owner = 'WKSP_SYPEXWS'
                                     and p.table_name = 'ISLR_CONCEPTOS'
                                     and p.constraint_type = 'P');
    if v_n <> 2 then
        falla('R1a', 'compras/proveedores no apuntan al catalogo ISLR (' || v_n || ' de 2)');
    end if;

    -- R1b: el catalogo sembrado con la tabla oficial. Sin conceptos no se puede
    -- calcular el ISLR (la tarea 4 lee de aqui) y sin el sustraendo correcto el
    -- importe retenido sale mal en cada compra.
    -- Los tres select de abajo van con MAX() y no con "select ... into" a secas:
    -- con el catalogo vacio un select into muere con ORA-01403 y se lleva por
    -- delante el RESULTADO entero, en vez de anotar el caso y seguir.
    select count(*) into v_n from islr_conceptos where activo = 'S';
    if v_n < 13 then falla('R1b', 'solo hay ' || v_n || ' conceptos activos (esperado >= 13)'); end if;

    select max(tarifa), max(sustraendo_ut) into v_tar, v_sus
      from islr_conceptos where codigo = '053';
    if v_tar is null then
        falla('R1b', 'no esta el concepto 053');
    elsif v_tar <> 1 or abs(v_sus - 0.8333) > 0.0001 then
        falla('R1b', '053 mal: tarifa ' || v_tar || ' sustraendo ' || v_sus);
    end if;

    select max(tarifa), max(sustraendo_ut) into v_tar, v_sus
      from islr_conceptos where codigo = '057';
    if v_tar is null then
        falla('R1b', 'no esta el concepto 057');
    elsif v_tar <> 3 or v_sus <> 2.5 then
        falla('R1b', '057 mal: tarifa ' || v_tar || ' sustraendo ' || v_sus);
    end if;

    select max(tarifa), max(sustraendo_ut) into v_tar, v_sus
      from islr_conceptos where codigo = '063';
    if v_tar is null then
        falla('R1b', 'no esta el concepto 063');
    elsif v_tar <> 5 or v_sus <> 0 then
        falla('R1b', '063 mal: tarifa ' || v_tar || ' sustraendo ' || v_sus);
    end if;

    -- Los tres conceptos con formula especial (primas de seguro y tarjetas de
    -- credito) quedan inactivos: si se pudieran elegir, la tarifa plana daria un
    -- importe que la tabla oficial no autoriza.
    select count(*) into v_n from islr_conceptos
     where codigo in ('040','065','067') and activo = 'N';
    if v_n <> 3 then falla('R1b', 'los conceptos con formula no estan inactivos'); end if;

    -- R2: el comprobante de IVA historico conserva numero y cifras. Se recorre
    -- RETENCIONES_IVA en vez de mirar un id fijo: si manana hay mas de uno, todos
    -- se revisan y ninguno se queda sin copiar en silencio.
    for r in (select * from retenciones_iva order by id_retencion) loop
        select count(*) into v_n
          from retenciones
         where tipo = 'IVA'
           and id_empresa = r.id_empresa
           and numero_comprobante = r.numero_comprobante
           and base_imponible_bs = r.base_imponible_bs
           and impuesto_bs = r.iva_causado_bs
           and retenido_bs = r.iva_retenido_bs;
        if v_n <> 1 then
            falla('R2', 'el comprobante ' || r.numero_comprobante || ' no se migro igual');
        end if;

        select count(*) into v_n
          from retenciones_det d
          join retenciones h on h.id_retencion = d.id_retencion
         where h.tipo = 'IVA'
           and h.id_empresa = r.id_empresa
           and h.numero_comprobante = r.numero_comprobante
           and d.id_compra = r.id_compra
           and d.sin_derecho_credito_bs = 0;
        if v_n < 1 then
            falla('R2', 'el comprobante ' || r.numero_comprobante || ' no tiene su linea');
        end if;
    end loop;

    -- R2b: lo que el papel necesita y no esta en las cifras de arriba. Un
    -- comprobante copiado sin fecha o sin el total del documento se imprime mal.
    for r in (select * from retenciones_iva order by id_retencion) loop
        select count(*) into v_n
          from retenciones h
          join compras c on c.id_compra = h.id_compra
         where h.tipo = 'IVA'
           and h.id_empresa = r.id_empresa
           and h.numero_comprobante = r.numero_comprobante
           and h.id_compra = r.id_compra
           and h.id_proveedor = c.id_proveedor
           and h.fecha_emision = r.fecha_emision
           and h.fecha_creacion = r.fecha_creacion
           and h.periodo_anio = r.periodo_anio
           and h.periodo_mes = r.periodo_mes
           and h.estado = r.estado
           and nvl(h.creado_por, '#') = nvl(r.creado_por, '#')
           and h.total_con_iva_bs = round(nvl(c.monto_total, 0) * nvl(c.tipo_cambio, 1), 2);
        if v_n <> 1 then
            falla('R2b', 'la cabecera del comprobante ' || r.numero_comprobante || ' no conserva sus datos');
        end if;

        -- La linea lleva los datos de la factura del proveedor.
        select count(*) into v_n
          from retenciones_det d
          join retenciones h on h.id_retencion = d.id_retencion
          join compras c on c.id_compra = d.id_compra
         where h.tipo = 'IVA'
           and h.id_empresa = r.id_empresa
           and h.numero_comprobante = r.numero_comprobante
           and d.fecha_factura = c.fecha_emision
           and nvl(d.nro_factura, '#') = nvl(c.folio_factura, '#')
           and nvl(d.nro_control, '#') = nvl(c.nro_control, '#')
           and nvl(d.tipo_documento, '#') = nvl(c.tipo_documento, '#');
        if v_n < 1 then
            falla('R2b', 'la linea del comprobante ' || r.numero_comprobante || ' no conserva los datos de la factura');
        end if;

        -- La alicuota de cada linea tiene que EXISTIR en el detalle de esa compra
        -- (fuera el IGTF y las retenciones, igual que la emision). Es la prueba de que
        -- no se invento un promedio: con una compra al 16 % y al 8 %, el 12 % no pasa.
        -- La linea de respaldo de una compra sin lineas gravadas es la excepcion, y se
        -- reconoce porque esa compra no tiene ninguna alicuota en compras_det.
        select count(*) into v_n
          from retenciones_det d
          join retenciones h on h.id_retencion = d.id_retencion
         where h.tipo = 'IVA'
           and h.id_empresa = r.id_empresa
           and h.numero_comprobante = r.numero_comprobante
           and exists (select 1
                         from compras_det dd
                        where dd.id_compra = d.id_compra
                          and nvl(dd.porcentaje_impuesto, 0) > 0
                          and not exists (select 1
                                            from impuestos i
                                           where i.id_impuesto = dd.id_impuesto
                                             and (i.cod_impuesto = 'IGTF'
                                                  or nvl(i.es_retencion, 'N') = 'S')))
           and not exists (select 1
                             from compras_det dd
                            where dd.id_compra = d.id_compra
                              and dd.porcentaje_impuesto = d.porcentaje
                              and nvl(dd.porcentaje_impuesto, 0) > 0
                              and not exists (select 1
                                                from impuestos i
                                               where i.id_impuesto = dd.id_impuesto
                                                 and (i.cod_impuesto = 'IGTF'
                                                      or nvl(i.es_retencion, 'N') = 'S')));
        if v_n > 0 then
            falla('R2b', 'el comprobante ' || r.numero_comprobante || ' tiene una alicuota que no esta en la compra');
        end if;

        -- Las lineas suman la cabecera. Un centimo de tolerancia por linea: cada
        -- alicuota redondea su propio importe y la cabecera es el total redondeado.
        select count(*) into v_n
          from retenciones h
         where h.tipo = 'IVA'
           and h.id_empresa = r.id_empresa
           and h.numero_comprobante = r.numero_comprobante
           and abs(h.base_imponible_bs
                   - (select nvl(sum(d.base_imponible_bs), 0)
                        from retenciones_det d
                       where d.id_retencion = h.id_retencion))
               <= 0.01 * (select count(*) from retenciones_det d
                           where d.id_retencion = h.id_retencion)
           and abs(h.impuesto_bs
                   - (select nvl(sum(d.impuesto_bs), 0)
                        from retenciones_det d
                       where d.id_retencion = h.id_retencion))
               <= 0.01 * (select count(*) from retenciones_det d
                           where d.id_retencion = h.id_retencion);
        if v_n <> 1 then
            falla('R2b', 'las lineas del comprobante ' || r.numero_comprobante || ' no suman la cabecera');
        end if;

        -- Consistencia secundaria de cada linea: base + IVA = total de la linea.
        -- NO se comprueba base x alicuota = IVA: el porcentaje sale de compras_det y
        -- con dos alicuotas ese producto no tiene por que dar (era el caso circular).
        select count(*) into v_n
          from retenciones_det d
          join retenciones h on h.id_retencion = d.id_retencion
         where h.tipo = 'IVA'
           and h.id_empresa = r.id_empresa
           and h.numero_comprobante = r.numero_comprobante
           and exists (select 1
                         from compras_det dd
                        where dd.id_compra = d.id_compra
                          and nvl(dd.porcentaje_impuesto, 0) > 0)
           and abs(d.total_con_iva_bs - (d.base_imponible_bs + d.impuesto_bs)) > 0.01;
        if v_n > 0 then
            falla('R2b', 'una linea del comprobante ' || r.numero_comprobante || ' no cuadra base + IVA');
        end if;
    end loop;

    -- R3: la migracion no consumio numeracion. Una sola serie por empresa y periodo,
    -- asi que el contador tiene que ser exactamente el ultimo numero que hay en
    -- RETENCIONES: si la copia hubiera pedido numero, el contador iria por delante y
    -- el siguiente comprobante se saltaria uno. Los periodos sin ningun comprobante
    -- (ni en el modelo nuevo ni en el viejo) se saltan: ahi no hay nada que cuadrar.
    for r in (select id_empresa, periodo, ultimo from retencion_contador) loop
        select count(*) into v_n
          from retenciones
         where id_empresa = r.id_empresa
           and substr(numero_comprobante, 1, 6) = r.periodo;

        select count(*) into v_viejo
          from retenciones_iva
         where id_empresa = r.id_empresa
           and to_char(fecha_emision, 'YYYYMM') = r.periodo;

        if v_n > 0 or v_viejo > 0 then
            select nvl(max(to_number(substr(numero_comprobante, 7))), 0) into v_max
              from retenciones
             where id_empresa = r.id_empresa
               and substr(numero_comprobante, 1, 6) = r.periodo
               and regexp_like(numero_comprobante, '^[0-9]{14}$');
            if r.ultimo <> v_max then
                falla('R3', 'el contador ' || r.id_empresa || '/' || r.periodo || ' va en ' || r.ultimo
                            || ' y el ultimo numero emitido es ' || v_max
                            || ' (si se emitio por el camino viejo, corre la migracion otra vez)');
            end if;
        end if;
    end loop;

    select nvl(max(ultimo), 0) into v_n
      from retencion_contador where periodo = v_periodo;
    if v_n <> v_ultimo_ini then
        falla('R3', 'el contador de ' || v_periodo || ' paso de ' || v_ultimo_ini || ' a ' || v_n);
    end if;

    -- -------------------------------------------------------------------------
    -- R5/R6/R7: el motor de calculo del ISLR.
    --
    -- Se calcula sobre compras de verdad y no sobre un subtotal inventado: la base
    -- es el SUBTOTAL del documento, que mantiene el trigger de totales a partir del
    -- detalle. Un subtotal escrito a mano probaria una ruta que la app no usa.
    -- -------------------------------------------------------------------------
    savepoint sp_islr;
    begin
        -- v_prov lo deja el proveedor de FIXTURE del bloque de preparacion (concepto de
        -- ISLR nulo): las compras de prueba no se cuelgan de un proveedor real.

        select min(u.username) into v_usuario
          from usuario u
          join usuario_empresa ue on ue.usuario_id = u.usuario_id
         where ue.id_empresa = 1
           and u.estado in ('ACTIVO', 'A', '1');

        select max(id_concepto) into v_con_003 from islr_conceptos where codigo = '003';
        select max(id_concepto) into v_con_057 from islr_conceptos where codigo = '057';
        select max(id_concepto) into v_con_063 from islr_conceptos where codigo = '063';

        if v_prov is null or v_usuario is null then
            falla('R5', 'no hay proveedor de fixture ni usuario activo de la empresa 1');
        elsif v_con_003 is null or v_con_057 is null or v_con_063 is null then
            falla('R5', 'faltan los conceptos 003/057/063 en ISLR_CONCEPTOS');
        else
            -- Compra del ejemplo del cliente: 1.067.106,36 Bs sin IVA (la factura
            -- 6472 de la carpeta libreria/). Folio y control explicitos para no
            -- consumir la serie FAC_PROV/CONTROL_PROV del proveedor.
            pkg_compras.prc_guardar_compra(
                p_id_compra            => v_compra_gra,
                p_id_empresa           => 1,
                p_id_proveedor         => v_prov,
                p_tipo_documento       => 'FAC',
                p_folio_factura        => 'ISLR-T4-GRANDE',
                p_nro_control          => '00-999901',
                p_fecha_emision        => trunc(sysdate),
                p_cod_moneda           => 'VES',
                p_tipo_cambio          => 1,
                p_porcentaje_retencion => 0,
                p_usuario              => v_usuario);

            pkg_compra_detalle.guardar_detalle(
                p_id_detalle           => v_det,
                p_id_compra            => v_compra_gra,
                p_num_linea            => 1,
                p_id_producto_servicio => null,
                p_descripcion          => 'Base ISLR del ejemplo',
                p_cantidad             => 1,
                p_precio_unitario      => 1067106.36,
                p_porcentaje_descuento => 0,
                p_monto_descuento      => 0,
                p_id_impuesto          => null,
                p_porcentaje_impuesto  => 0,
                p_usuario              => v_usuario);

            -- Compra chica: 1.000 Bs, por debajo del sustraendo de 2,5 UT.
            v_det := null;
            pkg_compras.prc_guardar_compra(
                p_id_compra            => v_compra_chi,
                p_id_empresa           => 1,
                p_id_proveedor         => v_prov,
                p_tipo_documento       => 'FAC',
                p_folio_factura        => 'ISLR-T4-CHICA',
                p_nro_control          => '00-999902',
                p_fecha_emision        => trunc(sysdate),
                p_cod_moneda           => 'VES',
                p_tipo_cambio          => 1,
                p_porcentaje_retencion => 0,
                p_usuario              => v_usuario);

            pkg_compra_detalle.guardar_detalle(
                p_id_detalle           => v_det,
                p_id_compra            => v_compra_chi,
                p_num_linea            => 1,
                p_id_producto_servicio => null,
                p_descripcion          => 'Base ISLR bajo el umbral',
                p_cantidad             => 1,
                p_precio_unitario      => 1000,
                p_porcentaje_descuento => 0,
                p_monto_descuento      => 0,
                p_id_impuesto          => null,
                p_porcentaje_impuesto  => 0,
                p_usuario              => v_usuario);

            -- Compra en DIVISA: el subtotal del documento esta en USD y la base del
            -- ISLR va en BOLIVARES, con la tasa del documento. Un motor que se
            -- olvide de la tasa retiene 900 veces menos en cada compra en divisa.
            v_det := null;
            pkg_compras.prc_guardar_compra(
                p_id_compra            => v_compra_usd,
                p_id_empresa           => 1,
                p_id_proveedor         => v_prov,
                p_tipo_documento       => 'FAC',
                p_folio_factura        => 'ISLR-T4-USD',
                p_nro_control          => '00-999903',
                p_fecha_emision        => trunc(sysdate),
                p_cod_moneda           => 'USD',
                p_tipo_cambio          => 900,
                p_porcentaje_retencion => 0,
                p_usuario              => v_usuario);

            pkg_compra_detalle.guardar_detalle(
                p_id_detalle           => v_det,
                p_id_compra            => v_compra_usd,
                p_num_linea            => 1,
                p_id_producto_servicio => null,
                p_descripcion          => 'Base ISLR en divisa',
                p_cantidad             => 1,
                p_precio_unitario      => 1000,
                p_porcentaje_descuento => 0,
                p_monto_descuento      => 0,
                p_id_impuesto          => null,
                p_porcentaje_impuesto  => 0,
                p_usuario              => v_usuario);
        end if;
    exception
        when others then
            rollback to sp_islr;
            v_compra_gra := null;
            v_compra_chi := null;
            v_compra_usd := null;
            falla('R5', 'no se pudo montar la compra de prueba: ' || substrb(sqlerrm, 1, 120));
    end;

    if v_compra_gra is not null and v_compra_chi is not null and v_compra_usd is not null then
        -- R5: 100 % de base y 5 % de tarifa, sin sustraendo. El papel del cliente
        -- dice 53.355,32 sobre 1.067.106,36 Bs.
        v_calc := pkg_retenciones.fn_islr_base_bs(v_compra_gra, v_con_063);
        if v_calc is null or v_calc <> 1067106.36 then
            falla('R5', 'la base del ISLR dio ' || num(v_calc) || ' en vez de 1.067.106,36');
        end if;

        v_calc := pkg_retenciones.fn_islr_retencion_bs(v_compra_gra, v_con_063);
        if v_calc is null or v_calc <> 53355.32 then
            falla('R5', 'el ISLR del ejemplo dio ' || num(v_calc) || ' en vez de 53.355,32');
        end if;

        -- R5b: compra en divisa. 1.000 USD al 900 son 900.000,00 Bs de base y el
        -- 5 % de 063 deja 45.000,00. Sin la tasa del documento la base seria 1.000
        -- y el retenido 50,00: toda compra en moneda extranjera retendria de menos.
        v_calc := pkg_retenciones.fn_islr_base_bs(v_compra_usd, v_con_063);
        if v_calc is null or v_calc <> 900000 then
            falla('R5b', 'la base en bolivares de una compra en USD dio ' || num(v_calc)
                         || ' en vez de 900.000,00 (falta la tasa del documento)');
        end if;

        v_calc := pkg_retenciones.fn_islr_retencion_bs(v_compra_usd, v_con_063);
        if v_calc is null or v_calc <> 45000 then
            falla('R5b', 'el ISLR de una compra en USD dio ' || num(v_calc) || ' en vez de 45.000,00');
        end if;

        -- R6: la UT sale de SYN_PARAMETROS, no de una constante escondida. Si el
        -- SENIAT la cambia se edita ahi y el calculo la sigue; una UT clavada en el
        -- codigo dejaria todos los papeles viejos sin que nadie lo note.
        select nvl(max(valor), 0) into v_ut from syn_parametros where clave = 'UT_ISLR';
        savepoint sp_ut;
        update syn_parametros set valor = 50 where clave = 'UT_ISLR';
        v_calc := pkg_retenciones.fn_valor_ut;
        rollback to sp_ut;
        if v_calc is null or v_calc <> 50 then
            falla('R6', 'la UT no es parametrizable: con 50 en SYN_PARAMETROS devolvio ' || num(v_calc));
        end if;
        v_calc := pkg_retenciones.fn_valor_ut;
        if v_calc is null or v_calc <> v_ut then
            falla('R6', 'fn_valor_ut no devuelve la UT de SYN_PARAMETROS (' || v_ut || ')');
        end if;

        -- El sustraendo en bolivares es lo que la emision guarda en la linea del
        -- comprobante: 2,5 UT x 43 = 107,50. Se comprueba aparte del retenido
        -- porque el papel lo imprime.
        v_calc := pkg_retenciones.fn_islr_sustraendo_bs(v_con_057);
        if v_calc is null or v_calc <> 107.50 then
            falla('R6', 'el sustraendo en bolivares dio ' || num(v_calc) || ' en vez de 107,50');
        end if;

        -- 3 % con sustraendo de 2,5 UT: 32.013,19 - 107,50 = 31.905,69. Un 3 %
        -- pelado daria 32.013,19 y el sustraendo de otra UT no cuadraria.
        v_calc := pkg_retenciones.fn_islr_retencion_bs(v_compra_gra, v_con_057);
        if v_calc is null or v_calc <> 31905.69 then
            falla('R6', 'el 3 % con sustraendo dio ' || num(v_calc) || ' en vez de 31.905,69');
        end if;

        -- R6b: un concepto con base_pct distinto de 100. 003 (honorarios) es 90 %
        -- de base y 34 % de tarifa: 1.067.106,36 x 90 % = 960.395,72, y el 34 % de
        -- eso deja 326.534,54. Si el BASE_PCT se ignorara, la base seria
        -- 1.067.106,36 y el retenido 362.816,16 (36.000 Bs de mas retenidos).
        v_calc := pkg_retenciones.fn_islr_base_bs(v_compra_gra, v_con_003);
        if v_calc is null or v_calc <> 960395.72 then
            falla('R6b', 'la base con base_pct 90 dio ' || num(v_calc) || ' en vez de 960.395,72');
        end if;

        v_calc := pkg_retenciones.fn_islr_retencion_bs(v_compra_gra, v_con_003);
        if v_calc is null or v_calc <> 326534.54 then
            falla('R6b', 'el 34 % sobre la base del 90 % dio ' || num(v_calc)
                         || ' en vez de 326.534,54 (con base_pct 100 daria 362.816,16)');
        end if;

        -- R7: 1.000 x 3 % = 30, menos 107,50 = -77,50. El piso lo deja en 0.
        v_calc := pkg_retenciones.fn_islr_retencion_bs(v_compra_chi, v_con_057);
        if v_calc is null or v_calc <> 0 then
            falla('R7', 'una base bajo el umbral devolvio ' || num(v_calc) || ' en vez de 0');
        end if;
    end if;

    -- Las compras de prueba no se quedan: la base del cliente sale como entro. El
    -- borrado del hijo y del padre no puede ir en la misma transaccion en esta ADB
    -- (ORA-12860), de ahi los dos commit.
    if v_compra_gra is not null or v_compra_chi is not null or v_compra_usd is not null then
        delete from compras_det
         where id_compra in (v_compra_gra, v_compra_chi, v_compra_usd);
        commit;
        delete from compras where id_compra in (v_compra_gra, v_compra_chi, v_compra_usd);
        commit;
    end if;

    -- -------------------------------------------------------------------------
    -- R4/R4b/R9/R9b/R10/R13/R13b/R14/R15: la emision y la anulacion.
    --
    -- Todo va dentro de un savepoint que se revierte al final: los casos emiten
    -- comprobantes de verdad, con su numero, y la base del cliente tiene que quedar
    -- como entro, contador de numeracion incluido. El rollback no devuelve los ids
    -- de las secuencias identity, pero el numero fiscal que imprime el papel
    -- (NUMERO_COMPROBANTE) si vuelve a su sitio.
    --
    -- El concepto de ISLR se pone con un UPDATE sobre la compra en BORRADOR porque
    -- prc_guardar_compra todavia no lo recibe (eso es la tarea 6); es lo mismo que
    -- hace la pantalla mientras la compra no esta registrada.
    -- -------------------------------------------------------------------------
    savepoint sp_emi;
    begin
        if v_prov is null or v_usuario is null then
            falla('R4', 'no hay proveedor ni usuario de la empresa 1 para las compras de la emision');
        elsif v_con_057 is null then
            falla('R4', 'falta el concepto 057 en ISLR_CONCEPTOS');
        else
            v_e_periodo := to_char(sysdate, 'YYYYMM');

            -- R4: 1.000 al 16 % son 160 de IVA y el 75 % retiene 120,00. El
            -- comprobante tiene que quedar en RETENCIONES: si la emision siguiera
            -- escribiendo en RETENCIONES_IVA, la pantalla y el papel nuevo saldrian
            -- sin comprobante aunque el importe se calculara bien.
            crea_compra('ISLR-T5-16', '00-999921', 'VES', 1, 75, v_e_id_iva);
            crea_linea(v_e_id_iva, 1, 'Linea al 16 por ciento', 1000, 1, 16);

            v_e_ret := pkg_retenciones.fn_retencion_bs(v_e_id_iva);
            if v_e_ret is null or v_e_ret <> 120 then
                falla('R4', 'fn_retencion_bs dio ' || num(v_e_ret) || ' en vez de 120,00');
            end if;

            pkg_compras.prc_registrar_compra(v_e_id_iva, v_usuario);

            select count(*) into v_n from retenciones
             where id_compra = v_e_id_iva and tipo = 'IVA' and estado = 'EMITIDO'
               and base_imponible_bs = 1000 and impuesto_bs = 160
               and retenido_bs = 120 and total_con_iva_bs = 1160;
            if v_n <> 1 then
                falla('R4', 'el comprobante de IVA al 75 % no quedo con 1.000 / 160 / 120 en RETENCIONES');
            end if;

            -- R4b: compra en divisa. Un comprobante en USD es un papel invalido: la
            -- base y el impuesto van en bolivares con la tasa del documento. 100 y 16
            -- USD al 900 son 90.000,00 y 14.400,00, y el 75 % retiene 10.800,00.
            v_caso_emi := 'R4b';
            crea_compra('ISLR-T5-USD', '00-999922', 'USD', 900, 75, v_e_id_usd);
            crea_linea(v_e_id_usd, 1, 'Linea en divisa al 16 por ciento', 100, 1, 16);
            pkg_compras.prc_registrar_compra(v_e_id_usd, v_usuario);

            select count(*) into v_n from retenciones
             where id_compra = v_e_id_usd and tipo = 'IVA'
               and base_imponible_bs = 90000 and impuesto_bs = 14400
               and retenido_bs = 10800 and total_con_iva_bs = 104400;
            if v_n <> 1 then
                falla('R4b', 'la compra en divisa no se llevo a bolivares con la tasa del documento');
            end if;

            -- R13: dos alicuotas. Se usa la fila del 8 % del catalogo (IVA Frontera,
            -- de Mexico) porque el catalogo de Venezuela solo tiene 16 %, 3 % y 0 %:
            -- la emision agrupa por el PORCENTAJE de la linea, no por el pais del
            -- impuesto, y eso es justo lo que el caso mide.
            v_caso_emi := 'R13';
            crea_compra('ISLR-T5-DOS', '00-999923', 'VES', 1, 75, v_e_id_dos);
            crea_linea(v_e_id_dos, 1, 'Linea al 16 por ciento', 1000, 1, 16);
            crea_linea(v_e_id_dos, 2, 'Linea al 8 por ciento', 500, 5, 8);
            pkg_compras.prc_registrar_compra(v_e_id_dos, v_usuario);

            select count(*) into v_n from retenciones_det d
              join retenciones h on h.id_retencion = d.id_retencion
             where h.id_compra = v_e_id_dos and h.tipo = 'IVA';
            if v_n <> 2 then
                falla('R13', 'la factura con dos alicuotas dejo ' || v_n || ' lineas (esperado 2)');
            end if;

            select count(*) into v_n from retenciones
             where id_compra = v_e_id_dos and tipo = 'IVA'
               and base_imponible_bs = 1500 and impuesto_bs = 200 and retenido_bs = 150;
            if v_n <> 1 then
                falla('R13', 'la cabecera no suma las dos alicuotas (1.500 / 200 / 150)');
            end if;

            select count(*) into v_n from retenciones_det d
              join retenciones h on h.id_retencion = d.id_retencion
             where h.id_compra = v_e_id_dos and h.tipo = 'IVA'
               and ((d.porcentaje = 16 and d.base_imponible_bs = 1000
                     and d.impuesto_bs = 160 and d.retenido_bs = 120)
                 or (d.porcentaje = 8 and d.base_imponible_bs = 500
                     and d.impuesto_bs = 40 and d.retenido_bs = 30));
            if v_n <> 2 then
                falla('R13', 'las lineas por alicuota no llevan su base, su IVA y su retenido');
            end if;

            -- R13b: la cabecera es el PORCENTAJE DEL IVA TOTAL (0,04 x 75 % = 0,03) y
            -- las lineas lo reparten: 0,02 y 0,02 no dan 0,03, asi que el centimo se le
            -- quita a la de mayor IVA y las dos suman exactamente la cabecera. Lo que
            -- estaba mal antes no era esto: era el resumen del BORRADOR, que sacaba el
            -- porcentaje de la suma SIN redondear los grupos.
            v_caso_emi := 'R13b';
            crea_compra('ISLR-T5-CENT', '00-999924', 'VES', 1, 75, v_e_id_cent);
            crea_linea(v_e_id_cent, 1, 'Centimo al 16 por ciento', 0.13, 1, 16);
            crea_linea(v_e_id_cent, 2, 'Centimo al 8 por ciento', 0.25, 5, 8);
            pkg_compras.prc_registrar_compra(v_e_id_cent, v_usuario);

            select nvl(sum(d.retenido_bs), -1), count(*) into v_e_ret, v_n
              from retenciones_det d
              join retenciones h on h.id_retencion = d.id_retencion
             where h.id_compra = v_e_id_cent and h.tipo = 'IVA';
            select nvl(max(retenido_bs), -1) into v_e_ret2
              from retenciones where id_compra = v_e_id_cent and tipo = 'IVA';
            if v_n <> 2 or v_e_ret <> v_e_ret2 or v_e_ret2 <> 0.03 then
                falla('R13b', 'las lineas suman ' || num(v_e_ret) || ' y la cabecera dice '
                              || num(v_e_ret2) || ' (esperado 0,03 en las dos)');
            end if;

            -- R15: el IGTF no se retiene. 1.000 al 16 % (base 1.000, IVA 160) mas 500
            -- al 3 % de IGTF: si el IGTF entrara en la base, seria 1.500 y el IVA 175.
            v_caso_emi := 'R15';
            crea_compra('ISLR-T5-IGTF', '00-999925', 'VES', 1, 75, v_e_id_igtf);
            crea_linea(v_e_id_igtf, 1, 'Linea al 16 por ciento', 1000, 1, 16);
            crea_linea(v_e_id_igtf, 2, 'Linea con IGTF', 500, 2, 3);
            pkg_compras.prc_registrar_compra(v_e_id_igtf, v_usuario);

            select count(*) into v_n from retenciones
             where id_compra = v_e_id_igtf and tipo = 'IVA'
               and base_imponible_bs = 1000 and impuesto_bs = 160 and retenido_bs = 120;
            if v_n <> 1 then
                falla('R15', 'el IGTF entro en la base o en el IVA retenido');
            end if;

            -- R16: ISLR por debajo del umbral. Concepto 057 (100 % de base, 3 % de
            -- tarifa y 2,5 UT de sustraendo) sobre 1.000 Bs: 30 - 107,50 da negativo,
            -- o sea 0. No se emite comprobante de ISLR y NO se consume numero: el
            -- contador sube UNO (el del IVA), no dos. Es el Review Focus #5 del spec.
            v_caso_emi := 'R16';
            crea_compra('ISLR-T5-BAJO', '00-999929', 'VES', 1, 75, v_e_id_bajo, v_con_057);
            crea_linea(v_e_id_bajo, 1, 'Base por debajo del sustraendo', 1000, 1, 16);

            select nvl(max(ultimo), 0) into v_e_cont from retencion_contador
             where id_empresa = 1 and periodo = v_e_periodo;

            pkg_compras.prc_registrar_compra(v_e_id_bajo, v_usuario);

            select nvl(max(ultimo), 0) into v_e_cont2 from retencion_contador
             where id_empresa = 1 and periodo = v_e_periodo;
            if v_e_cont2 <> v_e_cont + 1 then
                falla('R16', 'el contador paso de ' || v_e_cont || ' a ' || v_e_cont2
                             || ' (esperado +1: el ISLR bajo el umbral no consume numero)');
            end if;

            select count(*) into v_n from retenciones
             where id_compra = v_e_id_bajo and tipo = 'ISLR';
            if v_n <> 0 then
                falla('R16', 'se emitio comprobante de ISLR con retenido 0');
            end if;

            -- El comprobante de IVA de esa misma compra SI tiene que existir: sin el,
            -- el caso no probaria que el ISLR se queda fuera por el umbral.
            select count(*) into v_n from retenciones
             where id_compra = v_e_id_bajo and tipo = 'IVA';
            if v_n <> 1 then
                falla('R16', 'la compra bajo el umbral no emitio su comprobante de IVA');
            end if;

            -- R14: registrar una nota de credito no emite comprobante ni consume
            -- numeracion (decision del dueno: solo las facturas). La nota se hace
            -- sobre una FAC de la misma empresa, que es lo que exige pkg_compras.
            v_caso_emi := 'R14';
            select nvl(max(ultimo), 0) into v_e_cont from retencion_contador
             where id_empresa = 1 and periodo = v_e_periodo;

            crea_compra('ISLR-T5-FAC', '00-999926', 'VES', 1, 75, v_e_id_fac);
            crea_linea(v_e_id_fac, 1, 'Factura que la nota acredita', 1000, 1, 16);

            pkg_compras.prc_guardar_compra(
                p_id_compra            => v_e_id_nc,
                p_id_empresa           => 1,
                p_id_proveedor         => v_prov,
                p_tipo_documento       => 'NC',
                p_folio_factura        => 'ISLR-T5-NC',
                p_nro_control          => '00-999927',
                p_fecha_emision        => trunc(sysdate),
                p_cod_moneda           => 'VES',
                p_tipo_cambio          => 1,
                p_porcentaje_retencion => 75,
                p_id_compra_origen     => v_e_id_fac,
                p_usuario              => v_usuario);
            crea_linea(v_e_id_nc, 1, 'Linea de la nota de credito', 1000, 1, 16);

            pkg_compras.prc_registrar_compra(v_e_id_nc, v_usuario);

            select count(*) into v_n from retenciones where id_compra = v_e_id_nc;
            if v_n <> 0 then
                falla('R14', 'la nota de credito emitio ' || v_n || ' comprobante(s)');
            end if;

            select nvl(max(ultimo), 0) into v_e_cont2 from retencion_contador
             where id_empresa = 1 and periodo = v_e_periodo;
            if v_e_cont2 <> v_e_cont then
                falla('R14', 'la nota movio el contador de ' || v_e_cont || ' a ' || v_e_cont2);
            end if;

            -- R9: una factura con retencion de IVA y concepto de ISLR emite los DOS
            -- comprobantes y consume DOS numeros consecutivos de la serie unica. El
            -- concepto se pasa por el PARAMETRO (como lo hara la pantalla), no con un
            -- UPDATE a mano: es el unico caso que ejercita la emision, asi que tiene
            -- que entrar por la misma puerta que el usuario.
            v_caso_emi := 'R9';
            crea_compra('ISLR-T5-ISLR', '00-999928', 'VES', 1, 75, v_e_id_islr, v_con_057);
            crea_linea(v_e_id_islr, 1, 'Servicio gravado al 16 por ciento', 10000, 1, 16);

            select nvl(max(ultimo), 0) into v_e_cont from retencion_contador
             where id_empresa = 1 and periodo = v_e_periodo;

            pkg_compras.prc_registrar_compra(v_e_id_islr, v_usuario);

            select nvl(max(ultimo), 0) into v_e_cont2 from retencion_contador
             where id_empresa = 1 and periodo = v_e_periodo;
            if v_e_cont2 <> v_e_cont + 2 then
                falla('R9', 'el contador paso de ' || v_e_cont || ' a ' || v_e_cont2
                             || ' (esperado +2: un comprobante de IVA y otro de ISLR)');
            end if;

            select max(numero_comprobante) into v_e_num1 from retenciones
             where id_compra = v_e_id_islr and tipo = 'IVA';
            select max(numero_comprobante) into v_e_num2 from retenciones
             where id_compra = v_e_id_islr and tipo = 'ISLR';
            if v_e_num1 is null or v_e_num2 is null then
                falla('R9', 'no se emitieron los dos comprobantes (IVA ' || nvl(v_e_num1, '-')
                             || ', ISLR ' || nvl(v_e_num2, '-') || ')');
            elsif to_number(substr(v_e_num2, 7)) <> to_number(substr(v_e_num1, 7)) + 1 then
                falla('R9', 'los numeros no son consecutivos: ' || v_e_num1 || ' y ' || v_e_num2);
            end if;

            -- R9b: la linea de ISLR guarda la foto completa del calculo. El concepto
            -- 057 es 100 % de base, 3 % de tarifa y 2,5 UT de sustraendo: 10.000 x 3 %
            -- = 300, menos 2,5 x 43 = 107,50, deja 192,50. La cabecera lleva el codigo
            -- y la actividad que imprime el papel.
            select count(*) into v_n
              from retenciones_det d
              join retenciones h on h.id_retencion = d.id_retencion
             where h.id_compra = v_e_id_islr and h.tipo = 'ISLR'
               and d.base_pct = 100 and d.tarifa = 3 and d.sustraendo_ut = 2.5
               and d.valor_ut = 43 and d.sustraendo_bs = 107.50
               and d.base_imponible_bs = 10000 and d.retenido_bs = 192.50
               and d.impuesto_bs = 0 and d.porcentaje = 3;
            if v_n <> 1 then
                falla('R9b', 'la linea de ISLR no guarda la foto (100 % / 3 % / 2,5 UT / 43 / 107,50)');
            end if;

            select count(*) into v_n from retenciones
             where id_compra = v_e_id_islr and tipo = 'ISLR'
               and id_concepto_islr = v_con_057 and codigo_concepto = '057'
               and actividad is not null
               and base_imponible_bs = 10000 and retenido_bs = 192.50
               and total_con_iva_bs = 11600;
            if v_n <> 1 then
                falla('R9b', 'la cabecera de ISLR no lleva el concepto, la actividad ni el importe');
            end if;

            -- R10: anular la compra deja los dos comprobantes ANULADO y les conserva
            -- el numero (el papel se conserva para auditoria, no se borra).
            v_caso_emi := 'R10';
            pkg_compras.prc_anular_compra(v_e_id_islr, v_usuario);

            select count(*) into v_n from retenciones
             where id_compra = v_e_id_islr and tipo in ('IVA', 'ISLR')
               and estado = 'ANULADO' and numero_comprobante in (v_e_num1, v_e_num2);
            if v_n <> 2 then
                falla('R10', 'al anular no quedaron los dos comprobantes ANULADO con su numero');
            end if;

            -- R17: ninguna compra SIN concepto de ISLR puede tener comprobante de
            -- ISLR. Se mira el bloque entero (R4, R4b, R13, R13b, R15 y la nota) en
            -- una sola pasada, y se comprueba que el caso no este vacio: esas mismas
            -- compras si tienen su comprobante de IVA.
            v_caso_emi := 'R17';
            select count(*) into v_n
              from retenciones h
              join compras c on c.id_compra = h.id_compra
             where c.folio_factura like 'ISLR-T5%' and c.id_concepto_islr is null
               and h.tipo = 'ISLR';
            if v_n <> 0 then
                falla('R17', 'una compra sin concepto emitio ' || v_n || ' comprobante(s) de ISLR');
            end if;

            select count(*) into v_n
              from retenciones h
              join compras c on c.id_compra = h.id_compra
             where c.folio_factura like 'ISLR-T5%' and c.id_concepto_islr is null
               and h.tipo = 'IVA';
            if v_n < 5 then
                falla('R17', 'el caso no mide nada: solo ' || v_n
                             || ' compras sin concepto emitieron su IVA (esperado 5)');
            end if;

            -- -----------------------------------------------------------------
            -- R11/R11b: los dos papeles.
            --
            -- La compra es la del ejemplo del cliente (factura 6472 del PDF de
            -- libreria/): 1.067.106,36 de base al 16 % y el concepto 063 al 5 %
            -- sin sustraendo. Con ella salen las DOS cifras del papel del cliente
            -- (170.737,02 de IVA, 128.052,77 retenido y 53.355,32 de ISLR), asi
            -- que un formato que se coma una columna o recalcule se ve aqui.
            -- -----------------------------------------------------------------
            v_caso_emi := 'R11';
            select max(id_concepto) into v_con_063 from islr_conceptos where codigo = '063';
            if v_con_063 is null then
                falla('R11', 'falta el concepto 063 en ISLR_CONCEPTOS');
            else
                crea_compra('ISLR-T5-R11', '00-999931', 'VES', 1, 75, v_e_id_r11, v_con_063);
                crea_linea(v_e_id_r11, 1, 'Arrendamiento del ejemplo del cliente', 1067106.36, 1, 16);
                pkg_compras.prc_registrar_compra(v_e_id_r11, v_usuario);

                select max(case when tipo = 'IVA' then numero_comprobante end),
                       max(case when tipo = 'ISLR' then numero_comprobante end)
                  into v_r11_iva, v_r11_islr
                  from retenciones where id_compra = v_e_id_r11;

                if v_r11_iva is null or v_r11_islr is null then
                    falla('R11', 'la compra del ejemplo no emitio los dos comprobantes');
                end if;

                -- Los RIF se leen de la base, no se escriben aqui: el papel tiene
                -- que traer el de la empresa y el del proveedor de verdad.
                select max(p.rif) into v_r11_rif_pro
                  from proveedores p where p.id_proveedor = v_prov;
                select max(e.rfc) into v_r11_rif_emp
                  from empresas e where e.id_empresa = 1;

                -- El de IVA: los bloques de la Providencia, las dos cifras del
                -- cliente y el codigo fijo de la transaccion.
                v_html := fn_imprimir_retencion(v_e_id_r11, 'IVA');
                if v_html is null then
                    falla('R11', 'no armo el comprobante de IVA');
                else
                    if instr(v_html, 'Comprobante de Retenci') = 0
                       or instr(v_html, 'sin derecho a Cr') = 0 then
                        falla('R11', 'el comprobante de IVA no trae los campos del formato');
                    end if;
                    if instr(v_html, 'SNAT/2025/000054') = 0 then
                        falla('R11', 'el comprobante de IVA no cita la providencia');
                    end if;
                    if instr(v_html, '1.067.106,36') = 0
                       or instr(v_html, '170.737,02') = 0
                       or instr(v_html, '128.052,77') = 0 then
                        falla('R11', 'el comprobante de IVA no trae la base, el IVA y el retenido');
                    end if;
                    if instr(v_html, '01-Reg') = 0 then
                        falla('R11', 'el comprobante de IVA no trae el tipo de transaccion');
                    end if;
                    if instr(v_html, v_r11_rif_pro) = 0
                       or instr(v_html, v_r11_rif_emp) = 0 then
                        falla('R11', 'el comprobante de IVA no trae el RIF de las dos partes');
                    end if;
                    if v_r11_iva is not null and instr(v_html, v_r11_iva) = 0 then
                        falla('R11', 'el comprobante de IVA no trae su numero');
                    end if;
                end if;

                -- Sin tipo (la pagina 31 lo llama con un solo argumento) sigue
                -- sirviendo el de IVA.
                v_html := fn_imprimir_retencion(v_e_id_r11);
                if v_html is null or instr(v_html, 'I.V.A.') = 0 then
                    falla('R11', 'sin el segundo argumento no imprime el comprobante de IVA');
                end if;

                -- El de ISLR: concepto, sustraendo y la cifra del cliente.
                v_html := fn_imprimir_retencion(v_e_id_r11, 'ISLR');
                if v_html is null then
                    falla('R11', 'no armo el comprobante de ISLR');
                else
                    if instr(v_html, 'Comprobante de Retenci') = 0 then
                        falla('R11', 'el comprobante de ISLR no tiene titulo');
                    end if;
                    if instr(v_html, '063') = 0 or instr(v_html, 'Sustraendo') = 0 then
                        falla('R11', 'el comprobante de ISLR no trae el concepto ni el sustraendo');
                    end if;
                    if instr(v_html, '53.355,32') = 0 or instr(v_html, '1.067.106,36') = 0 then
                        falla('R11', 'el comprobante de ISLR no trae la base y el retenido');
                    end if;
                    if instr(v_html, 'Decreto 1.808') = 0 then
                        falla('R11', 'el comprobante de ISLR no cita el Decreto 1.808');
                    end if;
                    if v_r11_islr is not null and instr(v_html, v_r11_islr) = 0 then
                        falla('R11', 'el comprobante de ISLR no trae su numero');
                    end if;
                end if;

                -- Donde no hay comprobante no puede salir un papel: ni ISLR en una
                -- compra sin concepto, ni nada en una nota de credito.
                if fn_imprimir_retencion(v_e_id_iva, 'ISLR') is not null then
                    falla('R11', 'inventa un comprobante de ISLR donde no lo hay');
                end if;
                if fn_imprimir_retencion(v_e_id_nc, 'IVA') is not null
                   or fn_imprimir_retencion(v_e_id_nc, 'ISLR') is not null then
                    falla('R11', 'inventa un comprobante para una nota de credito');
                end if;

                -- R11b: la reimpresion no recalcula. Se mueve la UT y la tarifa del
                -- concepto en el catalogo, y tambien el TOTAL DE LA COMPRA, y el papel
                -- tiene que seguir diciendo lo que se emitio. Si la funcion mirara
                -- ISLR_CONCEPTOS, SYN_PARAMETROS o COMPRAS, saldria 362.816,16 (34 %),
                -- 106.710.636,00 (UT 100) o 49.999,95 (999.999 al 5 %).
                savepoint sp_r11;
                update syn_parametros set valor = 100 where clave = 'UT_ISLR';
                update islr_conceptos set tarifa = 34 where codigo = '063';
                update compras set monto_total = 999999 where id_compra = v_e_id_r11;

                v_html := fn_imprimir_retencion(v_e_id_r11, 'ISLR');
                if v_html is null or instr(v_html, '53.355,32') = 0 then
                    falla('R11b', 'la reimpresion recalculo con la UT o el concepto vigente');
                end if;
                -- El total del documento tambien es foto: el de la compra ya es
                -- 999.999 y el papel tiene que seguir diciendo 1.237.843,38.
                if v_html is not null
                   and (instr(v_html, '1.237.843,38') = 0 or instr(v_html, '999.999,00') > 0) then
                    falla('R11b', 'la reimpresion tomo el total de la compra y no el emitido');
                end if;
                rollback to sp_r11;

                -- Una cabecera sin lineas no se imprime: saldria una tabla vacia con
                -- totales en 0,00, que es un papel en blanco con aspecto de valido.
                savepoint sp_r11c;
                delete from retenciones_det
                 where id_retencion in (select id_retencion from retenciones
                                         where id_compra = v_e_id_r11 and tipo = 'ISLR');
                v_html := fn_imprimir_retencion(v_e_id_r11, 'ISLR');
                if v_html is not null then
                    falla('R11', 'imprime un comprobante sin lineas (papel en blanco)');
                end if;
                rollback to sp_r11c;
            end if;
        end if;

        rollback to sp_emi;
    exception
        when others then
            rollback to sp_emi;
            falla(v_caso_emi, 'la emision revento: ' || substrb(sqlerrm, 1, 150));
    end;

    -- -------------------------------------------------------------------------
    -- R8: el concepto de ISLR se hereda del proveedor y se puede cambiar.
    --
    -- Va FUERA del savepoint de la emision a proposito: necesita COMMIT entre altas
    -- (varias DML sobre tablas con identity en la misma transaccion dan ORA-12839 en
    -- esta ADB) y un COMMIT se lleva por delante el savepoint. Por eso el caso se
    -- limpia solo: al empezar (arriba) y al terminar (abajo).
    -- -------------------------------------------------------------------------
    declare
        v_prov8 number;
        v_a     number;
        v_b     number;
        v_con   number;
    begin
        -- Los conceptos se vuelven a leer: si el bloque R5 se cayo antes de asignarlos,
        -- aqui valen nulo y el caso no puede medir nada.
        select max(id_concepto) into v_con_063 from islr_conceptos where codigo = '063';
        select max(id_concepto) into v_con_057 from islr_conceptos where codigo = '057';
        if v_usuario is null then
            select min(u.username) into v_usuario
              from usuario u
              join usuario_empresa ue on ue.usuario_id = u.usuario_id
             where ue.id_empresa = 1
               and u.estado in ('ACTIVO', 'A', '1');
        end if;

        if v_con_063 is null or v_con_057 is null or v_usuario is null then
            falla('R8', 'faltan los conceptos 057/063 o un usuario de la empresa 1');
        else
            -- El proveedor de la prueba: concepto 063 (tarifa plana 5 %, sin sustraendo).
            insert into proveedores (id_empresa, rif, razon_social, tipo_persona, cod_pais,
                                     estado, retener_iva, porcentaje_retencion, es_spe,
                                     dias_credito, id_concepto_islr)
            values (1, 'R8-ISLR-0001', 'Proveedor de prueba R8', 'J', 'VE',
                    'ACTIVO', 'N', 0, 'N', 0, v_con_063)
            returning id_proveedor into v_prov8;
            commit;

            -- (a) alta SIN pasar el concepto: lo hereda del proveedor.
            pkg_compras.prc_guardar_compra(
                p_id_compra            => v_a,
                p_id_empresa           => 1,
                p_id_proveedor         => v_prov8,
                p_tipo_documento       => 'FAC',
                p_folio_factura        => 'ISLR-T6-HEREDA',
                p_nro_control          => '00-999961',
                p_fecha_emision        => trunc(sysdate),
                p_cod_moneda           => 'VES',
                p_tipo_cambio          => 1,
                p_porcentaje_retencion => 0,
                p_usuario              => v_usuario);
            commit;

            select id_concepto_islr into v_con from compras where id_compra = v_a;
            if v_con is null or v_con <> v_con_063 then
                falla('R8', 'el alta sin concepto no heredo el del proveedor: '
                             || num(v_con) || ' en vez de ' || v_con_063);
            end if;

            -- (b) la actualizacion manda: se cambia al 057.
            pkg_compras.prc_guardar_compra(
                p_id_compra            => v_a,
                p_id_empresa           => 1,
                p_id_proveedor         => v_prov8,
                p_tipo_documento       => 'FAC',
                p_folio_factura        => 'ISLR-T6-HEREDA',
                p_nro_control          => '00-999961',
                p_fecha_emision        => trunc(sysdate),
                p_cod_moneda           => 'VES',
                p_tipo_cambio          => 1,
                p_porcentaje_retencion => 0,
                p_id_concepto_islr     => v_con_057,
                p_usuario              => v_usuario);
            commit;

            select id_concepto_islr into v_con from compras where id_compra = v_a;
            if v_con is null or v_con <> v_con_057 then
                falla('R8', 'la actualizacion no cambio el concepto: '
                             || num(v_con) || ' en vez de ' || v_con_057);
            end if;

            -- (b2) GUARDAR SIN PASAR EL PARAMETRO (centinela -1) NO BORRA EL CONCEPTO.
            -- Es la fuga que tenia la version anterior: la pantalla de la 28 no manda el
            -- item, y con "nulo borra" cada guardado de un borrador dejaba la compra sin
            -- ISLR y su comprobante no se emitia. Aqui se guarda igual que la pantalla
            -- (sin el parametro) y el concepto tiene que seguir siendo el 057 de (b).
            pkg_compras.prc_guardar_compra(
                p_id_compra            => v_a,
                p_id_empresa           => 1,
                p_id_proveedor         => v_prov8,
                p_tipo_documento       => 'FAC',
                p_folio_factura        => 'ISLR-T6-HEREDA',
                p_nro_control          => '00-999961',
                p_fecha_emision        => trunc(sysdate),
                p_cod_moneda           => 'VES',
                p_tipo_cambio          => 1,
                p_porcentaje_retencion => 0,
                p_usuario              => v_usuario);
            commit;

            select id_concepto_islr into v_con from compras where id_compra = v_a;
            if v_con is null or v_con <> v_con_057 then
                falla('R8', 'guardar sin pasar el parametro borro el concepto: '
                             || num(v_con) || ' en vez de ' || v_con_057);
            end if;

            -- (b3) 0 = sin concepto: es lo que mandara la pantalla cuando el usuario
            -- elija "sin concepto", y tiene que borrarlo.
            pkg_compras.prc_guardar_compra(
                p_id_compra            => v_a,
                p_id_empresa           => 1,
                p_id_proveedor         => v_prov8,
                p_tipo_documento       => 'FAC',
                p_folio_factura        => 'ISLR-T6-HEREDA',
                p_nro_control          => '00-999961',
                p_fecha_emision        => trunc(sysdate),
                p_cod_moneda           => 'VES',
                p_tipo_cambio          => 1,
                p_porcentaje_retencion => 0,
                p_id_concepto_islr     => 0,
                p_usuario              => v_usuario);
            commit;

            select id_concepto_islr into v_con from compras where id_compra = v_a;
            if v_con is not null then
                falla('R8', 'el 0 no borro el concepto (quedo ' || v_con || ')');
            end if;

            -- (c) un concepto explicito en el ALTA gana al del proveedor.
            pkg_compras.prc_guardar_compra(
                p_id_compra            => v_b,
                p_id_empresa           => 1,
                p_id_proveedor         => v_prov8,
                p_tipo_documento       => 'FAC',
                p_folio_factura        => 'ISLR-T6-EXPLICITA',
                p_nro_control          => '00-999962',
                p_fecha_emision        => trunc(sysdate),
                p_cod_moneda           => 'VES',
                p_tipo_cambio          => 1,
                p_porcentaje_retencion => 0,
                p_id_concepto_islr     => v_con_057,
                p_usuario              => v_usuario);
            commit;

            select id_concepto_islr into v_con from compras where id_compra = v_b;
            if v_con is null or v_con <> v_con_057 then
                falla('R8', 'el concepto explicito del alta no gano al del proveedor: '
                             || num(v_con) || ' en vez de ' || v_con_057);
            end if;

            -- La base del cliente sale como entro. Hijo primero y con commit en medio.
            -- Los comprobantes van delante por si R8 llega a registrar una compra: hoy
            -- no lo hace, pero si algun dia lo hace la suite tiene que seguir corriendo.
            delete from retenciones_det where id_compra in (v_a, v_b);
            commit;
            delete from retenciones where id_compra in (v_a, v_b);
            commit;
            delete from compras_det where id_compra in (v_a, v_b);
            commit;
            delete from compras where id_compra in (v_a, v_b);
            commit;
            delete from proveedores where id_proveedor = v_prov8;
            commit;
        end if;
    exception
        when others then
            falla('R8', 'el caso revento: ' || substrb(sqlerrm, 1, 140));
            -- Limpieza de mejor esfuerzo: si el caso se cayo a medias, lo que alcanzo a
            -- insertarse no se puede quedar (el proximo intento chocaria con el RIF).
            begin
                delete from retenciones_det where id_compra in (v_a, v_b);
                commit;
            exception when others then null;
            end;
            begin
                delete from retenciones where id_compra in (v_a, v_b);
                commit;
            exception when others then null;
            end;
            begin
                delete from compras_det where id_compra in (v_a, v_b);
                commit;
            exception when others then null;
            end;
            begin
                delete from compras where id_compra in (v_a, v_b);
                commit;
            exception when others then null;
            end;
            begin
                delete from proveedores where id_proveedor = v_prov8;
                commit;
            exception when others then null;
            end;
    end;

    -- -------------------------------------------------------------------------
    -- R12: las pantallas del final.
    --
    -- La 31 tiene que poder imprimir los DOS comprobantes (antes solo el de IVA,
    -- con el tipo clavado en la llamada), la 28 tiene que dejar elegir el concepto
    -- de ISLR y ofrecer el segundo boton, y la etiqueta del estado (Procesada) no
    -- puede tocar el valor guardado: de el dependen las condiciones de servidor, la
    -- emision y el libro.
    --
    -- Va aparte y con su propio manejador: es un caso de METADATOS, y si revienta
    -- no puede llevarse por delante la limpieza ni el RESULTADO.
    -- -------------------------------------------------------------------------
    declare
        v_txt varchar2(32767);
    begin
        select count(*) into v_n from apex_260100.apex_application_page_items
         where application_id = 100 and page_id = 31 and item_name = 'P31_TIPO';
        if v_n <> 1 then falla('R12', 'la pagina 31 no tiene P31_TIPO'); end if;

        -- El tipo viaja en la fuente de la region: si se queda en la llamada de una
        -- sola linea, el boton de ISLR imprime el papel de IVA sin avisar.
        select count(*) into v_n from apex_260100.apex_application_page_regions
         where application_id = 100 and page_id = 31 and region_static_id = 'retencion-print'
           and upper(region_source) like '%P31_TIPO%';
        if v_n <> 1 then falla('R12', 'la region del comprobante no usa el tipo'); end if;

        select count(*) into v_n from apex_260100.apex_application_page_items
         where application_id = 100 and page_id = 28 and item_name = 'P28_ID_CONCEPTO_ISLR';
        if v_n <> 1 then falla('R12', 'la pagina 28 no tiene el concepto de ISLR'); end if;

        select count(*) into v_n from apex_260100.apex_application_page_buttons
         where application_id = 100 and page_id = 28 and button_name = 'BTN_IMPRIMIR_RET_ISLR';
        if v_n <> 1 then falla('R12', 'la pagina 28 no tiene el boton del comprobante de ISLR'); end if;

        if fn_estado_compra('REGISTRADA') <> 'Procesada' then
            falla('R12', 'la etiqueta de REGISTRADA no es Procesada');
        end if;
        if fn_estado_compra('BORRADOR') <> 'Borrador' or fn_estado_compra('ANULADA') <> 'Anulada' then
            falla('R12', 'las otras etiquetas de estado no cuadran');
        end if;
        -- Un valor que no es un estado conocido se devuelve tal cual: la funcion es
        -- solo para mostrar y no puede inventarse etiquetas.
        if fn_estado_compra('OTRO') <> 'OTRO' then
            falla('R12', 'fn_estado_compra cambia un estado que no conoce');
        end if;

        -- El valor guardado NO se toca. En vez de exigir que quede una compra en
        -- REGISTRADA (eso depende de los datos del cliente y se pone rojo el dia que
        -- se procese la ultima), se comprueba el invariante de verdad: que ninguna
        -- compra tenga guardada una ETIQUETA en ESTADO.
        select count(*) into v_n from compras
         where estado in ('Borrador', 'Procesada', 'Anulada');
        if v_n > 0 then
            falla('R12', 'hay ' || v_n || ' compras con la etiqueta guardada en ESTADO');
        end if;

        -- El guardado de la 28 tiene que mandar el concepto con el centinela 0 y NO
        -- con nullif: el paquete usa -1 para "no lo toco" y 0 para "sin concepto", y
        -- nullif convertiria un item vacio en "no lo toco"... o al reves, borraria el
        -- concepto heredado. Es la trampa que costo la tarea 6.
        v_txt := ' ';
        for r in (select process_source from apex_260100.apex_application_page_proc
                   where application_id = 100 and page_id = 28
                     and static_id = 'guardar-compra') loop
            v_txt := v_txt || r.process_source;
        end loop;
        if instr(lower(v_txt), 'p_id_concepto_islr') = 0 then
            falla('R12', 'el guardado de la 28 no manda el concepto de ISLR');
        elsif instr(lower(v_txt), 'nullif(fn_clean_num(:p28_id_concepto_islr)') > 0 then
            falla('R12', 'el guardado de la 28 usa nullif en el concepto (tiene que ser 0)');
        end if;

        -- El resumen y el detalle de la compra NO pueden pintarse con un id ajeno: el
        -- item P28_ID_COMPRA no esta protegido y un POST con el id de otra empresa
        -- ensenaria sus importes y sus lineas. La condicion de region los apaga.
        select count(*) into v_n from apex_260100.apex_application_page_regions
         where application_id = 100 and page_id = 28
           and region_static_id in ('compra-resumen', 'compra-lineas')
           and condition_type_code = 'EXISTS'
           and lower(condition_expression1) like '%id_empresa%'
           and lower(condition_expression1) like '%f_empresa_activa%';
        if v_n <> 2 then
            falla('R12', 'el resumen y el detalle no filtran la empresa por condicion (' || v_n || ' de 2)');
        end if;

        -- El boton del comprobante de ISLR depende del COMPROBANTE emitido, no del
        -- concepto: por debajo del umbral no hay papel y el boton imprimiria nada.
        -- Va como expresion PL/SQL (como el resto de botones de la app) y la
        -- comprobacion vive en fn_compra_tiene_islr: una condicion PL/SQL no admite
        -- subconsultas y no queremos depender del BOOLEAN en SQL de 23ai+.
        select count(*) into v_n from apex_260100.apex_application_page_buttons
         where application_id = 100 and page_id = 28
           and button_name = 'BTN_IMPRIMIR_RET_ISLR'
           and condition_type_code = 'EXPRESSION'
           and upper(nvl(condition_expression2, '#')) = 'PLSQL'
           and lower(condition_expression1) like '%fn_compra_tiene_islr%';
        if v_n <> 1 then
            falla('R12', 'el boton del comprobante de ISLR no depende del comprobante emitido');
        end if;

        -- El estado de un comprobante anulado es 'ANULADO', no 'ANULADA': con el
        -- literal equivocado la condicion nunca era cierta y el boton salia igual.
        v_txt := ' ';
        for r in (select text from all_source
                   where owner = 'WKSP_SYPEXWS' and name = 'FN_COMPRA_TIENE_ISLR'
                     and type = 'FUNCTION' order by line) loop
            v_txt := v_txt || r.text;
        end loop;
        if instr(lower(v_txt), '''anulado''') = 0 then
            falla('R12', 'fn_compra_tiene_islr no descarta el comprobante ANULADO');
        end if;
        if instr(lower(v_txt), '''anulada''') > 0 then
            falla('R12', 'fn_compra_tiene_islr compara contra ANULADA (es ANULADO)');
        end if;

        -- La pagina 31 (el comprobante) comprueba que la compra sea de una empresa
        -- del usuario: la funcion de impresion solo recibe el id.
        select count(*) into v_n from apex_260100.apex_application_page_proc
         where application_id = 100 and page_id = 31
           and static_id = 'valida-empresa-retencion'
           and lower(process_source) like '%fn_usuario_empresa_valida%';
        if v_n <> 1 then
            falla('R12', 'la pagina 31 no comprueba la empresa del comprobante');
        end if;
    exception
        when others then
            falla('R12', 'el caso revento: ' || substrb(sqlerrm, 1, 140));
    end;

    -- -------------------------------------------------------------------------
    -- R18-R22: el cierre de la revision final (2026-11-20).
    --
    -- Todo dentro de un savepoint que se revierte al final: estos casos registran
    -- compras de verdad y emiten comprobantes (numeracion incluida).
    -- -------------------------------------------------------------------------
    savepoint sp_cierre;
    declare
        v_emp2    number := 2;
        v_prov2   number;
        v_usr2    varchar2(100);
        v_compra2 number;
        v_cont_a  number;
        v_cont_b  number;
        v_estado2 varchar2(20);
        v_id19    number;
        v_id20    number;
        v_id      number;
        v_tasa    number;
        v_m       number;
        v_g       number;
        v_prev    number;
        v_emit    number;
        v_suma    number;
        v_n2      number;
        v_txt2    varchar2(32767);
        v_con     number;
        v_ok      boolean;
    begin
        -- ---------------------------------------------------------------------
        -- R18 (C1): la compra de OTRA empresa no se registra ni se anula.
        -- ---------------------------------------------------------------------
        begin
            select min(u.username) into v_usr2
              from usuario u
              join usuario_empresa ue on ue.usuario_id = u.usuario_id
             where ue.id_empresa = v_emp2
               and u.estado in ('ACTIVO', 'A', '1');

            if v_usr2 is null then
                falla('R18', 'no hay usuario de la empresa 2 para la prueba');
            else
                insert into proveedores (id_empresa, rif, razon_social, tipo_persona, cod_pais,
                                         estado, retener_iva, porcentaje_retencion, es_spe,
                                         dias_credito)
                values (v_emp2, 'CIERRE-T8-PROV', 'Proveedor de prueba del cierre', 'J', 'MX',
                        'ACTIVO', 'S', 75, 'N', 0)
                returning id_proveedor into v_prov2;

                pkg_compras.prc_guardar_compra(
                    p_id_compra      => v_compra2,
                    p_id_empresa     => v_emp2,
                    p_id_proveedor   => v_prov2,
                    p_tipo_documento => 'FAC',
                    p_folio_factura  => 'CIERRE-T8-1',
                    p_nro_control    => '00-999941',
                    p_fecha_emision  => trunc(sysdate),
                    p_cod_moneda     => 'VES',
                    p_tipo_cambio    => 1,
                    p_usuario        => v_usr2);

                pkg_compra_detalle.guardar_detalle(
                    p_id_detalle           => v_id,
                    p_id_compra            => v_compra2,
                    p_num_linea            => 1,
                    p_id_producto_servicio => null,
                    p_descripcion          => 'Linea de prueba del cierre',
                    p_cantidad             => 1,
                    p_precio_unitario      => 100,
                    p_porcentaje_descuento => 0,
                    p_monto_descuento      => 0,
                    p_id_impuesto          => null,
                    p_porcentaje_impuesto  => 16,
                    p_usuario              => v_usr2);

                select nvl(max(ultimo), 0) into v_cont_a
                  from retencion_contador
                 where id_empresa = v_emp2 and periodo = to_char(sysdate, 'YYYYMM');

                -- El intruso es el usuario de la empresa 1.
                v_ok := false;
                begin
                    pkg_compras.prc_registrar_compra(v_compra2, v_usuario);
                exception
                    when others then
                        v_ok := (sqlcode = -20003);
                end;
                if not v_ok then
                    falla('R18', 'registrar la compra de otra empresa no dio -20003');
                end if;

                v_ok := false;
                begin
                    pkg_compras.prc_anular_compra(v_compra2, v_usuario);
                exception
                    when others then
                        v_ok := (sqlcode = -20003);
                end;
                if not v_ok then
                    falla('R18', 'anular la compra de otra empresa no dio -20003');
                end if;

                -- Y tampoco se reescribe la cabecera con la empresa de uno.
                v_ok := false;
                begin
                    pkg_compras.prc_guardar_compra(
                        p_id_compra      => v_compra2,
                        p_id_empresa     => 1,
                        p_id_proveedor   => v_prov,
                        p_folio_factura  => 'CIERRE-T8-1',
                        p_fecha_emision  => trunc(sysdate),
                        p_cod_moneda     => 'VES',
                        p_tipo_cambio    => 1,
                        p_usuario        => v_usuario);
                exception
                    when others then
                        v_ok := (sqlcode = -20003);
                end;
                if not v_ok then
                    falla('R18', 'guardar una compra ajena no dio -20003');
                end if;

                select estado into v_estado2 from compras where id_compra = v_compra2;
                select nvl(max(ultimo), 0) into v_cont_b
                  from retencion_contador
                 where id_empresa = v_emp2 and periodo = to_char(sysdate, 'YYYYMM');
                select count(*) into v_n2 from retenciones where id_compra = v_compra2;

                if v_estado2 <> 'BORRADOR' or v_n2 > 0 or v_cont_b <> v_cont_a then
                    falla('R18', 'el POST ajeno dejo la compra ' || v_estado2 || ', emitio '
                                  || v_n2 || ' comprobante(s) o consumio numeracion de la empresa 2');
                end if;

                -- Control positivo: el usuario de la empresa duena si la registra.
                pkg_compras.prc_registrar_compra(v_compra2, v_usr2);
                select count(*) into v_n2 from retenciones
                 where id_compra = v_compra2 and tipo = 'IVA';
                if v_n2 <> 1 then
                    falla('R18', 'el usuario de la empresa duena no pudo registrar su compra');
                end if;
            end if;
        exception
            when others then
                falla('R18', 'el caso revento: ' || substrb(sqlerrm, 1, 120));
        end;

        -- ---------------------------------------------------------------------
        -- R19 (I2): el resumen del BORRADOR y el comprobante dicen lo mismo en divisa.
        -- ---------------------------------------------------------------------
        begin
            select fn_tasa_ves(trunc(sysdate), 'USD') into v_tasa from dual;
            if v_tasa is null or v_tasa <= 1 then
                falla('R19', 'no hay tasa USD del dia para la compra en divisa');
            else
                -- Importe de IVA por grupo que hace que el 75 % NO sea exacto: con el,
                -- sacar el porcentaje de la SUMA (como antes) se separa un centimo del
                -- papel. Se busca con la tasa real del dia, no con un numero clavado.
                v_m := 0.01;
                for i in 1 .. 40 loop
                    v_g := round(v_m * v_tasa, 2);
                    if round(v_g * 0.75, 2) <> v_g * 0.75 then
                        v_m := round(v_m, 4); exit;
                    end if;
                    v_m := round(v_m + 0.01, 2);
                end loop;

                crea_compra('CIERRE-T8-USD', '00-999942', 'USD', v_tasa, 75, v_id19);
                crea_linea(v_id19, 1, 'Linea al 16 por ciento', round(v_m * 100 / 16, 4), 1, 16);
                crea_linea(v_id19, 2, 'Linea al 8 por ciento', round(v_m * 100 / 8, 4), 5, 8);

                v_prev := pkg_retenciones.fn_retencion_bs(v_id19);
                pkg_compras.prc_registrar_compra(v_id19, v_usuario);

                select retenido_bs into v_emit
                  from retenciones
                 where id_compra = v_id19 and tipo = 'IVA';
                select nvl(sum(d.retenido_bs), 0) into v_suma
                  from retenciones_det d
                  join retenciones h on h.id_retencion = d.id_retencion
                 where h.id_compra = v_id19 and h.tipo = 'IVA';

                if v_prev <> v_emit then
                    falla('R19', 'el resumen dice ' || num(v_prev) || ' y el comprobante '
                                  || num(v_emit));
                end if;
                if v_suma <> v_emit then
                    falla('R19', 'las lineas suman ' || num(v_suma) || ' y la cabecera '
                                  || num(v_emit));
                end if;

                select count(*) into v_n2
                  from retenciones_det d
                  join retenciones h on h.id_retencion = d.id_retencion
                 where h.id_compra = v_id19 and h.tipo = 'IVA'
                   and nvl(d.base_imponible_bs, 0) > 0
                   and nvl(d.retenido_bs, 0) = 0;
                if v_n2 > 0 then
                    falla('R19', 'hay ' || v_n2 || ' linea(s) con base y retenido 0,00');
                end if;

                if not fn_compra_tiene_iva(v_id19) then
                    falla('R19', 'la compra registrada no tiene comprobante de IVA');
                end if;
            end if;
        exception
            when others then
                falla('R19', 'el caso revento: ' || substrb(sqlerrm, 1, 120));
        end;

        -- ---------------------------------------------------------------------
        -- R20 (I3): sin papel emitido no hay boton de imprimir.
        -- ---------------------------------------------------------------------
        begin
            crea_compra('CIERRE-T8-SIN', '00-999943', 'VES', 1, 0, v_id20);
            crea_linea(v_id20, 1, 'Linea al 16 por ciento', 1000, 1, 16);
            pkg_compras.prc_registrar_compra(v_id20, v_usuario);

            if fn_compra_tiene_iva(v_id20) then
                falla('R20', 'una compra sin retencion dice tener comprobante de IVA');
            end if;
            select count(*) into v_n2 from retenciones where id_compra = v_id20;
            if v_n2 <> 0 then
                falla('R20', 'una compra al 0 % emitio ' || v_n2 || ' comprobante(s)');
            end if;

            select count(*) into v_n2 from apex_260100.apex_application_page_buttons
             where application_id = 100 and page_id = 28
               and button_name = 'BTN_IMPRIMIR_RETENCION'
               and lower(condition_expression1) like '%fn_compra_tiene_iva%';
            if v_n2 <> 1 then
                falla('R20', 'el boton del comprobante de IVA no depende del comprobante emitido');
            end if;
        exception
            when others then
                falla('R20', 'el caso revento: ' || substrb(sqlerrm, 1, 120));
        end;

        -- ---------------------------------------------------------------------
        -- R21 (I1): el concepto por defecto del proveedor se fija en la pagina 23.
        -- ---------------------------------------------------------------------
        begin
            select count(*) into v_n2 from apex_260100.apex_application_page_items
             where application_id = 100 and page_id = 23
               and item_name = 'P23_ID_CONCEPTO_ISLR';
            if v_n2 <> 1 then
                falla('R21', 'la pagina 23 no tiene el concepto de ISLR');
            end if;

            v_txt2 := ' ';
            for r in (select process_source from apex_260100.apex_application_page_proc
                       where application_id = 100 and page_id = 23
                         and static_id = 'carga-proveedor') loop
                v_txt2 := v_txt2 || r.process_source;
            end loop;
            if instr(lower(v_txt2), 'p23_id_concepto_islr') = 0 then
                falla('R21', 'la carga de la 23 no trae el concepto del proveedor');
            end if;

            v_txt2 := ' ';
            for r in (select process_source from apex_260100.apex_application_page_proc
                       where application_id = 100 and page_id = 23
                         and static_id = 'guardar-proveedor') loop
                v_txt2 := v_txt2 || r.process_source;
            end loop;
            if instr(lower(v_txt2), 'id_concepto_islr') = 0
               or instr(lower(v_txt2), 'nullif(fn_clean_num(:p23_id_concepto_islr)') = 0 then
                falla('R21', 'el guardado de la 23 no escribe el concepto con 0 -> null');
            end if;

            v_txt2 := ' ';
            for r in (select lov_definition from apex_260100.apex_application_page_items
                       where application_id = 100 and page_id = 23
                         and item_name = 'P23_ID_CONCEPTO_ISLR') loop
                v_txt2 := v_txt2 || nvl(r.lov_definition, ' ');
            end loop;
            if instr(lower(v_txt2), 'activo') = 0 or instr(lower(v_txt2), 'tarifa') = 0 then
                falla('R21', 'la lista de la 23 no filtra los activos o no ensena la tarifa');
            end if;

            -- Comportamiento: el concepto que quede en el proveedor lo hereda la compra.
            update proveedores set id_concepto_islr = v_con_063 where id_proveedor = v_prov;
            crea_compra('CIERRE-T8-HER', '00-999944', 'VES', 1, 0, v_id);
            select id_concepto_islr into v_con from compras where id_compra = v_id;
            if nvl(v_con, -1) <> v_con_063 then
                falla('R21', 'la compra no heredo el concepto del proveedor');
            end if;
            update proveedores set id_concepto_islr = null where id_proveedor = v_prov;
        exception
            when others then
                falla('R21', 'el caso revento: ' || substrb(sqlerrm, 1, 120));
        end;

        -- ---------------------------------------------------------------------
        -- R22 (I4): cambiar la tasa de un BORRADOR reprecia sus lineas.
        -- ---------------------------------------------------------------------
        begin
            select fn_tasa_ves(trunc(sysdate), 'USD') into v_tasa from dual;
            crea_compra('CIERRE-T8-TASA', '00-999945', 'VES', 1, 0, v_id);
            crea_linea(v_id, 1, 'Linea de la repreciacion', 100, 1, 16);

            pkg_compras.prc_guardar_compra(
                p_id_compra            => v_id,
                p_id_empresa           => 1,
                p_id_proveedor         => v_prov,
                p_tipo_documento       => 'FAC',
                p_folio_factura        => 'CIERRE-T8-TASA',
                p_nro_control          => '00-999945',
                p_fecha_emision        => trunc(sysdate),
                p_cod_moneda           => 'USD',
                p_tipo_cambio          => v_tasa,
                p_porcentaje_retencion => 0,
                p_usuario              => v_usuario);

            select count(*) into v_n2 from compras_det
             where id_compra = v_id
               and tasa_cambio_aplicada = v_tasa
               and subtotal_bs = round(subtotal_linea * v_tasa, 2)
               and total_bs = round(total_linea * v_tasa, 2);
            if v_n2 <> 1 then
                falla('R22', 'cambiar la tasa del borrador no reprecia la linea');
            end if;

            select count(*) into v_n2 from compras
             where id_compra = v_id and tipo_cambio = v_tasa;
            if v_n2 <> 1 then
                falla('R22', 'la cabecera no tomo la tasa nueva');
            end if;
        exception
            when others then
                falla('R22', 'el caso revento: ' || substrb(sqlerrm, 1, 120));
        end;
    end;

    -- Nada de esto se queda: compras, comprobantes y numeracion vuelven a su sitio.
    rollback to savepoint sp_cierre;

    -- El proveedor de fixture de las compras de prueba tampoco se queda: la base del
    -- cliente sale como entro. Si no se puede borrar es que quedo una compra colgada y
    -- hay que decirlo, no reventar sin RESULTADO.
    begin
        delete from proveedores where id_empresa = 1 and rif = 'ISLR-T5-PROV';
        commit;
    exception
        when others then
            rollback;
            falla('LIMPIEZA', 'el proveedor de fixture no se pudo borrar: '
                              || substrb(sqlerrm, 1, 100));
    end;

    raise_application_error(-20100,
        substrb('RESULTADO: FALLAS=' || v_fallas || v_lista, 1, 3000));
end;
/
