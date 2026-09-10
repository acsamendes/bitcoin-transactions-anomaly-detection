CREATE OR REPLACE TABLE `silver.tx_origin_index`
CLUSTER BY `hash`
OPTIONS (
  description = 'Índice unificado de origem temporal de transações. Une os hashes de 2020 (bronze.transactions) com os anteriores (bronze.tx_pre2020_ref) numa única tabela estreita, para viabilizar o join de idade de moeda sem reconstruir a união a cada execução.'
) AS
SELECT
  `hash`,
  block_timestamp,
  block_number,
  '20260909-silver-v1' AS _batch_id,
  CURRENT_TIMESTAMP()  AS _processed_at
FROM (
  SELECT `hash`, block_timestamp, block_number
  FROM `bronze.transactions`
  WHERE DATE(block_timestamp) BETWEEN DATE '2020-01-01' AND DATE '2020-12-31'
  UNION ALL
  SELECT `hash`, block_timestamp, block_number
  FROM `bronze.tx_pre2020_ref`
);
