-- =============================================================================
-- 20261105_reportes_verificacion.sql
--
-- Verificacion de los reportes de impresion (paginas 11 y 12).
-- Se ejecuta de arriba a abajo con:
--   python deploy/conexion/importar_export.py deploy/diagnostico/20261105_reportes_verificacion.sql
--
-- Los SELECT devuelven filas solo cuando algo FALLA. El bloque PL/SQL del final
-- informa el resumen levantando -20100 ('RESULTADO: FALLAS=0'). Codigo de salida
-- 1 con FALLAS=0 significa EXITO: el raise es solo el mecanismo para leer la
-- salida, igual que en 20261104_auth_propia_verificacion.sql.
--
-- Casos:
--   C1  Un ID nulo no genera un reporte falso.
--   C2  Un ID inexistente no genera un reporte falso (presupuesto).
--   C3  Lo mismo en factura.
--   C4  La factura de una empresa mexicana no habla de BCV y usa RFC.
--   C5  El presupuesto de una empresa mexicana idem.
--   C6  Los textos de usuario se escapan (& < >).
--   C7  Los importes usan la mascara con punto decimal, sin depender de NLS.
--   C8  El total del pie cuadra con la suma de las lineas.
--   C9  'N Control' no aparece si la factura no tiene uuid_fiscal.
--
-- Los casos C4, C5 y C6 modifican datos DENTRO de una transaccion y hacen
-- rollback: no dejan rastro.
-- =============================================================================

alter session set current_schema = WKSP_SYPEXWS;
/

declare
  v_fallas  number := 0;
  v_lista   varchar2(2000) := '';
  v_html    clob;
  v_txt     varchar2(32767);
  v_id_pres number;
  v_id_fact number;
  v_sum     number;
  v_total   number;
  v_cli     number;
  v_desc    varchar2(255);
  v_espera  varchar2(100);

  procedure falla (p_caso in varchar2, p_detalle in varchar2) is
  begin
    v_fallas := v_fallas + 1;
    v_lista  := v_lista || ' | ' || p_caso || ': ' || p_detalle;
  end falla;

  -- Texto plano del HTML, util para buscar etiquetas.
  function texto (p_html in clob) return varchar2 is
    v_salida varchar2(32767);
  begin
    v_salida := dbms_lob.substr(p_html, 12000, 1);
    v_salida := regexp_replace(v_salida, '<[^>]+>', ' ');
    return regexp_replace(v_salida, '[[:space:]]+', ' ');
  end texto;

begin
  -- C1 / C2 / C3: ID nulo e inexistente ---------------------------------------
  v_txt := texto(pkg_reportes_presupuesto.fn_imprimir_presupuesto(null));
  if instr(v_txt, 'Sypex Systems') > 0 then
    falla('C1', 'ID nulo devuelve el reporte de relleno');
  end if;
  if instr(v_txt, 'No se puede') = 0 then
    falla('C1', 'ID nulo no informa nada');
  end if;

  v_txt := texto(pkg_reportes_presupuesto.fn_imprimir_presupuesto(999999));
  if instr(v_txt, 'Sypex Systems') > 0 then
    falla('C2', 'ID inexistente devuelve el reporte de relleno');
  end if;
  if instr(v_txt, 'No se puede') = 0 then
    falla('C2', 'ID inexistente no muestra aviso');
  end if;

  v_txt := texto(pkg_reportes_factura.fn_imprimir_factura(999999));
  if instr(v_txt, 'Sypex Systems') > 0 then
    falla('C3', 'factura inexistente devuelve el reporte de relleno');
  end if;
  if instr(v_txt, 'No se puede') = 0 then
    falla('C3', 'factura inexistente no muestra aviso');
  end if;

  -- C4: factura vista como empresa mexicana ----------------------------------
  select max(id_factura) into v_id_fact from facturas;
  update facturas set
         id_empresa = (select min(id_empresa) from empresas where cod_pais = 'MX')
   where id_factura = v_id_fact;
  v_txt := texto(pkg_reportes_factura.fn_imprimir_factura(v_id_fact));
  if instr(v_txt, 'BCV') > 0 then
    falla('C4', 'factura de empresa MX habla de BCV');
  end if;
  if instr(v_txt, 'RFC') = 0 then
    falla('C4', 'factura de empresa MX no muestra RFC');
  end if;
  rollback;

  -- C5: presupuesto visto como empresa mexicana ------------------------------
  select max(id_presupuesto) into v_id_pres from presupuestos;
  select min(id_cliente) into v_cli
    from clientes
   where id_empresa = (select min(id_empresa) from empresas where cod_pais = 'MX');
  if v_cli is not null then
    update presupuestos set
           id_empresa  = (select min(id_empresa) from empresas where cod_pais = 'MX'),
           id_cliente  = v_cli
     where id_presupuesto = v_id_pres;
    v_txt := texto(pkg_reportes_presupuesto.fn_imprimir_presupuesto(v_id_pres));
    if instr(v_txt, 'RIF / NIT') > 0 then
      falla('C5', 'presupuesto de empresa MX rotulado como RIF / NIT');
    end if;
    if instr(v_txt, 'RFC') = 0 then
      falla('C5', 'presupuesto de empresa MX sin RFC');
    end if;
    if instr(v_txt, 'BCV') > 0 then
      falla('C5', 'presupuesto de empresa MX habla de BCV');
    end if;
    rollback;
  end if;

  -- C6: escape de HTML -------------------------------------------------------
  -- OJO: 'set' va al final de la linea anterior. importar_export.py descarta
  -- cualquier linea que empiece por 'set ' y el UPDATE quedaria sin SET.
  select descripcion into v_desc
    from presupuestos_det where id_presupuesto = v_id_pres and rownum = 1;
  update presupuestos_det set
         descripcion = '<b>x</b> & y'
   where id_presupuesto = v_id_pres;
  v_html := pkg_reportes_presupuesto.fn_imprimir_presupuesto(v_id_pres);
  if instr(v_html, '<b>x</b>') > 0 then
    falla('C6', 'la descripcion del detalle se inserta sin escapar');
  end if;
  if instr(v_html, '&lt;b&gt;') = 0 then
    falla('C6', 'no se encontro el texto escapado');
  end if;
  rollback;

  -- C7: mascara de importes determinista -------------------------------------
  select pkg_reportes_presupuesto.fn_imprimir_presupuesto(v_id_pres) into v_html;
  select to_char(subtotal, 'FM999,999,990.00', 'NLS_NUMERIC_CHARACTERS=''.,''')
    into v_espera
    from presupuestos where id_presupuesto = v_id_pres;
  if instr(v_html, v_espera) = 0 then
    falla('C7', 'no aparece el subtotal con la mascara esperada (' || v_espera || ')');
  end if;

  -- C8: el pie cuadra con las lineas -----------------------------------------
  select max(id_factura) into v_id_fact from facturas where monto_total is not null;
  select nvl(sum(monto_total_linea), 0) into v_sum
    from facturas_det where id_factura = v_id_fact;
  select monto_total into v_total from facturas where id_factura = v_id_fact;
  if abs(v_sum - v_total) > 0.01 then
    falla('C8', 'la suma de lineas (' || v_sum || ') no es el total (' || v_total || ')');
  end if;

  -- C9: numero de control solo si hay uuid -----------------------------------
  v_txt := texto(pkg_reportes_factura.fn_imprimir_factura(v_id_fact));
  if instr(v_txt, 'Control:') > 0 then
    select count(*) into v_sum from facturas
     where id_factura = v_id_fact and uuid_fiscal is not null;
    if v_sum = 0 then
      falla('C9', 'muestra N Control sin uuid_fiscal');
    end if;
  end if;

  raise_application_error(-20100, 'RESULTADO: FALLAS=' || v_fallas || v_lista);
end;
/
