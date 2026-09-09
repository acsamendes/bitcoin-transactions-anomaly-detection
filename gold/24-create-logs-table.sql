CREATE TABLE IF NOT EXISTS `trabalho1-pdm-2026.gold._transformation_log` (
  batch_id         STRING    NOT NULL,
  tabela_destino   STRING    NOT NULL,
  tabela_origem    STRING    NOT NULL,
  processed_at     TIMESTAMP NOT NULL,
  periodo_inicio   DATE,
  periodo_fim      DATE,
  linhas_geradas   INT64,
  observacao       STRING
)
OPTIONS (
  description = 'Log de execuções da camada Gold. Uma linha por carga.'
);
