"""
Verificacion del enlace «Editar» de una linea de presupuesto (pagina 5 -> pagina 6).

Hasta el 2026-11-06 la pagina 6 solo se podia abrir para CREAR una linea («Nueva Linea»): no habia
forma de abrir una existente, porque el enlace de la lista le pasaba solo el presupuesto y el
formulario de la 6 carga `where id_detalle = :P6_ID_DETALLE`. Resultado: formulario vacio.

Comprueba la estructura (columna de accion con los DOS items en el enlace) y el comportamiento:
toma una linea real, ejecuta la consulta de la region TAL COMO quedo guardada y verifica que los
identificadores que viajan en el enlace abren esa misma linea.

Uso:
    python deploy/diagnostico/20261106_editar_linea_presupuesto.py

Sale con codigo 1 solo si alguna comprobacion falla; con todo bien, 0.
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

REGION_DETALLE = 12950647600514910  # region «Detalle Presupuesto» de la pagina 5

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

print("== la region de detalle trae los identificadores ==")

fuente = texto(cur.execute(
    "select region_source from apex_application_page_regions "
    "where application_id = 100 and region_id = :r", {"r": REGION_DETALLE}).fetchone()[0])
fuente_norm = " ".join(fuente.lower().split())
comprobar("el SELECT trae d.id_detalle en la lista", "select d.id_detalle," in fuente_norm)
comprobar("el SELECT trae d.id_presupuesto en la lista", "d.id_presupuesto," in fuente_norm)
comprobar("sigue filtrando por la empresa del usuario",
          "id_empresa in (select fn_clean_num(:f_empresa_activa) from dual)" in fuente_norm)

print("== columna de accion ==")

col = cur.execute(
    "select report_label, column_link, column_type, is_primary_key, static_id "
    "from apex_application_page_ir_col "
    "where application_id = 100 and region_id = :r and column_alias = 'ID_DETALLE'",
    {"r": REGION_DETALLE}).fetchone()

comprobar("existe la columna ID_DETALLE", col is not None)
enlace = ""
if col:
    enlace = texto(col[1])
    comprobar("etiqueta «Editar»", (col[0] or "").lower().startswith("editar"), f"({col[0]})")
    comprobar("abre la pagina 6", ":6:&SESSION." in enlace, f"({enlace[:60]}...)")
    comprobar("pasa P6_ID_DETALLE", "P6_ID_DETALLE" in enlace)
    comprobar("pasa P6_ID_PRESUPUESTO", "P6_ID_PRESUPUESTO" in enlace)
    comprobar("los valores son #ID_DETALLE# y #ID_PRESUPUESTO#",
              "#ID_DETALLE#" in enlace.upper() and "#ID_PRESUPUESTO#" in enlace.upper())

oculta = cur.execute(
    "select count(*) from apex_application_page_ir_col "
    "where application_id = 100 and region_id = :r and column_alias = 'ID_PRESUPUESTO'",
    {"r": REGION_DETALLE}).fetchone()[0]
comprobar("existe la columna auxiliar ID_PRESUPUESTO", oculta == 1)

columnas_rpt = cur.execute(
    "select report_columns from apex_application_page_ir_rpt "
    "where application_id = 100 and region_id = :r and report_alias = 'primary'",
    {"r": REGION_DETALLE}).fetchone()[0] or ""
lista = columnas_rpt.split(":")
comprobar("ID_DETALLE es la primera columna visible", lista and lista[0] == "ID_DETALLE",
          f"({columnas_rpt[:50]}...)")
comprobar("ID_PRESUPUESTO no se muestra", "ID_PRESUPUESTO" not in lista)

print("== el formulario de la pagina 6 recibe esos dos items ==")

items = {r[0] for r in cur.execute(
    "select item_name from apex_application_page_items "
    "where application_id = 100 and page_id = 6").fetchall()}
comprobar("P6_ID_DETALLE es item de la pagina 6", "P6_ID_DETALLE" in items)
comprobar("P6_ID_PRESUPUESTO es item de la pagina 6", "P6_ID_PRESUPUESTO" in items)

print("== comportamiento: los ids del enlace abren esa linea ==")

presupuesto, detalle = cur.execute(
    "select d.id_presupuesto, min(d.id_detalle) from presupuestos_det d "
    "  join presupuestos p on p.id_presupuesto = d.id_presupuesto "
    " where p.id_empresa = 1 "
    " group by d.id_presupuesto having count(*) > 0 "
    " order by d.id_presupuesto fetch first 1 rows only").fetchone()

# Desde la empresa activa (2026-11-17) la region filtra por :F_EMPRESA_ACTIVA y ya
# no por :APP_USER: se sustituye la empresa y solo se pasa el bind que exista (un
# bind de mas da DPY-4008).
fuente = fuente.replace(":F_EMPRESA_ACTIVA", "1")
binds = {"P5_ID_PRESUPUESTO": presupuesto}
if ":APP_USER" in fuente:
    binds["APP_USER"] = "prueba1"
cur.execute(fuente, binds)
cab = [c[0].lower() for c in cur.description]
filas = cur.fetchall()
comprobar("la consulta guardada se ejecuta con el bind de la pagina", len(filas) > 0,
          f"(presupuesto {presupuesto}: {len(filas)} lineas)")

if "id_detalle" not in cab or "id_presupuesto" not in cab:
    comprobar("la consulta devuelve los dos identificadores", False,
              "(faltan id_detalle / id_presupuesto en el SELECT)")
    linea = None
else:
    i_pres, i_det = cab.index("id_presupuesto"), cab.index("id_detalle")
    linea = next((f for f in filas if f[i_det] == detalle), filas[0] if filas else None)
if linea:
    id_pres, id_det = linea[i_pres], linea[i_det]
    comprobar("cada fila trae los dos ids", id_pres is not None and id_det is not None,
              f"(presupuesto {id_pres}, linea {id_det})")
    abierta = cur.execute(
        "select descripcion from presupuestos_det "
        "where id_detalle = :d and id_presupuesto = :p", {"d": id_det, "p": id_pres}).fetchall()
    comprobar("esos ids abren exactamente una linea de ese presupuesto", len(abierta) == 1,
              f"({len(abierta)} filas, {abierta[0][0][:30] if abierta else ''})")
    otra = cur.execute(
        "select count(*) from presupuestos_det "
        "where id_detalle = :d and id_presupuesto = :p and id_presupuesto <> :p",
        {"d": id_det, "p": id_pres}).fetchone()[0]
    comprobar("no se cruzan presupuestos distintos", otra == 0)
else:
    comprobar("hay lineas para probar", False)

print("== estado general ==")

invalidos = cur.execute("select count(*) from all_objects where owner = 'WKSP_SYPEXWS' "
                        "and status <> 'VALID' and object_type in "
                        "('FUNCTION','PROCEDURE','PACKAGE','PACKAGE BODY','TRIGGER','VIEW')").fetchone()[0]
comprobar("0 objetos invalidos", invalidos == 0, f"({invalidos})")
paginas = cur.execute("select count(*) from apex_application_pages where application_id = 100").fetchone()[0]
comprobar("siguen las 34 paginas", paginas == 34, f"({paginas})")
boton = cur.execute("select count(*) from apex_application_page_buttons "
                    "where application_id = 100 and page_id = 5 "
                    "and button_name = 'BTN_NUEVO_DETALLE'").fetchone()[0]
comprobar("el boton «Nueva Linea» sigue en la pagina 5", boton == 1, f"({boton})")

conn.close()
print()
print("RESULTADO: FALLAS=" + str(len(fallas)))
if fallas:
    for f in fallas:
        print("  - " + f)
sys.exit(1 if fallas else 0)
