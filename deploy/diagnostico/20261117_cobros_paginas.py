#!/usr/bin/env python3
"""
Pantallas de cobros (2026-11-17): pagina 24 (lista) y 25 (dialogo).

  P1  existen las paginas 24 «Cobros» y 25 «Cobro», con su alias y proteccion 'C'
  P2  la 24 tiene la region de filtros, la lista y el boton de registrar
  P3  la lista lee RECIBOS, filtra por las empresas del usuario y por los filtros
  P4  la 25 es modal, tiene los items del cobro y llama a pkg_cobros al guardar
  P5  la 25 tiene los procesos de anular y conciliar, y el cierre condicionado
  P6  las dos tienen guarda de rol
  P7  hay accion dinamica por cada item que recalcula (factura, monto, moneda)
  P8  el menu trae «Cobros» apuntando a la 24

Uso:  python deploy/diagnostico/20261117_cobros_paginas.py
Sale 1 si algo falla.
"""
import io
import os
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(RAIZ, "deploy", "conexion"))
import oracledb  # noqa: E402
from verificar_conexion import CONNECT_STRING as CS, credenciales  # noqa: E402

fallas = []


def comprobar(nombre, condicion, detalle=""):
    print(("  OK  " if condicion else "  MAL ") + nombre + (" " + str(detalle) if detalle else ""))
    if not condicion:
        fallas.append(nombre)


conn = oracledb.connect(user=credenciales()["DB_USER"],
                        password=credenciales()["DB_PASSWORD"], dsn=CS)
cur = conn.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")

# P1
for pagina, nombre, alias in ((24, "Cobros", "COBROS"), (25, "Cobro", "COBRO")):
    fila = cur.execute("""select page_name, page_alias, page_mode, page_access_protection
                            from apex_application_pages
                           where application_id = 100 and page_id = :p""", p=pagina).fetchone()
    comprobar("P1 existe la pagina %d (%s)" % (pagina, nombre), fila is not None)
    if fila:
        comprobar("P1 la %d se llama %s" % (pagina, nombre), fila[0] == nombre, f"({fila[0]})")
        comprobar("P1 la %d tiene alias %s" % (pagina, alias), fila[1] == alias, f"({fila[1]})")
        comprobar("P1 la %d pide checksum" % pagina, fila[3] == "Arguments Must Have Checksum", f"({fila[3]})")
        if pagina == 25:
            comprobar("P1 la 25 es modal", fila[2] == "Modal Dialog", f"({fila[2]})")

# P2
regiones24 = cur.execute("""select region_name, source_type_plugin_static_id
                              from apex_application_page_regions
                             where application_id = 100 and page_id = 24""").fetchall()
nombres24 = [r[0] for r in regiones24]
comprobar("P2 la 24 tiene la region de filtros", "Filtros" in nombres24, f"({nombres24})")
comprobar("P2 la 24 tiene la lista de cobros", "Cobros" in nombres24)
comprobar("P2 la lista es un informe SQL",
          any(r[0] == "Cobros" and (r[1] or "") == "NATIVE_SQL_REPORT" for r in regiones24),
          f"({[r[1] for r in regiones24]})")
n = cur.execute("""select count(*) from apex_application_page_buttons
                    where application_id = 100 and page_id = 24 and button_name = 'BTN_NUEVO_COBRO'""").fetchone()[0]
comprobar("P2 el boton Registrar cobro esta", n == 1, f"({n})")

# P3
fila_lista = cur.execute("""select to_clob(region_source) from apex_application_page_regions
                             where application_id = 100 and page_id = 24 and region_name = 'Cobros'""").fetchone()
lista = fila_lista[0] if fila_lista else ""
if hasattr(lista, "read"):
    lista = lista.read()
comprobar("P3 la lista lee RECIBOS", "from recibos" in (lista or "").lower())
comprobar("P3 filtra por las empresas del usuario", "v_empresas_usuario" in lista.lower())
comprobar("P3 respeta los filtros", all(f in lista.upper() for f in ("P24_DESDE", "P24_HASTA", "P24_ESTADO")))
comprobar("P3 la lista tiene el selector para abrir un cobro",
          "P25_ID_RECIBO" in (lista or "") or "id_recibo" in (lista or "").lower())

# P4
items25 = [f[0] for f in cur.execute("""select item_name from apex_application_page_items
                                         where application_id = 100 and page_id = 25""").fetchall()]
for item in ("P25_ID_RECIBO", "P25_ID_FACTURA", "P25_FECHA_COBRO", "P25_ID_FORMA_PAGO",
             "P25_COD_MONEDA", "P25_TIPO_CAMBIO", "P25_MONTO", "P25_APLICA_IGTF",
             "P25_IGTF", "P25_RETENCION", "P25_NRO_COMPROBANTE", "P25_NETO", "P25_REFERENCIA"):
    comprobar("P4 existe %s" % item, item in items25)

procesos = dict(cur.execute("""select process_name, to_clob(process_source)
                                 from apex_application_page_proc
                                where application_id = 100 and page_id = 25""").fetchall())
for nombre, texto in list(procesos.items()):
    if hasattr(texto, "read"):
        procesos[nombre] = texto.read()
guardar = procesos.get("Guardar cobro", "")
comprobar("P4 el guardado llama a pkg_cobros", "prc_registrar_cobro" in guardar)
comprobar("P4 el guardado manda la retencion y el comprobante",
          "p_retencion_iva_bs" in guardar and "p_nro_comprobante" in guardar)

# P5
comprobar("P5 existe el proceso de anular", "prc_anular_cobro" in procesos.get("Anular cobro", ""))
comprobar("P5 existe el proceso de conciliar", "prc_conciliar" in procesos.get("Conciliar cobro", ""))
cerrar = cur.execute("""select process_name from apex_application_page_proc
                         where application_id = 100 and page_id = 25
                           and process_type = 'Close popup window'""").fetchall()
comprobar("P5 existe el cierre de ventana", len(cerrar) == 1 and cerrar[0][0] == "Cerrar cobro", f"({cerrar})")

# La condicion no la expone el diccionario: se vigila en el export, que es lo que se importa.
export = io.open(os.path.join(RAIZ, "pagina_apex", "f100.sql"), encoding="utf-8",
                 errors="replace").read()
i = export.index("p_static_id=>'cerrar-cobro'")
bloque_cierre = export[i:i + 900]
comprobar("P5 el cierre esta condicionado a los botones (no a cualquier submit)",
          "BTN_SALIR_COBRO" in bloque_cierre and "BTN_GUARDAR_COBRO" in bloque_cierre)

# P6
for pagina in (24, 25):
    n = cur.execute("""select count(*) from apex_application_page_proc
                        where application_id = 100 and page_id = :p
                          and lower(process_source) like '%fn_tiene_rol%'""", p=pagina).fetchone()[0]
    comprobar("P6 la pagina %d tiene guarda de rol" % pagina, n >= 1, f"({n})")

# P7
eventos = [f[0] for f in cur.execute("""select when_element from apex_application_page_da
                                          where application_id = 100 and page_id = 25""").fetchall()]
for item in ("P25_ID_FACTURA", "P25_MONTO", "P25_COD_MONEDA"):
    comprobar("P7 hay accion dinamica sobre %s" % item, item in eventos, f"({eventos})")

# P9: la guarda de la 25 no deja entrar a CONSULTA (registra dinero) y los
# botones de escritura estan condicionados al rol.
guarda25 = cur.execute("""select to_clob(process_source) from apex_application_page_proc
                           where application_id = 100 and page_id = 25
                             and lower(process_source) like '%fn_tiene_rol%'""").fetchall()
texto_guardas = ""
for fila in guarda25:
    texto_guardas += (fila[0].read() if hasattr(fila[0], "read") else (fila[0] or ""))
comprobar("P9 la guarda de la 25 no incluye CONSULTA",
          "CONSULTA" not in texto_guardas.upper(), f"({texto_guardas[:60]})")

# La condicion del boton no la expone el diccionario: se vigila en el export.
export = io.open(os.path.join(RAIZ, "pagina_apex", "f100.sql"), encoding="utf-8",
                 errors="replace").read()
for nombre in ("BTN_GUARDAR_COBRO", "BTN_ANULAR_COBRO", "BTN_CONCILIAR"):
    i = export.index("p_button_name=>'%s'" % nombre)
    bloque = export[i:i + 700]
    comprobar("P9 el boton %s exige rol" % nombre, "fn_tiene_rol" in bloque,
              f"({bloque[:0]})")

# P10: el cobro se abre desde el selector de la lista (el enlace de fila de un
# informe clasico no se pinta).
export2 = io.open(os.path.join(RAIZ, 'pagina_apex', 'f100.sql'), encoding='utf-8',
                  errors='replace').read()
comprobar('P10 la lista tiene el selector de cobros',
          'P24_ID_RECIBO' in export2)
comprobar('P10 y el boton de abrir con el id',
          "p_button_redirect_url=>'f?p=&APP_ID.:25:&APP_SESSION.::&DEBUG.:25:P25_ID_RECIBO:&P24_ID_RECIBO.'"
          in export2)

# P11: la lista se puede buscar por texto (referencia, factura, control o RIF).
export3 = io.open(os.path.join(RAIZ, "pagina_apex", "f100.sql"), encoding="utf-8",
                  errors="replace").read()
comprobar("P11 la lista tiene el campo Buscar", "p_name=>'P24_BUSCAR'" in export3)
comprobar("P11 y filtra por referencia, factura, control y RIF",
          all(t in export3 for t in ("nvl(r.referencia", "f.folio_factura", "f.nro_control", "c.rif")))
comprobar("P11 el buscador tambien filtra la lista de «Abrir un cobro»",
          export3.count("nvl(:P24_BUSCAR") == 2, f"({export3.count('nvl(:P24_BUSCAR')})")

# P8
n = cur.execute("""select count(*) from apex_application_list_entries
                    where application_id = 100 and list_name = 'Navigation Menu'
                      and upper(entry_text) = 'COBROS'""").fetchone()[0]
comprobar("P8 el menu trae Cobros", n == 1, f"({n})")

conn.close()
print()
print("RESULTADO: FALLAS=" + str(len(fallas)))
for f in fallas:
    print("  - " + f)
sys.exit(1 if fallas else 0)
