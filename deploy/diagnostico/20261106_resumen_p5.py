"""
Verificacion de la tarjeta «Resumen Financiero» de la pagina 5.

El dueno pidio que la tarjeta se viera como la de Facturacion «por imagen», no que se le quitaran
lineas. Se habia entendido mal y la version anterior ocultaba el descuento cuando era cero, el
gasto real cuando no habia gastos y el total equivalente cuando la moneda era VES.

Ahora la tarjeta muestra siempre las ocho lineas: Subtotal Bruto, Descuento Total, Subtotal Neto,
Impuestos/IVA, Total, Total equivalente (VES), Gasto real y Desviacion.

Uso:
    python deploy/diagnostico/20261106_resumen_p5.py

Sale con codigo 1 solo si alguna comprobacion falla; con todo bien, 0.
"""
import os
import re
import sys

import oracledb

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

REPO = r"C:\Users\luism\OneDrive\Documents\Apex_luis"
CS = ("(DESCRIPTION=(RETRY_COUNT=5)(RETRY_DELAY=2)"
      "(ADDRESS=(PROTOCOL=TCPS)(PORT=1521)(HOST=adb.mx-monterrey-1.oraclecloud.com))"
      "(CONNECT_DATA=(SERVICE_NAME=GFD7E2575D251AE_SYPEXSQL_high.adb.oraclecloud.com))"
      "(SECURITY=(SSL_SERVER_DN_MATCH=YES)))")

REGION = 12541094704283236  # «Resumen Financiero» de la pagina 5

d = {}
for l in open(os.path.join(REPO, ".env"), encoding="utf-8"):
    l = l.strip()
    if l and not l.startswith("#") and "=" in l:
        k, v = l.split("=", 1)
        d[k.strip()] = v.strip()

fallas = []


def comprobar(nombre, condicion, detalle=""):
    print(f"  [{'OK   ' if condicion else 'FALLA'}] {nombre} {detalle}".rstrip())
    if not condicion:
        fallas.append(nombre)


def texto(valor):
    if valor is None:
        return ""
    return valor.read() if hasattr(valor, "read") else str(valor)


conn = oracledb.connect(user=d["DB_USER"], password=d["DB_PASSWORD"], dsn=CS)
cur = conn.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")

fuente = texto(cur.execute(
    "select region_source from apex_application_page_regions "
    "where application_id = 100 and region_id = :r", {"r": REGION}).fetchone()[0])
norm = " ".join(fuente.lower().split())

print("== las ocho lineas estan siempre ==")

for etiqueta in ("Subtotal Bruto (", "Descuento Total (", "Subtotal Neto (", "Impuestos / IVA",
                 "Total (", "Total equivalente (VES)", "Gasto real", "Desviacion"):
    comprobar("linea «" + etiqueta.strip() + "»", etiqueta.lower() in norm)

print("== nada queda condicionado ==")

for guarda in ("if v_total_descuento > 0", "if v_gasto_real > 0", "if upper(v_moneda)"):
    comprobar("sin «" + guarda + "»", guarda not in norm)

print("== el calculo sigue siendo el mismo que facturacion ==")

comprobar("suma las lineas para el total", "sum(monto_total_linea)" in norm)
comprobar("la mascara es la de facturacion", "'fm999g999g999g990d00'" in norm.replace('"', "'"))
comprobar("no vuelve el formato de pesos", "'$999,999,990.00')" not in norm)
comprobar("sigue trayendo el gasto real", "pkg_gasto_real.fn_total_gasto_usd" in norm)
comprobar("sigue filtrando por el presupuesto elegido", ":p5_id_presupuesto" in norm)

print("== el HTML real de la tarjeta ==")

# El cuerpo de la region es un bloque PL/SQL completo que termina en RETURN v_html. Se ejecuta
# cambiando ese RETURN por una asignacion a un bind de salida: asi se ve el HTML de verdad.
cuerpo = fuente.replace("RETURN v_html;", ":salida := v_html;")


def tarjeta(pid):
    salida = cur.var(oracledb.DB_TYPE_CLOB)
    cur.execute("begin " + cuerpo + " end;", {"P5_ID_PRESUPUESTO": str(pid), "salida": salida})
    return texto(salida.getvalue())


ETIQUETAS = ("Subtotal Bruto", "Descuento Total", "Subtotal Neto", "Impuestos / IVA",
             "Total equivalente (VES)", "Gasto real", "Desviacion")

fila = cur.execute(
    "select d.id_presupuesto, min(d.id_detalle) "
    "  from presupuestos_det d join presupuestos p on p.id_presupuesto = d.id_presupuesto "
    " where p.id_empresa = 1 group by d.id_presupuesto order by 1 fetch first 1 rows only").fetchone()

pid, id_det = fila
try:
    # El dato de prueba puede traer descuento en cualquier linea: para el caso
    # «sin descuento» se ponen todas a cero dentro de la transaccion (rollback al
    # final). Con el fixture del 2026-11-08 el presupuesto 12 ya traia 37,50.
    cur.execute("update presupuestos_det set monto_descuento = 0 where id_presupuesto = :p",
                {"p": pid})
    html = tarjeta(pid)
    faltan = [x for x in ETIQUETAS if x not in html]
    comprobar(f"sin descuento: salen las ocho lineas (presupuesto {pid})", not faltan,
              f"(faltan: {', '.join(faltan)})" if faltan else "")
    comprobar("sin descuento: el descuento sale en cero, no desaparece",
              "Descuento Total" in html and re.search(r"-0[.,]00", html) is not None)

    # Con descuento: se fuerza en una transaccion y se revierte al terminar.
    cur.execute("update presupuestos_det set monto_descuento = 10 where id_detalle = :d", {"d": id_det})
    html2 = tarjeta(pid)
    faltan2 = [x for x in ETIQUETAS if x not in html2]
    comprobar("con descuento: las ocho lineas siguen saliendo", not faltan2,
              f"(faltan: {', '.join(faltan2)})" if faltan2 else "")
    comprobar("con descuento: muestra el importe", re.search(r"-10[.,]00", html2) is not None)
except Exception as e:  # noqa: BLE001
    print("  error ejecutando la region:", e)
    comprobar("la tarjeta se ejecuta de verdad", False)
finally:
    conn.rollback()

print("== estado general ==")

invalidos = cur.execute("select count(*) from all_objects where owner = 'WKSP_SYPEXWS' "
                        "and status <> 'VALID' and object_type in "
                        "('FUNCTION','PROCEDURE','PACKAGE','PACKAGE BODY','TRIGGER','VIEW')").fetchone()[0]
comprobar("0 objetos invalidos", invalidos == 0, f"({invalidos})")
paginas = cur.execute("select count(*) from apex_application_pages where application_id = 100").fetchone()[0]
comprobar("siguen las 34 paginas", paginas == 34, f"({paginas})")

conn.close()
print()
print("RESULTADO: FALLAS=" + str(len(fallas)))
if fallas:
    for f in fallas:
        print("  - " + f)
sys.exit(1 if fallas else 0)
