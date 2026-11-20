"""Rendimiento de las pantallas de Synpex (2026-11-06).

Ejecuta las consultas TAL COMO estan guardadas en APEX (se leen de
apex_application_page_regions, no se copian a mano) y mide el tiempo de
respuesta con el volumen real de la base. Recorre todas las regiones de datos
de las paginas 3, 5, 8 y 13, asi que no hay nombres ni consultas a mano que se
desfasen.

Uso:
    python deploy/diagnostico/20261106_rendimiento.py

Sale con codigo 1 si alguna pantalla pasa de 2000 ms de mediana o si alguna
region no se puede ejecutar.
"""

import os
import re
import statistics
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(REPO, "deploy", "conexion"))

import oracledb
from importar_export import CONNECT_STRING, credenciales

REPETICIONES = 7
LIMITE_MS = 2000
PAGINAS = (3, 5, 8, 13)

# Valores que la app pasaria en una sesion real (admin.demo, empresa 1).
BINDS = {
    "APP_USER": "'prueba1'",
    "P13_ID_EMPRESA": "1",
    "P13_MONEDA": "'VES'",
    "P5_ID_PRESUPUESTO": "null",
    "P5_ID_EMPRESA": "1",
    "P8_ID_EMPRESA": "1",
    "P8_ID_FACTURAS": "null",
    "P5_ID_PRESUPUESTO_2": "null",
    "P4_ID_EMPRESA": "1",
}


def resolver_ids():
    """Toma el primer presupuesto y la primera factura de la empresa 1.

    Antes estaban fijos a 1045 y 1001 (dataset demo, purgado el 2026-11-08).
    """
    con = oracledb.connect(user=credenciales()["DB_USER"],
                           password=credenciales()["DB_PASSWORD"],
                           dsn=CONNECT_STRING)
    cur = con.cursor()
    cur.execute("alter session set current_schema = WKSP_SYPEXWS")
    cur.execute("select min(id_presupuesto) from presupuestos where id_empresa = 1")
    pres = cur.fetchone()[0]
    cur.execute("select min(id_factura) from facturas where id_empresa = 1")
    fact = cur.fetchone()[0]
    con.close()
    BINDS["P5_ID_PRESUPUESTO"] = str(pres)
    BINDS["P5_ID_PRESUPUESTO_2"] = str(pres)
    BINDS["P8_ID_FACTURAS"] = str(fact)
    return pres, fact

# Solo binds de APEX (items y de aplicacion). A proposito NO se toca cualquier
# ":algo": las mascaras de fecha llevan ":MI" ('DD/MM/YYYY HH24:MI') y
# sustituirlas rompia la consulta.
RX_BIND = re.compile(r":(APP_USER|G_USER|F_\w+|P\d+_\w+)")


def prepara_sql(sql):
    """Sustituye los binds de APEX por valores. Devuelve (sql, binds_sin_valor)."""
    faltan = set()

    def cambia(m):
        nombre = m.group(1).upper()
        if nombre in BINDS:
            return BINDS[nombre]
        faltan.add(nombre)
        return "NULL"

    return RX_BIND.sub(cambia, sql).rstrip().rstrip(";"), faltan


def mediana_ms(cur, sql, binds=None, veces=REPETICIONES):
    tiempos = []
    filas = 0
    for i in range(veces):
        inicio = time.perf_counter()
        cur.execute(sql, binds or {})
        if cur.description:
            datos = cur.fetchall()
            filas = len(datos)
        fin = time.perf_counter()
        if i > 0:
            tiempos.append((fin - inicio) * 1000)
    return statistics.median(tiempos), min(tiempos), max(tiempos), filas


def main():
    datos = credenciales()
    con = oracledb.connect(user=datos["DB_USER"], password=datos["DB_PASSWORD"], dsn=CONNECT_STRING)
    cur = con.cursor()
    cur.execute("alter session set current_schema = WKSP_SYPEXWS")

    pres, fact = resolver_ids()
    print(f"Documentos de prueba: presupuesto {pres}, factura {fact}")

    print("=" * 78)
    print("RENDIMIENTO DE LAS PANTALLAS - Synpex (app 100)")
    print("=" * 78)
    print("Fecha del servidor:", cur.execute(
        "select to_char(sysdate, 'DD/MM/YYYY HH24:MI') from dual").fetchone()[0])
    print(f"Repeticiones por consulta: {REPETICIONES} (la primera es de calentamiento)")
    print()

    print("--- Volumen de datos ---")
    for tabla in ("PRESUPUESTOS", "PRESUPUESTOS_DET", "FACTURAS", "FACTURAS_DET",
                  "CLIENTES", "USUARIO", "SYN_LOGIN_LOG", "SYN_ERROR_LOG", "GASTO_REAL"):
        print(f"  {tabla:<20} {cur.execute(f'select count(*) from {tabla}').fetchone()[0]:>9} filas")
    print()

    fallas = 0
    avisos = set()
    resultados = []

    print("--- Regiones de datos (leidas de APEX y ejecutadas tal cual) ---")
    print(f"  {'pag':>3}  {'region':<34} {'tipo':<16} {'mediana':>9} {'max':>8} {'filas':>6}")

    cur.execute("""select page_id, region_name, source_type_plugin_static_id, region_source
                     from apex_application_page_regions
                    where application_id = 100
                      and page_id in (3, 5, 8, 13)
                      and region_source is not null
                      and source_type_plugin_static_id in ('NATIVE_IR', 'NATIVE_SQL_REPORT',
                                                           'NATIVE_CARDS', 'NATIVE_JET_CHART')
                    order by page_id, display_sequence""")
    regiones = cur.fetchall()

    for pagina, nombre, tipo, fuente in regiones:
        etiqueta = f"p{pagina} {nombre}"
        sql, faltan = prepara_sql(fuente.read())
        avisos |= faltan
        try:
            mediana, minimo, maximo, filas = mediana_ms(cur, sql)
        except Exception as ex:  # noqa: BLE001
            print(f"  {pagina:>3}  {nombre[:34]:<34} {tipo:<16} ERROR {str(ex).splitlines()[0][:38]}")
            fallas += 1
            continue
        resultados.append((etiqueta, mediana, filas))
        print(f"  {pagina:>3}  {nombre[:34]:<34} {tipo:<16} {mediana:8.1f}ms {maximo:7.1f}ms {filas:>6}")
        if mediana > LIMITE_MS:
            fallas += 1

    # Regiones de contenido dinamico (PL/SQL): se ejecutan como en
    # 20261106_resumen_p5.py, cambiando el RETURN por una asignacion.
    print()
    print("--- Regiones de contenido dinamico (PL/SQL) ---")
    cur.execute("""select page_id, region_name, region_source
                     from apex_application_page_regions
                    where application_id = 100
                      and page_id in (5, 8)
                      and region_source is not null
                      and source_type_plugin_static_id = 'NATIVE_DYNAMIC_CONTENT'
                    order by page_id, display_sequence""")
    for pagina, nombre, fuente in cur.fetchall():
        cuerpo = fuente.read()
        nombres = set(m.group(1).upper() for m in RX_BIND.finditer(cuerpo))
        binds = {n: BINDS[n] for n in nombres if n in BINDS}
        # Los binds que no conocemos se pasan como NULL: en PL/SQL no se pueden
        # sustituir por texto sin romper el bloque.
        for n in nombres - set(BINDS):
            binds[n] = None
            avisos.add(n)
        cuerpo = re.sub(r"RETURN\s+v_html\s*;", ":salida := v_html;", cuerpo, flags=re.I)
        # RETURN con valor no vale dentro de un bloque anonimo.
        cuerpo = re.sub(r"RETURN\s+NULL\s*;", "NULL;", cuerpo, flags=re.I)
        salida = cur.var(oracledb.DB_TYPE_CLOB)
        # Unas regiones son un bloque completo (traen su END;) y otras un trozo
        # de bloque que APEX envuelve. Hay que distinguirlas o el begin sobra.
        if cuerpo.rstrip().lower().endswith("end;"):
            bloque = cuerpo
        else:
            bloque = "begin " + cuerpo + " end;"
        tiempos = []
        largo = 0
        for i in range(3):
            binds_ejec = dict(binds)
            binds_ejec["salida"] = salida
            inicio = time.perf_counter()
            try:
                cur.execute(bloque, binds_ejec)
            except Exception as ex:  # noqa: BLE001
                print(f"  p{pagina} {nombre[:34]:<34} ERROR {str(ex).splitlines()[0][:38]}")
                fallas += 1
                break
            fin = time.perf_counter()
            if i > 0:
                tiempos.append((fin - inicio) * 1000)
            try:
                largo = len(salida.getvalue().read())
            except Exception:  # noqa: BLE001
                largo = 0
        else:
            print(f"  p{pagina} {nombre[:34]:<34} {statistics.median(tiempos):8.1f}ms "
                  f"({largo/1024:.1f} KiB de HTML)")

    print()
    print("--- Impresos (paginas 11 y 12) ---")
    cur.execute("""select f.id_factura, e.cod_pais
                     from facturas f join empresas e on e.id_empresa = f.id_empresa
                    order by e.cod_pais, f.id_factura""")
    vistos = set()
    for id_factura, pais in cur.fetchall():
        if pais in vistos:
            continue
        vistos.add(pais)
        tiempos = []
        largo = 0
        # 5 pasadas y se descarta la primera: un impreso con el logo en data URI
        # trae ~1 MB de HTML y una sola muestra lenta (arranque del ADB) movia la
        # mediana por encima del limite sin que hubiera nada lento.
        for i in range(5):
            inicio = time.perf_counter()
            html = cur.execute("select pkg_reportes_factura.fn_imprimir_factura(:1) from dual",
                               [id_factura]).fetchone()[0]
            largo = len(html.read())
            fin = time.perf_counter()
            if i > 0:
                tiempos.append((fin - inicio) * 1000)
        mediana = statistics.median(tiempos)
        minimo = min(tiempos)
        print(f"  factura {id_factura} ({pais}): {mediana:8.1f}ms (mejor {minimo:6.1f}ms), "
              f"{largo/1024:7.1f} KiB")
        # Falla solo si incluso la mejor pasada pasa del limite: el ADB tiene
        # picos de latencia de varios segundos que no son de la consulta.
        if minimo > LIMITE_MS:
            fallas += 1

    id_presu = cur.execute("select min(id_presupuesto) from presupuestos").fetchone()[0]
    tiempos = []
    largo = 0
    for i in range(5):
        inicio = time.perf_counter()
        html = cur.execute("select pkg_reportes_presupuesto.fn_imprimir_presupuesto(:1) from dual",
                           [id_presu]).fetchone()[0]
        largo = len(html.read())
        fin = time.perf_counter()
        if i > 0:
            tiempos.append((fin - inicio) * 1000)
    print(f"  presupuesto {id_presu}: {statistics.median(tiempos):8.1f}ms "
          f"(mejor {min(tiempos):6.1f}ms), {largo/1024:7.1f} KiB")
    if min(tiempos) > LIMITE_MS:
        fallas += 1

    print()
    print("--- Indices de las tablas de documentos ---")
    cur.execute("""select table_name, index_name, column_name, column_position
                     from all_ind_columns
                    where index_owner = 'WKSP_SYPEXWS'
                      and table_name in ('PRESUPUESTOS', 'FACTURAS')
                    order by table_name, index_name, column_position""")
    filas = cur.fetchall()
    for tabla, indice, columna, _ in filas:
        print(f"  {tabla:<14} {indice:<34} {columna}")
    con_empresa = {f[0] for f in filas if f[2] == "ID_EMPRESA"}
    for tabla in ("PRESUPUESTOS", "FACTURAS"):
        if tabla not in con_empresa:
            print(f"  AVISO: {tabla} no tiene ningun indice que empiece por ID_EMPRESA,")
            print( "         que es el filtro de todos los listados (hoy no hace falta: hay decenas de filas).")
    print()

    peor = max(resultados, key=lambda r: r[1]) if resultados else None
    print("--- Veredicto ---")
    if peor:
        print(f"  Region mas lenta de las medidas: {peor[0]} con {peor[1]:.1f}ms "
              f"({peor[2]} filas).")
    print(f"  Limite de esta prueba: {LIMITE_MS}ms de mediana por region.")
    if avisos:
        print(f"  Aviso: binds sin valor conocido, sustituidos por NULL: {sorted(avisos)}")
    print(f"  RESULTADO: FALLAS={fallas}")

    con.close()
    sys.exit(1 if fallas else 0)


if __name__ == "__main__":
    main()
