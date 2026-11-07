"""Impreso del presupuesto: los totales van en la moneda del documento (2026-11-07).

Lo que estaba mal: el rotulo era `TOTAL USD` siempre, con el importe en la
moneda DEL DOCUMENTO, y el "total local" se calculaba como `total * tipo_cambio`
(que da bolivares) aunque el local fuera MXN. Con el presupuesto 1206 de Empresa
Mexico (MXN) salia:

    TOTAL USD: $417.60        (son 417,60 MXN)
    TOTAL MXN: MXN $1,085.76  (son Bs 1.085,76)

Ahora: total principal en la moneda del documento, `TOTAL USD` con el
equivalente y `TOTAL <local>` solo cuando el local no es la moneda del
documento. Los factores salen de fn_tasa_ves (bolivares por unidad).

Uso:  python deploy/diagnostico/20261107_imprimir_presupuesto.py
Sale con codigo 1 si algo falla.
"""

import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(REPO, "deploy", "conexion"))

import oracledb
from importar_export import CONNECT_STRING, credenciales

ETIQUETA = {"VES": "TOTAL BS", "MXN": "TOTAL MXN", "USD": "TOTAL USD"}
SIMBOLO = {"VES": "Bs.", "MXN": "MXN $", "USD": "$"}

fallas = 0


def comprueba(ok, texto, detalle=""):
    global fallas
    print(f"  [{'OK   ' if ok else 'FALLA'}] {texto}" + (f" ({detalle})" if detalle else ""))
    if not ok:
        fallas += 1


def num(valor):
    """Mismo formato que fn_num(..., 'FM999,999,990.00')."""
    return f"{valor:,.2f}"


def totales(html):
    """Devuelve {etiqueta: valor} de las filas del bloque de totales."""
    salida = {}
    patron = re.compile(
        r"<strong>(TOTAL [A-Z]+):</strong>\s*</td>\s*<td[^>]*>\s*<strong>[^0-9]*([0-9][0-9,\.]*)",
        re.S)
    for m in patron.finditer(html):
        salida[m.group(1)] = m.group(2)
    return salida


def main():
    datos = credenciales()
    con = oracledb.connect(user=datos["DB_USER"], password=datos["DB_PASSWORD"], dsn=CONNECT_STRING)
    cur = con.cursor()
    cur.execute("alter session set current_schema = WKSP_SYPEXWS")

    # Un presupuesto por moneda, con su moneda local
    cur.execute("""select cod_moneda, min(id_presupuesto), count(*)
                     from presupuestos group by cod_moneda order by 1""")
    por_moneda = {r[0]: r[1] for r in cur.fetchall()}
    print("Presupuestos por moneda:", por_moneda)

    # El 1206 es el del PDF del dueno (Empresa Mexico, documento y moneda local
    # en MXN): el caso que estaba mal. Se prueba aparte porque el "min por
    # moneda" cae en una empresa de Venezuela.
    cur.execute("select count(*) from presupuestos where id_presupuesto = 1206")
    if cur.fetchone()[0]:
        por_moneda["MXN (empresa MX, 1206)"] = 1206

    for moneda, pid in sorted(por_moneda.items()):
        print(f"\n== presupuesto {pid} ({moneda}) ==")
        cur.execute("""select p.cod_moneda, p.tipo_cambio, p.fecha_emision, nvl(p.total, 0),
                              nvl(pa.moneda_local, 'USD')
                         from presupuestos p
                         join empresas e on e.id_empresa = p.id_empresa
                         left join paises pa on pa.cod_pais = e.cod_pais
                        where p.id_presupuesto = :1""", [pid])
        moneda_doc, tasa, fecha, total, local = cur.fetchone()
        cur.execute("select fn_tasa_ves(:f, :m), fn_tasa_ves(:f, 'USD') from dual",
                    {"f": fecha, "m": local})
        tasa_local, tasa_usd = cur.fetchone()

        # La misma regla que el package: bolivares por unidad
        factor_usd = 1 if moneda_doc == "USD" else (tasa or 1) / (tasa_usd or 1)
        factor_local = 1 if moneda_doc == local else (tasa or 1) / (tasa_local or 1)
        esperado_usd = round(total * factor_usd, 2)
        esperado_local = round(total * factor_local, 2)

        html = cur.execute("select pkg_reportes_presupuesto.fn_imprimir_presupuesto(:1) from dual",
                           [pid]).fetchone()[0].read()
        t = totales(html)

        etiqueta_doc = ETIQUETA.get(moneda_doc, "TOTAL " + moneda_doc)
        comprueba(etiqueta_doc in t, f"total en la moneda del documento ({etiqueta_doc})", str(t))
        if etiqueta_doc in t:
            comprueba(t[etiqueta_doc] == num(total),
                      f"{etiqueta_doc} = {num(total)}", t[etiqueta_doc])

        if moneda_doc != "USD":
            comprueba("TOTAL USD" in t, "hay equivalente en USD")
            if "TOTAL USD" in t:
                comprueba(t["TOTAL USD"] == num(esperado_usd),
                          f"TOTAL USD = {num(esperado_usd)}", t["TOTAL USD"])

        etiqueta_local = ETIQUETA.get(local, "TOTAL " + local)
        if moneda_doc != local:
            comprueba(etiqueta_local in t, f"hay total en la moneda local ({etiqueta_local})")
            if etiqueta_local in t:
                comprueba(t[etiqueta_local] == num(esperado_local),
                          f"{etiqueta_local} = {num(esperado_local)}", t[etiqueta_local])
        else:
            comprueba(etiqueta_local not in t or etiqueta_local == etiqueta_doc,
                      f"no se repite el total local cuando es la moneda del documento ({local})")

        # El error viejo: local = total * tipo_cambio
        viejo = num(total * (tasa or 1))
        if local != "VES" and viejo != num(esperado_local):
            for etiqueta, valor in t.items():
                if etiqueta.startswith("TOTAL ") and etiqueta not in (etiqueta_doc, "TOTAL USD"):
                    comprueba(valor != viejo,
                              f"{etiqueta} no es el total x tipo_cambio ({viejo})", valor)

    print(f"\nRESULTADO: FALLAS={fallas}")
    con.close()
    sys.exit(1 if fallas else 0)


if __name__ == "__main__":
    main()
