SELECT
  COUNT(*)                          AS transacoes,
  COUNTIF(is_coinbase)              AS coinbase,
  COUNT(DISTINCT block_number)      AS blocos,
  MIN(DATE(block_timestamp))        AS inicio,
  MAX(DATE(block_timestamp))        AS fim,
  COUNTIF(ARRAY_LENGTH(inputs)  <> input_count)  AS inconsist_inputs,
  COUNTIF(ARRAY_LENGTH(outputs) <> output_count) AS inconsist_outputs
FROM `trabalho1-pdm-2026.bronze.transactions`
WHERE DATE(block_timestamp) BETWEEN DATE '2020-01-01' AND DATE '2020-12-31';
