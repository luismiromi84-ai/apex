-- =============================================================================
-- empresa_fiscal.sql
--
-- Datos fiscales que la factura de forma libre (Venezuela) imprime y que no
-- caben en EMPRESAS: direccion, telefono y email del emisor, la providencia
-- SENIAT con su rango de numeracion autorizado, y los datos de la imprenta.
--
-- Una fila por empresa (1:1). Si una empresa no tiene fila, el impreso omite
-- esos bloques en vez de fallar.
--
-- Los valores de ejemplo salen de libreria/factura-ejemplo-prefactura.pdf.
-- =============================================================================

  CREATE TABLE "EMPRESA_FISCAL"
   (	"ID_EMPRESA" NUMBER NOT NULL ENABLE,
	"DIRECCION_FISCAL" VARCHAR2(300),
	"TELEFONO" VARCHAR2(60),
	"EMAIL" VARCHAR2(120),
	"NRO_PROVIDENCIA" VARCHAR2(60),
	"PROV_FECHA" DATE,
	"CONTROL_DESDE" VARCHAR2(30),
	"CONTROL_HASTA" VARCHAR2(30),
	"IMPRENTA_NOMBRE" VARCHAR2(150),
	"IMPRENTA_RIF" VARCHAR2(30),
	"IMPRENTA_DIRECCION" VARCHAR2(300),
	"IMPRENTA_TELEFONO" VARCHAR2(60),
	"IMPRENTA_EMAIL" VARCHAR2(120),
	 CONSTRAINT "PK_EMPRESA_FISCAL" PRIMARY KEY ("ID_EMPRESA")
  USING INDEX  ENABLE,
	 CONSTRAINT "FK_EMPRESA_FISCAL" FOREIGN KEY ("ID_EMPRESA")
	  REFERENCES "EMPRESAS" ("ID_EMPRESA") ENABLE
   ) ;

COMMENT ON TABLE "EMPRESA_FISCAL" IS 'Datos fiscales del emisor y de la imprenta para la factura de forma libre (VE)';
COMMENT ON COLUMN "EMPRESA_FISCAL"."CONTROL_DESDE" IS 'Primer numero de control autorizado por la providencia';
COMMENT ON COLUMN "EMPRESA_FISCAL"."CONTROL_HASTA" IS 'Ultimo numero de control autorizado por la providencia';
