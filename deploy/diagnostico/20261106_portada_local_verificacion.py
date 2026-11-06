#!/usr/bin/env python3
# =============================================================================
# 20261106_portada_local_verificacion.py
#
# Verificacion LOCAL de la portada comercial (pagina 15). No toca la red ni la
# base: compara la fuente de trabajo (libreria/portada/portada_synpex.html) con
# el bloque que va dentro del export (pagina_apex/f100.sql).
#
# Por que existe: mientras la ACL de la instancia este cerrada no se puede
# importar ni pedir la pagina por HTTP, asi que lo unico comprobable es que el
# HTML tenga lo que debe tener y que el bloque del export sea SQL valido.
#
# Las trampas que vigila, todas medidas en este repo:
#   - una comilla simple sin doblar rompe el import entero (PLS-00103)
#   - los acentos se corrompen al pasar el bloque por el export
#   - el bloque termina en '))' (o ')))' si el ultimo elemento es un unistr)
#
# Uso (desde la raiz del repo):
#   python deploy/diagnostico/20261106_portada_local_verificacion.py
#
# Sale con codigo 1 solo si alguna comprobacion falla; con todo bien, 0.
# =============================================================================

import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PORTADA = os.path.join(REPO, "libreria", "portada", "portada_synpex.html")
EXPORT = os.path.join(REPO, "pagina_apex", "f100.sql")

ANCLAS = ("spx-inicio", "spx-servicios", "spx-nosotros", "spx-contacto")
PROHIBIDAS = ("4.280", "579.472", "98,7")
WHATSAPP = "https://wa.me/528111198920"
CORREO = "mailto:luismiromi84@hotmail.com"

fallas = []


def comprobar(nombre, condicion, detalle=""):
    print(f"  [{'OK   ' if condicion else 'FALLA'}] {nombre} {detalle}".rstrip())
    if not condicion:
        fallas.append(nombre)


def leer_portada():
    with open(PORTADA, encoding="utf-8") as f:
        return f.read()


def lineas_esperadas():
    """El HTML de la portada convertido a los literales SQL que debe tener el export.

    Es el mismo doblado que hace la sincronizacion: cada linea entre comillas
    simples, con cada ' interna doblada, coma al final y cierre en '))'.
    """
    with open(PORTADA, encoding="utf-8") as f:
        html = f.read().replace("\r\n", "\n").split("\n")
    while html and html[-1] == "":
        html.pop()
    literales = ["'" + l.replace("'", "''") + "'," for l in html]
    literales[-1] = literales[-1][:-1] + "))"
    return literales


def leer_region():
    """Devuelve solo las lineas del bloque de la region de la pagina 15.

    Se ancla en el marcador 'prompt --application/pages/page_00015' y acota el
    final en 'prompt --application/pages/page_00016': sin ese tope, si la pagina
    15 se quedara sin fuente se leeria la region de otra pagina y el chequeo
    daria un falso OK.
    """
    with open(EXPORT, encoding="utf-8") as f:
        lineas = f.read().splitlines()

    inicio_pagina = None
    for i, linea in enumerate(lineas):
        if "prompt --application/pages/page_00015" in linea:
            inicio_pagina = i
            break
    if inicio_pagina is None:
        fallas.append("no se encontro la pagina 15 en el export")
        return ""

    fin_pagina = len(lineas)
    for i in range(inicio_pagina + 1, len(lineas)):
        if "prompt --application/pages/page_00016" in lineas[i]:
            fin_pagina = i
            break

    inicio = None
    for i in range(inicio_pagina, fin_pagina):
        if ",p_plug_source=>wwv_flow_string.join(wwv_flow_t_varchar2(" in lineas[i]:
            inicio = i + 1
            break
    if inicio is None:
        fallas.append("no se encontro el p_plug_source de la region de la pagina 15")
        return ""

    for i in range(inicio, fin_pagina):
        if lineas[i].lstrip().startswith(",p_attributes=>"):
            return "\n".join(lineas[inicio:i])

    fallas.append("la region de la pagina 15 no cierra con ',p_attributes=>'")
    return "\n".join(lineas[inicio:fin_pagina])


def main():
    if not os.path.exists(PORTADA):
        sys.exit(f"No existe {PORTADA}")
    if not os.path.exists(EXPORT):
        sys.exit(f"No existe {EXPORT}")

    portada = leer_portada()
    region = leer_region()

    print("== portada (libreria/portada/portada_synpex.html) ==")
    comprobar("empieza por el contenedor", 'class="spx-portada"' in portada)
    comprobar("sin JavaScript", "<script" not in portada.lower())
    comprobar("cada ancla del menu tiene su seccion",
              all(f'id="{a}"' in portada for a in ANCLAS))
    comprobar("el menu enlaza a las cuatro anclas",
              all(f'href="#{a}"' in portada for a in ANCLAS))
    comprobar("WhatsApp exacto", WHATSAPP in portada)
    comprobar("correo exacto", CORREO in portada)
    comprobar("Ingresar a la pagina 1", "f?p=&APP_ID.:1:&APP_SESSION." in portada)
    comprobar("Ingresar NO va al login", "f?p=&APP_ID.:9999" not in portada)
    comprobar("sin cifras inventadas", not any(p in portada for p in PROHIBIDAS),
              "" if not any(p in portada for p in PROHIBIDAS)
              else "(" + ", ".join(p for p in PROHIBIDAS if p in portada) + ")")
    comprobar("enlaces externos con noopener",
              portada.count('target="_blank"') ==
              len(re.findall(r'target="_blank"[^>]*rel="noopener"', portada)))
    comprobar("sin manejadores JS en linea",
              "onclick=" not in portada.lower() and "javascript:" not in portada.lower())
    comprobar("respeta reduced-motion", "prefers-reduced-motion" in portada)
    comprobar("tipografia con respaldo de sistema", "system-ui" in portada)
    # El CSS se compara sin espacios alrededor de los dos puntos: el
    # comportamiento es el mismo con "overflow-x: hidden" y "overflow-x:hidden",
    # y el test no debe dictar el formato del archivo.
    css = re.sub(r"\s*:\s*", ":", portada)
    comprobar("sin desbordamiento horizontal", "overflow-x:hidden" in css)
    comprobar("hay media query movil", "@media (max-width:900px)" in css)

    print("\n== region del export (pagina_apex/f100.sql, pagina 15) ==")
    comprobar("la region trae las cuatro anclas",
              all(f'id="{a}"' in region for a in ANCLAS))
    comprobar("la region trae el WhatsApp", WHATSAPP in region)
    comprobar("sin mojibake", "\ufffd" not in region)
    comprobar("acentos intactos en el export", "Información" in region)
    comprobar("cierre del bloque join", region.rstrip().endswith("'))"))
    comprobar("todas las lineas son literales SQL",
              all(l.strip().startswith("'") for l in region.splitlines() if l.strip()))

    # La invariante que de verdad importa: el bloque del export tiene que ser el
    # HTML de libreria/, linea por linea y con las comillas dobladas. Comparar
    # solo marcas sueltas deja pasar que las dos copias se desincronicen (paso
    # el 2026-11-06: se corrigio el HTML y se sincronizo el export sin volver a
    # commitear el HTML).
    esperadas = lineas_esperadas()
    reales = region.splitlines()
    if reales == esperadas:
        comprobar("el export dice exactamente lo mismo que libreria/", True,
                  f"({len(reales)} lineas)")
    else:
        comprobar("el export dice exactamente lo mismo que libreria/", False,
                  f"({len(reales)} vs {len(esperadas)} lineas)")
        for n, (a, b) in enumerate(zip(reales, esperadas), 1):
            if a != b:
                fallas.append(f"linea {n} distinta: export={a.strip()[:60]!r} "
                              f"libreria={b.strip()[:60]!r}")
                break

    # Una comilla simple sin doblar deja la linea con un numero impar de
    # comillas, y el import entero muere con PLS-00103.
    impares = [(n, l) for n, l in enumerate(region.splitlines(), 1) if l.count("'") % 2]
    for n, linea in impares:
        fallas.append(f"comilla impar en la linea {n}: {linea.strip()[:60]}")
    comprobar("sin comillas impares (se doblan)", not impares,
              "" if not impares else f"({len(impares)} linea(s))")

    print(f"\nRESULTADO: FALLAS={len(fallas)}")
    for f in fallas:
        print("  -", f)
    sys.exit(1 if fallas else 0)


if __name__ == "__main__":
    main()
