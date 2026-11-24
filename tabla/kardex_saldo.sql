-- =============================================================================
-- KARDEX_SALDO
--
-- La disponibilidad y el costo promedio ponderado de cada articulo, por empresa
-- (2026-11-24). Una fila por empresa y articulo.
--
--   CANTIDAD            = suma de las entradas menos las salidas (puede quedar
--                         negativa si el parametro lo permite; el CPP no cambia)
--   VALOR_BS            = saldo valorado oficial (a la tasa de cada documento)
--   VALOR_REF           = el mismo saldo en la divisa de referencia
--   COSTO_PROMEDIO_BS   = lo que se aplica a la PROXIMA salida
--
-- Es derivable de KARDEX_MOV, y por eso hay una verificacion que compara los dos
-- (saldo = suma de movimientos). Se guarda para que la lista de inventario y la
-- emision de una factura lean una fila y no recorran el historico.
--
-- La escribe PKG_INVENTARIO.
-- =============================================================================

CREATE TABLE "KARDEX_SALDO"
 (	"ID_EMPRESA" NUMBER NOT NULL ENABLE,
	"ID_PRODUCTO_SERVICIO" NUMBER NOT NULL ENABLE,
	"CANTIDAD" NUMBER(14,4) DEFAULT 0 NOT NULL ENABLE,
	"VALOR_BS" NUMBER(18,2) DEFAULT 0 NOT NULL ENABLE,
	"VALOR_REF" NUMBER(18,2) DEFAULT 0 NOT NULL ENABLE,
	"COSTO_PROMEDIO_BS" NUMBER(18,6) DEFAULT 0 NOT NULL ENABLE,
	"COSTO_PROMEDIO_REF" NUMBER(18,6) DEFAULT 0 NOT NULL ENABLE,
	"ULTIMO_MOVIMIENTO" NUMBER,
	"ACTUALIZADO_EL" TIMESTAMP(6) DEFAULT SYSTIMESTAMP,
	 CONSTRAINT "PK_KARDEX_SALDO" PRIMARY KEY ("ID_EMPRESA", "ID_PRODUCTO_SERVICIO")
  USING INDEX ENABLE,
	 CONSTRAINT "FK_KARDEX_SALDO_EMPRESA" FOREIGN KEY ("ID_EMPRESA")
	  REFERENCES "EMPRESAS" ("ID_EMPRESA") ENABLE,
	 CONSTRAINT "FK_KARDEX_SALDO_PRODUCTO" FOREIGN KEY ("ID_PRODUCTO_SERVICIO")
	  REFERENCES "PRODUCTO_SERVICIO" ("ID_PRODUCTO_SERVICIO") ENABLE,
	 CONSTRAINT "FK_KARDEX_SALDO_MOV" FOREIGN KEY ("ULTIMO_MOVIMIENTO")
	  REFERENCES "KARDEX_MOV" ("ID_MOVIMIENTO") ENABLE
  ) ;

CREATE INDEX "IX_KARDEX_SALDO_ARTICULO" ON "KARDEX_SALDO" ("ID_PRODUCTO_SERVICIO") ;
