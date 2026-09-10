CREATE OR REPLACE TABLE `silver.tx_inputs`
PARTITION BY DATE(block_timestamp)
CLUSTER BY spent_transaction_hash
OPTIONS (
  require_partition_filter = TRUE,
  description = 'Inputs desaninhados de bronze.transactions. Uma linha por input. Valores em satoshi. Clusterizado por spent_transaction_hash para viabilizar o join de idade de moeda. Campo rbf_signaled segue a sinalização do BIP125 (sequence menor que 0xFFFFFFFE), avaliado por input; a leitura correta por transação é LOGICAL_OR.'
) AS
SELECT
  t.`hash`                    AS transaction_hash,
  t.block_number,
  t.block_timestamp,
  t.is_coinbase,
  i.index                     AS input_index,
  i.spent_transaction_hash,
  i.spent_output_index,
  i.value                     AS value_satoshi,
  i.type                      AS script_type,
  i.sequence,
  i.sequence < 0xFFFFFFFE     AS rbf_signaled,
  i.required_signatures,
  ARRAY_LENGTH(i.addresses)   AS address_count,
  CASE WHEN ARRAY_LENGTH(i.addresses) = 1
       THEN i.addresses[SAFE_OFFSET(0)]
  END                         AS address_single,
  i.addresses,
  t._batch_id                 AS _source_batch_id,
  '20260909-silver-v1'        AS _batch_id,
  CURRENT_TIMESTAMP()         AS _processed_at
FROM `bronze.transactions` AS t,
UNNEST(t.inputs) AS i
WHERE DATE(t.block_timestamp) BETWEEN DATE '2020-01-01' AND DATE '2020-12-31';
