#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Excel de «Costos de inventario» (pagina 45 -> 49), descarga real en el navegador (2026-11-25).

  X1 «Excel costo de ventas» descarga un .xls con membrete, columnas y la fila TOTALES
  X2 los totales del archivo cuadran con la base (costo de ventas del periodo en Bs)
  X3 «Excel inventario valorado» descarga el valorado al corte con su fila TOTALES
  X4 un rol sin acceso (FACTURACION) no puede abrir la descarga (-20003)

Usa la empresa con mas movimientos de kardex y un usuario temporal ADMIN.

    python deploy/diagnostico/20261125_costos_excel_navegador.py
"""
import importlib.util
import os
import re
import shutil
import sys
import tempfile
import time

AQUI = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("aud", os.path.join(AQUI, "20261125_auditoria_estandar.py"))
aud = importlib.util.module_from_spec(spec)
spec.loader.exec_module(aud)

fallas = []
DESC = os.path.join(tempfile.gettempdir(), "opencode", "descargas-costos")
shutil.rmtree(DESC, ignore_errors=True)
os.makedirs(DESC, exist_ok=True)


def ok(nombre, cond, det=""):
    print(("  OK   " if cond else "  FALLA") + " " + nombre + ("" if cond else "  -> " + str(det)[:220]))
    if not cond:
        fallas.append(nombre)


c = aud.credenciales()
con = aud.oracledb.connect(user=c["DB_USER"], password=c["DB_PASSWORD"], dsn=aud.CS)
cur = con.cursor()
cur.execute("alter session set current_schema = WKSP_SYPEXWS")
cur.execute("select id_empresa from kardex_mov group by id_empresa order by count(*) desc fetch first 1 rows only")
EMP = cur.fetchone()[0]
cur.execute("""select nvl(sum(-pkg_inventario.fn_signo(tipo_movimiento) * costo_total_bs), 0) from kardex_mov
                where id_empresa = :e and tipo_movimiento in ('SALIDA_FACTURA','SALIDA_ND_CLIENTE','ENTRADA_NC_CLIENTE')
                  and fecha_movimiento >= date '2026-11-01' and fecha_movimiento < trunc(sysdate) + 1""", e=EMP)
ESPERADO = round(float(cur.fetchone()[0]), 2)

BORRA = ("begin delete from usuario_empresa where usuario_id in (select usuario_id from usuario "
         "where upper(username)=upper(:u)); commit; delete from usuario where "
         "upper(username)=upper(:u); commit; end;")


def usuario(u, rol):
    cur.execute(BORRA, u=u)
    cur.execute("""insert into usuario (username,email,password_hash,estado,id_empresa,rol_id,
                                         debe_cambiar_clave,reintentos_fallidos)
                   values (:u,:e,sypex_hash_password(:p),'ACTIVO',:emp,
                           (select id_rol from syn_roles where codigo_rol=:r),'N',0)""",
                u=u, e=u + "@synpex.local", p=aud.CLAVE, emp=EMP, r=rol)
    con.commit()


usuario("diag.costx", "ADMIN")
usuario("diag.costf", "FACTURACION")


def espera_archivo(prefijo, seg=40):
    fin = time.time() + seg
    while time.time() < fin:
        for f in os.listdir(DESC):
            if f.startswith(prefijo) and f.endswith(".xls"):
                time.sleep(1)
                return os.path.join(DESC, f)
        time.sleep(0.5)
    return None


def totales(ruta):
    h = open(ruta, encoding="utf-8", errors="replace").read()
    i = h.find("TOTALES")
    celdas = re.findall(r">([^<]*)</td>", h[i:i + 1500]) if i >= 0 else []
    return h, [x for x in celdas if x.strip()]


nav = aud.Nav(puerto=9309)
try:
    aud.USUARIO = "diag.costx"
    ses = aud.entrar(nav)
    if not ses:
        sys.exit("login fallido")
    nav.cmd("Browser.setDownloadBehavior", behavior="allow", downloadPath=DESC)
    nav.js('window.location.href="%s/f?p=100:45:%s"' % (aud.BASE, ses))
    nav.esperar('!!document.getElementById("P45_DESDE")', 40)
    time.sleep(2)
    nav.js('apex.item("P45_DESDE").setValue("01/11/2026");')
    nav.js('document.getElementById("B43000000000002290").click()')
    ruta = espera_archivo("costo-ventas-")
    if ruta:
        h, tot = totales(ruta)
        ok("X1 Excel costo de ventas con membrete y TOTALES",
           "Costo de ventas del periodo" in h and "RIF:" in h and len(tot) >= 3, tot[:6])
        # tras TOTALES: unidades | costo Bs | costo USD | costo moneda doc (la celda vacia se descarta)
        costo = float(tot[1]) if len(tot) > 1 else -1
        ok("X2 el costo en Bs cuadra con la base (%.2f)" % ESPERADO, abs(costo - ESPERADO) < 0.02, tot[:6])
    else:
        ok("X1 Excel costo de ventas con membrete y TOTALES", False, os.listdir(DESC))
        ok("X2 el costo en Bs cuadra con la base", False, "sin archivo")

    nav.js('window.location.href="%s/f?p=100:45:%s"' % (aud.BASE, ses))
    nav.esperar('!!document.getElementById("P45_DESDE")', 40)
    time.sleep(2)
    nav.js('document.getElementById("B43000000000002291").click()')
    ruta = espera_archivo("inventario-valorado-")
    if ruta:
        h, tot = totales(ruta)
        ok("X3 Excel inventario valorado con TOTALES", "Inventario valorado al corte" in h and len(tot) >= 3, tot[:6])
    else:
        ok("X3 Excel inventario valorado con TOTALES", False, os.listdir(DESC))
    nav.cerrar()

    # X4: un rol sin acceso
    nav = aud.Nav(puerto=9310)
    aud.USUARIO = "diag.costf"
    ses2 = aud.entrar(nav)
    # sin REQUEST en la URL: con argumentos sin checksum APEX bloquea antes (proteccion C)
    nav.js('window.location.href="%s/f?p=100:49:%s"' % (aud.BASE, ses2))
    nav.esperar('document.readyState === "complete"', 30)
    time.sleep(2)
    tx = str(nav.js("document.body.innerText") or "")
    ok("X4 FACTURACION no puede descargar", "No tiene permisos" in tx, tx[:150])
finally:
    nav.cerrar()
    cur.execute(BORRA, u="diag.costx")
    cur.execute(BORRA, u="diag.costf")
    con.close()

print("\nRESULTADO: FALLAS=%d" % len(fallas))
for f in fallas:
    print("  - " + f)
sys.exit(1 if fallas else 0)
