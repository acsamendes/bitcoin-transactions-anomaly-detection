DELETE FROM `bronze._ingestion_log` WHERE TRUE;

INSERT INTO `bronze._ingestion_log`
  (batch_id, tabela_destino, tabela_origem, ingested_at,
   periodo_inicio, periodo_fim, linhas_carregadas, observacao)
SELECT
  '20260909-bronze-v1', 'bronze.blocks',
  'gs://${BUCKET}/blocks/',
  MIN(_ingested_at), DATE '2020-01-01', DATE '2020-12-31', COUNT(*),
  'Cópia fiel carregada da zona de aterrissagem no GCS. Origem primária bigquery-public-data.crypto_bitcoin.blocks, exportada em Parquet com compressão ZSTD.'
FROM `bronze.blocks`
WHERE DATE(timestamp) BETWEEN DATE '2020-01-01' AND DATE '2020-12-31';

INSERT INTO `bronze._ingestion_log`
  (batch_id, tabela_destino, tabela_origem, ingested_at,
   periodo_inicio, periodo_fim, linhas_carregadas, observacao)
SELECT
  '20260909-bronze-v1', 'bronze.transactions',
  'gs://${BUCKET}/transactions/',
  MIN(_ingested_at), DATE '2020-01-01', DATE '2020-12-31', COUNT(*),
  'Cópia fiel carregada da zona de aterrissagem no GCS. Arrays reconstruídas em SQL para desfazer o encapsulamento LIST aplicado pelo formato Parquet na exportação.'
FROM `bronze.transactions`
WHERE DATE(block_timestamp) BETWEEN DATE '2020-01-01' AND DATE '2020-12-31';

INSERT INTO `bronze._ingestion_log`
  (batch_id, tabela_destino, tabela_origem, ingested_at,
   periodo_inicio, periodo_fim, linhas_carregadas, observacao)
SELECT
  '20260909-bronze-v1', 'bronze.tx_pre2020_ref',
  'gs://${BUCKET}/tx_pre2020_ref/',
  MIN(_ingested_at), NULL, DATE '2019-12-31', COUNT(*),
  'Tabela de referência derivada, com três colunas selecionadas na exportação. Resolve a censura à esquerda no cálculo de idade de moeda.'
FROM `bronze.tx_pre2020_ref`;
