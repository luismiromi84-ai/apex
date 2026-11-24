"""
Verificacion de la portada publica (pagina 15) y del arranque de la app.

Comprueba dos capas:

  1. HTTP: la raiz de la app sirve la portada, la portada trae todas sus
     secciones y no se cuelan el cromo de APEX ni enlaces a paginas que no
     existen. Las paginas que ya funcionaban siguen respondiendo igual.
  2. Base de datos: la region tiene un tipo de plugin que resuelve, la pagina
     es publica con la plantilla Blank y no se rompio nada del resto
     (17 paginas, guardas de rol y de propiedad, item del cambio de clave,
     cero objetos invalidos).

Uso:
    python deploy/diagnostico/20261105_portada_verificacion.py

Sale con codigo 1 solo si alguna comprobacion falla; con todo bien, 0.

Nota sobre el pasado: esta pagina respondia HTTP 400 porque el export traia
,p_plug_source_type=>'NATIVE_STATIC_CONTENT' en la region, un identificador que
no existe en APEX 26.1. La region quedaba con SOURCE_TYPE_CODE
'NATIVE_STATIC_CONTENT' y el render moria en WWV_FLOW_PLUGIN con ORA-01403.
Una region de contenido estatico no lleva ese atributo: el tipo valido es
STATIC_TEXT / NATIVE_STATIC.
"""
import os
import sys
import urllib.error
import urllib.request

import oracledb

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

REPO = r"C:\Users\luism\OneDrive\Documents\Apex_luis"
CS = ("(DESCRIPTION=(RETRY_COUNT=5)(RETRY_DELAY=2)"
      "(ADDRESS=(PROTOCOL=TCPS)(PORT=1521)(HOST=adb.mx-monterrey-1.oraclecloud.com))"
      "(CONNECT_DATA=(SERVICE_NAME=GFD7E2575D251AE_SYPEXSQL_high.adb.oraclecloud.com))"
      "(SECURITY=(SSL_SERVER_DN_MATCH=YES)))")
BASE = "https://gfd7e2575d251ae-sypexsql.adb.mx-monterrey-1.oraclecloudapps.com/ords/f?p=100"

d = {}
for l in open(os.path.join(REPO, ".env"), encoding="utf-8"):
    l = l.strip()
    if l and not l.startswith("#") and "=" in l:
        k, v = l.split("=", 1); d[k.strip()] = v.strip()

fallas = []


def comprobar(nombre, condicion, detalle=""):
    print(f"  [{'OK   ' if condicion else 'FALLA'}] {nombre} {detalle}".rstrip())
    if not condicion:
        fallas.append(nombre)


print("== HTTP ==")
try:
    with urllib.request.urlopen(BASE, timeout=40) as r:
        raiz = r.read().decode("utf-8", errors="replace")
        comprobar("la raiz de la app sirve la portada",
                  "Presupuestos, facturación y clientes" in raiz, f"(HTTP {r.status})")
except urllib.error.HTTPError as e:
    comprobar("la raiz de la app sirve la portada", False, f"(HTTP {e.code})")
    raiz = ""

try:
    with urllib.request.urlopen(BASE + ":15", timeout=40) as r:
        portada = r.read().decode("utf-8", errors="replace")
        comprobar("la pagina 15 responde 200", r.status == 200,
                  f"({len(portada):,} bytes)")
except urllib.error.HTTPError as e:
    portada = ""
    comprobar("la pagina 15 responde 200", False, f"(HTTP {e.code})")

for marca in ("spx-portada", "spx-hero", "spx-servicios", "spx-servicio",
              "spx-indicadores", "spx-pie", "wa.me/528111198920",
              "Presupuestos, facturación y clientes"):
    comprobar(f"la portada trae {marca}", marca in portada)

# Desde el 2026-11-06 la portada es una pagina comercial con cuatro secciones
# reales; antes el menu apuntaba tres veces al mismo ancla.
for ancla in ("spx-inicio", "spx-servicios", "spx-nosotros", "spx-contacto"):
    comprobar(f"la portada trae la seccion {ancla}", f'id="{ancla}"' in portada)

comprobar("sin comentario de instrucciones a la vista",
          "Pegar TODO este bloque" not in portada)
comprobar("sin la cabecera de la region (New)", ">New<" not in portada)
comprobar("sin el usuario de APEX a la vista", ">nobody<" not in portada)
comprobar("sin enlaces a la pagina 17 (no existe)", "/synpex/17" not in portada)

for pagina, esperado, que in ((2, 200, "registro"), (14, 200, "recuperar clave"),
                              (9999, 200, "login"), (1, 302, "home privada")):
    try:
        with urllib.request.urlopen(f"{BASE}:{pagina}", timeout=40) as r:
            comprobar(f"pagina {pagina} ({que}) sigue igual", r.status == esperado,
                      f"(HTTP {r.status})")
    except urllib.error.HTTPError as e:
        comprobar(f"pagina {pagina} ({que}) sigue igual", e.code == esperado,
                  f"(HTTP {e.code})")

print("\n== base de datos ==")
with oracledb.connect(user=d["DB_USER"], password=d["DB_PASSWORD"], dsn=CS) as con:
    cur = con.cursor()
    cur.execute("alter session set current_schema = WKSP_SYPEXWS")

    def uno(sql):
        cur.execute(sql)
        return cur.fetchone()[0]

    comprobar("la app tiene 47 paginas",
              uno("select count(*) from apex_application_pages where application_id = 100") == 47)

    cur.execute("""select source_type, source_type_code
                   from apex_application_page_regions
                   where application_id = 100 and page_id = 15""")
    fila = cur.fetchone()
    comprobar("la region tiene tipo de plugin que resuelve",
              fila == ("Static Content", "STATIC_TEXT"), str(fila))

    cur.execute("""select page_template, page_requires_authentication, page_access_protection
                   from apex_application_pages
                   where application_id = 100 and page_id = 15""")
    plantilla, requiere_auth, proteccion = cur.fetchone()
    comprobar("la pagina 15 es publica", requiere_auth == "No", f"({proteccion})")
    comprobar("la pagina 15 usa la plantilla Blank", plantilla == "Blank", f"({plantilla})")

    comprobar("siguen las 39 guardas de rol",
              uno("""select count(*) from apex_application_page_proc
                     where application_id = 100
                       and upper(process_name) like 'VALIDA ROL%'""") == 39)
    comprobar("siguen las 8 guardas de propiedad de documento",
              uno("""select count(*) from apex_application_page_proc
                     where application_id = 100
                       and (process_source like '%fn_presupuesto_propio%'
                            or process_source like '%fn_factura_propio%')""") == 8)
    comprobar("sigue la guarda del cambio de clave (proceso de aplicacion)",
              uno("""select count(*) from apex_application_processes
                     where application_id = 100
                       and upper(process_name) like 'CAMBIO%CLAVE%'""") == 1)
    comprobar("sigue el item F_DEBE_CAMBIAR_CLAVE",
              uno("""select count(*) from apex_application_items
                     where application_id = 100
                       and upper(item_name) = 'F_DEBE_CAMBIAR_CLAVE'""") == 1)
    comprobar("la portada no sale en el menu de navegacion",
              uno("""select count(*) from apex_application_list_entries
                     where application_id = 100
                       and entry_target like '%:15:%'""") == 0)

    # --- acabado de las listas y navegacion ---
    comprobar("el Panel General no avisa de cambios sin guardar",
              uno("""select count(*) from apex_application_pages
                     where application_id = 100 and page_id = 13
                       and warn_on_unsaved_changes = 'No'""") == 1)

    comprobar("la lista de Presupuestos selecciona con checkbox, como Facturacion",
              uno("""select count(*) from apex_application_page_ir_col
                     where application_id = 100 and page_id = 5
                       and column_alias = 'SELECCIONAR'
                       and html_expression like '%js-select-invoice%'
                       and column_link is null""") == 1)

    comprobar("la tarjeta de totales de Presupuestos usa el mismo formato",
              uno("""select count(*) from apex_application_page_regions
                     where application_id = 100 and page_id = 5
                       and region_name = 'Resumen Financiero'
                       and region_source like '%FM999G999G999G990D00%'
                       and region_source like '%financial-summary%'
                       and region_source like '%monto_total_linea%'""") == 1)

    # Ojo: user_objects seria los objetos de ADMIN (el usuario de la conexion), no
    # los de la app. Se pregunta por el esquema dueno.
    comprobar("cero objetos invalidos en WKSP_SYPEXWS",
              uno("""select count(*) from all_objects
                      where owner = 'WKSP_SYPEXWS' and status = 'INVALID'
                        and object_type in ('FUNCTION', 'PROCEDURE', 'PACKAGE',
                                            'PACKAGE BODY', 'TRIGGER', 'VIEW')""") == 0)

print(f"\nRESULTADO: FALLAS={len(fallas)}")
for f in fallas:
    print("  -", f)
sys.exit(1 if fallas else 0)
