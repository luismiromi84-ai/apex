"""
Prueba de concurrencia de folios.

Escenario real: dos usuarios guardan a la vez. Cada uno calcula su folio con
max(folio)+1; si coinciden, la base solo puede aceptar uno. Lo que hay que
demostrar:

  1. Dos sesiones que calculan el mismo folio: la primera entra, la segunda
     espera el bloqueo y falla con ORA-00001. No se duplica nada.
  2. El package traduce ese ORA-00001 a un mensaje entendible (-20021 en
     presupuestos, -20022 en facturas).
  3. Dos folios distintos calculados a la vez: los dos entran.
"""
import os
import threading
import time

import oracledb

REPO = r"C:\Users\luism\OneDrive\Documents\Apex_luis"
CS = ("(DESCRIPTION=(RETRY_COUNT=5)(RETRY_DELAY=2)"
      "(ADDRESS=(PROTOCOL=TCPS)(PORT=1521)(HOST=adb.mx-monterrey-1.oraclecloud.com))"
      "(CONNECT_DATA=(SERVICE_NAME=GFD7E2575D251AE_SYPEXSQL_high.adb.oraclecloud.com))"
      "(SECURITY=(SSL_SERVER_DN_MATCH=YES)))")
EMPRESA = 1
# El cliente ya no es fijo: se toma el primero de la empresa (el dataset demo
# se purgo el 2026-11-08).
CLIENTE = None

d = {}
for l in open(os.path.join(REPO, ".env"), encoding="utf-8"):
    l = l.strip()
    if l and not l.startswith("#") and "=" in l:
        k, v = l.split("=", 1); d[k.strip()] = v.strip()


def conectar():
    con = oracledb.connect(user=d["DB_USER"], password=d["DB_PASSWORD"], dsn=CS)
    cur = con.cursor()
    cur.execute("alter session set current_schema = WKSP_SYPEXWS")
    return con


def siguiente_folio(cur):
    cur.execute("select nvl(max(folio), 0) + 1 from presupuestos where id_empresa = :1", [EMPRESA])
    return cur.fetchone()[0]


def insertar(cur, folio):
    global CLIENTE
    if CLIENTE is None:
        cur.execute("select min(id_cliente) from clientes where id_empresa = :e", [EMPRESA])
        CLIENTE = cur.fetchone()[0]

    cur.execute("""insert into presupuestos
                     (id_presupuesto, id_empresa, folio, id_cliente, fecha_emision,
                      estado, cod_moneda, tipo_cambio, subtotal, impuesto_iva, total,
                      observaciones, creado_por)
                   values (seq_prueba_folio.nextval, :1, :2, :3, sysdate,
                           'PENDIENTE', 'USD', 1, 0, 0, 0,
                           'prueba de concurrencia', 'PRUEBA')""", [EMPRESA, folio, CLIENTE])


def limpiar():
    con = conectar()
    cur = con.cursor()
    cur.execute("""delete from presupuestos_det where id_presupuesto in
                     (select id_presupuesto from presupuestos where observaciones = 'prueba de concurrencia')""")
    cur.execute("delete from presupuestos where observaciones = 'prueba de concurrencia'")
    con.commit()
    con.close()


resultado = {}


def sesion(nombre, folio, espera_antes_de_commit):
    con = None
    try:
        con = conectar()
        cur = con.cursor()
        insertar(cur, folio)
        if espera_antes_de_commit:
            time.sleep(espera_antes_de_commit)
        con.commit()
        resultado[nombre] = ("OK", None)
    except oracledb.DatabaseError as e:
        codigo = e.args[0].code
        resultado[nombre] = ("FALLO", codigo)
        if con:
            con.rollback()
    finally:
        if con:
            con.close()


def correr_hilos(tareas):
    hilos = [threading.Thread(target=sesion, args=t) for t in tareas]
    for h in hilos:
        h.start()
    for h in hilos:
        h.join(timeout=25)


# ---------------------------------------------------------------------------
print("0) preparacion")
con = conectar()
cur = con.cursor()
cur.execute("""begin
                   execute immediate 'create sequence seq_prueba_folio start with 990001';
               exception
                   when others then null;
               end;""")
con.commit()
limpiar()

# ---------------------------------------------------------------------------
print("\n1) dos sesiones que calculan el MISMO folio al mismo tiempo")
resultado.clear()
folio = None
con2 = conectar()
cur2 = con2.cursor()
folio = siguiente_folio(cur2)
con2.close()
print(f"   las dos calculan max(folio)+1 = {folio}")

correr_hilos([
    ("A", folio, 3),      # entra y tarda 3 s en confirmar
    ("B", folio, 0),      # intenta el mismo folio y se queda esperando el bloqueo
])
for nombre in ("A", "B"):
    estado, codigo = resultado.get(nombre, ("sin respuesta", None))
    extra = f" (ORA-{codigo})" if codigo else ""
    print(f"   sesion {nombre}: {estado}{extra}")

a, b = resultado.get("A", ("?", None)), resultado.get("B", ("?", None))
uno_solo = (a[0] == "OK") != (b[0] == "OK")
perdedor = a if a[0] == "FALLO" else b
print(f"   [{'OK ' if uno_solo else 'FALLA'}] entro exactamente una de las dos")
print(f"   [{'OK ' if perdedor[1] == 1 else 'FALLA'}] la que perdio fallo con ORA-00001 (unico), no con otra cosa")

cur.execute("""select count(*) from presupuestos
               where observaciones = 'prueba de concurrencia' and folio = :1""", [folio])
n = cur.fetchone()[0]
print(f"   [{'OK ' if n == 1 else 'FALLA'}] filas con el folio {folio}: {n}")
limpiar()

# ---------------------------------------------------------------------------
print("\n2) el package traduce el choque a un mensaje entendible")
con3 = conectar()
cur3 = con3.cursor()
insertar(cur3, folio)
con3.commit()
con3.close()

con4 = conectar()
cur4 = con4.cursor()
try:
    cur4.execute("""declare
                        v_id number := null;
                    begin
                        pkg_presupuestos.prc_guardar_presupuesto(
                            p_id_presupuesto    => v_id,
                            p_id_empresa        => :1,
                            p_id_cliente        => :2,
                            p_folio             => :3,
                            p_cod_moneda        => 'USD',
                            p_fecha_vencimiento => sysdate + 30,
                            p_fecha_emision     => sysdate,
                            p_tipo_cambio       => 1,
                            p_estado            => 'PENDIENTE',
                            p_observaciones     => 'prueba de concurrencia',
                            p_usuario           => 'PRUEBA');
                    end;""", [EMPRESA, CLIENTE, str(folio)])
    print("   [FALLA] el package acepto el folio repetido")
except oracledb.DatabaseError as e:
    codigo = e.args[0].code
    mensaje = e.args[0].message.splitlines()[0]
    print(f"   [{'OK ' if codigo == 20021 else 'FALLA'}] ORA-{codigo}: {mensaje[:110]}")
con4.rollback()
con4.close()
limpiar()

# ---------------------------------------------------------------------------
print("\n3) dos folios distintos calculados a la vez: los dos entran")
resultado.clear()
con5 = conectar()
cur5 = con5.cursor()
base = siguiente_folio(cur5)
con5.close()
correr_hilos([("A", base, 2), ("B", base + 1, 0)])
for nombre in ("A", "B"):
    estado, codigo = resultado.get(nombre, ("sin respuesta", None))
    print(f"   sesion {nombre} con folio {base if nombre == 'A' else base + 1}: {estado}"
          + (f" (ORA-{codigo})" if codigo else ""))
ambos = resultado.get("A", ("",))[0] == "OK" and resultado.get("B", ("",))[0] == "OK"
print(f"   [{'OK ' if ambos else 'FALLA'}] entraron las dos")
limpiar()
con = conectar()
cur = con.cursor()
cur.execute("drop sequence seq_prueba_folio")
con.commit()
con.close()
print("\nsecuencia de prueba eliminada")
