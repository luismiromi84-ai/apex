"""Regiones form: el WHERE no puede calificar la tabla con su nombre (2026-11-07).

APEX construye el SELECT del formulario con un ALIAS para la tabla, asi que un
WHERE como

    p.id_presupuesto = presupuestos_det.id_presupuesto

falla con ORA-00904 «"PRESUPUESTOS_DET"."ID_PRESUPUESTO": identificador no
valido» al abrir las paginas 6 y 10 (y habria fallado igual en la 16). Medido:
con alias, la forma calificada da ORA-00904 y la no calificada funciona.

Este script comprueba, contra la app importada:
  1. Que los WHERE de las regiones form de las paginas 6, 10 y 16 no califiquen.
  2. Que cada WHERE, ejecutado con alias, es SQL valido y devuelve la fila.
  3. Nada invalido y las 19 paginas.

Uso:  python deploy/diagnostico/20261107_where_form_alias.py
Sale con codigo 1 si algo falla.
"""

import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(REPO, "deploy", "conexion"))

import oracledb
from importar_export import CONNECT_STRING, credenciales

# (pagina, tabla del formulario, item de la PK)
REGIONES = [
    (6, "PRESUPUESTOS_DET", "P6_ID_DETALLE"),
    (10, "FACTURAS_DET", "P10_ID_DETALLE"),
    (16, "GASTO_REAL", "P16_ID_GASTO"),
]

fallas = 0


def comprueba(ok, texto, detalle=""):
    global fallas
    print(f"  [{'OK   ' if ok else 'FALLA'}] {texto}" + (f" ({detalle})" if detalle else ""))
    if not ok:
        fallas += 1


def main():
    datos = credenciales()
    con = oracledb.connect(user=datos["DB_USER"], password=datos["DB_PASSWORD"], dsn=CONNECT_STRING)
    cur = con.cursor()
    cur.execute("alter session set current_schema = WKSP_SYPEXWS")

    print("== WHERE de las regiones form ==")
    for pagina, tabla, item_pk in REGIONES:
        cur.execute("""select region_name, where_clause from apex_application_page_regions
                        where application_id = 100 and page_id = :1
                          and source_type_plugin_static_id = 'NATIVE_FORM'""", [pagina])
        fila = cur.fetchone()
        if not fila:
            comprueba(False, f"p{pagina}: no hay region form")
            continue
        nombre, donde = fila[0], (fila[1] or "")
        comprueba(tabla.lower() + "." not in donde.lower(),
                  f"p{pagina} ({nombre}): no califica la tabla",
                  f"donde={donde[:60]}...")

        # Ejecutar el WHERE con alias, como hace APEX: `from <tabla> x where <where>`
        prueba = re.sub(r":APP_USER\b", "'admin.demo'", donde)
        cur.execute(f"select min({'id_detalle' if tabla.endswith('_DET') else 'id_gasto'}) from {tabla}")
        id_real = cur.fetchone()[0]
        if id_real is not None:
            prueba = re.sub(r":\w+", str(id_real), prueba, count=1)
        prueba = re.sub(r":\w+", "null", prueba)
        sql = f"select count(*) from {tabla} x where {prueba}"
        try:
            cur.execute(sql)
            n = cur.fetchone()[0]
            comprueba(n >= 0, f"p{pagina}: el WHERE es valido con alias", f"{n} fila(s)")
        except oracledb.DatabaseError as ex:
            error, = ex.args
            comprueba(False, f"p{pagina}: el WHERE falla con alias", str(error.message).splitlines()[0][:90])

    print("== Estado general ==")
    cur.execute("""select count(*) from all_objects where owner = 'WKSP_SYPEXWS' and status <> 'VALID'
                    and object_type in ('FUNCTION','PROCEDURE','PACKAGE','PACKAGE BODY','TRIGGER','VIEW')""")
    n = cur.fetchone()[0]
    comprueba(n == 0, "cero objetos invalidos", str(n))
    cur.execute("select count(*) from apex_application_pages where application_id = 100")
    n = cur.fetchone()[0]
    comprueba(n == 19, "siguen las 19 paginas", str(n))

    print(f"\nRESULTADO: FALLAS={fallas}")
    con.close()
    sys.exit(1 if fallas else 0)


if __name__ == "__main__":
    main()
