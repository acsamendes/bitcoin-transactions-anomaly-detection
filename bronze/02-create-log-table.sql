CREATE TABLE IF NOT EXISTS `bronze._ingestion_log` (
  batch_id           STRING    NOT NULL,
  tabela_destino     STRING    NOT NULL,
  tabela_origem      STRING    NOT NULL,
  ingested_at        TIMESTAMP NOT NULL,
  periodo_inicio     DATE,
  periodo_fim        DATE,
  linhas_carregadas  INT64,
  observacao         STRING
)
OPTIONS (
  description = 'Log de execuções de ingestão. Uma linha por carga.'
);
