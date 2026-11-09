"""
Verificacion: la nota de credito se guarda con la TASA de su factura (2026-11-09).

Por que: por el principio de correlacion (providencias de facturacion del SENIAT) la
nota que corrige una factura lleva las mismas condiciones economicas y tributarias
que se pactaron: la tasa de cambio y la alicuota de IVA de ESA factura, no las del
dia en que se emite la nota.

Comprueba:
  C1  el proceso de guardado de la pagina 9 toma la tasa y la fecha de la factura
      de origen cuando es una nota con `id_factura_origen`
  C2  prc_guardar_factura tiene el parametro P_FECHA_REFERENCIA
  C3  guardar una NC sobre una factura con tasa 896,1225 deja esa tasa en la nota
  C4  una tasa de 1 (dato historico malo) se rechaza aunque haya fecha de
      referencia: el proceso debe caer a la tasa del dia de la factura
  C5  una factura FAC nueva sigue usando la tasa que manda la pagina (la del dia)
  C6  una NC cuyo total supera el de la factura de origen -> -20049

Todo se hace dentro de una transaccion que se revierte al final.

Uso:
    python deploy/diagnostico/20261109_nota_tasa_origen.py
"""
import os
import sys

import oracledb

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

REPO = r"C:\Users\luism\OneDrive\Documents\Apex_luis"
CS = ("(DESCRIPTION=(RETRY_COUNT=5)(RETRY_DELAY=2)"
      "(ADDRESS=(PROTOCOL=TCPS)(PORT=1521)(HOST=adb.mx-monterrey-1.oraclecloud.com))"
      "(CONNECT_DATA=(SERVICE_NAME=GFD7E2575D251AE_SYPEXSQL_high.adb.oraclecloud.com))"
      "(SECURITY=(SSL_SERVER_DN_MATCH=YES)))")

d = {}
for l in open(os.path.join(REPO, ".env"), encoding="utf-8"):
    l = l.strip()
    if l and not l.startswith("#") and "=" in l:
        k, v = l.split("=", 1)
        d[k.strip()] = v.strip()

fallas = []


def comprobar(nombre, condicion, detalle=""):
    print(("  OK  " if condicion else "  MAL ") + nombre + (" " + detalle if detalle else ""))
    if not condicion:
        fallas.append(nombre + " " + detalle)


conn = oracledb.connect(user=d["DB_USER"], password=d["DB_PASSWORD"], dsn=CS)
cur = conn.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")

# --- C1: el proceso de la pagina 9 lee la tasa de la factura de origen ---------
proc = cur.execute("""
    select dbms_lob.substr(process_source, 32000, 1)
      from apex_application_page_proc
     where application_id = 100 and page_id = 9
       and process_name = 'Insert/update Facturacion'
""").fetchone()[0]
texto = " ".join((proc or "").split())
comprobar("C1 el proceso consulta la factura de origen para la tasa",
          "from facturas" in texto.lower() and "id_factura_origen" in texto.lower()
          and "fecha_referencia" in texto.lower(),
          "(busca la rama de la tasa)")
comprobar("C1 el proceso avisa cuando la factura no tiene tasa valida",
          "tasa valida" in texto.lower() or "tasa del dia de la factura" in texto.lower())

# --- C2: el package tiene el parametro -----------------------------------------
args = [r[0] for r in cur.execute("""
    select argument_name from all_arguments
     where owner = 'WKSP_SYPEXWS' and package_name = 'PKG_FACTURACION'
       and object_name = 'PRC_GUARDAR_FACTURA' and argument_name is not null
""")]
comprobar("C2 prc_guardar_factura tiene P_FECHA_REFERENCIA",
          "P_FECHA_REFERENCIA" in args, f"({len(args)} parametros)")

# --- datos base ---------------------------------------------------------------
emp = 1
origen, moneda, tasa_origen, cli = cur.execute("""
    select id_factura, cod_moneda, tipo_cambio, id_cliente
      from facturas
     where id_empresa = :e and tipo_documento = 'FAC' and estado <> 'ANULADA'
       and cod_moneda <> 'VES' and tipo_cambio > 1
     order by id_factura asc fetch first 1 rows only
""", e=emp).fetchone()
fecha_origen = cur.execute("select to_char(fecha_emision,'DD/MM/YYYY') from facturas where id_factura = :i",
                           i=origen).fetchone()[0]
print(f"  factura de origen: {origen} ({moneda}, tasa {tasa_origen}, del {fecha_origen})")


def guardar(tipo, tasa, fecha_ref=None, total=0, origen_id=None, estado="PENDIENTE"):
    """Devuelve (id, error)."""
    salida = cur.var(oracledb.NUMBER)
    try:
        cur.execute("""
            begin
              pkg_facturacion.prc_guardar_factura(
                p_id_factura        => :id,
                p_id_empresa        => :e,
                p_folio_factura     => null,
                p_id_cliente        => :cli,
                p_id_presupuesto    => null,
                p_rfc_emisor        => 'EMP123456789',
                p_rfc_receptor      => null,
                p_uuid_fiscal       => null,
                p_uso_cfdi          => null,
                p_forma_pago        => null,
                p_metodo_pago       => null,
                p_condicion_pago    => null,
                p_fecha_emision     => to_char(sysdate,'DD/MM/YYYY'),
                p_fecha_vencimiento => null,
                p_estado            => :est,
                p_subtotal          => :tot,
                p_monto_impuesto    => 0,
                p_monto_total       => :tot,
                p_observaciones     => 'verificacion tasa nota',
                p_cod_moneda        => :mon,
                p_tipo_cambio       => :tasa,
                p_usuario           => 'VERIFICACION',
                p_tipo_documento    => :tipo,
                p_id_factura_origen => :orig,
                p_fecha_referencia  => to_date(:ref, 'DD/MM/YYYY'));
            end;
        """, id=salida, e=emp, cli=cli, est=estado, tot=total, mon=moneda,
              tasa=tasa, tipo=tipo, orig=origen_id, ref=fecha_ref)
        return salida.getvalue(), None
    except oracledb.DatabaseError as ex:
        error, = ex.args
        return None, error


# --- C3: la nota se queda con la tasa de su factura ----------------------------
nueva, err = guardar("NC", tasa_origen, fecha_ref=fecha_origen, origen_id=origen)
if err is not None:
    comprobar("C3 la NC se guarda con la tasa del origen", False, f"({err.message[:80]})")
else:
    t = cur.execute("select tipo_cambio from facturas where id_factura = :i", i=nueva).fetchone()[0]
    comprobar("C3 la NC se guarda con la tasa del origen", abs(t - tasa_origen) < 0.000001,
              f"(nota {nueva}: {t} vs factura {tasa_origen})")

# --- C4: una tasa 1 se rechaza aunque haya referencia --------------------------
_, err = guardar("NC", 1, fecha_ref=fecha_origen, origen_id=origen)
comprobar("C4 una tasa de 1 se rechaza con -20061",
          err is not None and err.code == 20061,
          f"({err.code if err else 'sin error'})")

# --- C5: una FAC sigue con la tasa que manda la pagina -------------------------
tasa_hoy = cur.execute("select fn_tasa_ves(sysdate, 'USD') from dual").fetchone()[0]
nueva, err = guardar("FAC", tasa_hoy)
if err is not None:
    comprobar("C5 una FAC nueva usa la tasa del dia", False, f"({err.message[:80]})")
else:
    t = cur.execute("select tipo_cambio, tipo_documento from facturas where id_factura = :i",
                    i=nueva).fetchone()
    comprobar("C5 una FAC nueva usa la tasa del dia",
              t[1] == "FAC" and abs(t[0] - tasa_hoy) < 0.000001, f"({t[0]})")

# --- C6: la NC no puede pasar el total de la factura ---------------------------
total_origen = cur.execute("select monto_total from facturas where id_factura = :i",
                           i=origen).fetchone()[0]
_, err = guardar("NC", tasa_origen, fecha_ref=fecha_origen, origen_id=origen,
                 total=total_origen + 1)
comprobar("C6 una NC que pasa el total de la factura da -20049",
          err is not None and err.code == 20049,
          f"({err.code if err else 'sin error'})")

conn.rollback()
conn.close()
print()
print("RESULTADO: FALLAS=" + str(len(fallas)))
if fallas:
    for f in fallas:
        print("  - " + f)
sys.exit(1 if fallas else 0)
