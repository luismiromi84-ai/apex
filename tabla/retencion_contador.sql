-- =============================================================================
-- tabla/retencion_contador.sql
--
-- Contador del numero de comprobante de retencion, por empresa y por mes.
--
-- POR QUE NO SE REUTILIZA FOLIO_CONTADOR: su clave es (id_empresa, tipo) y el
-- numero del comprobante lleva el mes en los seis primeros digitos y REINICIA
-- cada mes (AAAAMM + 8 digitos). Con la clave de FOLIO_CONTADOR habria que
-- resetear a mano el ultimo dia del mes.
--
-- Se incrementa con UPDATE ... RETURNING (la fila queda bloqueada hasta el
-- COMMIT), el mismo patron atomico de fn_asignar_folio: dos sesiones que emitan
-- a la vez reciben numeros distintos.
-- =============================================================================

create table retencion_contador (
    id_empresa number     not null enable,
    periodo    char(6)    not null enable,
    ultimo     number(8)  default 0 not null enable,
    constraint pk_retencion_contador primary key (id_empresa, periodo)
        using index enable,
    constraint fk_retcont_empresa foreign key (id_empresa)
        references empresas (id_empresa) enable,
    constraint chk_retcont_ultimo check (ultimo >= 0) enable
);

comment on column retencion_contador.periodo is 'AAAAMM del mes en que se emiten los comprobantes';
comment on column retencion_contador.ultimo is 'Ultimo consecutivo entregado en ese mes para esa empresa';
