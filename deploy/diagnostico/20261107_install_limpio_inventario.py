#!/usr/bin/env python3
# =============================================================================
# 20261107_install_limpio_inventario.py
#
# Compara lo que la INSTALACION LIMPIA del repositorio crea con lo que existe
# de verdad en WKSP_SYPEXWS. Sirve para que un esquema nuevo no salga a medias.
#
# Por que existe: medido el 2026-11-07, install.sql + install_bodies.sql no
# cargaban varias cosas que la app necesita (y sin roles nadie puede entrar).
# Esto lo detecta antes de que lo descubra un cliente en una instalacion nueva.
#
# Que compara:
#   1. Objetos: tablas, secuencias, funciones, procedimientos, packages (spec y
#      body), triggers y vistas que crean los scripts @@ de install.sql e
#      install_bodies.sql, contra ALL_OBJECTS/ALL_SEQUENCES/ALL_TABLES.
#   2. Jobs del scheduler (no estan en ALL_OBJECTS).
#   3. Roles de SYN_ROLES (sin al menos ADMIN nadie puede entrar).
#   4. Catalogo de ISLR: los 16 conceptos en el script y en la base (13 activos).
#   5. Columnas de cada tabla: lo que declara tabla/<tabla>.sql contra
#      ALL_TAB_COLUMNS. Detecta el DDL canonico desfasado respecto a la base.
#
# Exclusiones (no son de la app): DEPT, EMP (tablas de ejemplo) y las de
# herramientas (DBTOOLS$%, APEX_%, WWV_%).
#
# Uso (desde la raiz del repo):
#   python deploy/diagnostico/20261107_install_limpio_inventario.py
#   python deploy/diagnostico/20261107_install_limpio_inventario.py --solo-objetos
#
# Sale con codigo 1 solo si hay huecos; con todo bien, 0.
# =============================================================================

import os
import re
import sys

import oracledb

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

CONNECT_STRING = (
    "(DESCRIPTION=(RETRY_COUNT=5)(RETRY_DELAY=2)"
    "(ADDRESS=(PROTOCOL=TCPS)(PORT=1521)(HOST=adb.mx-monterrey-1.oraclecloud.com))"
    "(CONNECT_DATA=(SERVICE_NAME=GFD7E2575D251AE_SYPEXSQL_high.adb.oraclecloud.com))"
    "(SECURITY=(SSL_SERVER_DN_MATCH=YES)))"
)

ESQUEMA = "WKSP_SYPEXWS"

# Objetos que existen en la base y no son de la app (no deben estar en install).
EXCLUIDOS = {"DEPT", "EMP", "DEPT_TRG1", "EMP_TRG1", "DEPT_SEQ", "EMP_SEQ", "DBTOOLS$MCP_LOG"}

# Contrato de la instalacion limpia: sin estos roles nadie puede autenticar
# (fn_autenticar_usuario exige un rol y las guardas lo comparan por codigo).
ROLES_MINIMOS = {"ADMIN", "GERENCIA", "VENTAS", "CONTABILIDAD", "ALMACEN", "CONSULTA", "FACTURACION"}

# Catalogo de conceptos de ISLR que la instalacion tiene que sembrar
# (deploy/install_datos.sql, el mismo merge que la migracion del 2026-11-19).
# Sin catalogo no se puede calcular el ISLR ni emitir su comprobante, y una
# instalacion limpia se quedaba con ISLR_CONCEPTOS vacia. De los 16, 13 son
# elegibles (ACTIVO='S') y 3 son informativos (040, 065 y 067).
ISLR_CODIGOS = {"002", "003", "018", "019", "040", "053", "054", "055", "057",
                "058", "059", "061", "062", "063", "065", "067"}
ISLR_ACTIVOS = 13

# Jobs que debe dejar una instalacion limpia.
JOBS_ESPERADOS = {"JOB_PURGA_LOGS", "JOB_ACTUALIZA_TASAS_BCV"}

TIPOS = ("TABLE", "SEQUENCE", "FUNCTION", "PROCEDURE", "PACKAGE", "PACKAGE BODY", "TRIGGER", "VIEW")

RE_CREATE = re.compile(
    r"create\s+(?:or\s+replace\s+)?(?:editionable\s+|noneditionable\s+)?"
    r"(table|sequence|function|procedure|package\s+body|package|trigger|view)\s+"
    r"\"?([A-Za-z0-9_$#]+)\"?",
    re.IGNORECASE,
)


def credenciales():
    datos = {}
    ruta = os.path.join(REPO, ".env")
    if os.path.exists(ruta):
        with open(ruta, encoding="utf-8") as f:
            for linea in f:
                linea = linea.strip()
                if linea and not linea.startswith("#") and "=" in linea:
                    clave, valor = linea.split("=", 1)
                    datos[clave.strip()] = valor.strip()
    datos["DB_USER"] = os.environ.get("DB_USER", datos.get("DB_USER"))
    datos["DB_PASSWORD"] = os.environ.get("DB_PASSWORD", datos.get("DB_PASSWORD"))
    if not datos.get("DB_USER") or not datos.get("DB_PASSWORD"):
        sys.exit("Faltan DB_USER y/o DB_PASSWORD (entorno o .env de la raiz).")
    return datos


def incluye(archivo):
    """Devuelve las rutas @@ de un script de instalacion, resueltas a disco."""
    rutas = []
    base = os.path.dirname(archivo)
    with open(archivo, encoding="utf-8", errors="replace") as f:
        for linea in f:
            m = re.match(r"\s*@@\s*(\S+)", linea)
            if m:
                rutas.append(os.path.normpath(os.path.join(base, m.group(1))))
    return rutas


def objetos_de_archivo(ruta):
    """(tipo, nombre) que crea un .sql canonico."""
    encontrados = set()
    if not os.path.exists(ruta):
        return encontrados
    with open(ruta, encoding="utf-8", errors="replace") as f:
        texto = f.read()
    # Quitar comentarios de linea para no confundir ejemplos comentados
    texto = re.sub(r"--[^\n]*", "", texto)
    for m in RE_CREATE.finditer(texto):
        tipo = re.sub(r"\s+", " ", m.group(1).upper())
        nombre = m.group(2).upper()
        if nombre in EXCLUIDOS:
            continue
        encontrados.add((tipo, nombre))
    return encontrados


def columnas_de_archivo(ruta):
    """Columnas declaradas en el CREATE TABLE de un tabla/*.sql (legacy)."""
    columnas = set()
    if not os.path.exists(ruta):
        return columnas
    with open(ruta, encoding="utf-8", errors="replace") as f:
        texto = f.read()
    m = re.search(r"create\s+table\s+\"?([A-Za-z0-9_$#]+)\"?\s*\((.*?)\)\s*;", texto,
                  re.IGNORECASE | re.DOTALL)
    if not m:
        return columnas
    # Una definicion de columna termina en coma. Las lineas que siguen a una sin
    # coma son CONTINUACION de la anterior (la clausula de una identity:
    # "minvalue ...", "increment by 1 ...", o la segunda linea de un check:
    # "or regexp_like(...)"). Sin esta regla el inventario inventaba columnas
    # llamadas INCREMENT y OR y daba FALLAS por un DDL que estaba bien.
    # Las palabras clave se comparan ENTERAS: con "startswith('OR')" se perdia
    # la columna ORIGEN de LOG_TASAS_BCV.
    claves = {"CONSTRAINT", "CHECK", "PRIMARY", "FOREIGN", "UNIQUE", "USING",
              "TABLESPACE", "ENABLE", "DISABLE", "REFERENCES", "NOT", "NULL",
              "DEFAULT", "MINVALUE", "MAXVALUE", "INCREMENT", "CACHE", "NOORDER",
              "NOCYCLE", "NOKEEP", "NOSCALE", "START", "GENERATED", "IDENTITY", "OR"}
    esperando_columna = True
    for linea in m.group(2).splitlines():
        linea = linea.strip()
        if not linea:
            continue
        if not esperando_columna:
            esperando_columna = linea.endswith(",")
            continue
        palabra = re.match(r"[A-Za-z0-9_$#]+", linea)
        if linea.startswith(")") or (palabra and palabra.group(0).upper() in claves):
            esperando_columna = linea.endswith(",")
            continue
        mc = re.match(r'"?([A-Za-z0-9_$#]+)"?\s+[A-Za-z]', linea)
        if mc:
            columnas.add(mc.group(1).upper())
        esperando_columna = linea.endswith(",")
    return columnas


def main():
    solo_objetos = "--solo-objetos" in sys.argv

    # --- 1. Lo que crean los scripts ---
    scripts = [os.path.join(REPO, "deploy", "install.sql"),
               os.path.join(REPO, "deploy", "install_bodies.sql")]
    esperados = set()
    faltantes_de_disco = []
    texto_scripts = ""
    for script in scripts:
        for ruta in incluye(script):
            if not os.path.exists(ruta):
                faltantes_de_disco.append(ruta)
                continue
            esperados |= objetos_de_archivo(ruta)
            with open(ruta, encoding="utf-8", errors="replace") as f:
                texto_scripts += "\n" + re.sub(r"--[^\n]*", "", f.read())
    texto_scripts = texto_scripts.upper()

    datos = credenciales()
    con = oracledb.connect(user=datos["DB_USER"], password=datos["DB_PASSWORD"], dsn=CONNECT_STRING)
    cur = con.cursor()
    cur.execute("alter session set current_schema = " + ESQUEMA)

    cur.execute("""select object_name, object_type from all_objects
                    where owner = :o and object_type in ('TABLE','FUNCTION','PROCEDURE','PACKAGE','PACKAGE BODY','TRIGGER','VIEW')""",
                o=ESQUEMA)
    reales = {(t, n) for n, t in cur.fetchall()}
    cur.execute("select sequence_name from all_sequences where sequence_owner = :o", o=ESQUEMA)
    reales |= {("SEQUENCE", n) for (n,) in cur.fetchall()}
    reales = {x for x in reales if x[1] not in EXCLUIDOS and not x[1].startswith("ISEQ$$_")}

    # --- 2. Jobs y roles: se comprueban en los SCRIPTS, no en la base ---
    # (que existan en la base no prueba que una instalacion nueva los cree)
    jobs = {j for j in JOBS_ESPERADOS if j in texto_scripts}
    roles = {r for r in ROLES_MINIMOS
             if re.search(r"(INSERT\s+INTO|MERGE\s+INTO)\s+SYN_ROLES[\s\S]{0,4000}?'" + re.escape(r) + "'",
                          texto_scripts)}

    # --- 2b. Catalogo de ISLR: se comprueba en el SCRIPT y en la base ---
    # (que la base de trabajo lo tenga no prueba que una instalacion nueva lo cree)
    pos = texto_scripts.find("MERGE INTO ISLR_CONCEPTOS")
    islr_script = set()
    if pos >= 0:
        islr_script = set(re.findall(r"SELECT\s+'([0-9]{3})'", texto_scripts[pos:pos + 6000]))

    # --- 3. Columnas ---
    drift = {}
    if not solo_objetos:
        cur.execute("select table_name from all_tables where owner = :o", o=ESQUEMA)
        tablas = sorted({n for (n,) in cur.fetchall() if n not in EXCLUIDOS})
        for tabla in tablas:
            archivo = os.path.join(REPO, "tabla", tabla.lower() + ".sql")
            if not os.path.exists(archivo):
                continue
            declaradas = columnas_de_archivo(archivo)
            cur.execute("""select column_name from all_tab_columns
                            where owner = :o and table_name = :t""", o=ESQUEMA, t=tabla)
            en_base = {n for (n,) in cur.fetchall()}
            faltan = en_base - declaradas
            sobran = declaradas - en_base
            if faltan or sobran:
                drift[tabla] = (sorted(faltan), sorted(sobran))

    # --- 4. Catalogo de ISLR en la base (lo que la app necesita para retener) ---
    islr_base = None
    try:
        cur.execute("""select count(*),
                              sum(case when activo = 'S' then 1 else 0 end)
                         from islr_conceptos""")
        islr_base = cur.fetchone()
    except oracledb.DatabaseError:
        islr_base = None

    con.close()

    # --- Informe ---
    fallas = 0

    print("=" * 70)
    print("INSTALACION LIMPIA: inventario contra la base")
    print("=" * 70)

    if faltantes_de_disco:
        fallas += 1
        print("\n[FALLA] scripts @@ que no existen en disco:")
        for ruta in faltantes_de_disco:
            print("   -", os.path.relpath(ruta, REPO))

    no_creados = sorted(reales - esperados)
    if no_creados:
        fallas += 1
        print("\n[FALLA] objetos de la base que la instalacion NO crea:")
        for tipo, nombre in no_creados:
            print("   - %-12s %s" % (tipo, nombre))
    else:
        print("\n[OK] todos los objetos de la base los crea la instalacion")

    sobrantes = sorted(esperados - reales)
    if sobrantes:
        print("\n[AVISO] la instalacion crea objetos que hoy no estan en la base:")
        for tipo, nombre in sobrantes:
            print("   - %-12s %s" % (tipo, nombre))

    if JOBS_ESPERADOS - jobs:
        fallas += 1
        print("\n[FALLA] jobs que la instalacion no crea:", ", ".join(sorted(JOBS_ESPERADOS - jobs)))
    else:
        print("[OK] la instalacion crea los dos jobs del scheduler")

    if ROLES_MINIMOS - roles:
        fallas += 1
        print("\n[FALLA] roles que la instalacion no siembra en SYN_ROLES:",
              ", ".join(sorted(ROLES_MINIMOS - roles)))
    else:
        print("[OK] la instalacion siembra los 7 roles de produccion")

    if ISLR_CODIGOS - islr_script:
        fallas += 1
        print("\n[FALLA] conceptos de ISLR que la instalacion no siembra:",
              ", ".join(sorted(ISLR_CODIGOS - islr_script)))
    else:
        print("[OK] la instalacion siembra los 16 conceptos de ISLR")

    if islr_base is None:
        fallas += 1
        print("\n[FALLA] no se pudo leer ISLR_CONCEPTOS (la tabla no existe o no es accesible)")
    else:
        total, activos = islr_base
        activos = activos or 0
        # Se exige el catalogo SEMBRADO, no que sea exactamente ese: el cliente puede
        # agregar conceptos desde la pagina 34 (paso con el 071, 2026-11-22).
        if total < len(ISLR_CODIGOS) or activos < ISLR_ACTIVOS:
            fallas += 1
            print("\n[FALLA] catalogo de ISLR en la base: %s conceptos, %s activos (esperado %s y %s)"
                  % (total, activos, len(ISLR_CODIGOS), ISLR_ACTIVOS))
        else:
            print("[OK] el catalogo de ISLR de la base tiene %s conceptos, %s activos" % (total, activos))

    if drift:
        fallas += 1
        print("\n[FALLA] DDL canonico desfasado respecto a la base (columnas):")
        for tabla, (faltan, sobran) in drift.items():
            print("   - %s" % tabla)
            if faltan:
                print("       falta en tabla/%s.sql: %s" % (tabla.lower(), ", ".join(faltan)))
            if sobran:
                print("       sobra en tabla/%s.sql: %s" % (tabla.lower(), ", ".join(sobran)))
    elif not solo_objetos:
        print("[OK] las columnas de tabla/ coinciden con la base")

    print("\nRESULTADO: FALLAS=%d" % fallas)
    return 1 if fallas else 0


if __name__ == "__main__":
    sys.exit(main())
