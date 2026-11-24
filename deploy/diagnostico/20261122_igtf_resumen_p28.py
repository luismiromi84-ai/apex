"""El IGTF del resumen de la compra (pagina 28) es la FOTO guardada (2026-11-22).

Ejecuta el CUERPO REAL de la region «Resumen de la compra» (tal como esta en APEX)
sobre una compra en divisa creada en una transaccion que se revierte: con
`igtf_bs = 123.45` y la empresa en NO SPE, el resumen tiene que mostrar 123,45 y
sumarlo al neto. Con el calculo en vivo daria 0 (no es SPE), que es el fallo que
se corrigio.

Uso: python deploy/diagnostico/20261122_igtf_resumen_p28.py
Sale 1 si algo falla.
"""
import os
import re
import sys

import oracledb

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
REPO = r"C:\Users\luism\OneDrive\Documents\Apex_luis"
sys.path.insert(0, os.path.join(REPO, "deploy", "conexion"))
from verificar_conexion import CONNECT_STRING as CS, credenciales  # noqa

REGION = 43000000000001170  # «Resumen de la compra», pagina 28
fallas = []


def comprobar(nombre, condicion, detalle=""):
    print(("  OK   " if condicion else "  FALLA") + " " + nombre +
          ("" if condicion else "  -> " + str(detalle)[:220]))
    if not condicion:
        fallas.append(nombre)


c = credenciales()
with oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=CS) as con:
    cur = con.cursor()
    cur.execute("alter session set current_schema = WKSP_SYPEXWS")

    fuente = cur.execute(
        "select region_source from apex_application_page_regions "
        "where application_id = 100 and region_id = :r", r=REGION).fetchone()[0]
    fuente = fuente.read() if hasattr(fuente, "read") else str(fuente)

    cuerpo = re.sub(r"return\s+([^;]+);", r":salida := \1; return;", fuente, flags=re.I)
    if not cuerpo.lstrip().lower().startswith("declare"):
        cuerpo = "begin " + cuerpo + " end;"

    def html_de(pid):
        salida = cur.var(oracledb.DB_TYPE_CLOB)
        cur.execute(cuerpo, {"P28_ID_COMPRA": str(pid), "salida": salida})
        val = salida.getvalue()
        return val.read() if hasattr(val, "read") else str(val)

    try:
        vid = cur.var(oracledb.NUMBER)
        cur.execute("insert into proveedores (id_empresa, rif, razon_social) "
                    "values (1, 'IGTF-RES-1', 'Proveedor IGTF resumen') "
                    "returning id_proveedor into :1", [vid])
        prov = int(vid.getvalue()[0])

        vc = cur.var(oracledb.NUMBER)
        cur.execute("insert into compras (id_empresa, id_proveedor, tipo_documento, "
                    "folio_factura, fecha_emision, cod_moneda, tipo_cambio, estado) "
                    "values (1, :p, 'FAC', 'IGTF-RES-1', sysdate, 'USD', 900, 'REGISTRADA') "
                    "returning id_compra into :2", [prov, vc])
        comp = int(vc.getvalue()[0])

        cur.execute("insert into compras_det (id_compra, num_linea, descripcion, cantidad, "
                    "precio_unitario, porcentaje_impuesto, monto_impuesto, subtotal_linea, "
                    "total_linea, tasa_cambio_aplicada, subtotal_bs, total_bs) "
                    "values (:c, 1, 'Servicio de prueba', 2, 50, 16, 16, 100, 116, 900, "
                    "90000, 104400)", c=comp)
        cur.execute("update compras set igtf_bs = 123.45, retencion_iva_bs = 12 "
                    "where id_compra = :c", c=comp)
        # Con el calculo en vivo, al no ser SPE el IGTF daria 0: la foto tiene que aguantar.
        cur.execute("update empresas set es_spe = 'N' where id_empresa = 1")

        html = html_de(comp)
        print("  html:", " ".join(html.split())[:160])
        comprobar("el resumen muestra el IGTF guardado (123,45)", "123,45" in html,
                  [x for x in html.split("<") if "IGTF" in x][:2])
        comprobar("y lo suma al neto a pagar (104.511,45)", "104.511,45" in html,
                  [x for x in html.split("<") if "NETO" in x.upper()][:2])
        comprobar("el rotulo dice la alicuota (IGTF 3 %)",
                  "IGTF 3 %" in html, [x for x in html.split("<") if "IGTF" in x][:2])
        comprobar("no depende de ES_SPE (la empresa quedo en NO)",
                  "123,45" in html)

        # Y una compra en BORRADOR sigue estimando en vivo (no hay foto todavia).
        cur.execute("update compras set estado = 'BORRADOR', igtf_bs = 0 where id_compra = :c",
                    c=comp)
        cur.execute("update empresas set es_spe = 'S' where id_empresa = 1")
        cur.execute("update forma_pago set genera_igtf = 'N' where genera_igtf = 'S'")
        html2 = html_de(comp)
        print("  borrador:", " ".join(html2.split())[:160])
        comprobar("en borrador se estima (aqui sin forma que genera: 0)", "123,45" not in html2)
    finally:
        con.rollback()

    invalidos = cur.execute("select count(*) from all_objects where owner = 'WKSP_SYPEXWS' "
                            "and status <> 'VALID'").fetchone()[0]
    comprobar("0 objetos invalidos", invalidos == 0, invalidos)
    con.close()

print()
print("RESULTADO: FALLAS=" + str(len(fallas)))
for f in fallas:
    print("  - " + f)
sys.exit(1 if fallas else 0)
