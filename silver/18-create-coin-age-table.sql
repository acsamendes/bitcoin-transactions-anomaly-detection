CREATE OR REPLACE TABLE `trabalho1-pdm-2026.silver.coin_age`
PARTITION BY DATE(block_timestamp)
CLUSTER BY transaction_hash
OPTIONS (
  require_partition_filter = TRUE,
  description = 'Idade dos UTXOs consumidos. Uma linha por input não coinbase. Resolve a origem temporal da moeda cruzando spent_transaction_hash contra silver.tx_origin_index.'
) AS
SELECT
  i.transaction_hash,
  i.input_index,
  i.block_timestamp,
  i.block_number,
  i.spent_transaction_hash,
  i.spent_output_index,
  i.value_satoshi,
  o.block_timestamp AS origem_timestamp,
  o.block_number    AS origem_block_number,
  TIMESTAMP_DIFF(i.block_timestamp, o.block_timestamp, HOUR) AS idade_horas,
  TIMESTAMP_DIFF(i.block_timestamp, o.block_timestamp, DAY)  AS idade_dias,
  i.block_number - o.block_number                            AS idade_blocos,
  o.`hash` IS NULL                                           AS origem_nao_resolvida,
  '20260909-silver-v1' AS _batch_id,
  CURRENT_TIMESTAMP()  AS _processed_at
FROM `trabalho1-pdm-2026.silver.tx_inputs` AS i
LEFT JOIN `trabalho1-pdm-2026.silver.tx_origin_index` AS o
  ON i.spent_transaction_hash = o.`hash`
WHERE DATE(i.block_timestamp) BETWEEN DATE '2020-01-01' AND DATE '2020-12-31'
  AND NOT i.is_coinbase;
