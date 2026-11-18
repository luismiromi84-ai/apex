#!/usr/bin/env python3
"""
El IGTF deja de ofrecerse en las lineas y SPE se edita en Administracion
(2026-11-17, tarea 6 del plan de cobros).

  C1  la LOV de impuestos de la pagina 6 filtra APLICA_EN = 'LINEA'
  C2  la LOV de impuestos de la pagina 10 filtra APLICA_EN = 'LINEA'
  C3  el item P19_ES_SPE existe en la pestana Empresa de la 19
  C4  el proceso de guardar empresa escribe es_spe en el update y en el insert

Se comprueba sobre el export (que es lo que se importa) y sobre la base.

Uso:  python deploy/diagnostico/20261117_cobros_igtf_lineas.py
Sale 1 si algo falla.
"""
import io
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
EXPORT = os.path.join(RAIZ, "pagina_apex", "f100.sql")
sys.path.insert(0, os.path.join(RAIZ, "deploy", "conexion"))
import oracledb  # noqa: E402
from verificar_conexion import CONNECT_STRING as CS, credenciales  # noqa: E402

fallas = []


def comprobar(nombre, condicion, detalle=""):
    print(("  OK  " if condicion else "  MAL ") + nombre + (" " + str(detalle) if detalle else ""))
    if not condicion:
        fallas.append(nombre)


def bloque_item(txt, nombre):
    marca = "p_name=>'%s'" % nombre
    i = txt.index(marca)
    return txt[i:txt.index(');', i)]


txt = io.open(EXPORT, encoding="utf-8", errors="replace").read()

# C1/C2: las dos LOV de impuestos de linea
for pagina, item in ((6, "P6_ID_IMPUESTO"), (10, "P10_ID_IMPUESTO")):
    bloque = bloque_item(txt, item)
    comprobar("C%s la LOV de %s filtra APLICA_EN" % (1 if pagina == 6 else 2, item),
              "APLICA_EN" in bloque.upper())

# C3: el item de SPE
try:
    bloque = bloque_item(txt, "P19_ES_SPE")
    tiene = True
except ValueError:
    tiene = False
comprobar("C3 existe el item P19_ES_SPE", tiene)

# C4: el proceso de guardar empresa escribe es_spe
procesos = re.findall(r"p_process_name=>'([^']+)'(.*?)\n\);\n", txt, re.S)
guardar = [cuerpo for nombre, cuerpo in procesos
           if "empresa" in nombre.lower() and ("update empresas" in cuerpo.lower()
                                               or "insert into empresas" in cuerpo.lower())]
comprobar("C4 hay un proceso de guardar empresa", len(guardar) >= 1, f"({len(guardar)})")
if guardar:
    cuerpo = " ".join(guardar).lower()
    comprobar("C4 el proceso escribe es_spe", "es_spe" in cuerpo)
    comprobar("C4 y tambien en el insert", "insert into empresas" in cuerpo and cuerpo.count("es_spe") >= 2,
              f"(menciones: {cuerpo.count('es_spe')})")

# Base: el item y el proceso tal como quedaron importados
conn = oracledb.connect(user=credenciales()["DB_USER"],
                        password=credenciales()["DB_PASSWORD"], dsn=CS)
cur = conn.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")

n = cur.execute("""select count(*) from apex_application_page_items
                    where application_id = 100 and page_id = 19 and item_name = 'P19_ES_SPE'""").fetchone()[0]
comprobar("C3 en la base: P19_ES_SPE esta en la 19", n == 1, f"({n})")

n = cur.execute("""select count(*) from apex_application_page_proc
                    where application_id = 100 and page_id = 19
                      and lower(process_source) like '%es_spe%'""").fetchone()[0]
comprobar("C4 en la base: el proceso de la 19 menciona es_spe", n >= 1, f"({n})")

n = cur.execute("""select count(*) from impuestos
                    where cod_pais = 'VE' and cod_impuesto = 'IGTF' and aplica_en = 'CABECERA'""").fetchone()[0]
comprobar("C5 en la base: el IGTF de VE es de CABECERA", n == 1, f"({n})")

# C6: la LOV tal como la ejecuta APEX ya no devuelve el IGTF
lov = cur.execute("""select lov_definition from apex_application_page_items
                      where application_id = 100 and page_id = 10
                        and item_name = 'P10_ID_IMPUESTO'""").fetchone()[0]
if hasattr(lov, "read"):
    lov = lov.read()
consulta = (lov.replace(":P10_ID_FACTURA", "null")
               .replace(":APP_USER", "'ADMIN'")
               .replace(":F_EMPRESA_ACTIVA", "1")
               .replace("fn_clean_num(null)", "null"))
cur.execute(consulta)
nombres = [f[0] for f in cur.fetchall()]
comprobar("C6 la LOV de la pagina 10 ya no ofrece IGTF",
          not any("IGTF" in (n or "").upper() for n in nombres),
          f"({len(nombres)} impuestos: {', '.join(nombres)[:90]})")
comprobar("C6 y sigue ofreciendo el IVA", any("IVA" in (n or "").upper() for n in nombres))

conn.close()

print()
print("RESULTADO: FALLAS=" + str(len(fallas)))
for f in fallas:
    print("  - " + f)
sys.exit(1 if fallas else 0)
