# Reglas de negocio — Synpex

Documento de referencia del sistema **Synpex** (Oracle APEX, gestión multiempresa de clientes,
presupuestos, facturación, compras y cobros/pagos, con soporte fiscal de **Venezuela** y **México**).

Este archivo viaja al repositorio de GitHub: es la fuente única de las reglas que el sistema aplica
hoy. Si una regla cambia en el código, se cambia aquí en el mismo commit.

Última revisión: **2026-11-23**.

---

## 1. Alcance y moneda

| Regla | Detalle |
|---|---|
| Países soportados | **Venezuela (VE)** y **México (MX)**. El país sale de `EMPRESAS.COD_PAIS` y decide impuestos, identificación fiscal y formato del papel. |
| Moneda base | **USD**. Todo importe se guarda en la moneda del documento y se convierte a bolívares con la tasa del documento. |
| Moneda del documento | La local del país de la empresa (`PAISES.MONEDA_LOCAL`) más **USD**. Una empresa venezolana factura en **VES o USD**; una mexicana en **MXN o USD**. |
| Importes | 2 decimales. La tasa se guarda con 6. |
| Formato de las cifras | **Según el país de la empresa activa:** Venezuela `1.234,56`, México `1,234.56` (pantallas, tablas, tarjetas y la validación de los campos). Lo fija `prc_nls_sesion` en cada petición; se apaga con `SYN_PARAMETROS.FORMATO_NUMERO_POR_PAIS = 0`. Los papeles impresos fijan su propio formato. |

## 2. Empresas y aislamiento

1. Cada **documento pertenece a una empresa** (`ID_EMPRESA`). No hay documentos compartidos.
2. Un **usuario** puede tener **una o varias empresas** (`USUARIO_EMPRESA`). `USUARIO.ID_EMPRESA` es
   solo la **empresa principal** y **no da permisos**: el permiso sale siempre de `USUARIO_EMPRESA`.
3. El usuario elige **una empresa activa** en la barra superior (`F_EMPRESA_ACTIVA`). Toda la app lee
   solo esa: **sin empresa elegida las listas salen vacías**, nunca dos empresas a la vez. Con una
   sola empresa se elige sola.
4. Un **administrador administra solo su empresa**: las altas, ediciones, desbloqueos y bajas de
   usuarios se limitan a las empresas que comparte (`FN_USUARIO_ADMINISTRABLE`).
5. Un documento **no puede usar un cliente de otra empresa** (error `-20029`), y los paquetes
   rechazan cualquier operación sobre un documento ajeno (`-20003`), aunque llegue el id por la URL.
6. Un usuario recién registrado **no entra** hasta que un administrador le asigne al menos una
   empresa y un rol.

## 3. Seguridad y usuarios

| Regla | Detalle |
|---|---|
| Autenticación | Propia (`NATIVE_CUSTOM` + `FN_AUTENTICAR_USUARIO`), no cuentas de APEX. |
| Contraseñas | PBKDF2-SHA256 con sal por usuario (100.000 iteraciones). El hash legado se convierte en el primer login correcto. |
| Mínimo de la clave | **8 caracteres** y **letras y números**. Se valida al registrarse y al cambiarla. |
| Bloqueo | **5 fallos consecutivos → 15 minutos**. Al vencer, el contador arranca de cero (se vuelve a bloquear a los 5). |
| Mensaje del login | Siempre «Usuario o contraseña incorrectos», más **«Intento N de 5»**. Al 5.º, leyenda de cuenta bloqueada con la hora de liberación. No se revela si la cuenta existe. |
| Cambio obligatorio | Si la clave la puso un administrador (`DEBE_CAMBIAR_CLAVE='S'`), el usuario **no puede usar la app** hasta cambiarla: cualquier página lo devuelve a «Recuperar contraseña». |
| Estados de la cuenta | `PENDIENTE`, `ACTIVO`, `INACTIVO`, bloqueada por intentos. **Un Estado nulo no autentica.** |
| Los usuarios **no se borran** | Se desactivan. La cuenta se conserva por auditoría; el intento de borrado responde que no se elimina. |
| Roles | `ADMIN`, `GERENCIA`, `VENTAS`, `CONTABILIDAD`, `ALMACEN`, `CONSULTA`, `FACTURACION`, `PRUEBA`. Se resuelven por **código**, nunca por id. Un empleado tiene **un rol** para todas sus empresas. |
| Lectura vs escritura | Las guardas de página dejan **ver** a más roles de los que pueden **escribir**; la escritura se cierra además en los botones y dentro de los paquetes. |
| Recuperar contraseña | Con **usuario + correo** de una cuenta activa se puede fijar una clave nueva (no se envía correo). Los intentos se auditan. |
| Auditoría | `SYN_LOGIN_LOG` (intentos), `SYN_RESET_PASSWORD_LOG` (cambios de clave), `SYN_ERROR_LOG` (errores de la app). Retención 90 días. |
| Sesión | 30 minutos de inactividad (aviso 2 minutos antes) y 8 horas de vida máxima. |

## 4. Terceros: clientes y proveedores

1. **Un cliente pertenece a una empresa**; un proveedor también. No se comparten.
2. **Ninguno se borra**: `ACTIVO` / `INACTIVO`. Un inactivo no se puede elegir en un documento nuevo.
3. **Identificación fiscal:**
   - **Venezuela:** RIF con **letra + dígitos**, con o sin guiones. La letra manda: **J** jurídico,
     **V** venezolano (natural), **E** extranjero. Jurídica **9 dígitos** (8 + verificador); natural
     **7 a 9** (la cédula más el verificador). El dígito verificador **no se comprueba**.
   - **México:** RFC de **12** (moral) o **13** (física).
   - El RIF/RFC se guarda en **mayúsculas**.
4. El **tipo de persona** (jurídica/natural) es un dato propio y **no se deduce de la letra** del RFC
   mexicano.
5. **Retención de IVA del cliente:** si es agente de retención, la factura retiene el **75 %** del IVA
   (porcentaje configurable por cliente, 0–100).
6. **SPE (Sujeto Pasivo Especial):** solo una empresa SPE causa IGTF; se marca en la empresa.
7. **Proveedor:** además lleva **días de crédito** (0–365, para el vencimiento de sus facturas) y un
   **concepto de ISLR por defecto** que hereda la compra.
8. El nombre de un cliente/proveedor **no puede ser un correo ni un teléfono**.

## 5. Catálogo de artículos y servicios

1. **Por empresa.** La misma referencia puede existir en dos empresas con precios distintos.
2. **Código interno automático y permanente:** serie `PROD-00001` para artículos y `SERV-00001` para
   servicios. Lo asigna el sistema al crear y **no se cambia ni se reutiliza**.
3. **Código de barras automático:** 8 dígitos por empresa (`10000001`…), permanente e irrepetible.
   Se usa para escanear en las líneas de documento y en el buscador del catálogo (Code 128 en las
   etiquetas).
4. `PRECIO_SUGERIDO` e `IMPUESTO_APLICABLE` son **sugerencias**: la línea del documento guarda su
   propio precio e impuesto.
5. Las existencias y su costo viven en el **kardex** (§6 Inventario), no en el catálogo.

## 6. Tasas de cambio

1. La tasa se guarda **en bolívares por unidad** de la moneda del documento: `USD→VES ≈ 918`,
   `MXN→VES ≈ 48`, `VES = 1`. **No es un factor a dólares.**
2. Se cargan por un **job diario a las 18:00** (hora de Caracas) que consulta la tasa publicada
   (`https://bcv.today`, espejo de la tasa oficial) y guarda USD y EUR; el **MXN se obtiene por
   cruce** (`USD/VES ÷ USD/MXN`, este último de referencia del BCE).
3. **La tasa del viernes rige sábado y domingo.** No hay publicación en fin de semana: la última
   vigente es la que se aplica. Que el sábado y el domingo tengan la tasa del viernes **no es un
   error**, es la práctica cambiaria venezolana.
4. Todo documento en moneda extranjera **exige tasa**:
   - vacía o ≤ 0 → error `-20061` (dice cuál es la del día);
   - **tasa = 1 en moneda extranjera → error `-20061`** (dejaría los montos en bolívares iguales a
     los de la divisa);
   - fuera del rango **0,5× … 2×** de la tasa de la tabla → error `-20061` (atrapa usar la tasa de
     otra moneda).
5. La tasa **se congela en el documento** al guardarlo. Cambiar la tasa del día no altera documentos
   ya emitidos.
6. En una **nota de crédito o débito** manda **la tasa y la alícuota de la factura original**.
7. Un cobro o un pago en moneda distinta a la del documento se convierte con **la tasa del día del
   cobro/pago**, no con la de emisión.

## 6. Inventario (kardex valorado)

1. **Kardex por empresa y artículo.** Cada entrada o salida es un **movimiento inmutable** con número
   propio (`K-000001`), cantidad, costo unitario y total, tasa del documento y documento de origen.
   **No se edita ni se borra**: se revierte con otro movimiento.
2. **Costo promedio ponderado (CPP).** Se recalcula con cada entrada y **se congela** en cada salida (el
   movimiento guarda el costo que se aplicó). Una salida que **agota** el saldo lo deja en cantidad 0 y
   valor **0,00 exactos**.
3. **Al cruzar desde existencia negativa a cero**, el CPP toma el costo unitario de la entrada que
   cruza: nunca queda en 0 con valor en el saldo (la próxima venta saldría a costo cero).
4. **Doble valoración congelada:** valor oficial en **bolívares** a la tasa del documento, y valor en la
   **divisa del documento** a esa misma tasa. Cambiar después la tabla de tasas **no mueve** el kardex.
5. **Entradas:** compra **registrada** (el importe de la línea se convierte a Bs con la tasa del
   documento), devolución de cliente (nota de crédito, **al costo con que salió** esa línea), nota de
   débito de proveedor, ajuste de entrada y **carga inicial**.
6. **Salidas:** factura **emitida** y nota de débito de cliente **al CPP vigente**; devolución a
   proveedor (nota de crédito de compra) **al costo de la línea de la compra original**; ajuste de salida.
7. **Los servicios no llevan inventario.** Una línea de servicio no crea saldo ni movimiento.
8. **El inventario se mueve al procesar/registrar, nunca al guardar un borrador.** Un borrador no
   compromete existencia.
9. **Anulaciones:** se **reversa** con un movimiento contrario al mismo costo. Si la factura ya tiene su
   **nota de crédito**, la devolución del stock la hace la nota y la anulación **no** lo devuelve otra
   vez. Una **compra con notas registradas no se puede anular** hasta anular las notas (`-20156`).
10. **Existencia negativa: se permite** (parámetro `INVENTARIO_PERMITE_NEGATIVO`, 1 = sí). En la
    operación real se despacha antes de que llegue la compra o la factura del proveedor; la lista marca
    el artículo como **Negativo** y el CPP no se inventa.
11. **Carga inicial:** una sola vez por artículo (mientras no tenga movimientos) y con **motivo
    obligatorio**. Es la forma de arrancar con el stock real contado.
12. **Todo ajuste exige motivo** y queda en el kardex como cualquier movimiento.
13. **Costo de ventas del período** = movimientos de venta (factura y nota de débito de cliente) menos
    las devoluciones de clientes. El **inventario valorado a una fecha** se recalcula **desde el kardex
    hasta esa fecha**, no desde el saldo de hoy.
14. **Fuera de alcance hoy:** multi-almacén, transferencias entre depósitos, lotes, vencimientos,
    números de serie y existencias comprometidas (reservas de pedidos).

**Toma física (2026-11-25).** Una toma guarda la existencia de cada producto activo al crearla y lo
contado. Al **aplicarla**, la diferencia entre lo contado y la existencia **de ese momento** entra al
kardex como ajuste de entrada o de salida, al costo promedio, con el motivo «Toma física N. …». Lo que
no se cuenta no se toca. Una sola toma abierta por empresa (`-20160`); una toma aplicada o anulada ya
no cambia (`-20161`); anular no mueve el kardex.

## 7. Presupuestos

1. **Numeración por empresa**, correlativa y sin huecos: `1055`, `1056`… La asigna el sistema al
   guardar; el folio en pantalla es solo la vista previa.
2. **Estados:** `PENDIENTE` → `ENVIADO` → `APROBADO` / `RECHAZADO`; y `CANCELADO` o `FACTURADO`.
3. Transiciones: no se retrocede. Un **`CANCELADO` es terminal**; un **`FACTURADO`** solo vuelve a
   `APROBADO` si se anula su factura.
4. **Documento cerrado = no se edita**: `CANCELADO` y `FACTURADO` no admiten cambios de cabecera ni
   de líneas (`-20024` / `-20003`).
5. «Procesar» solo aplica a un `PENDIENTE`; en otro estado dice el folio y el estado (`-20025`).
6. Un presupuesto facturado **no se cancela** hasta anular la factura: el mensaje lista qué factura
   lo usa (`-20026`).
7. **Gasto real:** se registran gastos contra un presupuesto (fecha, monto, moneda, tasa) y el
   sistema muestra **gastado** y **desviación** contra lo presupuestado, en USD. Un presupuesto
   cerrado no acepta gastos nuevos (`-20044`).
8. Los totales de cabecera los recalcula la base desde las líneas: **no se escriben a mano**.

## 8. Facturación

1. **Tipos de documento:** `FAC` (factura), `NC` (nota de crédito), `ND` (nota de débito).
2. **Series de folio independientes por empresa:** `F-1041`, `NC-1`, `ND-1`. La `F-` es **una sola
   serie** (las notas históricas también ocupan números de ella).
3. **N° de control (Venezuela):** se toma del **rango de la providencia** (`EMPRESA_FISCAL`,
   `CONTROL_DESDE`…`CONTROL_HASTA`) con contador atómico por empresa, formato `00-000123`. El rango
   agotado es error `-20062`; un control tecleado fuera de rango o con otro prefijo, `-20063`.
   **La numeración de control es COMPARTIDA** (criterio del contador, 2026-11-25): facturas, notas
   de crédito y notas de débito toman el N° de control de **una misma secuencia correlativa**, en el
   orden en que se crean. Ejemplo: F-1 → `00-000001`, F-2 → `00-000002`, NC-1 → `00-000003`,
   ND-1 → `00-000004`, F-3 → `00-000005`. El folio de cada tipo sigue su propia serie.
   Las notas emitidas antes de esa fecha quedaron sin control (no se renumeran).
   **El rango tiene que servir para numerar:** «desde» y «hasta» con el **mismo prefijo** y la **misma
   cantidad de dígitos**, y desde ≤ hasta (`00-000001` / `00-010000`). Datos fiscales no deja guardar
   un rango que no cumpla (`-20067`, `fn_rango_control_error`).
4. **UUID Fiscal (CFDI) es de México**: hoy se teclea a mano; la app **no timbra** ante el SAT.
5. Cada país muestra su campo: en Venezuela el **N° de Control**; en México el **UUID Fiscal**.
6. **Estados:** `PENDIENTE` (borrador) → `TIMBRADA` → `PARCIAL` → `PAGADA`; y `ANULADA`.
   - En **Venezuela** `TIMBRADA` se muestra **«PROCESADA»**, tanto en la **factura** como en la **nota
     de crédito o débito** (2026-11-25; en Venezuela no se timbra). En México se muestra **«TIMBRADA»**,
     que es lo que pasa de verdad. El dato guardado es siempre el mismo; solo cambia lo que se lee
     (`fn_estado_factura`).
7. **Un documento emitido es inmutable:** `TIMBRADA`, `PARCIAL`, `PAGADA` y `ANULADA` no se editan
   (ni cabecera ni líneas). Solo se edita un `PENDIENTE`.
8. **Anular** una factura emite automáticamente una **nota de crédito por el total** (misma empresa,
   cliente, moneda y **tasa de la factura**, con todas sus líneas) y luego marca la factura
   `ANULADA`. La nota nace **procesada**. No se puede anular una factura con cobros vivos (`-20091`).
   **«Anular» es solo para facturas (FAC):** a una nota de crédito o débito no se le ofrece; para
   revertir una nota se emite el documento contrario (una ND para una NC).
   **Un borrador (PENDIENTE) se anula sin nota de crédito:** nunca se emitió. Queda `ANULADA` y
   **conserva su folio y su N° de control** (no se borra: la numeración fiscal no puede tener huecos).
   **A un cliente INACTIVO no se le factura** (`-20068`): ni se guarda ni se emite una factura suya;
   las notas sí, para poder anular sus facturas anteriores.
   **Qué significa `ANULADA` en Venezuela:** la factura queda sin efecto fiscal **por su nota de
   crédito**, no se borra: conserva folio, N° de control y su rastro, y su saldo pasa a 0 porque la
   nota lo cancela. Las dos aparecen en el libro y en el reporte (la factura en `ANULADA` y la nota en
   `PROCESADA`), que es lo que exige el SENIAT: el documento anulado se conserva y se acredita.
9. **Nota de crédito / débito:**
   - dice **qué factura acredita** (factura origen obligatoria en el módulo de compras; en ventas la
     nota se arma con sus líneas);
   - lleva la **tasa y la alícuota de la factura original**;
   - **no puede superar el total** de la factura que acredita (`-20049`);
   - una nota de crédito **resta** saldo; una de débito **suma**;
   - **una nota no se cobra**: lo que se cobra es la factura (`fn_factura_cobrable` solo devuelve
     cierto para una `FAC` en `TIMBRADA`/`PARCIAL` con saldo).
10. **Retención de IVA (cliente agente):** **75 % del IVA de las líneas al 16 %**, sin las exentas y
    **sin el IGTF**. Se calcula en la base (`FN_IVA_RETENIDO_BS`) y el trigger la recalcula con cada
    línea.
11. **Comprobante de retención obligatorio:** una factura con retención > 0 y sin número de
    comprobante no se guarda (`-20064`).
12. Los totales de cabecera los recalcula el trigger desde las líneas. **`SUBTOTAL_LINEA` es el neto
    de la línea** (bruto − descuento). El precio unitario se guarda a **2 decimales**: lo que se
    imprime es lo que se calcula.
13. El **IGTF no se elige en una línea**: se causa con el cobro.

## 9. Cobros (recibos)

1. Un **recibo** cobra una factura; una factura puede tener **varios** recibos (abonos).
2. **Saldo de la factura** = total − notas de crédito timbradas + notas de débito timbradas − cobros
   activos. Se calcula en la moneda de la factura (`FN_SALDO_FACTURA`). Un saldo negativo es **saldo
   a favor del cliente**.
3. **No se borra un recibo: se anula.** Anulado, la factura recupera el saldo.
4. **Estado de la factura según el saldo:** saldo ≤ 0,01 → `PAGADA`; sin cobros y con saldo →
   `TIMBRADA`; con abonos → `PARCIAL`. Se recalcula también al procesar o anular una nota.
5. **Moneda del cobro:** la del país de la empresa activa más USD. Si difiere de la de la factura, se
   convierte con la **tasa del día del cobro**.
6. **IGTF:** 3 % **solo** si la empresa es **SPE**, el cobro es en **divisas** y la forma de pago lo
   genera (efectivo/divisas). La alícuota se lee del catálogo de impuestos, no está en el código.
7. **Neto del recibo** = monto − retención + IGTF. El IGTF **suma** (lo paga el cliente), no es
   ingreso de la empresa.
8. **Retención:** se teclea según el comprobante; la pantalla propone el 75 % del IVA cobrado.
9. **Referencia bancaria:** obligatoria en las formas de pago que dejan rastro bancario; con
   efectivo queda bloqueada y vacía (`FORMA_PAGO.REQUIERE_REF`).
10. **Conciliado** es una marca manual (hoy no hay conciliación automática con extractos).
11. Los recibos **no se editan** una vez guardados: se anulan y se registra otro.

## 10. Compras

1. **Estados:** `BORRADOR` (se muestra como **«Pendiente»**) → `REGISTRADA` (**«Procesada»**) →
   `ANULADA`. En `REGISTRADA`/`ANULADA` no se edita ni se tocan líneas (`-20083`).
2. Al **registrar** se emiten los comprobantes de retención: **IVA** (si hay IVA retenible) e **ISLR**
   (si el concepto da un monto mayor que cero). Una **nota de crédito o débito de compra no emite
   comprobante** ni consume número.
3. **N° de factura y N° de control del proveedor:** los numera el proveedor. La app los **propone**
   con sus propias series (`FAC_PROV` → `45`, `CONTROL_PROV` → `00-000045`) y, si el usuario teclea
   el número del papel, **se respeta** y la serie no se mueve. El N° de control exige 3 caracteres o
   más (`-20089`); el N° de factura no se valida (cada proveedor numera distinto).
4. **Nota de crédito/débito de compra:** exige la **factura afectada** (`-20097`) y lleva la tasa de
   la factura original.
5. **Retención de IVA:** sobre el IVA de las líneas al 16 %, sin exentas y **sin IGTF**. El
   porcentaje depende del **tipo de persona del proveedor** (dueño, 2026-11-25): **persona jurídica
   (J) 75 %**, **persona natural (V o E) 100 %**. Proveedor lo propone al elegir el tipo de RIF y se
   puede ajustar si el contador lo indica; un proveedor que no retiene (`Retiene IVA = No`) queda en 0.
6. **Retención de ISLR:** se calcula con el **concepto** del proveedor o de la compra, según el
   Decreto 1.808: `(base × base% − sustraendo_UT × UT) × tarifa / 100`. La **UT** es un parámetro del
   sistema (hoy 43,00 Bs, editable en Administración). El importe se congela en el comprobante: si la
   UT cambia, los comprobantes ya emitidos no se alteran. **Si el ISLR da cero o negativo no se emite
   comprobante.**
7. **IGTF de compra:** 3 % si la empresa es SPE, la forma de pago lo genera y el documento está en
   divisas. Se **congela en la compra** (`COMPRAS.IGTF_BS`) al registrarla; pantalla, libro, pagos y
   papeles leen esa foto.
8. **Vencimiento:** fecha de la factura + días de crédito del proveedor.
9. **La factura del proveedor se imprime** desde la app, con la nota de que el original es del
   proveedor y no lo sustituye.

## 11. Pagos a proveedores

1. **Importe de una compra** = total + IGTF − retención de IVA − retención de ISLR + notas de débito
   − notas de crédito. Las notas **solo cuentan cuando están `REGISTRADA`**.
2. **Saldo** = importe − lo aplicado por pagos `ACTIVO`. Una sola fórmula (`FN_IMPORTE_COMPRA` /
   `FN_SALDO_COMPRA`); nadie más calcula saldos.
3. Un pago se **reparte** entre facturas; el sobrante queda como **saldo a favor** del proveedor y
   puede aplicarse después.
4. El reparto sugerido es **FIFO** (primero lo más viejo).
5. **Un pago registrado no se edita:** se anula y se registra otro. Con el pago abierto se ven sus
   facturas en solo lectura.
6. **Conciliar** es una marca manual. El saldo a favor solo se ofrece si el pago está **no
   conciliado**.
7. Los importes de la pantalla se muestran **en la moneda de la factura**; la retención de IVA se
   guarda en bolívares y se convierte al mostrarla.

## 11 bis. Cajas y bancos

1. Cada empresa tiene sus **cajas y cuentas bancarias** (`CUENTAS_FONDOS`): nombre, tipo (caja o
   banco), banco, número de cuenta, moneda y estado. **Una sola es la principal** («Caja principal»,
   creada con la empresa) y la empresa no puede quedarse sin ella.
2. **Un cobro dice a qué caja o cuenta entra el dinero** (Destino) y **un pago de cuál sale**
   (Origen). Si no se elige, va a la **principal** (`fn_cuenta_fondos`). La cuenta tiene que ser de la
   empresa y estar activa (`-20125`).
3. La pantalla **Cajas y bancos** muestra por cuenta los cobros (entradas: el neto del cobro), los
   pagos (salidas: el pago con su IGTF) y el **saldo**, todo en bolívares a la tasa de cada movimiento.
   Es la base de la conciliación bancaria.

## 11 ter. Conciliación bancaria

1. Por **caja o cuenta y período** se marcan los cobros y pagos que aparecen en el extracto del banco.
2. **Saldo según el sistema** = saldo inicial (el saldo del banco del último cierre de esa cuenta) +
   cobros marcados − pagos marcados (con su IGTF), en la **moneda de la cuenta**.
3. Solo se **cierra** si coincide con el saldo según el banco (diferencia 0, `-20172`). Lo no marcado
   queda «en tránsito» y aparece en el período siguiente.
4. Una conciliación abierta por cuenta (`-20170`); el período no puede pisar el último cierre
   (`-20171`). Anular una abierta desmarca sus movimientos.

## 12. Impuestos

| País | Impuestos |
|---|---|
| Venezuela | IVA General **16 %**, IGTF **3 %** (de cabecera), Exento **0 %** |
| México | IVA General **16 %**, IVA Frontera **8 %** |

1. Las líneas solo ofrecen impuestos **del país de la empresa del documento** y de tipo **línea**.
2. El **% del impuesto** de la línea lo manda el impuesto elegido (exento deja 0).
3. El **IGTF** es de cabecera: no se elige en la línea, se causa con el cobro o el pago.

## 13. Libro de compras y ventas

1. Se emite **mensual o quincenal** (mes completo, 1.ª quincena 1–15, 2.ª quincena 16 al final).
2. Todo en **bolívares**, con la **tasa del documento**.
3. **La nota de crédito resta y la de débito suma.** Las **anuladas salen en 0** (conservan folio y
   control).
4. Se desglosa por alícuota (base 16 %, IVA 16 %, base 8 %, IVA 8 %, exento, base IGTF, IGTF 3 %) y
   el **total cuadra** con bases + IVA + IGTF. El IGTF de las compras va en su propia columna y fila.
5. Incluye **ventas y compras**; el bloque de un país **no** se muestra en el otro.
6. Descarga en **Excel** (números de verdad, RIF y N° de control como texto para no perder ceros) y en
   **PDF** por impresión del navegador.

## 14. Numeración y correlativos

1. **Contadores atómicos por empresa y serie** (`FOLIO_CONTADOR`): un folio no se repite aunque dos
   usuarios guarden a la vez.
2. Series: `PRESUPUESTO`, `FAC`, `NC`, `ND`, `CONTROL`, `ARTICULO`, `PROD`, `SERV`, `FAC_PROV`,
   `CONTROL_PROV`.
3. Los números **no se reutilizan**. Se pueden **ver y fijar** desde Administración › Secuencias,
   nunca por debajo del máximo ya emitido (`-20140`) ni fuera del rango de la providencia (`-20141`).
   Las series del proveedor no se fijan a mano (`-20142`).

## 15. Documentos impresos

1. Todos llevan el **logo de la empresa** (si no tiene logo, salen sin hueco ni imagen rota).
2. Al imprimir sale **solo el documento** (sin menú ni cabecera de la app).
3. Papeles disponibles: factura de venta (forma libre venezolana), presupuesto, **recibo de cobro**,
   **comprobante de retención de IVA** (Providencia SNAT/2025/000054), **comprobante de ISLR**
   (Decreto 1.808), **comprobante de pago**, **factura de compra** y **libro** (Excel/PDF).
4. La factura de compra **no sustituye** el original del proveedor: lo dice en el papel.

## 16. Auditoría y datos que no se borran

1. **Usuarios**: no se borran, se desactivan.
2. **Clientes y proveedores**: no se borran, se inactivan.
3. **Recibos y pagos**: no se editan ni se borran, se anulan.
4. **Documentos emitidos**: no se editan; se anulan con su nota.
5. Se registran intentos de login, cambios de clave y errores de la aplicación (90 días).

## 17. Fuera de alcance (a propósito, hoy)

| Tema | Estado |
|---|---|
| **Inventario** | **Implementado** el 2026-11-24: kardex con CPP, doble valoración, ajustes, carga inicial, costo de ventas e inventario valorado (con descarga a Excel). Toma física implementada el 2026-11-25. |
| **Listas de precios** por empresa / precios por proveedor | Sin implementar. |
| **Conciliación bancaria automática** con extractos | Solo marca manual. |
| **CFDI de México** (timbrado SAT: PAC, CSD, XML 4.0, acuse) | Sin implementar; **última prioridad**. En Venezuela no se timbra. |
| **Contabilidad** (plan de cuentas, asientos, estados) | Hechas el 2026-11-25: alcance respondido por el contador de Venezuela, plan de cuentas del contador (formato Profit), asientos manuales (borrador, confirmación, reverso), cierre mensual y libros (balance de comprobación, diario, mayor analítico, con Excel). Asientos automáticos con «Contabilizar» del cierre mensual (fase 4): ventas, notas, cobros con retención, IGTF y diferencial cambiario, compras, retenciones, pagos e inventario; anulaciones por reverso. Fase 5: estado de resultados y balance general (en pantalla y Excel), cierre anual (un asiento al 31/12 que lleva el resultado al patrimonio; se rehace reversándolo) y pago al SENIAT de retenciones e IGTF (no más de lo pendiente). Además (2026-11-25): flujo de efectivo (método directo), cambios en el patrimonio, resumen de impuestos, libro de retenciones, libro de inventarios y **liquidación mensual del IVA** (débito − crédito − excedente anterior − retenciones de clientes → IVA por pagar o excedente; una por mes). Falta la revisión del contador con un mes real. México espera. |
| **Multiempresa “ver todas a la vez”** | No: la empresa activa filtra todo. |
