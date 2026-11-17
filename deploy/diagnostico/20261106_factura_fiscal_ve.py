"""
Verificacion de la factura fiscal venezolana (forma libre).

Plantilla: `libreria/factura-ejemplo-prefactura.pdf` (ejemplo del cliente). Comprueba que
`pkg_reportes_factura.fn_imprimir_factura` imprime la forma libre para empresas de Venezuela y el
documento generico para las de Mexico, que los datos fiscales salen (RIF, numero de control,
direccion, imprenta, providencia) y que el TOTAL en bolivares cuadra con el detalle.

Uso:
    python deploy/diagnostico/20261106_factura_fiscal_ve.py
"""
import os
import re
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


def numero(texto):
    """'15.093,11' -> 15093.11"""
    return float(texto.replace(".", "").replace(",", "."))


conn = oracledb.connect(user=d["DB_USER"], password=d["DB_PASSWORD"], dsn=CS)
cur = conn.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")


def uno(sql, args=None):
    cur.execute(sql, args or {})
    return cur.fetchone()[0]


def imprimir(fid):
    html = cur.callfunc("pkg_reportes_factura.fn_imprimir_factura",
                        oracledb.DB_TYPE_CLOB, [fid])
    return html.read() if hasattr(html, "read") else html


print("== datos fiscales cargados ==")

fila = cur.execute("select direccion_fiscal, telefono, email, nro_providencia, prov_fecha, "
                   "       control_desde, control_hasta, imprenta_nombre, imprenta_rif "
                   "  from empresa_fiscal where id_empresa = 1").fetchone()
comprobar("empresa 1 tiene fila en empresa_fiscal", fila is not None)
if fila:
    comprobar("direccion, telefono y email del emisor",
              all(x is not None for x in fila[0:3]))
    comprobar("providencia y rango de control",
              all(x is not None for x in fila[3:7]), f"({fila[3]} / {fila[5]}..{fila[6]})")
    comprobar("datos de la imprenta", all(x is not None for x in fila[7:9]))

sin_control = uno("select count(*) from facturas where nro_control is null")
comprobar("todas las facturas tienen numero de control", sin_control == 0, f"({sin_control})")

rep = uno("select count(*) from (select id_empresa, nro_control from facturas "
          " group by id_empresa, nro_control having count(*) > 1)")
comprobar("el numero de control no se repite dentro de la empresa", rep == 0, f"({rep})")

print("== la empresa de Venezuela imprime forma libre ==")

ve = uno("select min(f.id_factura) from facturas f join empresas e on e.id_empresa = f.id_empresa "
         " where e.cod_pais = 'VE'")
html_ve = imprimir(ve)

for marca in ("fe-emisor", "fe-cliente", "fe-lineas", "fe-totales", "fe-leyenda", "fe-imprenta"):
    comprobar(f"el documento trae «{marca}»", marca in html_ve)
for texto in ("N&ordm; CONTROL", "R.I.F.", "Base imponible", "Providencia SENIAT", "Imprenta",
              "SIN TACHADURA"):
    comprobar(f"el documento trae «{texto}»", texto in html_ve)
comprobar("el numero de control de la factura sale impreso",
          uno("select nro_control from facturas where id_factura = :f", {"f": ve}) in html_ve)

print("== los totales en bolivares cuadran ==")

tasa = uno("select nvl(tipo_cambio, 1) from facturas where id_factura = :f", {"f": ve})
total_det = uno("select round(nvl(sum(monto_total_linea), 0), 2) from facturas_det "
                " where id_factura = :f", {"f": ve})
esperado = round(total_det * tasa, 2)

m = re.search(r">TOTAL</td>\s*<td class=\"num\">Bs\. ([\d.,]+)</td>", html_ve)
comprobar("el TOTAL en Bs. aparece en el documento", m is not None)
if m:
    impreso = numero(m.group(1))
    comprobar("TOTAL impreso = lineas x tasa", abs(impreso - esperado) < 0.01,
              f"({impreso} vs {esperado}; factura {ve}, tasa {tasa})")

grupos = re.findall(r"Base imponible \([\d.,]+ %\)</td>\s*<td class=\"num\">Bs\. ([\d.,]+)</td>",
                    html_ve)
ivas = re.findall(r"IVA \([\d.,]+ %\)</td>\s*<td class=\"num\">Bs\. ([\d.,]+)</td>", html_ve)
comprobar("hay al menos un grupo de alicuota", len(grupos) >= 1, f"({len(grupos)})")
if grupos and ivas and m:
    suma = round(sum(numero(x) for x in grupos) + sum(numero(x) for x in ivas), 2)
    comprobar("suma de (base + IVA) de los grupos = TOTAL", abs(suma - numero(m.group(1))) < 0.02,
              f"({suma})")

print("== las empresas de Mexico siguen con el documento generico ==")

mx = uno("select min(f.id_factura) from facturas f join empresas e on e.id_empresa = f.id_empresa "
         " where e.cod_pais = 'MX'")
if mx:
    html_mx = imprimir(mx)
    comprobar("no usa la forma libre", "fe-leyenda" not in html_mx and "SIN TACHADURA" not in html_mx)
    comprobar("mantiene su total en su moneda", "TOTAL MXN" in html_mx,
              f"(factura {mx})")
else:
    print("  (sin facturas de Mexico para comparar)")

print("== estado general ==")

invalidos = uno("select count(*) from all_objects where owner = 'WKSP_SYPEXWS' "
                "and status <> 'VALID' and object_type in "
                "('FUNCTION','PROCEDURE','PACKAGE','PACKAGE BODY','TRIGGER','VIEW')")
comprobar("0 objetos invalidos", invalidos == 0, f"({invalidos})")
paginas = uno("select count(*) from apex_application_pages where application_id = 100")
comprobar("siguen las 25 paginas", paginas == 25, f"({paginas})")

conn.close()
print()
print("RESULTADO: FALLAS=" + str(len(fallas)))
if fallas:
    for f in fallas:
        print("  - " + f)
sys.exit(1 if fallas else 0)
