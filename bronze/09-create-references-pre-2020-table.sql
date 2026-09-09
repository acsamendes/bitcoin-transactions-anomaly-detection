CREATE OR REPLACE TABLE `trabalho1-pdm-2026.bronze.tx_pre2020_ref`
CLUSTER BY `hash`
OPTIONS (
  description = 'Mapeamento entre hash de transação e timestamp de criação para transações anteriores a 2020. Usado para resolver a idade de moedas gastas em 2020 cujo UTXO nasceu fora do recorte.'
) AS
SELECT
  `hash`,
  block_timestamp,
  block_number,
  '20260907-bronze-v1' AS _batch_id,
  CURRENT_TIMESTAMP()  AS _ingested_at
FROM `bigquery-public-data.crypto_bitcoin.transactions`
WHERE block_timestamp_month < DATE '2020-01-01';
