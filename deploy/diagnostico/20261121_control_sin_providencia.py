"""
Verificacion: el rango de control se imprime aunque no haya providencia (2026-11-21).

El dueno dijo que **no tiene la providencia** y que va a cargar **solo el rango de control**
(«Control desde» / «Control hasta»). Medido: `fn_asignar_control` y `fn_control_en_rango` solo
miran esas dos columnas, asi que la numeracion automatica funciona sin providencia. Pero el
**impreso de la factura** (`pkg_reportes_factura.fn_imprimir_factura_ve`) ponia el rango
DENTRO del bloque `IF v_prov IS NOT NULL`, asi que sin providencia el papel salia **sin el
rango**, que es justo lo que exige la forma libre.

Comprueba cuatro escenarios sobre una factura real, cada uno en su savepoint y sin commitear
(el dato de la empresa no se toca):

  1. solo el rango            -> sale «Control desde No.», no sale «Providencia SENIAT»
  2. providencia + fecha + rango -> salen los dos
  3. solo la providencia (sin fecha ni rango) -> sale la providencia y NO queda «de fecha» ni
                                 un «Control desde No.  hasta No.» vacio
  4. nada configurado         -> no sale ninguno de los dos, y el documento sigue imprimiendose

Y ademas, con solo el rango: `fn_asignar_control` entrega el siguiente numero y
`fn_control_en_rango` acepta uno de dentro del rango.

Uso:
    python deploy/diagnostico/20261121_control_sin_providencia.py

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
omitidos = []


def comprobar(nombre, condicion, detalle=""):
    print(f"  [{'OK   ' if condicion else 'FALLA'}] {nombre} {detalle}".rstrip())
    if not condicion:
        fallas.append(nombre)


def omitir(nombre, motivo):
    print(f"  [OMITIDO] {nombre} -- {motivo}")
    omitidos.append(nombre)


def texto(valor):
    if valor is None:
        return ""
    return valor.read() if hasattr(valor, "read") else str(valor)


conn = oracledb.connect(user=d["DB_USER"], password=d["DB_PASSWORD"], dsn=CS)
cur = conn.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")

IMPRIME = "WKSP_SYPEXWS.PKG_REPORTES_FACTURA.FN_IMPRIMIR_FACTURA"


def imprime(v_factura):
    return texto(cur.callfunc(IMPRIME, oracledb.DB_TYPE_CLOB, [v_factura]))


def configura(prov, fecha, desde, hasta):
    """Deja EMPRESA_FISCAL de la empresa 1 en el escenario pedido, DENTRO de la transaccion."""
    cur.execute(
        "update empresa_fiscal set nro_providencia = :p, "
        "prov_fecha = to_date(:f, 'DD/MM/YYYY'), "
        "control_desde = :d, control_hasta = :h where id_empresa = 1",
        {"p": prov, "f": fecha, "d": desde, "h": hasta})


print("== punto de partida ==")

fila = cur.execute(
    "select nro_providencia, to_char(prov_fecha, 'DD/MM/YYYY'), control_desde, control_hasta "
    "from empresa_fiscal where id_empresa = 1").fetchone()
if fila is None:
    print("  la empresa 1 no tiene fila en EMPRESA_FISCAL; no hay nada que medir")
    sys.exit(1)
print(f"  hoy: providencia={fila[0]!r} fecha={fila[1]!r} desde={fila[2]!r} hasta={fila[3]!r}")

fac = cur.execute(
    "select min(id_factura) from facturas where id_empresa = 1 and tipo_documento = 'FAC'").fetchone()[0]

if not fac:
    omitir("impresos", "la empresa 1 no tiene facturas (FAC) que imprimir")
else:
    print(f"  factura de prueba: {fac}")

    print("== 1. solo el rango, sin providencia (el caso del dueno) ==")
    cur.execute("savepoint sp1")
    configura(None, None, "00-000001", "00-010000")
    html = imprime(fac)
    comprobar("el papel trae el rango", "Control desde No. 00-000001" in html
              and "hasta No. 00-010000" in html)
    comprobar("y no inventa la providencia", "Providencia SENIAT" not in html)
    cur.execute("rollback to sp1")

    print("== 2. providencia + fecha + rango ==")
    cur.execute("savepoint sp2")
    configura("01/01060", "12/11/2008", "00-000001", "00-010000")
    html = imprime(fac)
    comprobar("sale la providencia con su fecha",
              "No. Providencia SENIAT 01/01060" in html and "de fecha 12/11/2008" in html)
    comprobar("y sale tambien el rango", "Control desde No. 00-000001" in html
              and "hasta No. 00-010000" in html)
    cur.execute("rollback to sp2")

    print("== 3. solo la providencia, sin fecha ni rango ==")
    cur.execute("savepoint sp3")
    configura("01/01060", None, None, None)
    html = imprime(fac)
    comprobar("sale la providencia", "No. Providencia SENIAT 01/01060" in html)
    comprobar("no queda un «de fecha» sin fecha", "de fecha" not in html)
    comprobar("no queda un rango vacio", "Control desde No." not in html)
    cur.execute("rollback to sp3")

    print("== 4. sin nada configurado ==")
    cur.execute("savepoint sp4")
    configura(None, None, None, None)
    html = imprime(fac)
    comprobar("no sale ninguna de las dos lineas",
              "Providencia SENIAT" not in html and "Control desde No." not in html)
    comprobar("y el documento sigue saliendo entero", len(html) > 1000, f"({len(html)} bytes)")
    cur.execute("rollback to sp4")

print("== la numeracion automatica solo necesita el rango ==")

cur.execute("savepoint sp5")
configura(None, None, "00-000001", "00-010000")
siguiente = cur.callfunc("WKSP_SYPEXWS.FN_ASIGNAR_CONTROL", str, [1])
comprobar("fn_asignar_control entrega un numero del rango",
          siguiente is not None and str(siguiente).startswith("00-"), f"({siguiente})")
en_rango = cur.callfunc("WKSP_SYPEXWS.FN_CONTROL_EN_RANGO", str, [1, str(siguiente)])
comprobar("fn_control_en_rango acepta el que entrega la funcion", en_rango is not None,
          f"({en_rango})")
cur.execute("rollback to sp5")

print("== estado general ==")

conn.rollback()

despues = cur.execute(
    "select nro_providencia, to_char(prov_fecha, 'DD/MM/YYYY'), control_desde, control_hasta "
    "from empresa_fiscal where id_empresa = 1").fetchone()
comprobar("los datos de la empresa siguen como estaban", despues == fila,
          f"({despues})")

invalidos = cur.execute("select count(*) from all_objects where owner = 'WKSP_SYPEXWS' "
                        "and status <> 'VALID' and object_type in "
                        "('FUNCTION','PROCEDURE','PACKAGE','PACKAGE BODY','TRIGGER','VIEW')").fetchone()[0]
comprobar("0 objetos invalidos", invalidos == 0, f"({invalidos})")

conn.close()
print()
print("RESULTADO: FALLAS=" + str(len(fallas))
      + (f" OMITIDOS={len(omitidos)}" if omitidos else ""))
if fallas:
    for f in fallas:
        print("  - " + f)
if omitidos:
    print("  omitidos: " + ", ".join(omitidos))
sys.exit(1 if fallas else 0)
