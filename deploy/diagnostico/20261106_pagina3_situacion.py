"""
Verificacion de la pagina 3: columna «Situacion» y region «Ultimos intentos».

Comprueba la estructura (region, columnas, expresion del badge) y el comportamiento: ejecuta la
consulta TAL COMO quedo guardada en APEX y, dentro de una transaccion con rollback, pone un usuario
bloqueado, otro pendiente y otro activo con clave por cambiar para ver que la columna los distingue.

Uso:
    python deploy/diagnostico/20261106_pagina3_situacion.py

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

IR_REGION_ID = 10564941614198500  # region «Gestion de Usuarios»

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


conn = oracledb.connect(user=d["DB_USER"], password=d["DB_PASSWORD"], dsn=CS)
cur = conn.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")  # APEX parsea como el esquema dueno


def uno(sql, args=None):
    cur.execute(sql, args or {})
    fila = cur.fetchone()
    return fila[0] if fila else None


def texto(valor):
    """CLOB o VARCHAR2 -> str."""
    if valor is None:
        return ""
    return valor.read() if hasattr(valor, "read") else str(valor)


print("== estructura de la region «Gestion de Usuarios» ==")

try:
    origenes = cur.execute(
        "select source_type, source_type_plugin_static_id, region_source "
        "from apex_application_page_regions "
        "where application_id = 100 and region_id = :r", {"r": IR_REGION_ID}).fetchone()
    tipo_plug = origenes[1]
    fuente = texto(origenes[2])
except Exception as e:  # noqa: BLE001
    print("  error leyendo la region:", e)
    tipo_plug, fuente = None, ""

fuente_norm = " ".join(fuente.lower().split())
comprobar("la region sigue siendo Interactive Report", tipo_plug == "NATIVE_IR", f"({tipo_plug})")
comprobar("el origen es SQL, no TABLE", "from usuario" in fuente_norm and "situacion" in fuente_norm,
          f"({len(fuente)} caracteres de fuente)")

print("== columna «Situacion» ==")

try:
    col = cur.execute(
        "select report_label, column_type, html_expression, display_order "
        "from apex_application_page_ir_col "
        "where application_id = 100 and region_id = :r and column_alias = 'SITUACION'",
        {"r": IR_REGION_ID}).fetchone()
except Exception as e:  # noqa: BLE001
    col = None
    print("  error:", e)

comprobar("existe la columna SITUACION", col is not None)
if col:
    etiqueta, ctype, html_expr, orden = col[0], col[1], texto(col[2]), col[3]
    comprobar("etiqueta «Situacion»", (etiqueta or "").lower().startswith("situaci"), f"({etiqueta})")
    comprobar("tipo STRING", ctype == "STRING", f"({ctype})")
    comprobar("el badge usa status-#SITUACION_CLASE#", "status-#situacion_clase#" in (html_expr or "").lower(),
              f"({html_expr[:60]}...)")
    comprobar("orden 7 (entre Estado y Fecha)", orden == 7, f"({orden})")

try:
    clave = cur.execute(
        "select count(*) from apex_application_page_ir_col "
        "where application_id = 100 and region_id = :r and column_alias = 'SITUACION_CLASE'",
        {"r": IR_REGION_ID}).fetchone()[0]
except Exception:  # noqa: BLE001
    clave = 0
comprobar("existe la columna auxiliar SITUACION_CLASE", clave == 1)

columnas_rpt = uno(
    "select report_columns from apex_application_page_ir_rpt "
    "where application_id = 100 and page_id = 3 and report_alias = 'primary'") or ""
comprobar("SITUACION esta en el informe por defecto", "SITUACION" in columnas_rpt.split(":"),
          f"({columnas_rpt})")
comprobar("SITUACION_CLASE NO se muestra", "SITUACION_CLASE" not in columnas_rpt.split(":"))
comprobar("PASSWORD_HASH ya no viaja al navegador",
          "PASSWORD_HASH" not in columnas_rpt.split(":")
          and "password_hash" not in fuente_norm,
          f"({columnas_rpt})")

print("== empresa y rol con nombre, no con id ==")

comprobar("el SELECT ya no trae u.id_empresa ni u.rol_id",
          "u.id_empresa," not in fuente_norm and "u.rol_id," not in fuente_norm)
comprobar("trae el nombre de la empresa", "e.nombre_empresa as empresa" in fuente_norm)
comprobar("trae el codigo del rol", "r.codigo_rol as rol" in fuente_norm)
comprobar("une EMPRESAS", "left join empresas e on e.id_empresa = u.id_empresa" in fuente_norm)
comprobar("une SYN_ROLES", "left join syn_roles r on r.id_rol = u.rol_id" in fuente_norm)

for alias, etiqueta in (("EMPRESA", "empresa"), ("ROL", "rol")):
    fila = cur.execute(
        "select report_label, column_type from apex_application_page_ir_col "
        "where application_id = 100 and region_id = :r and column_alias = :a",
        {"r": IR_REGION_ID, "a": alias}).fetchone()
    comprobar(f"existe la columna {alias}", fila is not None)
    if fila:
        comprobar(f"{alias} es texto con etiqueta «{etiqueta}»",
                  fila[1] == "STRING" and (fila[0] or "").lower() == etiqueta,
                  f"({fila[0]}, {fila[1]})")

comprobar("EMPRESA se muestra en el informe", "EMPRESA" in columnas_rpt.split(":"))
comprobar("ROL se muestra en el informe", "ROL" in columnas_rpt.split(":"))

print("== la consulta devuelve nombres ==")

if "from usuario" in fuente_norm:
    cur.execute(fuente)
    cab = [c[0].lower() for c in cur.description]
    filas = cur.fetchall()
    if "empresa" in cab and "rol" in cab:
        i_e, i_r, i_u = cab.index("empresa"), cab.index("rol"), cab.index("username")
        muestra = {str(f[i_u]).upper(): (f[i_e], f[i_r]) for f in filas}
        comprobar("las filas traen nombre de empresa", all(f[i_e] is not None for f in filas),
                  f"({len(filas)} filas)")
        comprobar("las filas traen codigo de rol", all(f[i_r] is not None for f in filas))
        comprobar("admin.demo sale con empresa y rol legibles",
                  muestra.get("ADMIN.DEMO", (None, None))[0] is not None
                  and str(muestra.get("ADMIN.DEMO", ("", ""))[1]).isupper(),
                  str(muestra.get("ADMIN.DEMO")))
    else:
        comprobar("la consulta trae las columnas empresa y rol", False, str(cab))

print("== region «Ultimos intentos» ==")

try:
    inte = cur.execute(
        "select region_name, source_type_plugin_static_id, region_source, display_sequence "
        "from apex_application_page_regions "
        "where application_id = 100 and page_id = 3 and region_name like '%intentos%'").fetchone()
except Exception as e:  # noqa: BLE001
    inte = None
    print("  error:", e)

comprobar("existe la region de intentos", inte is not None)
if inte:
    nombre_r, tipo_r, fuente_r, sec_r = inte[0], inte[1], texto(inte[2]), inte[3]
    fuente_r_norm = " ".join(fuente_r.lower().split())
    comprobar("es un report clasico (NATIVE_SQL_REPORT)", tipo_r == "NATIVE_SQL_REPORT", f"({tipo_r})")
    comprobar("lee syn_login_log", "syn_login_log" in fuente_r_norm)
    comprobar("limita a 20 filas", "fetch first 20 rows only" in fuente_r_norm)
    comprobar("va debajo del IR y de los errores", sec_r is not None and sec_r >= 30, f"({sec_r})")

print("== la consulta guardada se ejecuta ==")

filas = []
try:
    cur.execute(fuente)
    cabeceras = [c[0].lower() for c in cur.description]
    filas = cur.fetchall()
    comprobar("devuelve las dos columnas de situacion", {"situacion", "situacion_clase"} <= set(cabeceras),
              f"({len(cabeceras)} columnas)")
    total_usuarios = uno("select count(*) from wksp_sypexws.usuario")
    comprobar("devuelve una fila por usuario", len(filas) == total_usuarios,
              f"({len(filas)} de {total_usuarios})")
except Exception as e:  # noqa: BLE001
    print("  error ejecutando la fuente:", e)
    cabeceras = []
    comprobar("la consulta guardada compila y devuelve filas", False)

print("== comportamiento de la columna (transaccion con rollback) ==")

if "situacion" in cabeceras:
    i_sit = cabeceras.index("situacion")
    i_usu = cabeceras.index("username")
    i_cla = cabeceras.index("situacion_clase")
    try:
        cur.execute("update wksp_sypexws.usuario set estado = 'ACTIVO', "
                    "bloqueado_hasta = sysdate + 1, debe_cambiar_clave = 'N' "
                    "where upper(username) = upper(:u)", {"u": "luis"})
        cur.execute("update wksp_sypexws.usuario set estado = 'PENDIENTE', "
                    "bloqueado_hasta = null, debe_cambiar_clave = 'N' "
                    "where upper(username) = upper(:u)", {"u": "ter"})
        cur.execute("update wksp_sypexws.usuario set estado = 'ACTIVO', "
                    "bloqueado_hasta = null, debe_cambiar_clave = 'S' "
                    "where upper(username) = upper(:u)", {"u": "ana"})
        cur.execute(fuente)
        cab2 = [c[0].lower() for c in cur.description]
        filas2 = cur.fetchall()
        j_sit, j_usu, j_cla = cab2.index("situacion"), cab2.index("username"), cab2.index("situacion_clase")
        por_usuario = {str(f[j_usu]).upper(): (f[j_sit], f[j_cla]) for f in filas2}

        def valor(usuario):
            return por_usuario.get(usuario.upper(), ("(no encontrado)", ""))

        comprobar("bloqueado -> «BLOQUEADO» / BLOQUEADO",
              valor("luis")[0] == "BLOQUEADO" and valor("luis")[1] == "BLOQUEADO", str(valor("luis")))
        comprobar("pendiente -> «PENDIENTE» / PENDIENTE",
              valor("ter")[0] == "PENDIENTE" and valor("ter")[1] == "PENDIENTE", str(valor("ter")))
        comprobar("clave por cambiar -> sufijo y clase ACTIVO",
              valor("ana")[0] == "ACTIVO (CLAVE POR CAMBIAR)" and valor("ana")[1] == "ACTIVO",
              str(valor("ana")))
    except Exception as e:  # noqa: BLE001
        print("  error en la prueba de comportamiento:", e)
        comprobar("prueba de comportamiento de las tres situaciones", False)
    finally:
        conn.rollback()

print("== estado general ==")

try:
    invalidos = uno("select count(*) from all_objects where owner = 'WKSP_SYPEXWS' "
                    "and status <> 'VALID' and object_type in "
                    "('FUNCTION','PROCEDURE','PACKAGE','PACKAGE BODY','TRIGGER','VIEW','TYPE','TYPE BODY')")
    comprobar("0 objetos invalidos", invalidos == 0, f"({invalidos})")
    paginas = uno("select count(*) from apex_application_pages where application_id = 100")
    comprobar("siguen las 19 paginas", paginas == 19, f"({paginas})")
    guarda = uno("select count(*) from apex_application_page_proc "
                 "where application_id = 100 and page_id = 3 and static_id = 'valida-rol-admin'")
    comprobar("la guarda de rol de la pagina 3 sigue", guarda == 1)
except Exception as e:  # noqa: BLE001
    print("  error:", e)
    comprobar("estado general", False)

conn.close()
print()
print("RESULTADO: FALLAS=" + str(len(fallas)))
if fallas:
    for f in fallas:
        print("  - " + f)
sys.exit(1 if fallas else 0)

