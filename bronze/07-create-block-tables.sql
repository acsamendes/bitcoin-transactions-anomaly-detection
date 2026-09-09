CREATE OR REPLACE TABLE `trabalho1-pdm-2026.bronze.blocks`
PARTITION BY DATE(timestamp)
CLUSTER BY number
OPTIONS (
  require_partition_filter = TRUE,
  description = 'Blocos Bitcoin 2020. Cópia fiel carregada da zona de aterrissagem gs://trabalho1-pdm-2026-landing/blocks/. Origem primária: bigquery-public-data.crypto_bitcoin.blocks.'
) AS
SELECT
  *,
  '20260909-bronze-v1' AS _batch_id,
  CURRENT_TIMESTAMP()  AS _ingested_at
FROM `trabalho1-pdm-2026.bronze._stg_blocks`;
