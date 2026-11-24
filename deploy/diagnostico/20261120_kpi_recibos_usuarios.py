#!/usr/bin/env python3
"""
Indicadores de Recibos (24) y de Usuarios (3): 2026-11-20.

Comprueba, contra la app importada:
  K1  las dos regiones son contenido dinamico PL/SQL y estan donde toca
      (la de la 24 encima de la lista, la de la 3 encima de las pestanas)
  K2  los cuatro numeros de la 24 salen de RECIBOS y de la empresa activa:
      la consulta guardada, ejecutada, da lo mismo que el SQL de la base
  K3  sin recibos en la empresa (la 2) la fila pinta guiones, no ceros
  K4  los cuatro numeros de la 3 son el mismo alcance que la lista de usuarios
      (los que comparten empresa con el administrador mas los que no tienen)
  K5  las insignias: ESTADO se muestra EMITIDO/ANULADO con su clase, el
      conciliado es un chip y la clase de cada estado esta en el CSS
  K6  estado general: 0 invalidos y las 37 paginas

Uso:  python deploy/diagnostico/20261120_kpi_recibos_usuarios.py
Sale con codigo 1 si algo falla.
"""
import io
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(RAIZ, "deploy", "conexion"))
import oracledb  # noqa: E402
from verificar_conexion import CONNECT_STRING as CS, credenciales  # noqa: E402

REGION_RECIBOS = 43000000000001440
REGION_USUARIOS = 43000000000001441

fallas = []


def comprobar(nombre, condicion, detalle=""):
    print(("  OK  " if condicion else "  MAL ") + nombre + (" " + str(detalle) if detalle else ""))
    if not condicion:
        fallas.append(nombre)


conn = oracledb.connect(user=credenciales()["DB_USER"],
                        password=credenciales()["DB_PASSWORD"], dsn=CS)
cur = conn.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")


def uno(sql, args=None):
    cur.execute(sql, args or {})
    fila = cur.fetchone()
    return fila[0] if fila else None


def texto(valor):
    if valor is None:
        return ""
    return valor.read() if hasattr(valor, "read") else str(valor)


def fuente(region_id):
    return texto(uno("""select to_clob(region_source) from apex_application_page_regions
                         where application_id = 100 and region_id = :r""", {"r": region_id}))


def valores(region_id, empresa, usuario):
    """Ejecuta la region tal como esta guardada y devuelve sus cuatro valores."""
    src = fuente(region_id)
    src = src.replace(":F_EMPRESA_ACTIVA", "'%s'" % empresa).replace(":APP_USER", "'%s'" % usuario)
    cur.execute("begin execute immediate 'drop function tmp_kpi'; exception when others then null; end;")
    cur.execute("create or replace function tmp_kpi return clob is\nbegin\n%s\nend;" % src)
    cur.execute("select tmp_kpi from dual")
    html = texto(cur.fetchone()[0])
    cur.execute("begin execute immediate 'drop function tmp_kpi'; end;")
    return re.findall(r'card-val">([^<]*)<', html), html


print("== K1: las regiones ==")
for region, pagina, nombre, secuencia in (
        (REGION_RECIBOS, 24, "Indicadores de recibos", 15),
        (REGION_USUARIOS, 3, "Indicadores de usuarios", 2)):
    fila = cur.execute("""select page_id, region_name, source_type_plugin_static_id,
                                 function_body_language, display_sequence
                            from apex_application_page_regions
                           where application_id = 100 and region_id = :r""", r=region).fetchone()
    comprobar("K1 existe %s en la pagina %d" % (nombre, pagina),
              fila is not None and fila[0] == pagina, fila[1] if fila else "sin region")
    if fila:
        comprobar("K1 %s es contenido dinamico PL/SQL" % nombre,
                  fila[2] == "NATIVE_DYNAMIC_CONTENT" and fila[3] == "PLSQL", (fila[2], fila[3]))
        comprobar("K1 %s va en la secuencia %d" % (nombre, secuencia), fila[4] == secuencia, fila[4])

# La de la 24 va encima de la lista; la de la 3, encima del selector de pestanas.
sec_lista = uno("""select display_sequence from apex_application_page_regions
                    where application_id = 100 and page_id = 24 and region_static_id = 'lista-cobros'""")
comprobar("K1 la fila de la 24 esta encima de la lista", sec_lista is not None and 15 < sec_lista, sec_lista)
sec_pest = uno("""select display_sequence from apex_application_page_regions
                   where application_id = 100 and page_id = 3 and region_static_id = 'usuarios-selector'""")
comprobar("K1 la fila de la 3 esta encima de las pestanas", sec_pest is not None and 2 < sec_pest, sec_pest)

print("== K2: los numeros de Recibos (empresa 1) ==")
vals, html = valores(REGION_RECIBOS, 1, "admin")
cur.execute("""select count(*), nvl(sum(nvl(monto_bs, monto_cobrado * nvl(tipo_cambio, 1))), 0),
                      nvl(sum(nvl(igtf_bs, 0)), 0),
                      count(case when conciliado = 'N' then 1 end)
                 from recibos
                where id_empresa = 1 and estado = 'ACTIVO'
                  and trunc(fecha_cobro, 'MM') = trunc(sysdate, 'MM')""")
n, bs, igtf, sinc = cur.fetchone()


def numero(valor):
    """'1.008,31' -> 1008.31.

    2026-11-23: la app pinta el formato venezolano (miles con punto, decimales
    con coma). Antes el par NLS de los indicadores estaba al reves y salia
    '1,008.31'; el test se habia escrito contra ese formato, que era el fallo.
    """
    limpio = (valor or "0").replace("&#8212;", "0").replace("—", "0").strip()
    if not limpio:
        return 0.0
    return float(limpio.replace(".", "").replace(",", "."))
comprobar("K2 «Recibos del mes» es el conteo del mes", vals[0] == str(n), (vals[0], n))
comprobar("K2 «Cobrado (Bs)» es la suma de MONTO_BS",
          abs(numero(vals[1]) - float(bs)) < 0.005, (vals[1], bs))
comprobar("K2 «IGTF (Bs)» es la suma de IGTF_BS",
          abs(numero(vals[2]) - float(igtf)) < 0.005, (vals[2], igtf))
comprobar("K2 «Sin conciliar» cuenta los EMITIDO sin conciliar", vals[3] == str(sinc), (vals[3], sinc))
comprobar("K2 el HTML trae las cuatro tarjetas", html.count('<div class="spx-card-lbl">') == 4,
          html.count('<div class="spx-card-lbl">'))

print("== K3: sin recibos la fila no miente ==")
vals2, _ = valores(REGION_RECIBOS, 2, "admin.mx")
comprobar("K3 la empresa 2 no tiene recibos y pinta guiones",
          all(v == "&#8212;" for v in vals2), vals2)

print("== K4: los numeros de Usuarios ==")
for usuario in ("admin", "admin.mx"):
    vals, _ = valores(REGION_USUARIOS, 1, usuario)
    cur.execute("""select count(*),
                          count(case when upper(nvl(u.estado, '#')) in ('ACTIVO', 'A', '1')
                                      and nvl(u.bloqueado_hasta, sysdate - 1) <= sysdate then 1 end),
                          count(case when u.bloqueado_hasta > sysdate then 1 end),
                          count(case when upper(nvl(u.estado, '#')) = 'PENDIENTE' then 1 end)
                     from usuario u
                    where exists (select 1
                                    from usuario_empresa ue
                                    join usuario_empresa mia on mia.id_empresa = ue.id_empresa
                                    join usuario a on a.usuario_id = mia.usuario_id
                                   where ue.usuario_id = u.usuario_id
                                     and upper(a.username) = upper(:u))
                       or not exists (select 1 from usuario_empresa x where x.usuario_id = u.usuario_id)""",
                {"u": usuario})
    esperado = [str(x) for x in cur.fetchone()]
    comprobar("K4 %s ve sus cuatro numeros" % usuario, vals == esperado, (vals, esperado))
    # Y el alcance es el de la lista: el mismo conteo que devuelve el IR.
    lista = uno("""select to_clob(region_source) from apex_application_page_regions
                    where application_id = 100 and page_id = 3 and region_name like 'Gesti%'""")
    cur.execute("select count(*) from (%s)" % texto(lista), {"APP_USER": usuario})
    comprobar("K4 %s: «Usuarios» es el mismo alcance que la lista" % usuario,
              int(vals[0]) == cur.fetchone()[0], (vals[0],))

print("== K5: insignias y chips ==")
fuente24 = " ".join(fuente(REGION_RECIBOS).lower().split())
lista24 = " ".join(texto(uno("""select to_clob(region_source) from apex_application_page_regions
                                  where application_id = 100 and page_id = 24
                                    and region_static_id = 'lista-cobros'""")).lower().split())
html_estado = texto(uno("""select html_expression from apex_application_page_ir_col
                             where application_id = 100 and page_id = 24 and column_alias = 'ESTADO'"""))
html_conc = texto(uno("""select html_expression from apex_application_page_ir_col
                           where application_id = 100 and page_id = 24 and column_alias = 'CONCILIADO'"""))
comprobar("K5 la lista muestra EMITIDO (el estado de la base es ACTIVO)",
          "then 'emitido'" in lista24 and "as estado" in lista24)
comprobar("K5 la columna Estado usa el badge", "status-#estado#" in html_estado.lower(), html_estado[:60])
comprobar("K5 la columna Conciliado es un chip", "spx-chip" in html_conc.lower(), html_conc[:60])

css24 = " ".join(texto(uno("""select to_clob(inline_css) from apex_application_pages
                               where application_id = 100 and page_id = 24""")).split())
for clase in (".status-EMITIDO", ".status-ANULADO", ".spx-chip--Si", ".spx-chip--No", ".spx-kpis", ".spx-card"):
    comprobar("K5 el CSS de la 24 define %s" % clase, clase in css24)

css3 = " ".join(texto(uno("""select to_clob(inline_css) from apex_application_pages
                              where application_id = 100 and page_id = 3""")).split())
for clase in (".status-ACTIVO", ".status-INACTIVO", ".status-PENDIENTE", ".status-BLOQUEADO",
              ".status-badge[data-spx", ".spx-kpis", ".spx-card"):
    comprobar("K5 el CSS de la 3 define %s" % clase, clase in css3)
html_sit = texto(uno("""select html_expression from apex_application_page_ir_col
                         where application_id = 100 and page_id = 3 and column_alias = 'SITUACION'"""))
comprobar("K5 la columna Situacion sigue emitiendo status-<clase> y lleva data-spx",
          "status-#situacion_clase#" in html_sit.lower() and "data-spx" in html_sit.lower(), html_sit[:80])

print("== K5b: el chip Conciliado dice «Si» con tilde, en el HTML servido ==")
# El rotulo lleva tilde; la CLASE del chip y el filtro siguen en ASCII (Si/No, SI/NO),
# porque el filtro compara contra S/N en la base.
lov = uno("""select lov_definition from apex_application_page_items
              where application_id = 100 and page_id = 24 and item_name = 'P24_CONCILIADO'""") or ""
comprobar("K5b el filtro ofrece «Si» con tilde", "Sí;SI" in lov, lov)
comprobar("K5b el filtro sigue comparando contra SI/NO", "SI,No;NO" in lov, lov)
comprobar("K5b la columna toma la clase de CONCILIADO_CLASE",
          "spx-chip--#conciliado_clase#" in html_conc.lower(), html_conc[:80])
comprobar("K5b CONCILIADO_CLASE esta declarada y oculta",
          uno("""select count(*) from apex_application_page_ir_col
                  where application_id = 100 and page_id = 24
                    and column_alias = 'CONCILIADO_CLASE'
                    and display_text_as = 'HIDDEN_ESCAPE_SC'""") == 1)

# HTML de verdad: login programatico con un usuario temporal y la pagina 24 servida.
from abrir_pagina import entrar, BASE as BASE_HTTP  # noqa: E402

USUARIO, CLAVE = "diag.chip24", "Diag#2026"
cur.execute("""begin delete from usuario_empresa where usuario_id in
                 (select usuario_id from usuario where upper(username) = upper(:u)); commit;
               delete from usuario where upper(username) = upper(:u); commit; end;""", u=USUARIO)
cur.execute("""insert into usuario (username, email, password_hash, estado, id_empresa, rol_id,
                                    debe_cambiar_clave, reintentos_fallidos)
               values (:u, :e, sypex_hash_password(:p), 'ACTIVO', 1,
                       (select id_rol from syn_roles where codigo_rol = 'ADMIN'), 'N', 0)""",
            u=USUARIO, e=USUARIO + "@synpex.local", p=CLAVE)
conn.commit()
recibo, conc_previo = None, "N"
try:
    opener, sesion = entrar(USUARIO, CLAVE)

    # Para que el chip «Si» exista de verdad en el HTML se marca un recibo como
    # conciliado (el mas reciente, para que salga en la primera pagina) y se
    # restaura en el finally. Sin esto la comprobacion quedaria a merced de que
    # el cliente tenga un recibo conciliado ese dia.
    recibo, conc_previo = cur.execute("""select id_recibo, nvl(conciliado, 'N') from (
                                            select id_recibo, conciliado from recibos
                                             where id_empresa = 1 and estado = 'ACTIVO'
                                             order by fecha_cobro desc, id_recibo desc)
                                          where rownum = 1""").fetchone()
    cur.execute("update recibos set conciliado = 'S' where id_recibo = :r", r=recibo)
    conn.commit()

    html_pagina = opener.open("%s/f?p=100:24:%s" % (BASE_HTTP, sesion), timeout=90)\
                        .read().decode("utf-8", "replace")
    comprobar("K5b la pagina 24 se sirve", "P24_CONCILIADO" in html_pagina, len(html_pagina))
    comprobar("K5b el HTML no muestra el rotulo viejo «Si» sin tilde",
              '">Si</span>' not in html_pagina)
    comprobar("K5b el HTML muestra «Si» con tilde y la clase del chip",
              'spx-chip--Si">Sí</span>' in html_pagina, recibo)
    comprobar("K5b el filtro se pinta con la opcion acentuada",
              "Sí</option>" in html_pagina, html_pagina.count("Sí</option>"))
finally:
    if recibo is not None:
        cur.execute("update recibos set conciliado = :c where id_recibo = :r",
                    c=conc_previo, r=recibo)
        conn.commit()
    cur.execute("""begin delete from usuario_empresa where usuario_id in
                     (select usuario_id from usuario where upper(username) = upper(:u)); commit;
                   delete from usuario where upper(username) = upper(:u); commit; end;""", u=USUARIO)
    conn.commit()

print("== K6: estado general ==")
comprobar("K6 cero objetos invalidos",
          uno("""select count(*) from all_objects where owner = 'WKSP_SYPEXWS'
                  and status <> 'VALID' and object_type in
                  ('FUNCTION','PROCEDURE','PACKAGE','PACKAGE BODY','TRIGGER','VIEW')""") == 0)
comprobar("K6 siguen las 43 paginas",
          uno("select count(*) from apex_application_pages where application_id = 100") == 43)

conn.close()
print()
print("RESULTADO: FALLAS=" + str(len(fallas)))
for f in fallas:
    print("  - " + f)
sys.exit(1 if fallas else 0)
