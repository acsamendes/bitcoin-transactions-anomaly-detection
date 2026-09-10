CREATE OR REPLACE TABLE `silver.tx_outputs`
PARTITION BY DATE(block_timestamp)
CLUSTER BY transaction_hash
OPTIONS (
  require_partition_filter = TRUE,
  description = 'Outputs desaninhados de bronze.transactions. Uma linha por output. Valores em satoshi. Campos script_asm e script_hex descartados.'
) AS
SELECT
  t.`hash`                    AS transaction_hash,
  t.block_number,
  t.block_timestamp,
  t.is_coinbase,
  o.index                     AS output_index,
  o.value                     AS value_satoshi,
  o.type                      AS script_type,
  o.required_signatures,
  ARRAY_LENGTH(o.addresses)   AS address_count,
  CASE WHEN ARRAY_LENGTH(o.addresses) = 1
       THEN o.addresses[SAFE_OFFSET(0)]
  END                         AS address_single,
  o.addresses,
  t._batch_id                 AS _source_batch_id,
  '20260909-silver-v1'        AS _batch_id,
  CURRENT_TIMESTAMP()         AS _processed_at
FROM `bronze.transactions` AS t,
UNNEST(t.outputs) AS o
WHERE DATE(t.block_timestamp) BETWEEN DATE '2020-01-01' AND DATE '2020-12-31';
