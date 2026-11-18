-- =============================================================================
-- FOLIO_CONTADOR
--
-- Un contador por empresa y tipo de documento. Sustituye el "max(folio)+1" que
-- se calculaba en las paginas 7 y 9: con dos usuarios guardando a la vez los dos
-- calculaban el mismo numero y uno se llevaba ORA-20021.
--
-- Lo incrementa fn_asignar_folio() con un UPDATE ... RETURNING dentro de la
-- misma transaccion del guardado, asi que la fila queda bloqueada hasta el
-- COMMIT y el segundo usuario espera y recibe el numero siguiente.
--
-- Tipos: PRESUPUESTO | FAC | NC | ND | CONTROL | FAC_PROV | CONTROL_PROV
--   PRESUPUESTO  -> 1047        (numero pelado)
--   FAC          -> F-1041
--   NC           -> NC-1
--   ND           -> ND-1
--   CONTROL      -> 00-000045   (control de NUESTRAS facturas de venta)
--   FAC_PROV     -> 45          (numeracion del PROVEEDOR, compras)
--   CONTROL_PROV -> 00-000045   (control del PROVEEDOR, compras)
-- =============================================================================

CREATE TABLE "FOLIO_CONTADOR"
 (	"ID_EMPRESA" NUMBER NOT NULL ENABLE,
	"TIPO" VARCHAR2(20) NOT NULL ENABLE,
	"ULTIMO" NUMBER DEFAULT 0 NOT NULL ENABLE,
	 CONSTRAINT "PK_FOLIO_CONTADOR" PRIMARY KEY ("ID_EMPRESA", "TIPO")
  USING INDEX  ENABLE,
	 CONSTRAINT "CK_FOLIO_CONTADOR_TIPO" CHECK (tipo IN ('PRESUPUESTO', 'FAC', 'NC', 'ND', 'CONTROL',
	                                                    'FAC_PROV', 'CONTROL_PROV')) ENABLE,
	 CONSTRAINT "FK_FOLIO_CONTADOR_EMPRESA" FOREIGN KEY ("ID_EMPRESA")
	  REFERENCES "EMPRESAS" ("ID_EMPRESA") ENABLE
  ) ;
