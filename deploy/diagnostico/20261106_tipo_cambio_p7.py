"""
Verificacion del tipo de cambio de la pagina 7 (Presupuestos).

El sistema guarda TIPO_CAMBIO como «bolivares por unidad de la moneda del documento»: en la tabla
TIPO_CAMBIO, USD->VES ~894, MXN->VES ~48, y VES = 1. Asi lo hace la facturacion (pagina 9), cuyo
detalle multiplica `subtotal_linea * tasa_cambio` para los montos en Bs.

La pagina 7 usaba `fn_tasa_cambio(fecha, moneda)`, que devuelve **1 para USD** (fue escrita como
factor a USD), asi que un presupuesto en USD salia con tipo de cambio 1 en vez de la tasa BCV.

Comprueba que la accion dinamica es igual a la de facturacion y que el SQL, ejecutado, devuelve la
tasa de la tabla para USD, VES y MXN.

Uso:
    python deploy/diagnostico/20261106_tipo_cambio_p7.py
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

print("== la accion dinamica de la pagina 7 ==")

# Las acciones dinamicas no estan en las vistas APEX_APPLICATION_PAGE_* publicas: se leen del
# export, que es la fuente que se importa.
export = open(os.path.join(REPO, "pagina_apex", "f100.sql"), encoding="utf-8").read()
desde = export.index("p_name=>'TIPO_CAMBIO'")
# 6000 y no 2200: el segundo evento (TIPO_CAMBIO_2, el de P7_COD_MONEDA) empieza a
# 2397 caracteres del primero, y con la ventana corta el test no lo veia.
bloque = export[desde:desde + 6000]

comprobar("la pagina 7 usa la misma consulta que facturacion", "moneda_destino = ''VES''" in bloque)
comprobar("no usa fn_tasa_cambio (devolvia 1 para USD)", "fn_tasa_cambio" not in bloque)
comprobar("el tipo de accion es SQL_STATEMENT", "'type', 'SQL_STATEMENT'" in bloque)
comprobar("se ejecuta al cargar la pagina", ",p_execute_on_page_init=>'Y'" in bloque)
# Una DA escucha UN item: desde el 2026-11-08 son dos eventos (P7_FECHA_EMISION y
# P7_COD_MONEDA). Antes el test exigia el elemento combinado "P7_FECHA_EMISION,P7_COD_MONEDA",
# que es justo el bug que hacia que la accion no se disparara nunca.
comprobar("dispara al cambiar la moneda", "p_triggering_element=>'P7_COD_MONEDA'" in bloque)
comprobar("dispara al cambiar la fecha", "p_triggering_element=>'P7_FECHA_EMISION'" in bloque)

print("== el SQL de la accion, ejecutado ==")

import re  # noqa: E402

m = re.search(r"'sql_query', wwv_flow_string\.join\(wwv_flow_t_varchar2\(\n(.*?)\)\),\n", bloque, re.S)
if not m:
    comprobar("encuentro el SQL de la accion en el export", False)
    sql = None
else:
    lineas = []
    for linea in m.group(1).split("\n"):
        linea = linea.strip().rstrip(",")
        lineas.append(linea[1:-1].replace("''", "'"))
    sql = "\n".join(lineas)
    comprobar("encuentro el SQL de la accion en el export", True, f"({len(sql)} caracteres)")

if sql:
    hoy = cur.execute("select to_char(sysdate, 'DD/MM/YYYY') from dual").fetchone()[0]
    for moneda, esperado in (("VES", 1), ("USD", None), ("MXN", None)):
        valor = cur.execute(sql, {"P7_COD_MONEDA": moneda, "P7_FECHA_EMISION": hoy}).fetchone()[0]
        if esperado == 1:
            comprobar(f"{moneda} -> 1", valor == 1, f"({valor})")
        else:
            en_tabla = cur.execute(
                "select max(tasa_cambio) keep (dense_rank last order by fecha_vigencia) "
                "  from tipo_cambio where moneda_origen = :m and moneda_destino = 'VES' "
                "   and tipo_tasa = 'REAL' and fecha_vigencia < trunc(sysdate) + 1",
                {"m": moneda}).fetchone()[0]
            comprobar(f"{moneda} -> la tasa BCV de la tabla", valor is not None and valor == en_tabla,
                      f"({valor} vs {en_tabla})")

print("== montos en bolivares: multiplicar, no dividir ==")

tasa_usd = cur.execute(
    "select max(tasa_cambio) keep (dense_rank last order by fecha_vigencia) from tipo_cambio "
    " where moneda_origen = 'USD' and moneda_destino = 'VES' and tipo_tasa = 'REAL' "
    "   and fecha_vigencia < trunc(sysdate) + 1").fetchone()[0]
comprobar("la tasa USD->VES es mayor que 1 (es bolivares por dolar)",
          tasa_usd is not None and tasa_usd > 1, f"({tasa_usd})")

print("== datos historicos con la tasa mal ==")

mal_pres = cur.execute("select count(*) from presupuestos where cod_moneda = 'USD' and nvl(tipo_cambio,1) = 1").fetchone()[0]
mal_fact = cur.execute("select count(*) from facturas where cod_moneda = 'USD' and nvl(tipo_cambio,1) = 1").fetchone()[0]
print(f"  presupuestos en USD con tipo_cambio = 1: {mal_pres}")
print(f"  facturas en USD con tipo_cambio = 1: {mal_fact}")

print("== estado general ==")

invalidos = cur.execute("select count(*) from all_objects where owner = 'WKSP_SYPEXWS' "
                        "and status <> 'VALID' and object_type in "
                        "('FUNCTION','PROCEDURE','PACKAGE','PACKAGE BODY','TRIGGER','VIEW')").fetchone()[0]
comprobar("0 objetos invalidos", invalidos == 0, f"({invalidos})")
paginas = cur.execute("select count(*) from apex_application_pages where application_id = 100").fetchone()[0]
comprobar("siguen las 35 paginas", paginas == 35, f"({paginas})")

conn.close()
print()
print("RESULTADO: FALLAS=" + str(len(fallas)))
if fallas:
    for f in fallas:
        print("  - " + f)
sys.exit(1 if fallas else 0)
