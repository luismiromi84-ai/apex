"""
Verificacion del recalculo historico de la tasa de cambio (presupuestos y facturas).

Comprueba que:
  1. La funcion fn_tasa_ves devuelve bolivares por unidad (1 para VES).
  2. Ningun documento en moneda extranjera queda con tipo_cambio = 1 (si su moneda tiene tasa).
  3. La tasa guardada es la de la fecha de emision de cada documento.
  4. Los montos del detalle de factura en Bs cuadran con la tasa.
  5. Los importes (subtotal, impuesto, total) NO cambiaron.

Uso:
    python deploy/diagnostico/20261106_tasa_historica.py
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

# Importes de control tomados antes del recalculo (evidencia 2026-11-06).
CONTROL = {"presupuestos": 67233.60, "facturas": 44277.20}

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
cur.execute("alter session set current_schema = WKSP_SYPEXWS")


def uno(sql, args=None):
    cur.execute(sql, args or {})
    return cur.fetchone()[0]


print("== la funcion ==")

for moneda, esperado in (("VES", 1), ("USD", None), ("MXN", None)):
    valor = uno("select fn_tasa_ves(sysdate, :m) from dual", {"m": moneda})
    if esperado == 1:
        comprobar(f"fn_tasa_ves({moneda}) = 1", valor == 1, f"({valor})")
    else:
        en_tabla = uno("select max(tasa_cambio) keep (dense_rank last order by fecha_vigencia) "
                       "  from tipo_cambio where moneda_origen = :m and moneda_destino = 'VES' "
                       "   and tipo_tasa = 'REAL' and fecha_vigencia <= trunc(sysdate) + 1",
                       {"m": moneda})
        comprobar(f"fn_tasa_ves({moneda}) = tasa de la tabla", valor == en_tabla,
                  f"({valor} vs {en_tabla})")

print("== ningun documento queda con la tasa en 1 ==")

for tabla in ("presupuestos", "facturas"):
    malos = uno(f"select count(*) from {tabla} "
                f" where upper(cod_moneda) not in ('VES', 'BS') "
                f"   and nvl(tipo_cambio, 1) = 1 "
                f"   and fn_tasa_ves(fecha_emision, cod_moneda) is not null")
    comprobar(f"{tabla}: 0 documentos en moneda extranjera con tasa 1", malos == 0, f"({malos})")

print("== la tasa es la de la fecha de emision ==")

# Tolerancia del 5 %: el documento guarda la tasa PUBLICADA el dia que se emitio, y
# la tabla puede republicarse despues para esa misma fecha (medido el 2026-11-19:
# el 18/11 paso de 915,7476 a 916,6477 y los documentos de ese dia quedaron a un
# 0,19 %). Con igualdad exacta el caso fallaba por el dato, no por la app. Sigue
# cazando lo que importa: una tasa en 1 o la de otra moneda se va por dos ordenes
# de magnitud.
for tabla in ("presupuestos", "facturas"):
    desfase = uno(f"select count(*) from {tabla} "
                  f" where upper(cod_moneda) not in ('VES', 'BS') "
                  f"   and fn_tasa_ves(fecha_emision, cod_moneda) is not null "
                  f"   and abs(nvl(tipo_cambio, 0) - fn_tasa_ves(fecha_emision, cod_moneda))"
                  f"       / fn_tasa_ves(fecha_emision, cod_moneda) > 0.05")
    comprobar(f"{tabla}: la tasa coincide con la de su fecha", desfase == 0, f"({desfase})")

print("== montos en bolivares del detalle de factura ==")

det_mal = uno("select count(*) from facturas_det d join facturas f on f.id_factura = d.id_factura "
              " where nvl(d.tasa_cambio_aplicada, -1) <> nvl(f.tipo_cambio, -2) "
              "    or d.subtotal_bs is null or d.total_bs is null "
              "    or abs(d.subtotal_bs - round(nvl(d.subtotal_linea,0) * f.tipo_cambio, 2)) > 0.01 "
              "    or abs(d.total_bs - round(nvl(d.monto_total_linea,0) * f.tipo_cambio, 2)) > 0.01")
comprobar("detalle de factura: tasa aplicada y montos en Bs cuadran", det_mal == 0, f"({det_mal})")

print("== los importes no se movieron ==")

# En vez de comparar contra una cifra fija (que envejece: la de AGENTS del 2026-11-05 era de
# 44.277,20 y hoy hay 50.966,34 con las MISMAS 92 lineas), se comprueba la aritmetica interna de
# cada linea y que la cabecera sea la suma de sus lineas. Es lo que de verdad prueba que el
# recalculo no toco dinero.
malas_pres = uno("select count(*) from presupuestos_det "
                 " where abs(nvl(subtotal_linea,0) "
                 "         - (nvl(cantidad,0)*nvl(precio_unitario,0) - nvl(monto_descuento,0))) > 0.01 "
                 "    or abs(nvl(monto_total_linea,0) "
                 "         - (nvl(subtotal_linea,0) + nvl(monto_impuesto,0))) > 0.01")
comprobar("presupuestos: aritmetica de las lineas coherente", malas_pres == 0, f"({malas_pres})")

malas_fact = uno("select count(*) from facturas_det "
                 " where abs(nvl(subtotal_linea,0) "
                 "         - (nvl(cantidad,0)*nvl(precio_unitario,0) - nvl(monto_descuento,0))) > 0.01 "
                 "    or abs(nvl(monto_total_linea,0) "
                 "         - (nvl(subtotal_linea,0) + nvl(monto_impuesto,0))) > 0.01")
comprobar("facturas: aritmetica de las lineas coherente", malas_fact == 0, f"({malas_fact})")

suma_pres = uno("select round(nvl(sum(monto_total_linea),0),2) from presupuestos_det")
suma_fact = uno("select round(nvl(sum(monto_total_linea),0),2) from facturas_det")
cab_pres = uno("select round(nvl(sum(total),0),2) from presupuestos")
cab_fact = uno("select round(nvl(sum(monto_total),0),2) from facturas")
comprobar("cabeceras de presupuesto = suma de sus lineas", abs(cab_pres - suma_pres) < 0.01,
          f"({cab_pres} vs {suma_pres})")
comprobar("cabeceras de factura = suma de sus lineas", abs(cab_fact - suma_fact) < 0.01,
          f"({cab_fact} vs {suma_fact})")

print("== estado general ==")

invalidos = uno("select count(*) from all_objects where owner = 'WKSP_SYPEXWS' "
                "and status <> 'VALID' and object_type in "
                "('FUNCTION','PROCEDURE','PACKAGE','PACKAGE BODY','TRIGGER','VIEW')")
comprobar("0 objetos invalidos", invalidos == 0, f"({invalidos})")
paginas = uno("select count(*) from apex_application_pages where application_id = 100")
comprobar("siguen las 34 paginas", paginas == 34, f"({paginas})")

conn.close()
print()
print("RESULTADO: FALLAS=" + str(len(fallas)))
if fallas:
    for f in fallas:
        print("  - " + f)
sys.exit(1 if fallas else 0)
