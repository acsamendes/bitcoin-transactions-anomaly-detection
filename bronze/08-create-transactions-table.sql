CREATE OR REPLACE TABLE `trabalho1-pdm-2026.bronze.transactions`
PARTITION BY DATE(block_timestamp)
CLUSTER BY `hash`
OPTIONS (
  require_partition_filter = TRUE,
  description = 'Transações de Bitcoin em 2020. Cópia fiel de bigquery-public-data.crypto_bitcoin.transactions.'
) AS
SELECT
  t.*,
  '20260907-bronze-v1' AS _batch_id,
  CURRENT_TIMESTAMP()  AS _ingested_at
FROM `bigquery-public-data.crypto_bitcoin.transactions` AS t
WHERE t.block_timestamp_month BETWEEN DATE '2020-01-01' AND DATE '2020-12-01'
  AND DATE(t.block_timestamp) BETWEEN DATE '2020-01-01' AND DATE '2020-12-31';
