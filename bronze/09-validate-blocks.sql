SELECT
  COUNT(*)                    AS total_blocos,
  MIN(number)                 AS bloco_min,
  MAX(number)                 AS bloco_max,
  MIN(DATE(timestamp))        AS inicio,
  MAX(DATE(timestamp))        AS fim,
  SUM(transaction_count)      AS transacoes_esperadas,
  COUNT(DISTINCT _batch_id)   AS lotes
FROM `bronze.blocks`
WHERE DATE(timestamp) BETWEEN DATE '2020-01-01' AND DATE '2020-12-31';
