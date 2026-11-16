"""
Verificacion del filtro de moneda del Panel General (pagina 13).

El Panel tenia la LOV de `P13_MONEDA` como lista fija (`STATIC:USD;USD,VES;VES,MXN;MXN`), asi que
una empresa venezolana veia MXN en el desplegable y al elegirla las tarjetas salian en cero. Las
paginas 5 y 8 siempre devolvieron «moneda local del pais de la empresa + USD».

Comprueba la estructura, que la consulta se ejecute para las dos empresas demo y que el valor por
defecto siga siendo la moneda local del usuario.

Uso:
    python deploy/diagnostico/20261106_panel_moneda.py

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

print("== item P13_MONEDA ==")

item = cur.execute(
    "select lov_definition, lov_named_lov, lov_cascade_parent_items "
    "from apex_application_page_items "
    "where application_id = 100 and page_id = 13 and item_name = 'P13_MONEDA'").fetchone()

comprobar("existe el item P13_MONEDA", item is not None)
lov = ""
if item:
    lov, lov_nombre, cascada = texto(item[0]), item[1], item[2]
    lov_norm = " ".join(lov.lower().split())
    comprobar("la LOV ya no es una lista fija", not lov.upper().startswith("STATIC:"),
              f"({lov[:40]}...)")
    comprobar("consulta la moneda del pais de la empresa", "paises" in lov_norm and "empresas" in lov_norm)
    comprobar("depende de P13_ID_EMPRESA", ":p13_id_empresa" in lov_norm)
    comprobar("agrega USD como el resto de la app", "'usd'" in lov_norm)
    comprobar("cascada desde P13_ID_EMPRESA", (cascada or "").upper() == "P13_ID_EMPRESA",
              f"({cascada})")

print("== la LOV devuelve lo correcto por empresa ==")

if lov:
    for empresa, esperadas in ((1, {"VES", "USD"}), (2, {"MXN", "USD"})):
        try:
            cur.execute(lov, {"P13_ID_EMPRESA": empresa})
            valores = {r[1] for r in cur.fetchall()}
            comprobar(f"empresa {empresa} -> {'/'.join(sorted(esperadas))}", valores == esperadas,
                      f"({', '.join(sorted(valores))})")
        except Exception as e:  # noqa: BLE001
            print("  error:", e)
            comprobar(f"la LOV se ejecuta para la empresa {empresa}", False)

print("== el defecto sigue siendo la moneda local del usuario ==")

usuario = cur.execute(
    "select u.username, e.nombre_empresa, nvl(p.moneda_local, 'USD') moneda, "
    "       (select nvl(max(p2.moneda_local), 'USD') from usuario u2 "
    "          join empresas e2 on e2.id_empresa = u2.id_empresa "
    "          left join paises p2 on p2.cod_pais = e2.cod_pais "
    "         where upper(u2.username) = upper(u.username) "
    "           and u2.estado in ('ACTIVO', 'A', '1') "
    "        having count(*) = 1) defecto "
    "  from usuario u "
    "  join empresas e on e.id_empresa = u.id_empresa "
    "  left join paises p on p.cod_pais = e.cod_pais "
    " where lower(u.username) in ('prueba1', 'prueba2') "
    " order by u.username").fetchall()

for nombre, empresa, moneda, defecto in usuario:
    comprobar(f"defecto de {nombre} = moneda local", defecto == moneda,
              f"({empresa}: {moneda} vs {defecto})")

print("== estado general ==")

invalidos = cur.execute("select count(*) from all_objects where owner = 'WKSP_SYPEXWS' "
                        "and status <> 'VALID' and object_type in "
                        "('FUNCTION','PROCEDURE','PACKAGE','PACKAGE BODY','TRIGGER','VIEW')").fetchone()[0]
comprobar("0 objetos invalidos", invalidos == 0, f"({invalidos})")
paginas = cur.execute("select count(*) from apex_application_pages where application_id = 100").fetchone()[0]
comprobar("siguen las 23 paginas", paginas == 23, f"({paginas})")

conn.close()
print()
print("RESULTADO: FALLAS=" + str(len(fallas)))
if fallas:
    for f in fallas:
        print("  - " + f)
sys.exit(1 if fallas else 0)
