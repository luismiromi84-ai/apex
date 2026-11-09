-- =============================================================================
-- Verificacion de pkg_factura_detalle.copiar_lineas_de_factura (2026-11-09)
--
-- Copia a la nota SOLO las lineas marcadas de la factura que acredita, con sus
-- importes y su alicuota de IVA tal como estaban, y aplica los topes.
--
-- Todo va en una transaccion con ROLLBACK: no deja documentos de prueba.
-- Cada caso limpia sus lineas antes del siguiente, porque el tope de cantidad es
-- acumulativo entre notas de credito y, si no se limpia, envenena los de despues.
--
-- Casos:
--   C1  copiar una linea: importes e impuesto identicos, id_detalle_origen apunta
--       a esa linea de la factura
--   C2  la cabecera recalcula por el trigger y su total es el de la linea
--   C3  lista vacia -> -20046
--   C4  la nota ya tiene lineas -> -20045
--   C5  un id_detalle de otro documento -> -20047 y la nota sin lineas
--   C6  pasarse de la cantidad facturada -> -20048
--   C7  factura de origen sin lineas -> mensaje propio, 0 filas
--   C8  el mismo id dos veces en la lista no duplica la linea
--   C9  dos lineas del origen con el mismo producto se copian las dos, y el tope
--       de cada una es independiente
--   C10 copiar_desde_factura (todas) sigue copiando todas
--   C11 en una nota de debito -> -20047 (el selector es solo para NC)
--   C12 una linea del origen con id_producto nulo se copia igual
--   C13 si cambia el porcentaje en IMPUESTOS despues de facturar, la linea
--       copiada conserva el de la factura
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;
/

declare
  v_fallas number := 0;
  v_lista  varchar2(3000) := '';
  v_emp    number := 1;
  v_origen number;
  v_nota   number;
  v_nota2  number;
  v_nota3  number;
  v_lin1   number;
  v_lin2   number;
  v_n      number;
  v_t      number;
  v_tx     number;
  v_cant   number;
  v_prec   number;
  v_ptot   number;
  v_imon   number;
  v_ipct   number;
  v_moneda varchar2(10);
  v_tasa   number;
  v_cli    number;

  procedure falla (p_caso in varchar2, p_detalle in varchar2) is
  begin
    v_fallas := v_fallas + 1;
    v_lista  := v_lista || ' | ' || p_caso || ': ' || p_detalle;
  end falla;

  -- Crea una nota (NC o ND) sobre la factura de origen y devuelve su id.
  procedure nueva_nota (p_tipo in varchar2, p_origen in number, p_id out number) is
  begin
    p_id := null;
    pkg_facturacion.prc_guardar_factura(
        p_id_factura        => p_id,
        p_id_empresa        => v_emp,
        p_folio_factura     => null,
        p_id_cliente        => v_cli,
        p_id_presupuesto    => null,
        p_rfc_emisor        => 'EMP123456789',
        p_rfc_receptor      => null,
        p_uuid_fiscal       => null,
        p_uso_cfdi          => null,
        p_forma_pago        => null,
        p_metodo_pago       => null,
        p_condicion_pago    => null,
        p_fecha_emision     => to_char(sysdate, 'DD/MM/YYYY'),
        p_fecha_vencimiento => null,
        p_estado            => 'PENDIENTE',
        p_subtotal          => 0,
        p_monto_impuesto    => 0,
        p_monto_total       => 0,
        p_observaciones     => 'verificacion copiar lineas',
        p_cod_moneda        => v_moneda,
        p_tipo_cambio       => v_tasa,
        p_usuario           => 'VERIFICACION',
        p_tipo_documento    => p_tipo,
        p_id_factura_origen => p_origen);
  end nueva_nota;

  -- Deja la nota sin lineas: el tope por cantidad es acumulativo.
  procedure limpiar (p_id in number) is
  begin
    delete from facturas_det where id_factura = p_id;
  end limpiar;

begin
  -- ---------------------------------------------------------------- datos base
  select id_factura into v_origen
    from (select f.id_factura
            from facturas f
           where f.id_empresa = v_emp
             and f.tipo_documento = 'FAC'
             and f.estado <> 'ANULADA'
             and (select count(*) from facturas_det d where d.id_factura = f.id_factura) >= 2
           order by f.id_factura asc)
   where rownum = 1;

  select cod_moneda, tipo_cambio, id_cliente into v_moneda, v_tasa, v_cli
    from facturas where id_factura = v_origen;

  select id_detalle into v_lin1
    from (select id_detalle from facturas_det where id_factura = v_origen
           order by id_detalle) where rownum = 1;
  select id_detalle into v_lin2
    from (select id_detalle from facturas_det where id_factura = v_origen
           order by id_detalle) offset 1 rows fetch next 1 rows only;

  select cantidad, precio_unitario, monto_total_linea, id_impuesto, porcentaje_impuesto
    into v_cant, v_prec, v_ptot, v_imon, v_ipct
    from facturas_det where id_detalle = v_lin1;

  nueva_nota('NC', v_origen, v_nota);

  -- C1: copiar una sola linea
  pkg_factura_detalle.copiar_lineas_de_factura(v_nota, v_origen, to_char(v_lin1), 'VERIFICACION');

  select count(*) into v_n from facturas_det where id_factura = v_nota;
  if v_n <> 1 then
    falla('C1', 'la nota quedo con ' || v_n || ' linea(s) en vez de 1');
  else
    select count(*) into v_n
      from facturas_det d
     where d.id_factura = v_nota
       and d.id_detalle_origen = v_lin1
       and d.cantidad = v_cant
       and d.precio_unitario = v_prec
       and nvl(d.id_impuesto, -1) = nvl(v_imon, -1)
       and nvl(d.porcentaje_impuesto, -1) = nvl(v_ipct, -1);
    if v_n <> 1 then
      falla('C1', 'la linea copiada no coincide con la original (importes o impuesto)');
    end if;
  end if;

  -- C2: la cabecera la recalculo el trigger
  select monto_total into v_t from facturas where id_factura = v_nota;
  if abs(v_t - v_ptot) > 0.01 then
    falla('C2', 'el total de la nota es ' || v_t || ' y la linea original ' || v_ptot);
  end if;

  -- C4: con lineas dentro, no deja copiar otra vez
  begin
    pkg_factura_detalle.copiar_lineas_de_factura(v_nota, v_origen, to_char(v_lin2), 'VERIFICACION');
    falla('C4', 'acepto copiar en una nota que ya tenia lineas');
  exception
    when others then
      if sqlcode <> -20045 then falla('C4', 'esperaba -20045 y fue ' || sqlcode); end if;
  end;
  limpiar(v_nota);

  -- C3: lista vacia
  nueva_nota('NC', v_origen, v_nota2);
  begin
    pkg_factura_detalle.copiar_lineas_de_factura(v_nota2, v_origen, null, 'VERIFICACION');
    falla('C3', 'acepto una lista vacia');
  exception
    when others then
      if sqlcode <> -20046 then falla('C3', 'esperaba -20046 y fue ' || sqlcode); end if;
  end;

  -- C5: un id_detalle que no es de la factura (se usa una linea de otra nota)
  pkg_factura_detalle.copiar_lineas_de_factura(v_nota, v_origen, to_char(v_lin1), 'VERIFICACION');
  select id_detalle into v_tx from facturas_det where id_factura = v_nota and rownum = 1;
  begin
    pkg_factura_detalle.copiar_lineas_de_factura(v_nota2, v_origen, to_char(v_tx), 'VERIFICACION');
    falla('C5', 'acepto una linea que no es de la factura que acredita');
  exception
    when others then
      if sqlcode <> -20047 then falla('C5', 'esperaba -20047 y fue ' || sqlcode); end if;
  end;
  select count(*) into v_n from facturas_det where id_factura = v_nota2;
  if v_n <> 0 then
    falla('C5', 'dejo ' || v_n || ' linea(s) en la nota tras rechazar la seleccion');
  end if;
  limpiar(v_nota);

  -- C6: pasarse de la cantidad facturada. Se acredita la linea completa en una
  -- nota y se infla su cantidad (como haria la pagina 10) para que la siguiente
  -- nota se pase.
  nueva_nota('NC', v_origen, v_nota3);
  pkg_factura_detalle.copiar_lineas_de_factura(v_nota3, v_origen, to_char(v_lin1), 'VERIFICACION');
  update facturas_det set cantidad = v_cant + 1 where id_factura = v_nota3 and id_detalle_origen = v_lin1;
  begin
    pkg_factura_detalle.copiar_lineas_de_factura(v_nota2, v_origen, to_char(v_lin1), 'VERIFICACION');
    falla('C6', 'acepto acreditar mas cantidad de la facturada');
  exception
    when others then
      if sqlcode <> -20048 then falla('C6', 'esperaba -20048 y fue ' || sqlcode); end if;
  end;
  limpiar(v_nota3);

  -- C7: factura de origen sin lineas
  insert into facturas (id_empresa, folio_factura, id_cliente, fecha_emision, estado,
                        cod_moneda, tipo_cambio, tipo_documento, creado_por,
                        subtotal, monto_impuesto, monto_total)
  values (v_emp, 'F-VACIA-' || to_char(systimestamp, 'HH24MISSFF3'), v_cli, sysdate, 'PENDIENTE',
          'VES', 1, 'FAC', 'VERIFICACION', 0, 0, 0)
  returning id_factura into v_tx;
  nueva_nota('NC', v_tx, v_nota3);
  begin
    pkg_factura_detalle.copiar_lineas_de_factura(v_nota3, v_tx, to_char(v_lin1), 'VERIFICACION');
    falla('C7', 'acepto copiar de una factura sin lineas');
  exception
    when others then
      if sqlcode not in (-20046, -20047) then
        falla('C7', 'esperaba -20046/-20047 y fue ' || sqlcode);
      end if;
  end;
  select count(*) into v_n from facturas_det where id_factura = v_nota3;
  if v_n <> 0 then
    falla('C7', 'dejo ' || v_n || ' linea(s) de una factura sin lineas');
  end if;

  -- C8: el mismo id dos veces no duplica
  pkg_factura_detalle.copiar_lineas_de_factura(
      v_nota2, v_origen, to_char(v_lin2) || ',' || to_char(v_lin2), 'VERIFICACION');
  select count(*) into v_n from facturas_det where id_factura = v_nota2;
  if v_n <> 1 then
    falla('C8', 'la lista repetida dejo ' || v_n || ' linea(s) en vez de 1');
  end if;
  limpiar(v_nota2);

  -- C9: dos lineas del origen con el mismo producto, con topes independientes
  update facturas_det set id_producto = (select id_producto from facturas_det where id_detalle = v_lin1) where id_detalle = v_lin2;
  pkg_factura_detalle.copiar_lineas_de_factura(
      v_nota2, v_origen, to_char(v_lin1) || ',' || to_char(v_lin2), 'VERIFICACION');
  select count(*) into v_n from facturas_det where id_factura = v_nota2;
  if v_n <> 2 then
    falla('C9', 'copio ' || v_n || ' lineas del mismo producto en vez de 2');
  end if;
  limpiar(v_nota2);

  -- C10: copiar_desde_factura sigue copiando todas
  pkg_factura_detalle.copiar_desde_factura(v_nota2, v_origen, 'VERIFICACION');
  select count(*) into v_n from facturas_det where id_factura = v_nota2;
  select count(*) into v_tx from facturas_det where id_factura = v_origen;
  if v_n <> v_tx then
    falla('C10', 'copiar_desde_factura copio ' || v_n || ' de ' || v_tx || ' lineas');
  end if;
  select count(*) into v_n from facturas_det
   where id_factura = v_nota2 and id_detalle_origen is null;
  if v_n > 0 then
    falla('C10', v_n || ' linea(s) sin id_detalle_origen al copiar todas');
  end if;
  limpiar(v_nota2);

  -- C11: en una nota de debito no se copia
  nueva_nota('ND', v_origen, v_nota3);
  begin
    pkg_factura_detalle.copiar_lineas_de_factura(v_nota3, v_origen, to_char(v_lin1), 'VERIFICACION');
    falla('C11', 'acepto copiar lineas en una nota de debito');
  exception
    when others then
      if sqlcode <> -20047 then falla('C11', 'esperaba -20047 y fue ' || sqlcode); end if;
  end;

  -- C12: linea del origen sin producto
  insert into facturas_det (id_factura, num_linea, descripcion, cantidad, precio_unitario,
                            porcentaje_descuento, monto_descuento, porcentaje_impuesto,
                            monto_impuesto, subtotal_linea, monto_total_linea, creado_por)
  values (v_origen, 90, 'linea sin producto', 1, 10, 0, 0, 0, 0, 10, 10, 'VERIFICACION')
  returning id_detalle into v_tx;
  pkg_factura_detalle.copiar_lineas_de_factura(v_nota2, v_origen, to_char(v_tx), 'VERIFICACION');
  select count(*) into v_n from facturas_det
   where id_factura = v_nota2 and id_detalle_origen = v_tx and id_producto is null;
  if v_n <> 1 then
    falla('C12', 'no copio la linea sin producto (' || v_n || ')');
  end if;
  limpiar(v_nota2);
  delete from facturas_det where id_detalle = v_tx;

  -- C13: cambiar la alicuota despues de facturar no cambia la de la nota
  update impuestos set porcentage = 8 where id_impuesto = v_imon;
  pkg_factura_detalle.copiar_lineas_de_factura(v_nota2, v_origen, to_char(v_lin1), 'VERIFICACION');
  select nvl(porcentaje_impuesto, -1) into v_n
    from facturas_det where id_factura = v_nota2 and id_detalle_origen = v_lin1;
  if abs(v_n - v_ipct) > 0.01 then
    falla('C13', 'la nota quedo con ' || v_n || '% y la factura con ' || v_ipct || '%');
  end if;
  limpiar(v_nota2);

  rollback;

  raise_application_error(-20100, 'RESULTADO: FALLAS=' || v_fallas || v_lista);
end;
/
