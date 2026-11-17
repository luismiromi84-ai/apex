#!/usr/bin/env python3
"""
Dos cobros a la vez sobre la misma factura (2026-11-17).

  K1  con dos sesiones reales cobrando el total a la vez, entra una sola: la otra
      recibe -20094 (supera el saldo) y el saldo NO queda negativo
  K2  el saldo final es 0 y la factura queda PAGADA, con un solo recibo activo
  K3  con montos que caben los dos (40 + 40 de 100), entran los dos

Antes del `for update` la segunda sesion veia el mismo saldo y dejaba la factura
en -100 (medido en la revision del 2026-11-17).

Uso:  python deploy/diagnostico/20261117_cobros_concurrencia.py
"""
import os
import sys
import threading
import time

import oracledb

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

REPO = r"C:\Users\luism\OneDrive\Documents\Apex_luis"
sys.path.insert(0, os.path.join(REPO, "deploy", "conexion"))
from verificar_conexion import CONNECT_STRING as CS, credenciales  # noqa: E402

fallas = []


def comprobar(nombre, condicion, detalle=""):
    print(("  OK  " if condicion else "  MAL ") + nombre + (" " + str(detalle) if detalle else ""))
    if not condicion:
        fallas.append(nombre)


def nueva_factura(cur, total):
    cur.execute("""insert into facturas (id_empresa, id_cliente, tipo_documento, folio_factura,
                                         cod_moneda, tipo_cambio, fecha_emision, subtotal,
                                         monto_impuesto, monto_total, estado, creado_por)
                   values (1, (select min(id_cliente) from clientes where id_empresa = 1),
                           'FAC', 'CONC-ZZ-' || to_char(systimestamp, 'HH24MISSFF3'),
                           'VES', 1, sysdate - 1, :t, 0, :t, 'TIMBRADA', 'test')""",
                t=total)
    cur.execute("select max(id_factura) from facturas where folio_factura like 'CONC-ZZ-%'")
    return cur.fetchone()[0]


def cobra(cur, factura, monto):
    salida = cur.var(oracledb.NUMBER)
    cur.execute("""begin
                     pkg_cobros.prc_registrar_cobro(
                        p_id_factura => :f, p_fecha => sysdate, p_id_forma_pago => null,
                        p_cod_moneda => 'VES', p_monto => :m, p_usuario => 'ADMIN',
                        p_id_recibo => :r);
                   end;""", f=factura, m=monto, r=salida)
    valor = salida.getvalue()
    return valor[0] if isinstance(valor, (list, tuple)) else valor


credenciales_dict = credenciales()
con1 = oracledb.connect(user=credenciales_dict["DB_USER"],
                        password=credenciales_dict["DB_PASSWORD"], dsn=CS)
con2 = oracledb.connect(user=credenciales_dict["DB_USER"],
                        password=credenciales_dict["DB_PASSWORD"], dsn=CS)
cur1 = con1.cursor()
cur2 = con2.cursor()
for c in (cur1, cur2):
    c.execute("alter session set current_schema = WKSP_SYPEXWS")

cur1.execute("begin delete from recibos where id_factura in "
             "(select id_factura from facturas where folio_factura like 'CONC-ZZ-%'); "
             "commit; delete from facturas where folio_factura like 'CONC-ZZ-%'; commit; end;")
con1.commit()

try:
    # K1: los dos cobran el total
    fac = nueva_factura(cur1, 100)
    con1.commit()

    cobra(cur1, fac, 100)          # sin commit: deja la fila bloqueada

    resultado = {}

    def segundo_cobro():
        try:
            cobra(cur2, fac, 100)
            resultado['ok'] = True
            con2.commit()
        except oracledb.DatabaseError as ex:
            resultado['codigo'] = int(ex.args[0].code) if ex.args and hasattr(ex.args[0], "code") else 0
            con2.rollback()

    hilo = threading.Thread(target=segundo_cobro)
    hilo.start()
    time.sleep(3)
    comprobar("K1 la segunda sesion se queda esperando el bloqueo", hilo.is_alive(),
              "(no espero: no habia FOR UPDATE)")

    con1.commit()                  # se suelta la factura
    hilo.join(30)
    # Con la factura ya pagada por la primera sesion, la segunda cae en la guarda de
    # estado (-20090). Vale cualquiera de los dos rechazos: lo que no puede es entrar.
    comprobar("K1 la segunda sesion no entra (-20090 o -20094)",
              abs(resultado.get('codigo', 0)) in (20090, 20094), f"({resultado})")

    saldo, estado, recibos = cur1.execute(
        """select fn_saldo_factura(:f), f.estado,
                  (select count(*) from recibos r where r.id_factura = :f and r.estado = 'ACTIVO')
             from facturas f where f.id_factura = :f""", f=fac).fetchone()
    comprobar("K2 el saldo queda en 0", abs(float(saldo)) < 0.01, f"({saldo})")
    comprobar("K2 la factura queda PAGADA", estado == "PAGADA", f"({estado})")
    comprobar("K2 hay un solo recibo activo", recibos == 1, f"({recibos})")

    # K3: dos abonos que caben
    fac = nueva_factura(cur1, 100)
    con1.commit()
    cobra(cur1, fac, 40)
    con1.commit()
    cobra(cur2, fac, 40)
    con2.commit()
    saldo, estado = cur1.execute("select fn_saldo_factura(:f), estado from facturas where id_factura = :f",
                                 f=fac).fetchone()
    comprobar("K3 los dos abonos entran y el saldo es 20", abs(float(saldo) - 20) < 0.01, f"({saldo})")
    comprobar("K3 la factura queda PARCIAL", estado == "PARCIAL", f"({estado})")
finally:
    cur1.execute("begin delete from recibos where id_factura in "
                 "(select id_factura from facturas where folio_factura like 'CONC-ZZ-%'); "
                 "commit; delete from facturas where folio_factura like 'CONC-ZZ-%'; commit; end;")
    con1.commit()
    con1.close()
    con2.close()

print()
print("RESULTADO: FALLAS=" + str(len(fallas)))
for f in fallas:
    print("  - " + f)
sys.exit(1 if fallas else 0)
