SELECT
  'outputs' AS tabela,
  COUNT(*)                            AS linhas,
  COUNT(DISTINCT transaction_hash)    AS transacoes,
  COUNTIF(address_single IS NULL)     AS sem_endereco_unico,
  COUNT(DISTINCT script_type)         AS tipos_script,
  MIN(DATE(block_timestamp))          AS inicio,
  MAX(DATE(block_timestamp))          AS fim
FROM `silver.tx_outputs`
WHERE DATE(block_timestamp) BETWEEN DATE '2020-01-01' AND DATE '2020-12-31'

UNION ALL

SELECT
  'inputs',
  COUNT(*),
  COUNT(DISTINCT transaction_hash),
  COUNTIF(address_single IS NULL),
  COUNT(DISTINCT script_type),
  MIN(DATE(block_timestamp)),
  MAX(DATE(block_timestamp))
FROM `silver.tx_inputs`
WHERE DATE(block_timestamp) BETWEEN DATE '2020-01-01' AND DATE '2020-12-31';
