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
omitidos = []


def comprobar(nombre, condicion, detalle=""):
    print(f"  [{'OK   ' if condicion else 'FALLA'}] {nombre} {detalle}".rstrip())
    if not condicion:
        fallas.append(nombre)


def omitir(nombre, motivo):
    """Caso que no se puede juzgar porque depende de un dato que pone el cliente.

    No cuenta como falla (la app no tiene la culpa de una configuracion
    opcional sin rellenar) pero tampoco pasa en silencio: se imprime y se
    resume al final.
    """
    print(f"  [OMITIDO] {nombre} -- {motivo}")
    omitidos.append((nombre, motivo))


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

# La providencia SENIAT, el rango de control y los datos de la imprenta son
# configuracion OPCIONAL que teclea el cliente en la pagina 19. Cuando no estan,
# el documento NO los imprime (es correcto) y la verificacion no puede darlo por
# fallo: se omite el caso, se dice por que y se siguen midiendo las invariantes
# que si dependen del sistema (los campos obligatorios, los controles unicos...).
prov, prov_fecha, desde, hasta, imp_nom, imp_rif = (None,) * 6

fila = cur.execute("select direccion_fiscal, telefono, email, nro_providencia, prov_fecha, "
                   "       control_desde, control_hasta, imprenta_nombre, imprenta_rif "
                   "  from empresa_fiscal where id_empresa = 1").fetchone()
comprobar("empresa 1 tiene fila en empresa_fiscal", fila is not None)
if fila:
    prov, prov_fecha, desde, hasta, imp_nom, imp_rif = fila[3:9]
    comprobar("direccion, telefono y email del emisor",
              all(x is not None for x in fila[0:3]))

    if prov is None or desde is None:
        omitir("providencia y rango de control",
               f"la empresa 1 no los tiene configurados (dato del cliente): "
               f"providencia={prov!r} control={desde!r}..{hasta!r}")
        # Lo que si se puede exigir sin el dato: que no haya mitades huerfanas.
        comprobar("sin providencia no queda fecha de providencia suelta",
                  prov is not None or prov_fecha is None)
        comprobar("sin control desde no queda control hasta suelto",
                  desde is not None or hasta is None)
    else:
        comprobar("providencia y rango de control",
                  all(x is not None for x in (prov, prov_fecha, desde, hasta)),
                  f"({prov} / {desde}..{hasta})")

    if imp_nom is None or imp_rif is None:
        omitir("datos de la imprenta",
               f"la empresa 1 no la tiene completa (dato del cliente): "
               f"nombre={imp_nom!r} rif={imp_rif!r}")
    else:
        comprobar("datos de la imprenta", True)

sin_control = uno("select count(*) from facturas f join empresas e on e.id_empresa = f.id_empresa "
                  " where e.cod_pais = 'VE' and f.tipo_documento = 'FAC' "
                  "   and f.nro_control is null")
comprobar("todas las FAC de Venezuela tienen numero de control", sin_control == 0, f"({sin_control})")

# Las notas (NC/ND) no llevan control propio y las facturas de Mexico usan UUID
# (CFDI), no N° de Control: el control es un dato venezolano de la factura. Los
# NULL se excluyen del group by porque Oracle los agrupa juntos.
rep = uno("select count(*) from (select id_empresa, nro_control from facturas "
          " where tipo_documento = 'FAC' and nro_control is not null "
          " group by id_empresa, nro_control having count(*) > 1)")
comprobar("el numero de control no se repite dentro de la empresa", rep == 0, f"({rep})")

print("== la empresa de Venezuela imprime forma libre ==")

ve = uno("select min(f.id_factura) from facturas f join empresas e on e.id_empresa = f.id_empresa "
         " where e.cod_pais = 'VE'")
html_ve = imprimir(ve)

for marca in ("fe-emisor", "fe-cliente", "fe-lineas", "fe-totales", "fe-leyenda", "fe-imprenta"):
    comprobar(f"el documento trae «{marca}»", marca in html_ve)
for texto in ("N&ordm; CONTROL", "R.I.F.", "Base imponible", "SIN TACHADURA"):
    comprobar(f"el documento trae «{texto}»", texto in html_ve)

# «Providencia SENIAT» e «Imprenta» solo se imprimen si el cliente los cargo.
if prov is not None:
    comprobar("el documento trae «Providencia SENIAT»", "Providencia SENIAT" in html_ve)
else:
    omitir("el documento trae «Providencia SENIAT»",
           "la empresa 1 no tiene providencia configurada (dato del cliente)")
    comprobar("sin providencia el documento no imprime el bloque vacio",
              "Providencia SENIAT" not in html_ve)

if imp_nom is not None:
    comprobar("el documento trae «Imprenta»", "Imprenta" in html_ve)
else:
    omitir("el documento trae «Imprenta»",
           "la empresa 1 no tiene nombre de imprenta (dato del cliente)")

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
comprobar("siguen las 36 paginas", paginas == 36, f"({paginas})")

conn.close()
print()
print("RESULTADO: FALLAS=" + str(len(fallas)) + " OMITIDOS=" + str(len(omitidos)))
for f in fallas:
    print("  - " + f)
if omitidos:
    print("  Casos omitidos (no son fallas: dependen de datos del cliente):")
    for nombre, motivo in omitidos:
        print("   * " + nombre + ": " + motivo)
sys.exit(1 if fallas else 0)
